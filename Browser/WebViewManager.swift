// Browser/WebViewManager.swift
import SwiftUI
import GhostStreamCore
import WebKit
import Photos
final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate, @unchecked Sendable {
    let tab: Tab
    let privacyEngine: PrivacyEngine
    let onMediaDetected: (DetectedMedia) -> Void
    private var pendingDownloadFilenames: [WKDownload: String] = [:] // ★ per-download filename tracking
    private var recentlyDownloadedURLs: Set<String> = [] // ★ F3: 중복 다운로드 방지
    var downloadManager: MediaDownloadManager?
    var bookmarkManager: BookmarkManager?
    weak var webView: WKWebView?   // set by BrowserWebView for cookie forwarding
    var downloadObserver: NSObjectProtocol?  // ★ NotificationCenter observer token
    var rulesObserver: NSObjectProtocol?  // ★ 광고 규칙 재적용 observer
    var lastUserInteraction: TimeInterval = 0  // ★ 사용자 제스처 시각 (납치광고 차단용)
    var cfChallengeActive: Bool = false  // ★ CF 챌린지 진행 중 (리다이렉트 차단 해제)
    static var programmaticNavigationUntil: TimeInterval = 0  // ★ 앱이 직접 시작한 네비게이션 표시
    /// ★ 현재(가장 최근) 메인 프레임 응답이 CF 챌린지였는지 — navigationResponse 헤더 기준
    ///   (cf-mitigated: challenge). 이 문서에는 어떤 JS도 넣지 않는다.
    private(set) var cfChallengeResponse = false
    private var reloadPending = false
    private var pendingContextImageURL: URL? // ★ F3: 이미지 꾹 눌러서 저장용
    init(tab: Tab, privacyEngine: PrivacyEngine, onMediaDetected: @escaping (DetectedMedia) -> Void) {
        self.tab = tab; self.privacyEngine = privacyEngine; self.onMediaDetected = onMediaDetected
    }
    // MARK: - Navigation
    func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) {
        // 새 네비게이션 — 응답 헤더를 받기 전까지는 CF 여부 미정
        cfChallengeResponse = false
        tab.isLoading = true; tab.isSecure = w.url?.scheme == "https"; tab.privacyReport.isHTTPS = tab.isSecure
        // 네비게이션 시작 시에도 canGoBack/Forward 즉시 갱신
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
        // ★ 응답 헤더로 CF 챌린지가 확인된 문서 → 아무것도 주입하지 않고 끝 (요소 숨김 CSS 포함)
        //   (핑거프린팅 방어 금지, CF 자동 처리 reload도 금지 → 루프 원천 차단)
        if cfChallengeResponse {
            cfChallengeActive = true
            return
        }
        // Reapply element hider rules (host+path 기반)
        if let host = w.url?.host {
            let rules = ElementHiderStore.shared.rules(for: host, path: w.url?.path)
            if !rules.isEmpty {
                let escapedCSS = rules.joined(separator: ",").replacingOccurrences(of: "'", with: "\\'")
                w.evaluateJavaScript("var s=document.createElement('style');s.textContent='\(escapedCSS){display:none!important}';document.head.appendChild(s);")
            }
        }
        // ★ 진단: CF 자동 처리 꺼짐 → 리로드/스크립트 제거는 하지 않음
        //   단, 핑거프린팅 방어는 CF 페이지에 절대 주입하면 안 된다.
        //   (Canvas/WebGL 스푸핑이 CF에게 봇 신호로 잡힘)
        //   v2.0.5: 도메인당 1회 → 매 페이지 로드마다 (CF가 아닐 때만)
        guard DiagnosticMode.cfHandlingEnabled else {
            injectFingerprintDefenseIfSafe(w)
            return
        }
        guard !reloadPending else {
            reloadPending = false
            let uc = w.configuration.userContentController
            uc.removeAllUserScripts()
            uc.addUserScript(WKUserScript(source: PrivacyScripts.earlyJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
            uc.addUserScript(WKUserScript(source: PrivacyScripts.mainJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
            return
        }
        // ★ CF 감지 — 단, '검증 진행 중'이면 방해하지 않음
        // 검증 중(Turnstile 스피너)에 reload를 걸면 검증이 중단되어 무한 반복됨
        w.evaluateJavaScript("""
        (function(){
            var t = document.title || '';
            // 언어 무관 CF 신호 우선 (제목은 로케일마다 다름)
            var sig = (typeof window._cf_chl_opt !== 'undefined')
                || (typeof window.__CF$cv$params !== 'undefined')
                || !!document.querySelector('script[src*="/cdn-cgi/challenge-platform/"]');
            var isCF = (sig
                || t === 'Just a moment...'
                || t.indexOf('Checking your browser') !== -1
                || t.indexOf('Attention Required') !== -1
                || t.indexOf('보안 확인') !== -1
                || t.indexOf('잠시만 기다') !== -1
                || !!document.querySelector('#challenge-form,.cf-browser-verification,#cf-wrapper,#cf-challenge-running')
                || location.hostname === 'challenges.cloudflare.com');
            if (!isCF) return '0';
            // Turnstile 위젯이 살아있고 검증 중이면 → 건드리지 않음
            var widget = document.querySelector('#challenge-stage, .cf-turnstile, iframe[src*="challenges.cloudflare.com"]');
            if (widget) return 'verifying';
            return '1';
        })()
        """) { [weak self, weak w] result, _ in
            guard let self = self, let w = w, let str = result as? String else { return }
            if str == "verifying" {
                // ★ CF가 정상 검증 중 → 아무것도 하지 않고 완료를 기다림
                self.cfChallengeActive = true
                return
            }
            if str == "1" {
                self.cfChallengeActive = true
                // ★ CF 감지 → handledDomains 상관없이 항상 처리
                self.reloadPending = true
                let uc = w.configuration.userContentController
                uc.removeAllUserScripts()
                uc.addUserScript(WKUserScript(
                    source: PrivacyScripts.mainJS,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                ))
                if DeviceProfileManager.shared.isDesktopMode {
                    w.customUserAgent = DeviceProfileManager.shared.currentProfile.userAgent
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { w.reload() }
            } else {
                // ★ CF 아닌 정상 페이지 도달 → 챌린지 종료
                self.cfChallengeActive = false
                // 비CF 페이지 → 매 로드마다 핑거프린팅 방어 주입 (진단 토글)
                self.injectFingerprintDefenseIfSafe(w)
            }
        }
    }

    // MARK: - Fingerprint defense (매 페이지, CF 페이지 제외)
    /// CF 신호 확인과 주입을 **한 번의 evaluateJavaScript 안에서** 수행한다.
    /// (확인 후 별도 호출로 주입하면 그 사이 문서가 바뀌는 경쟁 조건이 생김)
    /// window.__gsFP 가드로 같은 문서에 이중 주입(프로토타입 이중 래핑)을 막는다.
    private func injectFingerprintDefenseIfSafe(_ w: WKWebView) {
        guard DiagnosticMode.fingerprintDefenseEnabled, !cfChallengeResponse,
              let fp = privacyEngine.fingerprintDefenseScript else { return }
        w.evaluateJavaScript("""
        (function(){
            var t = document.title || '';
            var h = location.hostname || '';
            var sig = (typeof window._cf_chl_opt !== 'undefined')
                || (typeof window.__CF$cv$params !== 'undefined')
                || !!document.querySelector('script[src*="/cdn-cgi/challenge-platform/"]')
                || !!document.querySelector('iframe[src*="challenges.cloudflare.com"]')
                || !!document.querySelector('#challenge-form,#challenge-stage,#challenge-running,.cf-turnstile,#cf-wrapper,.cf-browser-verification');
            var isCF = (sig
                || t === 'Just a moment...'
                || t.indexOf('Checking your browser') !== -1
                || t.indexOf('Attention Required') !== -1
                || t.indexOf('보안 확인') !== -1
                || h.indexOf('challenges.cloudflare.com') !== -1);
            if (isCF) return '1';
            if (window.__gsFP) return '2';
            window.__gsFP = true;
            \(fp)
            return '0';
        })()
        """)
    }

    // MARK: - CF challenge detection by response header
    /// Cloudflare가 챌린지 페이지를 응답할 때 붙이는 문서화된 헤더: `cf-mitigated: challenge`.
    /// 보조 신호: Server: cloudflare + 403/503 + HTML (구형 IUAM/차단 페이지).
    /// 차단 페이지를 CF로 오인해도 결과는 "그 문서에 스크립트 미주입"뿐이라 무해하다.
    static func isCloudflareChallenge(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else { return false }
        if let mitigated = http.value(forHTTPHeaderField: "cf-mitigated"),
           mitigated.lowercased().contains("challenge") {
            return true
        }
        let server = http.value(forHTTPHeaderField: "Server")?.lowercased() ?? ""
        let mime = http.mimeType?.lowercased() ?? ""
        return server.contains("cloudflare")
            && (http.statusCode == 403 || http.statusCode == 503)
            && mime.contains("html")
    }

    /// 메인 프레임 응답마다 호출: CF 챌린지 문서면 user script를 전부 빼고,
    /// 아니면 (진단 토글이 켜져 있을 때) earlyJS/mainJS를 복원한다.
    /// - 결정 핸들러 호출 **전에** 실행 → 커밋될 새 문서의 documentStart 주입에 반영됨.
    /// - reload/load/취소를 절대 하지 않는다 (상태만 맞춤) → 루프 불가.
    /// - 이미 원하는 상태면 아무것도 안 함 (멱등).
    private func applyUserScriptPolicy(to w: WKWebView, isCFChallenge: Bool) {
        cfChallengeResponse = isCFChallenge
        let uc = w.configuration.userContentController
        if isCFChallenge {
            cfChallengeActive = true
            if !uc.userScripts.isEmpty { uc.removeAllUserScripts() }
            return
        }
        // CF 자동 처리(진단, 기본 OFF)가 reload를 진행 중이면 그쪽이 스크립트를 관리한다
        guard DiagnosticMode.contentScriptsEnabled, !reloadPending else { return }
        let sources = uc.userScripts.map { $0.source }
        let hasEarly = sources.contains(PrivacyScripts.earlyJS)
        let hasMain = sources.contains(PrivacyScripts.mainJS)
        guard !(hasEarly && hasMain) else { return }
        uc.removeAllUserScripts()
        uc.addUserScript(WKUserScript(source: PrivacyScripts.earlyJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        uc.addUserScript(WKUserScript(source: PrivacyScripts.mainJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
    }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: any Error) { tab.isLoading = false }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: any Error) { tab.isLoading = false }
    // MARK: - Redirect Hijack Blocking + App Store scheme blocking
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
        let scheme = url.scheme?.lowercased() ?? ""
        // 앱 스토어 강제 이동만 차단
        if ["itms-apps", "itms-appss", "itms", "intent", "pikpak", "market"].contains(scheme) {
            decisionHandler(.cancel)
            return
        }
        // tel/sms/mailto 등은 시스템이 처리
        if ["tel", "sms", "mailto", "facetime"].contains(scheme) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }
        // ★ http/https는 항상 허용 (v1.7.2 동작 복원)
        //   여기서 리다이렉트를 판정하면 CF 챌린지 통과 이동까지 막혀
        //   무한 루프가 발생한다. 납치광고는 createWebViewWith에서만 처리.
        // ★ QA: <a download> / blob: 다운로드 링크는 표시가 아니라 다운로드로 (iOS 14.5+)
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - Intercept media responses → WKDownload
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // ★ v2.0.5: CF 챌린지 응답(cf-mitigated: challenge) → 이 문서에는 user script 없음.
        //   정책 결정(.allow 등)은 아래 기존 로직 그대로 — 여기서는 취소/리로드하지 않는다.
        if navigationResponse.isForMainFrame {
            applyUserScriptPolicy(to: webView,
                                  isCFChallenge: Self.isCloudflareChallenge(navigationResponse.response))
        }
        let url = navigationResponse.response.url
        let mime = navigationResponse.response.mimeType ?? ""
        let ext = url?.pathExtension.lowercased() ?? ""
        // ★ QA: 쿼리를 잘라 비교하던 '최근 다운로드' 게이트 제거 — download.php?id=1 / ?id=2 가 같은 URL로 취급되어
        //   두 번째 파일이 다운로드 대신 웹뷰 표시로 빠지던 문제. 사용자가 직접 연 링크는 항상 정책대로 처리한다.
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
        // ★ GoFile/파일 호스팅 다운로드 URL 패턴
        let host = url?.host?.lowercased() ?? ""
        if host.contains("gofile.io") && (url?.path.contains("/download") == true || url?.path.contains("/dl") == true) {
            decisionHandler(.download)
            return
        }
        // 기타 파일 호스팅 직접 다운로드 패턴
        if host.contains("mediafire.com") || host.contains("mega.nz") || host.contains("pixeldrain.com") {
            if mime.contains("octet-stream") || mime.contains("application/") {
                decisionHandler(.download)
                return
            }
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
        // ★ QA: WebView가 표시할 수 없는 MIME(main frame)은 다운로드 (빈 화면 방지)
        if navigationResponse.isForMainFrame && !navigationResponse.canShowMIMEType {
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
        let src = navigationResponse.response.url
        let title = src?.lastPathComponent.removingPercentEncoding ?? src?.lastPathComponent ?? "파일"
        downloadManager?.trackWebKitDownload(download, title: title, sourceURL: src)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
        let src = navigationAction.request.url
        let title = src?.lastPathComponent.removingPercentEncoding ?? src?.lastPathComponent ?? "파일"
        downloadManager?.trackWebKitDownload(download, title: title, sourceURL: src)
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        // ★ HTTP validation
        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            if statusCode >= 400 {
                NotificationCenter.default.post(name: .downloadFailed, object: "서버 오류: HTTP \(statusCode)")
                return nil
            }
            // Reject HTML/JSON responses (login pages, error pages)
            let srcExt = response.url?.pathExtension.lowercased() ?? ""
            if let mime = httpResponse.mimeType?.lowercased(),
               (mime.contains("text/html") || mime == "application/json"),
               !["html", "htm", "json"].contains(srcExt) {
                downloadManager?.finishWebKitDownload(download, fileURL: nil, errorMessage: "서버가 파일 대신 웹페이지를 반환")
                NotificationCenter.default.post(name: .downloadFailed, object: "다운로드 실패: 서버가 파일 대신 웹페이지를 반환")
                return nil
            }
        }
        // ★ QA: 공통 규칙 (Content-Disposition filename* 한글 → 제목(영상) → suggestedFilename → URL) + 확장자 보정
        let title = activeWKDownloads[download] ?? ""
        let mime = response.mimeType?.lowercased() ?? ""
        let filename = DownloadFileNaming.resolveFilename(response: response, suggested: suggestedFilename, title: title,
                                                          sourceURL: response.url,
                                                          preferTitle: !title.isEmpty && mime.hasPrefix("video/"))
        // ★ QA: 같은 이름이 있으면 지우지 않고 "이름 (1).ext" — 이전 다운로드 덮어쓰기/동시 다운로드 충돌 방지
        let dest = DownloadFileNaming.reserveUniqueURL(in: MediaDownloadManager.downloadDirectory, filename: filename)
        pendingDownloadFilenames[download] = dest.lastPathComponent
        return dest
    }
    func downloadDidFinish(_ download: WKDownload) {
        let title = activeWKDownloads.removeValue(forKey: download) ?? pendingDownloadFilenames[download] ?? "파일"
        let fname = pendingDownloadFilenames.removeValue(forKey: download)
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        if let fname = fname {
            let filePath = dir.appendingPathComponent(fname)
            DownloadFileNaming.releaseReservation(filePath)
            let size = MediaDownloadManager.fileSize(filePath)
            // ★ 빈 파일 또는 (MIME 위장) 에러 페이지 감지
            let ext = filePath.pathExtension.lowercased()
            let isHTML = !["html", "htm"].contains(ext) && DownloadFileNaming.looksLikeHTML(fileAt: filePath)
            if size < MediaDownloadManager.minimumValidFileSize || isHTML {
                try? FileManager.default.removeItem(at: filePath)
                let msg = isHTML ? "다운로드 실패: 서버가 파일 대신 웹페이지를 반환" : "다운로드 실패: 파일이 비어 있음"
                downloadManager?.finishWebKitDownload(download, fileURL: nil, errorMessage: msg)
                NotificationCenter.default.post(name: .downloadFailed, object: msg)
                return
            }
            let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            // ★ QA: EXIF/GPS 제거는 MediaDownloadManager가 백그라운드에서 수행(실패 시 토스트) — 메인 스레드 동기 처리 제거
            downloadManager?.finishWebKitDownload(download, fileURL: filePath, errorMessage: nil)
            NotificationCenter.default.post(name: .downloadCompleted,
                object: "✅ \(title) 다운로드 완료 (\(sizeStr))")
        } else {
            NotificationCenter.default.post(name: .downloadCompleted, object: "✅ \(title) 다운로드 완료")
        }
    }
    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        activeWKDownloads.removeValue(forKey: download)
        // ★ 불완전 파일 정리
        if let fname = pendingDownloadFilenames.removeValue(forKey: download) {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Downloads", isDirectory: true)
            let file = dir.appendingPathComponent(fname)
            DownloadFileNaming.releaseReservation(file)
            try? FileManager.default.removeItem(at: file)
        }
        let nsError = error as NSError
        let msg: String
        switch nsError.code {
        case NSURLErrorTimedOut: msg = "다운로드 시간 초과"
        case NSURLErrorNotConnectedToInternet: msg = "인터넷 연결 없음"
        case NSURLErrorCancelled: msg = "다운로드 취소됨"
        default: msg = "다운로드 실패: \(error.localizedDescription)"
        }
        downloadManager?.finishWebKitDownload(download, fileURL: nil, errorMessage: msg)
        NotificationCenter.default.post(name: .downloadFailed, object: msg)
    }
    // MARK: - New window (target=_blank / window.open)
    func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // ★ v1.7.2 동작 복원 — CF가 창을 여는 경우를 막지 않음
        // 사용자 클릭이면 새 탭, 그 외에는 현재 창에서 처리
        if a.navigationType == .linkActivated, let url = a.request.url {
            NotificationCenter.default.post(name: .openInNewTab, object: url)
            return nil
        }
        if a.targetFrame == nil { w.load(a.request) }
        return nil
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
        // 링크가 없으면 iOS 기본 메뉴 사용 (Save Photo 등 네이티브)
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
                case "dash", "ts": continue  // ★ QA: .mpd/.ts 조각은 단독 다운로드 불가 (2초짜리 조각/XML 저장 방지)
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
            if let sel = dict["selector"] as? String, let host = tab.url?.host {
                ElementHiderStore.shared.addRule(sel, for: host, path: tab.url?.path)
            }
        case "privacyEvent":
            if let ev = dict["event"] as? String {
                switch ev {
                case "user_gesture":
                    // ★ 사용자 제스처 시각 기록 (납치광고 차단 판단용)
                    lastUserInteraction = Date().timeIntervalSince1970
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
        dm.updateUserAgent(from: wv)
        wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            // ★ QA: HTTPCookieStorage.shared 는 디스크에 영구 저장 → 사생활 탭(nonPersistent) 쿠키가 디스크로 새고 Fire 후에도 남음
            dm.importCookies(cookies)
        }
    }
    // ★ NEW: Download with cookies pre-loaded (async-safe)
    func downloadWithCookiesSync(media: DetectedMedia) {
        guard let wv = webView, let dm = downloadManager else { return }
        dm.updateUserAgent(from: wv)  // ★ QA: URLSession/HLS 요청 UA = 실제 WKWebView UA
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
        // ★ QA: DASH/MSE·blob·.ts 조각 등은 시작 전에 이유를 알려준다 (조용히 엉뚱한 파일 저장 방지)
        let probe = DetectedMedia(url: url, type: url.absoluteString.contains(".m3u8") ? .hls : .mp4, quality: "Auto",
                                  title: title, referer: "", thumbnail: nil, estimatedSize: nil)
        if let reason = MediaDownloadManager.unsupportedReason(for: probe) {
            NotificationCenter.default.post(name: .downloadFailed, object: reason)
            return
        }
        // ★ QA: 중복 판정은 전체 URL로 (쿼리 제거 시 ?id=1 / ?id=2 다른 파일이 조용히 무시됨)
        //   JS 버튼이 downloadVideo + alohaDownload 를 동시에 보내는 이중 호출은 그대로 걸러진다.
        let normalizedURL = url.absoluteString
        guard !recentlyDownloadedURLs.contains(normalizedURL) else {
            NotificationCenter.default.post(name: .downloadCompleted, object: "이미 다운로드 중입니다")
            return
        }
        recentlyDownloadedURLs.insert(normalizedURL)
        // 3분 후 해제
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self] in
            self?.recentlyDownloadedURLs.remove(normalizedURL)
        }
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
        if let ref = tab.url?.absoluteString, !ref.isEmpty {  // ★ QA: 빈 Referer 헤더 전송 금지
            request.setValue(ref, forHTTPHeaderField: "Referer")
        }
        Task { @MainActor in
            do {
                let download = try await wv.startDownload(using: request)
                download.delegate = self
                activeWKDownloads[download] = title
                downloadManager?.trackWebKitDownload(download, title: title, sourceURL: url)  // ★ QA: 목록/진행률/취소
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
// MARK: - WebView Configuration
enum WebViewConfigurator {
    static func makeConfiguration(for tab: Tab, privacyEngine: PrivacyEngine, coordinator: WebViewCoordinator) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = tab.dataStore
        // ★ 네트워크 릴레이 — 명시적으로 켠 경우에만 적용
        if #available(iOS 17.0, *), DiagnosticMode.relayEnabled {
            RelayManager.shared.applyRelay(to: tab.dataStore)
        }
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // ★ UA에 앱 이름이 붙지 않도록 (CF가 비-Safari 앱으로 인식하는 것 방지)
        //   Safari의 Version/ 토큰은 major.minor 2자리 형식이므로 동일하게 맞춘다.
        //   (systemVersion이 "26.0.1"이면 Safari는 "Version/26.0"으로 표기)
        let sysVer = UIDevice.current.systemVersion
        let verParts = sysVer.split(separator: ".")
        let safariVersion = verParts.count >= 2
            ? "\(verParts[0]).\(verParts[1])"
            : sysVer
        config.applicationNameForUserAgent = "Version/\(safariVersion) Mobile/15E148 Safari/604.1"
        // ★ CF 챌린지가 창을 열어야 할 수 있으므로 기본값 유지
        //   (v1.7.3에서 false로 바꾼 것이 CF 검증을 방해했음)
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(iOS 15.4, *) {
            config.preferences.isElementFullscreenEnabled = true
        }
        let uc = WKUserContentController()
        for name in ["mediaFound","alohaDownload","downloadVideo","blobCapture","elementHidden","privacyEvent"] {
            uc.add(coordinator, name: name)
        }
        // ★ 콘텐츠 스크립트 (진단 토글)
        if DiagnosticMode.contentScriptsEnabled {
            uc.addUserScript(WKUserScript(source: PrivacyScripts.earlyJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
            uc.addUserScript(WKUserScript(source: PrivacyScripts.mainJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        }
        config.userContentController = uc
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // ★ 광고 차단 규칙 (진단 토글)
        let blocker = privacyEngine.contentBlocker
        if DiagnosticMode.adBlockEnabled {
            if blocker.isCompiled {
                blocker.applyCachedRules(to: uc)
            }
            coordinator.rulesObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name("gsContentRulesCompiled"), object: nil, queue: .main
            ) { [weak uc] _ in
                guard let uc = uc else { return }
                uc.removeAllContentRuleLists()
                blocker.applyCachedRules(to: uc)
            }
        }
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
