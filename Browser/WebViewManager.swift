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
                source: WebViewConfigurator.mainJS,
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
        // ★ HTTP validation
        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            if statusCode >= 400 {
                NotificationCenter.default.post(name: .downloadFailed, object: "서버 오류: HTTP \(statusCode)")
                return nil
            }
            // Reject HTML responses (login pages, error pages)
            if let mime = httpResponse.mimeType?.lowercased(), mime.contains("text/html") {
                NotificationCenter.default.post(name: .downloadFailed, object: "다운로드 실패: 서버가 영상 대신 웹페이지를 반환")
                return nil
            }
        }

        // Build filename: prefer title from activeWKDownloads, then suggested
        let title = activeWKDownloads[download] ?? suggestedFilename
        var filename = suggestedFilename
        if filename.isEmpty || filename == "Unknown" {
            let ext = (response as? HTTPURLResponse)?.mimeType?.contains("mp4") == true ? "mp4" : "mp4"
            filename = "\(title.prefix(50))_\(Int(Date().timeIntervalSince1970)).\(ext)"
        }
        filename = filename.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        pendingDownloadFilename = filename

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
        return dest
    }

    func downloadDidFinish(_ download: WKDownload) {
        let title = activeWKDownloads.removeValue(forKey: download) ?? pendingDownloadFilename ?? "파일"
        // Check file size
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        if let fname = pendingDownloadFilename {
            let filePath = dir.appendingPathComponent(fname)
            let size = (try? FileManager.default.attributesOfItem(atPath: filePath.path)[.size] as? Int) ?? 0
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            NotificationCenter.default.post(name: .downloadCompleted, object: "✅ \(title) 다운로드 완료 (\(sizeStr))")
        } else {
            NotificationCenter.default.post(name: .downloadCompleted, object: "✅ \(title) 다운로드 완료")
        }
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        activeWKDownloads.removeValue(forKey: download)
        let nsError = error as NSError
        let msg: String
        switch nsError.code {
        case NSURLErrorTimedOut: msg = "다운로드 시간 초과"
        case NSURLErrorNotConnectedToInternet: msg = "인터넷 연결 없음"
        case NSURLErrorCancelled: msg = "다운로드 취소됨"
        default: msg = "다운로드 실패: \(error.localizedDescription)"
        }
        NotificationCenter.default.post(name: .downloadFailed, object: msg)
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
        case "downloadVideo":
            guard let urlStr2 = dict["url"] as? String, let url2 = URL(string: urlStr2) else { return }
            if url2.scheme == "blob" || url2.scheme == "data" {
                NotificationCenter.default.post(name: .downloadFailed, object: "이 영상은 스트리밍 전용으로 직접 다운로드할 수 없습니다")
                return
            }
            // ★ 방법 1: WKWebView.startDownload — 브라우저 세션(쿠키/인증) 그대로 사용
            // 삼성 브라우저 / 알로하와 동일한 방식
            startWKDownload(url: url2, title: (dict["title"] as? String) ?? "Video")
        case "alohaDownload":
            guard let urlStr = dict["url"] as? String, let url = URL(string: urlStr) else { return }
            if urlStr == "__hide_overlay__" {
                // Debounce: 전체화면 종료 후 1.5초 뒤에 숨김 (즉시 숨기면 안 됨)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    FullscreenDownloadOverlay.shared.hide()
                }
                return
            }
            if url.scheme == "blob" || url.scheme == "data" {
                NotificationCenter.default.post(name: .downloadFailed, object: "이 영상은 스트리밍 전용입니다 (blob/MediaSource)")
                return
            }
            let title = (dict["title"] as? String) ?? url.deletingPathExtension().lastPathComponent
            let quality = (dict["quality"] as? String) ?? "Auto"
            let isFullscreen = (dict["fullscreen"] as? Bool) == true
            if isFullscreen {
                if let dm = downloadManager {
                    FullscreenDownloadOverlay.shared.show(url: url, title: title, quality: quality, downloadManager: dm)
                }
            } else {
                // ★ 방법 1: WKWebView.startDownload
                startWKDownload(url: url, title: title)
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

    // MARK: - Cookie Sync — ★ 쿠키를 먼저 동기화한 후 다운로드 시작
    func syncCookiesToDownloadManager() {
        guard let wv = webView, let dm = downloadManager else { return }
        wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let storage = HTTPCookieStorage.shared
            cookies.forEach { storage.setCookie($0) }
            dm.cookieStorage = storage
            // Also set on URLSession config
            dm.urlSession?.configuration.httpCookieStorage?.setCookies(cookies, for: wv.url, mainDocumentURL: nil)
        }
    }

    // ★ NEW: Download with cookies pre-loaded (async-safe)
    func downloadWithCookiesSync(media: DetectedMedia) {
        guard let wv = webView, let dm = downloadManager else { return }
        wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            // Cookies are ready NOW — start download
            DispatchQueue.main.async {
                dm.downloadWithCookies(media: media, cookies: cookies, saveToVault: false)
            }
        }
    }

    // MARK: - ★★★ WKWebView.startDownload — 핵심 다운로드 방법 ★★★
    // 삼성 브라우저 / 알로하와 동일: 브라우저 자체 네트워크 스택 사용
    // → 쿠키, 인증 토큰, Referer 자동 포함 → CDN이 정상 응답
    private var activeWKDownloads: [WKDownload: String] = [:]  // download → title

    func startWKDownload(url: URL, title: String) {
        guard let wv = webView else {
            // Fallback: WKWebView 참조 없으면 URLSession으로
            let media = DetectedMedia(url: url, type: url.absoluteString.contains(".m3u8") ? .hls : .mp4,
                quality: "Auto", title: title, referer: tab.url?.absoluteString ?? "",
                thumbnail: nil, estimatedSize: nil)
            downloadWithCookiesSync(media: media)
            return
        }

        // HLS는 URLSession으로 (m3u8 파싱 필요)
        if url.absoluteString.contains(".m3u8") {
            let media = DetectedMedia(url: url, type: .hls, quality: "HLS", title: title,
                referer: tab.url?.absoluteString ?? "", thumbnail: nil, estimatedSize: nil)
            downloadWithCookiesSync(media: media)
            return
        }

        // ★ MP4/WebM/MOV: WKWebView.startDownload — 브라우저 세션 그대로 사용
        var request = URLRequest(url: url)
        request.setValue(tab.url?.absoluteString ?? "", forHTTPHeaderField: "Referer")

        Task { @MainActor in
            do {
                let download = try await wv.startDownload(using: request)
                download.delegate = self
                activeWKDownloads[download] = title
                NotificationCenter.default.post(name: .downloadCompleted, object: "다운로드 시작: \(title)")
            } catch {
                // Fallback: WKDownload 실패 시 URLSession으로 재시도
                let media = DetectedMedia(url: url, type: .mp4, quality: "Auto", title: title,
                    referer: tab.url?.absoluteString ?? "", thumbnail: nil, estimatedSize: nil)
                downloadWithCookiesSync(media: media)
            }
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
        if #available(iOS 15.4, *) {
            config.preferences.isElementFullscreenEnabled = true
        }
        let uc = WKUserContentController()
        for name in ["mediaFound","alohaDownload","downloadVideo","blobCapture","elementHidden","privacyEvent"] {
            uc.add(coordinator, name: name)
        }
        if let fp = privacyEngine.fingerprintDefenseScript {
            uc.addUserScript(WKUserScript(source: fp, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        uc.addUserScript(WKUserScript(source: Self.earlyJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        uc.addUserScript(WKUserScript(source: Self.mainJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        config.userContentController = uc
        privacyEngine.contentBlocker.applyCachedRules(to: uc)
        return config
    }

    // ═══════════════════════════════════════════════════════════════
    // EARLY JS — Network interceptors + Performance API (DevTools Network 탭 방식)
    // ═══════════════════════════════════════════════════════════════
    static let earlyJS = """
    (function(){
    if(window.__gsE)return;window.__gsE=true;
    window.__gsURLs=window.__gsURLs||[];
    window.__gsVideoURLs=window.__gsVideoURLs||[];

    function E(u,t,l,n){
        if(!u||u.startsWith('blob:')||u.startsWith('data:'))return;
        // Resolve relative URLs
        try{u=new URL(u,location.href).href;}catch(e){return;}
        if(window.__gsURLs.indexOf(u)!==-1)return;
        window.__gsURLs.push(u);
        window.__gsVideoURLs.push({url:u,type:t||'mp4',label:l||'Auto',time:Date.now()});
        try{window.webkit.messageHandlers.mediaFound.postMessage({
            sources:[{url:u,type:t||'mp4',label:l||'Auto'}],
            title:n||document.title||'Media',referer:location.href,thumb:null
        });}catch(e){}
    }

    // ★ Pattern matching for video URLs
    var vidPat=/\\.(mp4|webm|m4v|mov|m3u8|ts|mpd)(\\?|#|$)/i;
    var cdnPat=/videoplayback|googlevideo|fbcdn.*video|cdninstagram.*video|twimg.*video|pbs\\.twimg|video-.*akamai|cloudfront.*video|vod.*akamaized/i;
    function isVideoURL(u){return vidPat.test(u)||cdnPat.test(u);}
    function typeFromURL(u){
        if(u.includes('.m3u8'))return 'hls';
        if(u.includes('.mpd'))return 'dash';
        if(u.includes('.ts')&&!u.includes('.tsinghua'))return 'ts';
        return 'mp4';
    }

    // ★★ PERFORMANCE API — 브라우저가 실제로 로드한 모든 리소스 URL 캡처 ★★
    // (DevTools Network 탭 → Media 필터와 동일한 원리)
    try{
        var perfObs=new PerformanceObserver(function(list){
            list.getEntries().forEach(function(entry){
                var u=entry.name;
                if(isVideoURL(u)){
                    E(u,typeFromURL(u),'Network:'+entry.initiatorType);
                }
            });
        });
        perfObs.observe({entryTypes:['resource']});
    }catch(e){}
    // Also scan existing resources
    try{
        performance.getEntriesByType('resource').forEach(function(entry){
            if(isVideoURL(entry.name)){
                E(entry.name,typeFromURL(entry.name),'Loaded:'+entry.initiatorType);
            }
        });
    }catch(e){}

    // ★ XHR intercept
    var _xo=XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open=function(m,u){
        if(typeof u==='string'&&isVideoURL(u))E(u,typeFromURL(u),'XHR');
        return _xo.apply(this,arguments);
    };

    // ★ Fetch intercept
    var _f=window.fetch;
    window.fetch=function(i){
        var u=typeof i==='string'?i:(i&&i.url?i.url:'');
        if(isVideoURL(u))E(u,typeFromURL(u),'Fetch');
        return _f.apply(this,arguments);
    };

    // ★ Blob URL intercept
    var _co=URL.createObjectURL.bind(URL);
    URL.createObjectURL=function(b){
        var u=_co(b);
        if(b&&b.type&&(b.type.startsWith('video/')||b.type.startsWith('audio/'))){
            try{var r=new FileReader();r.onload=function(e){
                try{window.webkit.messageHandlers.blobCapture.postMessage({data:e.target.result,mimeType:b.type});}catch(x){}
            };r.readAsDataURL(b.slice(0,50*1024*1024));}catch(e){}
        }
        return u;
    };

    // ★ HTMLMediaElement.src setter intercept — catch programmatic src changes
    try{
        var srcDesc=Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype,'src');
        if(srcDesc&&srcDesc.set){
            var origSet=srcDesc.set;
            Object.defineProperty(HTMLMediaElement.prototype,'src',{
                set:function(v){
                    if(v&&typeof v==='string'&&!v.startsWith('blob:')&&!v.startsWith('data:')){
                        if(isVideoURL(v))E(v,typeFromURL(v),'SrcSet');
                    }
                    return origSet.call(this,v);
                },
                get:srcDesc.get,
                configurable:true
            });
        }
    }catch(e){}
    })();
    """

    // ═══════════════════════════════════════════════════════════════
    // MAIN JS — UI buttons, fullscreen bar, scanner
    // ═══════════════════════════════════════════════════════════════
    static let mainJS = """
    (function(){
    if(window.__gsM)return;window.__gsM=true;
    window.__gsURLs=window.__gsURLs||[];
    window.__gsVideoURLs=window.__gsVideoURLs||[];

    function E(u,t,l,n){
        if(!u||u.startsWith('blob:')||u.startsWith('data:'))return;
        try{u=new URL(u,location.href).href;}catch(e){return;}
        if(window.__gsURLs.indexOf(u)!==-1)return;
        window.__gsURLs.push(u);
        window.__gsVideoURLs.push({url:u,type:t||'mp4',label:l||'Auto',time:Date.now()});
        try{window.webkit.messageHandlers.mediaFound.postMessage({
            sources:[{url:u,type:t||'mp4',label:l||'Auto'}],
            title:n||document.title||'Media',referer:location.href,thumb:null
        });}catch(e){}
    }

    // ★ Get best downloadable URL for a video element
    function bestSrc(v){
        // 1. Direct src (non-blob)
        var s=v.currentSrc||v.src||'';
        if(s&&!s.startsWith('blob:')&&!s.startsWith('data:'))return s;
        // 2. <source> elements
        var ss=v.querySelectorAll('source');
        for(var i=0;i<ss.length;i++){
            if(ss[i].src&&!ss[i].src.startsWith('blob:')&&!ss[i].src.startsWith('data:'))return ss[i].src;
        }
        // 3. Network-intercepted URLs (Performance API + XHR/fetch)
        // Use most recent video URL from our capture list
        if(window.__gsVideoURLs&&window.__gsVideoURLs.length>0){
            // Prefer m3u8 > mp4 > other
            var hlsURLs=window.__gsVideoURLs.filter(function(x){return x.type==='hls';});
            if(hlsURLs.length>0)return hlsURLs[hlsURLs.length-1].url;
            var mp4URLs=window.__gsVideoURLs.filter(function(x){return x.type==='mp4';});
            if(mp4URLs.length>0)return mp4URLs[mp4URLs.length-1].url;
            return window.__gsVideoURLs[window.__gsVideoURLs.length-1].url;
        }
        // 4. Re-scan Performance API right now
        try{
            var vidPat=/\\.(mp4|webm|m4v|mov|m3u8|ts)(\\?|#|$)/i;
            var cdnPat=/videoplayback|googlevideo|fbcdn.*video|cdninstagram.*video|twimg.*video/i;
            var entries=performance.getEntriesByType('resource');
            for(var j=entries.length-1;j>=0;j--){
                var name=entries[j].name;
                if(vidPat.test(name)||cdnPat.test(name))return name;
            }
        }catch(e){}
        return null;
    }

    // ★ Download button on each video
    function addBtn(v){
        if(v.dataset.gsB)return;v.dataset.gsB='1';
        var w=v.parentElement;if(!w)return;
        if(getComputedStyle(w).position==='static')w.style.position='relative';
        var b=document.createElement('div');
        b.innerHTML='\\u2B07';
        b.style.cssText='position:absolute;top:8px;right:8px;z-index:999999;background:rgba(0,180,140,0.92);border-radius:50%;width:40px;height:40px;display:flex;align-items:center;justify-content:center;cursor:pointer;box-shadow:0 2px 10px rgba(0,0,0,0.5);pointer-events:auto;font-size:20px;color:white;-webkit-backdrop-filter:blur(4px);';
        b.onclick=function(e){e.stopPropagation();e.preventDefault();
            var src=bestSrc(v);
            if(src){
                try{window.webkit.messageHandlers.downloadVideo.postMessage({url:src,title:document.title,quality:(v.videoHeight||'Auto')+'p'});}catch(x){}
                try{window.webkit.messageHandlers.alohaDownload.postMessage({url:src,title:document.title,quality:(v.videoHeight||'Auto')+'p'});}catch(x){}
                b.textContent='\\u2705';b.style.background='rgba(34,197,94,0.92)';
                setTimeout(function(){b.textContent='\\u2B07';b.style.background='rgba(0,180,140,0.92)';},2500);
            }else{
                b.textContent='\\u274C';b.style.background='rgba(220,50,50,0.92)';
                setTimeout(function(){b.textContent='\\u2B07';b.style.background='rgba(0,180,140,0.92)';},2500);
            }
        };
        b.ontouchend=function(e){e.stopPropagation();};
        w.appendChild(b);
        // Listen to media events to capture real src
        ['play','playing','loadeddata','canplay','loadedmetadata'].forEach(function(evt){
            v.addEventListener(evt,function(){var s=bestSrc(v);if(s)E(s,s.includes('.m3u8')?'hls':'mp4',(v.videoHeight||'Auto')+'p');},{once:true});
        });
    }

    // ★ Full page scan
    function scanAll(){
        document.querySelectorAll('video').forEach(function(v){
            addBtn(v);
            var s=bestSrc(v);if(s)E(s,s.includes('.m3u8')?'hls':'mp4',(v.videoHeight||'Auto')+'p');
        });
        document.querySelectorAll('img').forEach(function(img){
            if(!img.src||img.src.startsWith('data:'))return;
            var g=img.src.toLowerCase().indexOf('.gif')!==-1;
            if(img.naturalWidth>100||g)E(img.src,g?'gif':'image','Image',img.alt);
        });
        // JW Player
        if(typeof jwplayer!=='undefined'){document.querySelectorAll('[id]').forEach(function(el){try{
            var p=jwplayer(el.id);if(!p||!p.getState)return;
            function ex(){var it=p.getPlaylistItem()||{};(it.sources||[]).forEach(function(s){if(s.file)E(s.file,s.file.includes('.m3u8')?'hls':'mp4',s.label||'JW');});}
            p.on('ready',ex);p.on('playlistItem',ex);if(p.getState()!=='idle')ex();
        }catch(e){}});}
        // Re-scan Performance API
        try{
            var vidPat=/\\.(mp4|webm|m4v|mov|m3u8|ts)(\\?|#|$)/i;
            var cdnPat=/videoplayback|googlevideo|fbcdn.*video|cdninstagram.*video|twimg.*video/i;
            performance.getEntriesByType('resource').forEach(function(entry){
                if(vidPat.test(entry.name)||cdnPat.test(entry.name)){
                    E(entry.name,entry.name.includes('.m3u8')?'hls':'mp4','PerfScan');
                }
            });
        }catch(e){}
    }

    // ★ Fullscreen events → tell native to show UIWindow overlay
    document.addEventListener('webkitbeginfullscreen',function(e){
        if(e.target&&e.target.tagName==='VIDEO'){
            var src=bestSrc(e.target);
            if(src){
                try{window.webkit.messageHandlers.alohaDownload.postMessage({url:src,title:document.title,quality:(e.target.videoHeight||'Auto')+'p',fullscreen:true});}catch(x){}
            }
        }
    },true);
    // ★ webkitendfullscreen REMOVED — this fires when iOS system player takes over,
    // causing the overlay to hide after 1 second. Overlay now only hides via X button.
    // CSS Fullscreen API
    function onFSChange(){
        var el=document.fullscreenElement||document.webkitFullscreenElement;
        if(el){
            var v=el.tagName==='VIDEO'?el:el.querySelector('video');
            if(v){
                var src=bestSrc(v);
                if(src){
                    try{window.webkit.messageHandlers.alohaDownload.postMessage({url:src,title:document.title,quality:(v.videoHeight||'Auto')+'p',fullscreen:true});}catch(x){}
                }
            }
        }else{
            try{window.webkit.messageHandlers.alohaDownload.postMessage({url:'__hide_overlay__',title:'',quality:'',fullscreen:false});}catch(x){}
        }
    }
    document.addEventListener('fullscreenchange',onFSChange);
    document.addEventListener('webkitfullscreenchange',onFSChange);

    // ★ Element hider
    var hm=false,hl=null;
    window._gsToggleHideMode=function(){hm=!hm;if(!hm&&hl){hl.style.outline='';hl=null;}return hm;};
    document.addEventListener('touchstart',function(e){if(!hm)return;e.preventDefault();e.stopPropagation();
        var el=document.elementFromPoint(e.touches[0].clientX,e.touches[0].clientY);
        if(!el||el===document.body)return;if(hl)hl.style.outline='';hl=el;el.style.outline='3px solid #FF4757';},{passive:false,capture:true});
    document.addEventListener('touchend',function(e){if(!hm||!hl)return;e.preventDefault();e.stopPropagation();
        var el=hl,sel='';if(el.id)sel='#'+el.id;else{var p=[];var c=el;while(c&&c!==document.body){var t=c.tagName.toLowerCase();
        if(c.className&&typeof c.className==='string'){var cls=c.className.trim().split(/\\s+/).filter(function(x){return x.length>0;}).slice(0,2).join('.');if(cls)t+='.'+cls;}
        p.unshift(t);c=c.parentElement;}sel=p.join('>');}
        el.style.display='none';el.style.outline='';hl=null;
        try{window.webkit.messageHandlers.elementHidden.postMessage({selector:sel});}catch(x){}},{passive:false,capture:true});

    // Context menu
    document.addEventListener('contextmenu',function(e){
        var el=e.target;
        if(el.tagName==='IMG'&&el.src)E(el.src,el.src.toLowerCase().indexOf('.gif')!==-1?'gif':'image','Image',el.alt);
        if(el.tagName==='VIDEO'||(el.closest&&el.closest('video'))){var v=el.tagName==='VIDEO'?el:el.closest('video');var s=bestSrc(v);
            if(s)try{window.webkit.messageHandlers.alohaDownload.postMessage({url:s,title:document.title,quality:(v.videoHeight||'Auto')+'p'});}catch(x){}}
    },true);

    // ★ Ad removal
    new MutationObserver(function(muts){muts.forEach(function(m){m.addedNodes.forEach(function(n){
        if(n.nodeType!==1)return;
        if(n.tagName==='IFRAME'){var s=n.src||'';if(s.match(/ad[.s]|doubleclick|googlesyndication|adfit|cauly|mobon|adpopcorn|realclick|admixer/i)){n.style.display='none';n.remove();try{window.webkit.messageHandlers.privacyEvent.postMessage({event:'ad_blocked'});}catch(x){}}}
        if(n.id&&n.id.match(/^(ad[-_]|ads[-_]|adv[-_]|banner|sponsor|dcAd|google_ads)/i)){n.style.display='none';try{window.webkit.messageHandlers.privacyEvent.postMessage({event:'ad_blocked'});}catch(x){}}
        if(n.className&&typeof n.className==='string'&&n.className.match(/(^|\\s)(ad[-_]|ads[-_]|adv[-_]|banner|sponsor|promo|ad_bottom|ad_center|appending_promo|adcenter)(\\s|$)/i)){n.style.display='none';try{window.webkit.messageHandlers.privacyEvent.postMessage({event:'ad_blocked'});}catch(x){}}
        if(n.tagName==='INS'&&n.className&&n.className.indexOf('adsbygoogle')!==-1){n.style.display='none';try{window.webkit.messageHandlers.privacyEvent.postMessage({event:'ad_blocked'});}catch(x){}}
        if(n.tagName==='VIDEO')addBtn(n);
        if(n.querySelectorAll)n.querySelectorAll('video').forEach(addBtn);
    });});}).observe(document.body||document.documentElement,{childList:true,subtree:true});

    // ★ Run + periodic rescan
    scanAll();setTimeout(scanAll,1000);setTimeout(scanAll,3000);setTimeout(scanAll,6000);
    setInterval(function(){
        document.querySelectorAll('video').forEach(function(v){
            if(!v.dataset.gsB)addBtn(v);
            if(!v.paused&&!v.dataset.gsE2){v.dataset.gsE2='1';var s=bestSrc(v);if(s)E(s,s.includes('.m3u8')?'hls':'mp4',(v.videoHeight||'Auto')+'p');}
        });
        // Re-scan Performance API periodically
        try{
            var vidPat=/\\.(mp4|webm|m4v|mov|m3u8|ts)(\\?|#|$)/i;
            var cdnPat=/videoplayback|googlevideo|fbcdn.*video|cdninstagram.*video|twimg.*video/i;
            performance.getEntriesByType('resource').forEach(function(entry){
                if(vidPat.test(entry.name)||cdnPat.test(entry.name)){
                    E(entry.name,entry.name.includes('.m3u8')?'hls':'mp4','Periodic');
                }
            });
        }catch(e){}
    },4000);
    })();
    """
}

// MARK: - Notifications
extension Notification.Name {
    static let openInNewTab = Notification.Name("openInNewTab")
    static let startImmediateDownload = Notification.Name("startImmediateDownload")
    static let downloadCompleted = Notification.Name("downloadCompleted")
    static let downloadFailed = Notification.Name("downloadFailed")
    static let wkDownloadRequested = Notification.Name("wkDownloadRequested")
}
