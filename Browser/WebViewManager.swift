// Browser/WebViewManager.swift
import SwiftUI
import GhostStreamCore
import WebKit
import Photos

final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate, @unchecked Sendable {
    let tab: Tab
    let privacyEngine: PrivacyEngine
    let onMediaDetected: (DetectedMedia) -> Void
    private var pendingDownloadFilename: String?

    var downloadManager: MediaDownloadManager?
    var bookmarkManager: BookmarkManager?
    weak var webView: WKWebView?   // set by BrowserWebView for cookie forwarding

    // CF: tracks domains where we've stripped fingerprint defense scripts
    private var cfStrippedDomains: Set<String> = []
    private var cfReloadPending = false
    private var pendingContextImageURL: URL? // ★ F3: 이미지 꾹 눌러서 저장용

    init(tab: Tab, privacyEngine: PrivacyEngine, onMediaDetected: @escaping (DetectedMedia) -> Void) {
        self.tab = tab; self.privacyEngine = privacyEngine; self.onMediaDetected = onMediaDetected
    }

    // MARK: - Navigation
    func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) {
        tab.isLoading = true; tab.isSecure = w.url?.scheme == "https"; tab.privacyReport.isHTTPS = tab.isSecure
        // ★ F4 FIX: 네비게이션 시작 시에도 canGoBack/Forward 즉시 갱신
        tab.canGoBack = w.canGoBack; tab.canGoForward = w.canGoForward
    }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        tab.isLoading = false; tab.title = w.title ?? ""; tab.url = w.url
        tab.canGoBack = w.canGoBack; tab.canGoForward = w.canGoForward

        // ★ 자동 방문 기록
        if let url = w.url, !tab.isPrivate,
           url.scheme == "https" || url.scheme == "http" {
            bookmarkManager?.addHistory(title: w.title ?? url.host ?? "", url: url)
        }

        // ★ 탭 썸네일 캡처
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 200
        w.takeSnapshot(with: config) { [weak self] image, _ in
            DispatchQueue.main.async { self?.tab.thumbnail = image }
        }
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
                source: PrivacyScripts.mainJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
            // ★ CF FIX: 데스크톱 모드에서 CF 감지 시 모바일 UA로 복원
            if DeviceProfileManager.shared.isDesktopMode {
                w.customUserAgent = DeviceProfileManager.shared.currentProfile.userAgent
            }
            // Now reload — CF will see real Safari fingerprint → pass
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { w.reload() }
        }
    }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: any Error) { tab.isLoading = false }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: any Error) { tab.isLoading = false }

    // MARK: - Block App Store redirects (PikPak 등)
    // ★ F3 FIX: 최소한의 차단만 — 기본 동작 유지
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
        let scheme = url.scheme?.lowercased() ?? ""
        // 앱 스토어/커스텀 스킴만 차단 (http/https는 항상 허용)
        if ["itms-apps", "itms-appss", "itms", "intent", "pikpak", "market"].contains(scheme) {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - Intercept media responses → WKDownload
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let url = navigationResponse.response.url
        let mime = navigationResponse.response.mimeType ?? ""
        let ext = url?.pathExtension.lowercased() ?? ""
        
        // ★ F2/F3 FIX: 미디어/파일 다운로드 (이미지는 제외 — 네비게이션 시 표시만)
        let downloadExts = [
            // 영상/오디오
            "mp4","m4v","mov","webm","mp3","m4a","flac","wav","ogg","aac",
            // 압축 파일
            "zip","rar","7z","tar","gz","bz2",
            // 문서
            "pdf","doc","docx","xls","xlsx","ppt","pptx","hwp",
            // 기타
            "apk","ipa","dmg","exe","iso","torrent"
            // ★ 이미지는 제외 (png/jpg/gif → 브라우저에서 표시, 사용자가 꾹 눌러 저장)
        ]
        if downloadExts.contains(ext) {
            decisionHandler(.download)
            return
        }
        
        // Video/Audio MIME type in main frame → trigger WKDownload  
        if (mime.hasPrefix("video/") || mime.hasPrefix("audio/")) && navigationResponse.isForMainFrame {
            decisionHandler(.download)
            return
        }

        // ★ Content-Disposition: attachment → 무조건 다운로드
        if let httpResponse = navigationResponse.response as? HTTPURLResponse,
           let contentDisp = httpResponse.value(forHTTPHeaderField: "Content-Disposition"),
           contentDisp.lowercased().contains("attachment") {
            decisionHandler(.download)
            return
        }

        // ★ 바이너리 MIME → 다운로드 (application/octet-stream, application/zip 등)
        let downloadMimes = ["application/octet-stream", "application/zip", "application/x-rar",
                             "application/x-7z-compressed", "application/pdf",
                             "application/x-gzip", "application/x-tar",
                             "application/vnd.android.package-archive"]
        if downloadMimes.contains(mime.lowercased()) && navigationResponse.isForMainFrame {
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
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        if let fname = pendingDownloadFilename {
            let filePath = dir.appendingPathComponent(fname)
            let size = (try? FileManager.default.attributesOfItem(atPath: filePath.path)[.size] as? Int) ?? 0
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)

            // ★ 자동 갤러리 저장 (피드백 1)
            let ext = filePath.pathExtension.lowercased()
            let isVideo = ["mp4","m4v","mov","webm"].contains(ext)
            let isImage = ["jpg","jpeg","png","webp","heic","gif"].contains(ext)
            if (isVideo || isImage) && size > 1024 {
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    guard status == .authorized || status == .limited else { return }
                    var placeholder: PHObjectPlaceholder?
                    PHPhotoLibrary.shared().performChanges({
                        let req = PHAssetCreationRequest.forAsset()
                        placeholder = req.placeholderForCreatedAsset
                        if isVideo {
                            req.addResource(with: .video, fileURL: filePath, options: nil)
                        } else if ext == "gif", let data = try? Data(contentsOf: filePath) {
                            req.addResource(with: .photo, data: data, options: nil)
                        } else if let data = try? Data(contentsOf: filePath) {
                            req.addResource(with: .photo, data: data, options: nil)
                        }
                    }) { success, _ in
                        DispatchQueue.main.async {
                            if success {
                                // ★ PHAsset localIdentifier 저장 (나중에 정확한 삭제용)
                                if let id = placeholder?.localIdentifier {
                                    GalleryAssetTracker.shared.track(filename: fname ?? "", assetID: id)
                                }
                                NotificationCenter.default.post(name: .downloadCompleted,
                                    object: "✅ \(title) 다운로드 + 갤러리 저장 완료 (\(sizeStr))")
                            } else {
                                NotificationCenter.default.post(name: .downloadCompleted,
                                    object: "✅ \(title) 다운로드 완료 (\(sizeStr)) — 갤러리 저장은 수동으로")
                            }
                        }
                    }
                }
            } else {
                NotificationCenter.default.post(name: .downloadCompleted, object: "✅ \(title) 다운로드 완료 (\(sizeStr))")
            }
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

    // MARK: - Pull-to-Refresh
    @objc func handlePullToRefresh(_ sender: UIRefreshControl) {
        webView?.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            sender.endRefreshing()
        }
    }

    // MARK: - Context Menu (long-press)
    func webView(_ webView: WKWebView, contextMenuConfigurationFor elementInfo: WKContextMenuElementInfo) async -> UIContextMenuConfiguration? {
        let linkURL = elementInfo.linkURL

        // ★ F2 FIX: 링크가 없으면 iOS 기본 메뉴 사용 (Save Photo 등 네이티브)
        guard let linkURL = linkURL else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIAction] = []

            actions.append(UIAction(title: "새 탭에서 열기", image: UIImage(systemName: "plus.square.on.square")) { _ in
                NotificationCenter.default.post(name: .openInNewTab, object: linkURL)
            })
            let ext = linkURL.pathExtension.lowercased()
            if ["mp4","m4v","mov","webm","gif","m3u8","png","jpg","jpeg","webp","zip","rar","pdf"].contains(ext) {
                actions.append(UIAction(title: "다운로드", image: UIImage(systemName: "arrow.down.circle.fill")) { [weak self] _ in
                    self?.startWKDownload(url: linkURL, title: linkURL.deletingPathExtension().lastPathComponent)
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
                switch ev {
                case "fingerprint_attempt":
                    tab.privacyReport.fingerprintAttempts += 1
                    privacyEngine.totalFingerprintDefenses += 1
                case "tracker_blocked":
                    tab.privacyReport.trackersBlocked += 1
                    privacyEngine.totalTrackersBlocked += 1
                case "ad_blocked":
                    tab.privacyReport.adsBlocked += 1
                    privacyEngine.totalAdsBlocked += 1
                default: break
                }
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
        uc.addUserScript(WKUserScript(source: PrivacyScripts.earlyJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        uc.addUserScript(WKUserScript(source: PrivacyScripts.mainJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        config.userContentController = uc
        privacyEngine.contentBlocker.applyCachedRules(to: uc)
        return config
    }

}

// MARK: - Gallery Asset Tracker (갤러리 저장 시 PHAsset ID 추적)
final class GalleryAssetTracker {
    static let shared = GalleryAssetTracker()
    private var map: [String: String] = [:] // filename → PHAsset localIdentifier

    func track(filename: String, assetID: String) {
        map[filename] = assetID
    }

    func assetID(for filename: String) -> String? {
        return map[filename]
    }

    func remove(filename: String) {
        map.removeValue(forKey: filename)
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let openInNewTab = Notification.Name("openInNewTab")
    static let startImmediateDownload = Notification.Name("startImmediateDownload")
    static let downloadCompleted = Notification.Name("downloadCompleted")
    static let downloadFailed = Notification.Name("downloadFailed")
    static let wkDownloadRequested = Notification.Name("wkDownloadRequested")
}
