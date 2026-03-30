// Browser/WebViewManager.swift
import SwiftUI
import WebKit
import Photos

final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate, @unchecked Sendable {
    let tab: Tab
    let privacyEngine: PrivacyEngine
    let onMediaDetected: (DetectedMedia) -> Void
    private var pendingDownloadFilename: String?

    var downloadManager: MediaDownloadManager?
    weak var webView: WKWebView?   // set by BrowserWebView for cookie forwarding

    // CF: tracks domains where we've stripped fingerprint defense scripts
    private var cfStrippedDomains: Set<String> = []
    private var cfReloadPending = false

    init(tab: Tab, privacyEngine: PrivacyEngine, onMediaDetected: @escaping (DetectedMedia) -> Void) {
        self.tab = tab; self.privacyEngine = privacyEngine; self.onMediaDetected = onMediaDetected
    }

    // MARK: - Navigation
    func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) {
        tab.isLoading = true; tab.isSecure = w.url?.scheme == "https"; tab.privacyReport.isHTTPS = tab.isSecure
    }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        tab.isLoading = false; tab.title = w.title ?? ""; tab.url = w.url
        tab.canGoBack = w.canGoBack; tab.canGoForward = w.canGoForward
        // Reapply element hider rules
        if let host = w.url?.host {
            let rules = ElementHiderStore.shared.rules(for: host)
            if !rules.isEmpty {
                let css = rules.joined(separator: ",") + "{display:none!important}"
                w.evaluateJavaScript("var s=document.createElement('style');s.textContent='\(css)';document.head.appendChild(s);")
            }
        }

        // ── Cloudflare: detect challenge, strip fingerprint scripts, reload ONCE ─
        // Skip if this domain already had scripts stripped (prevents second loop)
        let host = w.url?.host ?? ""
        guard !cfReloadPending else {
            cfReloadPending = false
            return
        }
        guard !cfStrippedDomains.contains(host) else { return }

        w.evaluateJavaScript("""
        (function(){
            var t = document.title || '';
            return (t === 'Just a moment...'
                || t.indexOf('Checking your browser') !== -1
                || t.indexOf('Attention Required') !== -1
                || !!document.querySelector('#challenge-form,.cf-browser-verification,#cf-wrapper')
                || location.hostname === 'challenges.cloudflare.com') ? '1' : '0';
        })()
        """) { [weak self, weak w] result, _ in
            guard let str = result as? String, str == "1",
                  let self = self, let w = w else { return }
            let domain = w.url?.host ?? ""
            self.cfStrippedDomains.insert(domain)
            self.cfReloadPending = true
            // ★ KEY FIX: remove ALL user scripts so fingerprint spoofing is gone
            let uc = w.configuration.userContentController
            uc.removeAllUserScripts()
            // Re-add ONLY the media-detection script (no fingerprint defense)
            uc.addUserScript(WKUserScript(
                source: WebViewConfigurator.injectionJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
            // Now reload — CF will see real Safari fingerprint → pass
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { w.reload() }
        }
    }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: any Error) { tab.isLoading = false }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: any Error) { tab.isLoading = false }

    // MARK: - Intercept media responses → WKDownload
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let url = navigationResponse.response.url
        let mime = navigationResponse.response.mimeType ?? ""
        let ext = url?.pathExtension.lowercased() ?? ""
        
        // Direct video file navigation → trigger WKDownload
        if ["mp4","m4v","mov","webm","mp3","m4a"].contains(ext) {
            decisionHandler(.download)
            return
        }
        
        // Video MIME type in main frame → trigger WKDownload  
        if (mime.hasPrefix("video/") || mime.hasPrefix("audio/")) && navigationResponse.isForMainFrame {
            decisionHandler(.download)
            return
        }
        
        // Non-main-frame media → emit for overlay button
        if let url = url, (mime.hasPrefix("video/") || mime.contains("gif")) && !navigationResponse.isForMainFrame {
            let type: DetectedMedia.MediaType = mime.contains("gif") ? .gif : .mp4
            emitMedia(url: url, type: type, quality: "Direct")
        }
        
        decisionHandler(.allow)
    }

    // MARK: - WKDownloadDelegate (iOS 14.5+)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        pendingDownloadFilename = suggestedFilename
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(suggestedFilename)
        if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
        return dest
    }

    func downloadDidFinish(_ download: WKDownload) {
        // Notify user download completed
        NotificationCenter.default.post(name: .downloadCompleted, object: pendingDownloadFilename)
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        NotificationCenter.default.post(name: .downloadFailed, object: error.localizedDescription)
    }

    // MARK: - New window (target=_blank)
    func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if a.targetFrame == nil { w.load(a.request) }; return nil
    }

    // MARK: - Context Menu (long-press)
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
                    self?.emitMedia(url: linkURL, type: ext == "gif" ? .gif : .mp4, quality: "Direct")
                })
                actions.append(UIAction(title: "사진 앱에 저장", image: UIImage(systemName: "photo.badge.arrow.down")) { _ in
                    Self.saveURLToPhotos(linkURL)
                })
            }
            actions.append(UIAction(title: "링크 복사", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.url = linkURL
            })
            return UIMenu(children: actions)
        }
    }

    // MARK: - JS Bridge
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any] else { return }
        switch message.name {
        case "mediaFound":
            guard let sources = dict["sources"] as? [[String: Any]], let ref = dict["referer"] as? String else { return }
            let title = (dict["title"] as? String) ?? "Media"
            let thumb = (dict["thumb"] as? String).flatMap { URL(string: $0) }
            var hasHLS = false
            for s in sources {
                guard let u = (s["url"] as? String).flatMap({ URL(string: $0) }) else { continue }
                // Skip data: URLs and empty URLs
                if u.scheme == "data" || u.absoluteString.isEmpty { continue }
                let typeStr = (s["type"] as? String) ?? ""
                let t: DetectedMedia.MediaType
                switch typeStr {
                case "hls": t = .hls
                case "gif": t = .gif
                case "image": t = .image
                case "webm": t = .webm
                default: t = .mp4
                }
                let media = DetectedMedia(url: u, type: t, quality: (s["label"] as? String) ?? "default",
                    title: title, referer: ref, thumbnail: thumb, estimatedSize: nil)
                if !tab.detectedMedia.contains(media) { tab.detectedMedia.append(media); onMediaDetected(media) }
                if t == .hls { hasHLS = true }
            }
            // Sync cookies eagerly when HLS is detected (auth streams need them)
            if hasHLS { syncCookiesToDownloadManager() }
        case "alohaDownload":
            guard let urlStr = dict["url"] as? String, let url = URL(string: urlStr) else { return }
            // Hide overlay signal from webkitendfullscreen
            if urlStr == "__hide_overlay__" { FullscreenDownloadOverlay.shared.hide(); return }
            // Reject blob: and data: URLs
            if url.scheme == "blob" || url.scheme == "data" {
                NotificationCenter.default.post(name: .downloadFailed, object: "이 영상은 스트리밍 전용으로 직접 다운로드할 수 없습니다 (blob/MediaSource)")
                return
            }
            let type: DetectedMedia.MediaType = urlStr.contains(".m3u8") ? .hls : .mp4
            let title = (dict["title"] as? String) ?? url.deletingPathExtension().lastPathComponent
            let quality = (dict["quality"] as? String) ?? "Auto"
            let isFullscreen = (dict["fullscreen"] as? Bool) == true
            let media = DetectedMedia(url: url, type: type, quality: quality, title: title,
                referer: tab.url?.absoluteString ?? "", thumbnail: nil, estimatedSize: nil)
            if isFullscreen {
                // Show native overlay button instead of auto-downloading
                // (user sees button and consciously taps to download)
                if let dm = downloadManager {
                    FullscreenDownloadOverlay.shared.show(url: url, title: title, quality: quality, downloadManager: dm)
                }
            } else {
                // Normal Aloha-style: 1-tap download from overlay button
                syncCookiesToDownloadManager()
                downloadManager?.download(media: media, saveToVault: false)
                onMediaDetected(media)
            }
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

    // MARK: - Cookie Sync
    func syncCookiesToDownloadManager() {
        guard let wv = webView, let dm = downloadManager else { return }
        wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let storage = HTTPCookieStorage.shared
            cookies.forEach { storage.setCookie($0) }
            dm.cookieStorage = storage
        }
    }

    private func emitMedia(url: URL, type: DetectedMedia.MediaType, quality: String) {
        let media = DetectedMedia(url: url, type: type, quality: quality,
            title: url.deletingPathExtension().lastPathComponent, referer: tab.url?.absoluteString ?? "", thumbnail: nil, estimatedSize: nil)
        if !tab.detectedMedia.contains(media) { tab.detectedMedia.append(media); onMediaDetected(media) }
    }

    // MARK: - Save to Photos (with proper permission check)
    static func saveURLToPhotos(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else { return }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else { return }
                PHPhotoLibrary.shared().performChanges {
                    let req = PHAssetCreationRequest.forAsset()
                    let isVideo = ["mp4","m4v","mov","webm"].contains(ext)
                    req.addResource(with: isVideo ? .video : .photo, data: data, options: nil)
                }
            }
        }.resume()
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
    // ===== ALOHA DOWNLOAD BUTTON =====
    function addDL(v){
        if(v.dataset.gsBtn)return;v.dataset.gsBtn='1';
        var w=v.parentElement;if(!w)return;
        if(getComputedStyle(w).position==='static')w.style.position='relative';
        var b=document.createElement('div');
        b.innerHTML='<svg width="22" height="22" viewBox="0 0 24 24" fill="none"><path d="M12 3v12m0 0l-4-4m4 4l4-4M5 19h14" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        b.style.cssText='position:absolute;top:8px;right:8px;z-index:999999;background:rgba(0,180,140,0.92);border-radius:50%;width:36px;height:36px;display:flex;align-items:center;justify-content:center;cursor:pointer;box-shadow:0 2px 8px rgba(0,0,0,0.4);pointer-events:auto;';
        b.onclick=function(e){e.stopPropagation();e.preventDefault();
            var src=v.currentSrc||v.src||'';
            v.querySelectorAll('source').forEach(function(s){if(!src&&s.src)src=s.src;});
            // Skip blob: URLs — they can't be downloaded directly
            if(src&&src.startsWith('blob:')){
                // Try to find a non-blob source from our intercepted URLs
                src='';
            }
            if(src&&!src.startsWith('blob:')&&!src.startsWith('data:')){
                window.webkit.messageHandlers.alohaDownload.postMessage({url:src,title:document.title,quality:(v.videoHeight||'Auto')+'p'});
                b.innerHTML='<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M5 13l4 4L19 7" stroke="white" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>';
                setTimeout(function(){b.innerHTML='<svg width="22" height="22" viewBox="0 0 24 24" fill="none"><path d="M12 3v12m0 0l-4-4m4 4l4-4M5 19h14" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';},2000);
            } else {
                // Show red X - can't download blob/data URLs
                b.innerHTML='<svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M18 6L6 18M6 6l12 12" stroke="white" stroke-width="3" stroke-linecap="round"/></svg>';
                b.style.background='rgba(220,50,50,0.92)';
                setTimeout(function(){b.innerHTML='<svg width="22" height="22" viewBox="0 0 24 24" fill="none"><path d="M12 3v12m0 0l-4-4m4 4l4-4M5 19h14" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';b.style.background='rgba(0,180,140,0.92)';},2000);
            }};        b.ontouchend=function(e){e.stopPropagation();};
        w.appendChild(b);
        v.addEventListener('webkitbeginfullscreen',function(){var src=v.currentSrc||v.src;if(src)window.webkit.messageHandlers.alohaDownload.postMessage({url:src,title:document.title,quality:(v.videoHeight||'Auto')+'p',fullscreen:true});});
        v.addEventListener('webkitendfullscreen',function(){window.webkit.messageHandlers.alohaDownload.postMessage({url:'__hide_overlay__',title:'',quality:'',fullscreen:false});});
        v.addEventListener('webkitpresentationmodechanged',function(e){if(v.webkitPresentationMode==='fullscreen'){var src=v.currentSrc||v.src;if(src)window.webkit.messageHandlers.alohaDownload.postMessage({url:src,title:document.title,quality:(v.videoHeight||'Auto')+'p',fullscreen:true});}});
        v.addEventListener('play',function(){if(!v.dataset.gsPlayed){v.dataset.gsPlayed='1';var src=v.currentSrc||v.src;if(src&&!src.startsWith('blob:')&&!src.startsWith('data:')){window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:src,type:src.includes('.m3u8')?'hls':'mp4',label:(v.videoHeight||'Auto')+'p'}],title:document.title,referer:location.href,thumb:v.poster||null});}}});
    }

    function scan(){
        document.querySelectorAll('video').forEach(addDL);
        document.querySelectorAll('video').forEach(function(v){
            var s=[];
            if(v.src&&!v.src.startsWith('blob:')&&!v.src.startsWith('data:'))s.push({url:v.src,type:v.src.includes('.m3u8')?'hls':'mp4',label:'default'});
            v.querySelectorAll('source').forEach(function(src){if(src.src&&!src.src.startsWith('blob:'))s.push({url:src.src,type:src.src.includes('.m3u8')?'hls':'mp4',label:src.getAttribute('label')||'default'});});
            if(s.length)window.webkit.messageHandlers.mediaFound.postMessage({sources:s,title:document.title,referer:location.href,thumb:v.poster||null});
        });
        document.querySelectorAll('img').forEach(function(img){if(!img.src||img.src.startsWith('data:'))return;
            var isGif=img.src.toLowerCase().indexOf('.gif')!==-1;
            if(img.naturalWidth>100||isGif)window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:img.src,type:isGif?'gif':'image',label:'Image'}],title:img.alt||document.title,referer:location.href,thumb:null});
        });
        if(typeof jwplayer!=='undefined'){document.querySelectorAll('[id]').forEach(function(el){try{var p=jwplayer(el.id);if(!p||!p.getState)return;
            function ex(){var it=p.getPlaylistItem()||{};var ss=(it.sources||[]).map(function(s){return{url:s.file,type:s.file&&s.file.includes('.m3u8')?'hls':'mp4',label:s.label||'default'};});
            if(ss.length)window.webkit.messageHandlers.mediaFound.postMessage({sources:ss,title:it.title||document.title,referer:location.href,thumb:it.image||null});}
            p.on('ready',ex);p.on('playlistItem',ex);if(p.getState()!=='idle')ex();}catch(e){}});}
    }
    var _xo=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){if(typeof u==='string'){
        if(u.includes('.m3u8'))window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:u,type:'hls',label:'HLS'}],title:document.title,referer:location.href,thumb:null});
        else if(u.match(/\\.(mp4|webm|m4v|mov)(\\?|$)/i)&&!u.startsWith('blob:'))window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:u,type:'mp4',label:'Direct'}],title:document.title,referer:location.href,thumb:null});
        else if(u.includes('googlevideo.com/videoplayback'))window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:u,type:'mp4',label:'YouTube'}],title:document.title,referer:location.href,thumb:null});
    }return _xo.apply(this,arguments);};
    var _f=window.fetch;window.fetch=function(i){var u=typeof i==='string'?i:(i&&i.url?i.url:'');
        if(u.includes('.m3u8'))window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:u,type:'hls',label:'HLS'}],title:document.title,referer:location.href,thumb:null});
        else if(u.match(/\\.(mp4|webm|m4v|mov)(\\?|$)/i)&&!u.startsWith('blob:'))window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:u,type:'mp4',label:'Direct'}],title:document.title,referer:location.href,thumb:null});
        else if(u.includes('googlevideo.com/videoplayback'))window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:u,type:'mp4',label:'YouTube'}],title:document.title,referer:location.href,thumb:null});
    return _f.apply(this,arguments);};
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

    // Long-press on images → download
    document.addEventListener('contextmenu',function(e){
        var el=e.target;
        if(el.tagName==='IMG'&&el.src){
            window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:el.src,type:el.src.toLowerCase().indexOf('.gif')!==-1?'gif':'image',label:'Image'}],title:el.alt||document.title,referer:location.href,thumb:null});
        }
        if(el.tagName==='VIDEO'||(el.closest&&el.closest('video'))){
            var v=el.tagName==='VIDEO'?el:el.closest('video');
            var src=v.currentSrc||v.src||'';
            v.querySelectorAll('source').forEach(function(s){if(!src&&s.src)src=s.src;});
            if(src)window.webkit.messageHandlers.alohaDownload.postMessage({url:src,title:document.title,quality:(v.videoHeight||'Auto')+'p'});
        }
    },true);

    // ===== DYNAMIC AD REMOVAL (Layer 3 — JS-based) =====
    var adObserver=new MutationObserver(function(mutations){
        mutations.forEach(function(m){
            m.addedNodes.forEach(function(node){
                if(node.nodeType!==1)return;
                // Remove ad iframes
                if(node.tagName==='IFRAME'){
                    var s=node.src||'';
                    if(s.match(/ad[.s]|doubleclick|googlesyndication|adfit|cauly|mobon|adpopcorn|realclick|admixer/i)){
                        node.style.display='none';node.remove();
                        window.webkit.messageHandlers.privacyEvent.postMessage({event:'ad_blocked'});
                    }
                }
                // Remove ad divs by ID/class patterns
                var el=node;
                if(el.id&&el.id.match(/^(ad[-_]|ads[-_]|adv[-_]|banner|sponsor|dcAd|google_ads)/i)){
                    el.style.display='none';
                    window.webkit.messageHandlers.privacyEvent.postMessage({event:'ad_blocked'});
                }
                if(el.className&&typeof el.className==='string'&&el.className.match(/(^|\\s)(ad[-_]|ads[-_]|adv[-_]|banner|sponsor|promo|ad_bottom|ad_center|appending_promo|adcenter)(\\s|$)/i)){
                    el.style.display='none';
                    window.webkit.messageHandlers.privacyEvent.postMessage({event:'ad_blocked'});
                }
                // Remove ins.adsbygoogle
                if(el.tagName==='INS'&&el.className&&el.className.indexOf('adsbygoogle')!==-1){
                    el.style.display='none';
                    window.webkit.messageHandlers.privacyEvent.postMessage({event:'ad_blocked'});
                }
            });
        });
    });
    if(document.body)adObserver.observe(document.body,{childList:true,subtree:true});

    new MutationObserver(scan).observe(document.body||document.documentElement,{childList:true,subtree:true});
    setTimeout(scan,800);setTimeout(scan,2500);setTimeout(scan,5000);
    // Periodic re-scan for dynamically loaded videos (YouTube, TikTok etc)
    setInterval(function(){
        document.querySelectorAll('video').forEach(function(v){
            if(!v.dataset.gsBtn)addDL(v);
            // If video is playing and has downloadable src, emit for snackbar
            if(!v.paused&&!v.dataset.gsEmitted){
                v.dataset.gsEmitted='1';
                var src=v.currentSrc||v.src||'';
                v.querySelectorAll('source').forEach(function(s){if(!src&&s.src)src=s.src;});
                if(src&&!src.startsWith('blob:')&&!src.startsWith('data:'))window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:src,type:src.includes('.m3u8')?'hls':'mp4',label:(v.videoHeight||'Auto')+'p'}],title:document.title,referer:location.href,thumb:v.poster||null});
            }
        });
    },3000);
    })();
    """
}

// MARK: - Notifications
extension Notification.Name {
    static let openInNewTab = Notification.Name("openInNewTab")
    static let startImmediateDownload = Notification.Name("startImmediateDownload")
    static let downloadCompleted = Notification.Name("downloadCompleted")
    static let downloadFailed = Notification.Name("downloadFailed")
}
