// Browser/WebViewManager.swift
import SwiftUI
import WebKit

final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, @unchecked Sendable {
    let tab: Tab
    let privacyEngine: PrivacyEngine
    let onMediaDetected: (DetectedMedia) -> Void

    init(tab: Tab, privacyEngine: PrivacyEngine, onMediaDetected: @escaping (DetectedMedia) -> Void) {
        self.tab = tab; self.privacyEngine = privacyEngine; self.onMediaDetected = onMediaDetected
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation n: WKNavigation!) {
        tab.isLoading = true; tab.isSecure = webView.url?.scheme == "https"; tab.privacyReport.isHTTPS = tab.isSecure
    }
    func webView(_ webView: WKWebView, didFinish n: WKNavigation!) {
        tab.isLoading = false; tab.title = webView.title ?? ""; tab.url = webView.url
        tab.canGoBack = webView.canGoBack; tab.canGoForward = webView.canGoForward
        if let host = webView.url?.host {
            let rules = ElementHiderStore.shared.rules(for: host)
            if !rules.isEmpty {
                let css = rules.joined(separator: ",") + "{display:none!important}"
                webView.evaluateJavaScript("var s=document.createElement('style');s.textContent='\(css)';document.head.appendChild(s);")
            }
        }
    }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: any Error) { tab.isLoading = false }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: any Error) { tab.isLoading = false }

    func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if let host = url.host, let pageHost = tab.url?.host, host != pageHost {
            tab.privacyReport.thirdPartyDomains.insert(host)
        }
        let ext = url.pathExtension.lowercased()
        if ["mp4","m4v","mov","webm"].contains(ext) { emitMedia(url: url, type: .mp4, quality: "Direct") }
        else if ext == "m3u8" { emitMedia(url: url, type: .hls, quality: "Auto") }
        return .allow
    }

    func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if a.targetFrame == nil { w.load(a.request) }; return nil
    }

    // === LONG-PRESS CONTEXT MENU (no Face ID, no photo save) ===
    func webView(_ webView: WKWebView, contextMenuConfigurationFor elementInfo: WKContextMenuElementInfo) async -> UIContextMenuConfiguration? {
        guard let linkURL = elementInfo.linkURL else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIAction] = []
            actions.append(UIAction(title: "새 탭에서 열기", image: UIImage(systemName: "plus.square.on.square")) { _ in
                NotificationCenter.default.post(name: .openInNewTab, object: linkURL)
            })
            let ext = linkURL.pathExtension.lowercased()
            if ["mp4","m4v","mov","webm","gif","m3u8","png","jpg","jpeg","webp"].contains(ext) {
                actions.append(UIAction(title: "다운로드", image: UIImage(systemName: "arrow.down.circle.fill")) { [weak self] _ in
                    let type: DetectedMedia.MediaType = ext == "gif" ? .gif : ext == "m3u8" ? .hls : .mp4
                    self?.emitMedia(url: linkURL, type: type, quality: "Direct")
                })
            }
            actions.append(UIAction(title: "링크 복사", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.url = linkURL
            })
            return UIMenu(children: actions)
        }
    }

    // === JS MESSAGE HANDLER ===
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any] else { return }
        switch message.name {
        case "mediaFound":
            guard let sources = dict["sources"] as? [[String: Any]], let ref = dict["referer"] as? String else { return }
            let title = (dict["title"] as? String) ?? "Media"
            let thumb = (dict["thumb"] as? String).flatMap { URL(string: $0) }
            for s in sources {
                guard let u = (s["url"] as? String).flatMap({ URL(string: $0) }) else { continue }
                let t: DetectedMedia.MediaType = (s["type"] as? String) == "hls" ? .hls : (s["type"] as? String) == "gif" ? .gif : .mp4
                let media = DetectedMedia(url: u, type: t, quality: (s["label"] as? String) ?? "default",
                    title: title, referer: ref, thumbnail: thumb, estimatedSize: nil)
                if !tab.detectedMedia.contains(media) { tab.detectedMedia.append(media); onMediaDetected(media) }
            }
        case "alohaDownload":
            guard let urlStr = dict["url"] as? String, let url = URL(string: urlStr) else { return }
            emitMedia(url: url, type: urlStr.contains(".m3u8") ? .hls : .mp4, quality: (dict["quality"] as? String) ?? "Auto")
        case "blobCapture":
            guard let dataURL = dict["data"] as? String, let mime = dict["mimeType"] as? String,
                  let range = dataURL.range(of: ","), let data = Data(base64Encoded: String(dataURL[range.upperBound...])) else { return }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("blob_\(UUID().uuidString).\(mime.contains("mp4") ? "mp4" : "webm")")
            try? data.write(to: tmp)
            let media = DetectedMedia(url: tmp, type: .blob, quality: "Blob", title: "Blob Video",
                referer: tab.url?.absoluteString ?? "", thumbnail: nil,
                estimatedSize: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
            tab.detectedMedia.append(media); onMediaDetected(media)
        case "elementHidden":
            if let sel = dict["selector"] as? String, let host = tab.url?.host { ElementHiderStore.shared.addRule(sel, for: host) }
        case "privacyEvent":
            if let ev = dict["event"] as? String {
                switch ev { case "fingerprint_attempt": tab.privacyReport.fingerprintAttempts += 1
                case "tracker_blocked": tab.privacyReport.trackersBlocked += 1; case "ad_blocked": tab.privacyReport.adsBlocked += 1; default: break }
            }
        default: break
        }
    }

    private func emitMedia(url: URL, type: DetectedMedia.MediaType, quality: String) {
        let media = DetectedMedia(url: url, type: type, quality: quality,
            title: url.deletingPathExtension().lastPathComponent, referer: tab.url?.absoluteString ?? "", thumbnail: nil, estimatedSize: nil)
        if !tab.detectedMedia.contains(media) { tab.detectedMedia.append(media); onMediaDetected(media) }
    }
}

// MARK: - Element Hider Store
final class ElementHiderStore {
    static let shared = ElementHiderStore()
    private var store: [String: [String]] = [:]
    init() {
        if let d = UserDefaults.standard.data(forKey: "elementHiderRules"),
           let s = try? JSONDecoder().decode([String:[String]].self, from: d) { store = s }
    }
    func addRule(_ sel: String, for host: String) {
        var r = store[host] ?? []; if !r.contains(sel) { r.append(sel); store[host] = r; save() }
    }
    func rules(for host: String) -> [String] { store[host] ?? [] }
    func clearRules(for host: String) { store.removeValue(forKey: host); save() }
    private func save() { if let d = try? JSONEncoder().encode(store) { UserDefaults.standard.set(d, forKey: "elementHiderRules") } }
}

// MARK: - WebView Configuration
enum WebViewConfigurator {
    static func makeConfiguration(for tab: Tab, privacyEngine: PrivacyEngine, coordinator: WebViewCoordinator) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = tab.dataStore
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let uc = WKUserContentController()
        for name in ["mediaFound","alohaDownload","blobCapture","elementHidden","privacyEvent"] {
            uc.add(coordinator, name: name)
        }
        if let fp = privacyEngine.fingerprintDefenseScript {
            uc.addUserScript(WKUserScript(source: fp, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        uc.addUserScript(WKUserScript(source: Self.injectionJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController = uc
        privacyEngine.contentBlocker.applyCachedRules(to: uc)
        return config
    }

    static let injectionJS = """
    (function(){
    // ===== ALOHA-STYLE DOWNLOAD BUTTON ON VIDEOS =====
    function addDLBtn(v){
        if(v.dataset.gsBtn)return; v.dataset.gsBtn='1';
        var w=v.parentElement; if(!w)return;
        if(getComputedStyle(w).position==='static')w.style.position='relative';
        var b=document.createElement('div');
        b.innerHTML='<svg width="24" height="24" viewBox="0 0 24 24" fill="none"><path d="M12 3v12m0 0l-4-4m4 4l4-4M5 19h14" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        b.style.cssText='position:absolute;top:8px;right:8px;z-index:999999;background:rgba(0,180,140,0.92);border-radius:50%;width:36px;height:36px;display:flex;align-items:center;justify-content:center;cursor:pointer;box-shadow:0 2px 8px rgba(0,0,0,0.4);';
        b.addEventListener('click',function(e){
            e.stopPropagation();e.preventDefault();
            var src=v.currentSrc||v.src||'';
            v.querySelectorAll('source').forEach(function(s){if(!src&&s.src)src=s.src;});
            if(src){
                window.webkit.messageHandlers.alohaDownload.postMessage({url:src,title:document.title,quality:(v.videoHeight||'Auto')+'p'});
                b.innerHTML='<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M5 13l4 4L19 7" stroke="white" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>';
                setTimeout(function(){b.innerHTML='<svg width="24" height="24" viewBox="0 0 24 24" fill="none"><path d="M12 3v12m0 0l-4-4m4 4l4-4M5 19h14" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';},2000);
            }
        });
        b.addEventListener('touchend',function(e){e.stopPropagation();});
        w.appendChild(b);
        v.addEventListener('webkitbeginfullscreen',function(){
            var src=v.currentSrc||v.src;
            if(src)window.webkit.messageHandlers.alohaDownload.postMessage({url:src,title:document.title,quality:(v.videoHeight||'Auto')+'p'});
        });
    }

    // ===== MEDIA SCANNER =====
    function scan(){
        document.querySelectorAll('video').forEach(function(v){ addDLBtn(v);
            var s=[];
            if(v.src)s.push({url:v.src,type:v.src.includes('.m3u8')?'hls':'mp4',label:'default'});
            v.querySelectorAll('source').forEach(function(src){if(src.src)s.push({url:src.src,type:src.src.includes('.m3u8')?'hls':'mp4',label:src.getAttribute('label')||'default'});});
            if(s.length)window.webkit.messageHandlers.mediaFound.postMessage({sources:s,title:document.title,referer:location.href,thumb:v.poster||null});
        });
        document.querySelectorAll('img').forEach(function(img){
            var src=img.src||'';
            if(src.match(/\\.gif(\\?|$)/i))
                window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:src,type:'gif',label:'GIF'}],title:img.alt||'GIF',referer:location.href,thumb:null});
        });
        if(typeof jwplayer!=='undefined'){
            document.querySelectorAll('[id]').forEach(function(el){try{var p=jwplayer(el.id);if(!p||!p.getState)return;
                function ex(){var it=p.getPlaylistItem()||{};var ss=(it.sources||[]).map(function(s){return{url:s.file,type:s.file&&s.file.includes('.m3u8')?'hls':'mp4',label:s.label||'default'};});
                if(ss.length)window.webkit.messageHandlers.mediaFound.postMessage({sources:ss,title:it.title||document.title,referer:location.href,thumb:it.image||null});}
                p.on('ready',ex);p.on('playlistItem',ex);if(p.getState()!=='idle')ex();}catch(e){}});
        }
    }

    // XHR/fetch intercept
    var _xo=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){if(typeof u==='string'&&u.includes('.m3u8'))window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:u,type:'hls',label:'HLS'}],title:document.title,referer:location.href,thumb:null});return _xo.apply(this,arguments);};
    var _f=window.fetch;window.fetch=function(i){var u=typeof i==='string'?i:(i&&i.url?i.url:'');if(u.includes('.m3u8'))window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:u,type:'hls',label:'HLS'}],title:document.title,referer:location.href,thumb:null});return _f.apply(this,arguments);};
    var _co=URL.createObjectURL.bind(URL);URL.createObjectURL=function(b){var u=_co(b);if(b&&b.type&&b.type.startsWith('video/')){var r=new FileReader();r.onload=function(e){window.webkit.messageHandlers.blobCapture.postMessage({data:e.target.result,mimeType:b.type});};r.readAsDataURL(b);}return u;};

    // ===== ELEMENT HIDER =====
    var hideMode=false,hlEl=null;
    window._gsToggleHideMode=function(){hideMode=!hideMode;if(!hideMode&&hlEl){hlEl.style.outline='';hlEl=null;}return hideMode;};
    document.addEventListener('touchstart',function(e){if(!hideMode)return;e.preventDefault();e.stopPropagation();
        var el=document.elementFromPoint(e.touches[0].clientX,e.touches[0].clientY);
        if(!el||el===document.body)return;if(hlEl)hlEl.style.outline='';hlEl=el;el.style.outline='3px solid #FF4757';},{passive:false,capture:true});
    document.addEventListener('touchend',function(e){if(!hideMode||!hlEl)return;e.preventDefault();e.stopPropagation();
        var el=hlEl,sel='';if(el.id)sel='#'+el.id;else{var p=[];var c=el;while(c&&c!==document.body){var t=c.tagName.toLowerCase();
        if(c.className&&typeof c.className==='string'){var cls=c.className.trim().split(/\\s+/).filter(function(x){return x.length>0;}).slice(0,2).join('.');if(cls)t+='.'+cls;}
        p.unshift(t);c=c.parentElement;}sel=p.join('>');}
        el.style.display='none';el.style.outline='';hlEl=null;
        window.webkit.messageHandlers.elementHidden.postMessage({selector:sel});},{passive:false,capture:true});

    new MutationObserver(scan).observe(document.body||document.documentElement,{childList:true,subtree:true});
    setTimeout(scan,800);setTimeout(scan,2500);setTimeout(scan,5000);
    })();
    """
}

extension Notification.Name {
    static let openInNewTab = Notification.Name("openInNewTab")
}
