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

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        tab.isLoading = true; tab.isSecure = webView.url?.scheme == "https"
        tab.privacyReport.isHTTPS = tab.isSecure
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tab.isLoading = false; tab.title = webView.title ?? ""
        tab.url = webView.url; tab.canGoBack = webView.canGoBack; tab.canGoForward = webView.canGoForward
        // Re-inject element hider rules for this domain
        if let host = webView.url?.host {
            let rules = ElementHiderStore.shared.rules(for: host)
            if !rules.isEmpty {
                let css = rules.joined(separator: ",") + "{display:none!important}"
                webView.evaluateJavaScript("var s=document.createElement('style');s.textContent='\(css)';document.head.appendChild(s);")
            }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { tab.isLoading = false }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { tab.isLoading = false }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if let host = url.host, let pageHost = tab.url?.host, host != pageHost {
            tab.privacyReport.thirdPartyDomains.insert(host)
        }
        let ext = url.pathExtension.lowercased()
        if ["mp4","m4v","mov","webm"].contains(ext) {
            emitMedia(url: url, type: .mp4, quality: "Direct")
        } else if ext == "m3u8" {
            emitMedia(url: url, type: .hls, quality: "Auto")
        }
        return .allow
    }

    func webView(_ webView: WKWebView, createWebViewWith config: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil { webView.load(action.request) }; return nil
    }

    // Long-press context menu with download
    func webView(_ webView: WKWebView, contextMenuConfigurationFor elementInfo: WKContextMenuElementInfo) async -> UIContextMenuConfiguration? {
        guard let url = elementInfo.linkURL else { return nil }
        let ext = url.pathExtension.lowercased()
        let isMedia = ["mp4","m4v","mov","webm","gif","m3u8","png","jpg","jpeg","webp"].contains(ext)
            || url.absoluteString.contains(".mp4") || url.absoluteString.contains(".gif")
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            var actions: [UIAction] = []
            actions.append(UIAction(title: "새 탭에서 열기", image: UIImage(systemName: "plus.square")) { _ in
                NotificationCenter.default.post(name: .openInNewTab, object: url)
            })
            if isMedia {
                actions.append(UIAction(title: "미디어 다운로드", image: UIImage(systemName: "arrow.down.circle.fill")) { [weak self] _ in
                    let type: DetectedMedia.MediaType = ext == "gif" ? .gif : ext == "m3u8" ? .hls : .mp4
                    self?.emitMedia(url: url, type: type, quality: "Direct")
                })
            }
            actions.append(UIAction(title: "링크 복사", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.url = url })
            actions.append(UIAction(title: "공유", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                if let s = UIApplication.shared.connectedScenes.first as? UIWindowScene, let r = s.windows.first?.rootViewController {
                    r.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
                }
            })
            return UIMenu(children: actions)
        }
    }

    // JS → Native bridge
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
            let type: DetectedMedia.MediaType = urlStr.contains(".m3u8") ? .hls : .mp4
            emitMedia(url: url, type: type, quality: (dict["quality"] as? String) ?? "Auto")
        case "blobCapture":
            guard let dataURL = dict["data"] as? String, let mime = dict["mimeType"] as? String,
                  let range = dataURL.range(of: ","), let data = Data(base64Encoded: String(dataURL[range.upperBound...])) else { return }
            let ext = mime.contains("mp4") ? "mp4" : "webm"
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("blob_\(UUID().uuidString).\(ext)")
            try? data.write(to: tmp)
            let media = DetectedMedia(url: tmp, type: .blob, quality: "Blob", title: "Blob Video",
                referer: tab.url?.absoluteString ?? "", thumbnail: nil,
                estimatedSize: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
            tab.detectedMedia.append(media); onMediaDetected(media)
        case "elementHidden":
            if let selector = dict["selector"] as? String, let host = tab.url?.host {
                ElementHiderStore.shared.addRule(selector, for: host)
            }
        case "privacyEvent":
            if let event = dict["event"] as? String {
                switch event {
                case "fingerprint_attempt": tab.privacyReport.fingerprintAttempts += 1
                case "tracker_blocked": tab.privacyReport.trackersBlocked += 1
                case "ad_blocked": tab.privacyReport.adsBlocked += 1
                default: break
                }
            }
        default: break
        }
    }

    private func emitMedia(url: URL, type: DetectedMedia.MediaType, quality: String) {
        let media = DetectedMedia(url: url, type: type, quality: quality,
            title: url.deletingPathExtension().lastPathComponent, referer: tab.url?.absoluteString ?? "",
            thumbnail: nil, estimatedSize: nil)
        if !tab.detectedMedia.contains(media) { tab.detectedMedia.append(media); onMediaDetected(media) }
    }
}

// MARK: - Element Hider Store (방해 요소 가리기)
final class ElementHiderStore {
    static let shared = ElementHiderStore()
    private var store: [String: [String]] = [:] // host → [css selectors]

    init() {
        if let data = UserDefaults.standard.data(forKey: "elementHiderRules"),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            store = decoded
        }
    }

    func addRule(_ selector: String, for host: String) {
        var rules = store[host] ?? []
        if !rules.contains(selector) { rules.append(selector); store[host] = rules; save() }
    }

    func rules(for host: String) -> [String] { store[host] ?? [] }

    func clearRules(for host: String) { store.removeValue(forKey: host); save() }

    private func save() {
        if let data = try? JSONEncoder().encode(store) { UserDefaults.standard.set(data, forKey: "elementHiderRules") }
    }
}

// MARK: - WebView Configuration
enum WebViewConfigurator {
    static func makeConfiguration(for tab: Tab, privacyEngine: PrivacyEngine, coordinator: WebViewCoordinator) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = tab.dataStore
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let uc = WKUserContentController()
        uc.add(coordinator, name: "mediaFound")
        uc.add(coordinator, name: "alohaDownload")
        uc.add(coordinator, name: "blobCapture")
        uc.add(coordinator, name: "elementHidden")
        uc.add(coordinator, name: "privacyEvent")
        // Fingerprint defense (runs before page loads)
        if let fp = privacyEngine.fingerprintDefenseScript {
            uc.addUserScript(WKUserScript(source: fp, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        // Aloha-style video overlay + media scanner + element hider (runs after page loads)
        uc.addUserScript(WKUserScript(source: Self.fullInjectionJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController = uc
        privacyEngine.contentBlocker.applyCachedRules(to: uc)
        return config
    }

    // === MASSIVE JS INJECTION ===
    // 1. Aloha-style video download overlay on ALL videos
    // 2. Media scanner (video/gif/hls/blob/jw player)
    // 3. Element hider (tap-to-hide like uBlock element picker)
    static let fullInjectionJS = """
    (function(){
    // ========== ALOHA STYLE VIDEO DOWNLOAD BUTTON ==========
    var dlBtnStyle='position:absolute;top:8px;right:8px;z-index:999999;background:rgba(0,212,170,0.9);color:#000;border:none;border-radius:50%;width:40px;height:40px;font-size:20px;cursor:pointer;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 8px rgba(0,0,0,0.3);';

    function addDownloadBtn(video){
        if(video.dataset.gsOverlay)return;
        video.dataset.gsOverlay='1';
        var wrap=video.parentElement;
        if(!wrap)return;
        if(getComputedStyle(wrap).position==='static')wrap.style.position='relative';

        var btn=document.createElement('button');
        btn.innerHTML='⬇';
        btn.setAttribute('style',dlBtnStyle);
        btn.addEventListener('click',function(e){
            e.stopPropagation();e.preventDefault();
            var src=video.currentSrc||video.src;
            if(!src){
                video.querySelectorAll('source').forEach(function(s){if(s.src&&!src)src=s.src;});
            }
            if(src){
                window.webkit.messageHandlers.alohaDownload.postMessage({
                    url:src,
                    title:document.title,
                    quality:video.videoHeight?video.videoHeight+'p':'Auto'
                });
                btn.innerHTML='✓';btn.style.background='rgba(29,209,161,1)';
                setTimeout(function(){btn.innerHTML='⬇';btn.style.background='rgba(0,212,170,0.9)';},2000);
            }
        });
        wrap.appendChild(btn);

        // Also show on fullscreen
        video.addEventListener('webkitbeginfullscreen',function(){
            var src=video.currentSrc||video.src;
            if(src){
                window.webkit.messageHandlers.alohaDownload.postMessage({
                    url:src,title:document.title,
                    quality:video.videoHeight?video.videoHeight+'p':'Auto'
                });
            }
        });
    }

    function scanVideos(){
        document.querySelectorAll('video').forEach(addDownloadBtn);
    }

    // ========== MEDIA SCANNER ==========
    function scanMedia(){
        // Videos
        document.querySelectorAll('video').forEach(function(v){
            var s=[];
            if(v.src)s.push({url:v.src,type:v.src.includes('.m3u8')?'hls':'mp4',label:'default'});
            v.querySelectorAll('source').forEach(function(src){
                if(src.src)s.push({url:src.src,type:src.src.includes('.m3u8')?'hls':'mp4',label:src.getAttribute('label')||'default'});
            });
            if(s.length)window.webkit.messageHandlers.mediaFound.postMessage({sources:s,title:document.title,referer:location.href,thumb:v.poster||null});
        });
        // GIFs
        document.querySelectorAll('img').forEach(function(img){
            if(img.src&&(img.src.endsWith('.gif')||img.src.includes('.gif?')))
                window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:img.src,type:'gif',label:'GIF'}],title:img.alt||'GIF',referer:location.href,thumb:null});
        });
        // JW Player
        if(typeof jwplayer!=='undefined'){
            document.querySelectorAll('[id]').forEach(function(el){
                try{var p=jwplayer(el.id);if(!p||!p.getState)return;
                    function ex(){var item=p.getPlaylistItem()||{};var ss=(item.sources||[]).map(function(s){
                        return{url:s.file,type:s.file&&s.file.includes('.m3u8')?'hls':'mp4',label:s.label||'default'};});
                        if(ss.length)window.webkit.messageHandlers.mediaFound.postMessage({sources:ss,title:item.title||document.title,referer:location.href,thumb:item.image||null});}
                    p.on('ready',ex);p.on('playlistItem',ex);if(p.getState()!=='idle')ex();
                }catch(e){}
            });
        }
    }

    // XHR/fetch intercept
    var _xo=XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open=function(m,u){if(typeof u==='string'&&u.includes('.m3u8'))window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:u,type:'hls',label:'HLS'}],title:document.title,referer:location.href,thumb:null});return _xo.apply(this,arguments);};
    var _f=window.fetch;window.fetch=function(i){var u=typeof i==='string'?i:(i&&i.url?i.url:'');if(u.includes('.m3u8'))window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:u,type:'hls',label:'HLS'}],title:document.title,referer:location.href,thumb:null});return _f.apply(this,arguments);};

    // Blob capture
    var _co=URL.createObjectURL.bind(URL);
    URL.createObjectURL=function(b){var u=_co(b);if(b&&b.type&&b.type.startsWith('video/')){var r=new FileReader();r.onload=function(e){window.webkit.messageHandlers.blobCapture.postMessage({data:e.target.result,mimeType:b.type});};r.readAsDataURL(b);}return u;};

    // ========== ELEMENT HIDER (방해 요소 가리기) ==========
    var hideMode=false;
    var highlightEl=null;
    window._gsToggleHideMode=function(){
        hideMode=!hideMode;
        if(!hideMode&&highlightEl){highlightEl.style.outline='';highlightEl=null;}
        return hideMode;
    };
    window._gsIsHideMode=function(){return hideMode;};

    document.addEventListener('touchstart',function(e){
        if(!hideMode)return;
        e.preventDefault();e.stopPropagation();
        var el=document.elementFromPoint(e.touches[0].clientX,e.touches[0].clientY);
        if(!el||el===document.body||el===document.documentElement)return;
        if(highlightEl)highlightEl.style.outline='';
        highlightEl=el;
        el.style.outline='3px solid rgba(255,71,87,0.8)';
    },{passive:false,capture:true});

    document.addEventListener('touchend',function(e){
        if(!hideMode||!highlightEl)return;
        e.preventDefault();e.stopPropagation();
        var el=highlightEl;
        // Generate unique CSS selector
        var selector='';
        if(el.id)selector='#'+el.id;
        else{
            var path=[];var cur=el;
            while(cur&&cur!==document.body){
                var tag=cur.tagName.toLowerCase();
                if(cur.className&&typeof cur.className==='string'){
                    var cls=cur.className.trim().split(/\\s+/).filter(function(c){return c.length>0&&!c.includes(':');}).slice(0,2).join('.');
                    if(cls)tag+='.'+cls;
                }
                path.unshift(tag);cur=cur.parentElement;
            }
            selector=path.join('>');
        }
        el.style.display='none';
        el.style.outline='';
        highlightEl=null;
        window.webkit.messageHandlers.elementHidden.postMessage({selector:selector});
    },{passive:false,capture:true});

    // ========== OBSERVER ==========
    new MutationObserver(function(){scanVideos();scanMedia();}).observe(document.body||document.documentElement,{childList:true,subtree:true});
    setTimeout(function(){scanVideos();scanMedia();},1000);
    setTimeout(function(){scanVideos();scanMedia();},3000);
    setTimeout(scanVideos,5000);
    })();
    """;
}

// MARK: - Notifications
extension Notification.Name {
    static let openInNewTab = Notification.Name("openInNewTab")
}
