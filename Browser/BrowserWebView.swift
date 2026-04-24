// Browser/BrowserWebView.swift
import SwiftUI
import GhostStreamCore
import WebKit

struct BrowserWebView: UIViewRepresentable {
    let tab: Tab
    let privacyEngine: PrivacyEngine
    let downloadManager: MediaDownloadManager
    let bookmarkManager: BookmarkManager
    let onMediaDetected: (DetectedMedia) -> Void
    @Binding var webViewRef: WKWebView?

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(tab: tab, privacyEngine: privacyEngine, onMediaDetected: onMediaDetected)
    }

    func makeUIView(context: Context) -> WKWebView {
        // ★ 탭이 이미 WebView를 가지고 있으면 재사용
        if let existing = tab.webView {
            // 새 coordinator에 delegate 재할당
            existing.navigationDelegate = context.coordinator
            existing.uiDelegate = context.coordinator
            context.coordinator.observeWebView(existing)
            context.coordinator.webView = existing
            context.coordinator.downloadManager = downloadManager
            context.coordinator.bookmarkManager = bookmarkManager
            DispatchQueue.main.async { webViewRef = existing }

            let coord = context.coordinator
            if let old = coord.downloadObserver { NotificationCenter.default.removeObserver(old) }
            coord.downloadObserver = NotificationCenter.default.addObserver(
                forName: .wkDownloadRequested, object: nil, queue: .main
            ) { [weak coord] n in
                guard let media = n.object as? DetectedMedia, let coord = coord else { return }
                coord.startWKDownload(url: media.url, title: media.title)
            }
            return existing
        }

        // 새 WKWebView 생성
        let config = WebViewConfigurator.makeConfiguration(for: tab, privacyEngine: privacyEngine, coordinator: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = DeviceProfileManager.shared.activeProfile.userAgent
        context.coordinator.downloadManager = downloadManager
        context.coordinator.bookmarkManager = bookmarkManager
        context.coordinator.observeWebView(webView)
        context.coordinator.webView = webView
        tab.webView = webView
        DispatchQueue.main.async { webViewRef = webView }
        if let url = tab.url { webView.load(URLRequest(url: url)) }

        // ★ Pull-to-Refresh (Safari/Chrome 스타일)
        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .systemTeal
        refreshControl.addTarget(context.coordinator, action: #selector(WebViewCoordinator.handlePullToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        // ★ Listen for download requests from FullscreenOverlay / snackbar
        let coord = context.coordinator
        // ★ FIX: 이전 옵저버 제거 후 등록 (탭 전환 시 누적 방지)
        if let old = coord.downloadObserver {
            NotificationCenter.default.removeObserver(old)
        }
        coord.downloadObserver = NotificationCenter.default.addObserver(
            forName: .wkDownloadRequested, object: nil, queue: .main
        ) { [weak coord] n in
            guard let media = n.object as? DetectedMedia, let coord = coord else { return }
            coord.startWKDownload(url: media.url, title: media.title)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: WebViewCoordinator) {
        if let obs = coordinator.downloadObserver {
            NotificationCenter.default.removeObserver(obs)
            coordinator.downloadObserver = nil
        }
        coordinator.removeObservers(from: webView)
    }
}

// MARK: - KVO
extension WebViewCoordinator {
    private static var kvoKey: UInt8 = 0

    func observeWebView(_ webView: WKWebView) {
        let obs = [
            webView.observe(\.estimatedProgress) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.tab.loadProgress = wv.estimatedProgress }
            },
            webView.observe(\.title) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.tab.title = wv.title ?? "" }
            },
            webView.observe(\.url) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.tab.url = wv.url; self?.tab.isSecure = wv.url?.scheme == "https"
                    self?.tab.canGoBack = wv.canGoBack; self?.tab.canGoForward = wv.canGoForward
                }
            },
            webView.observe(\.isLoading) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.tab.isLoading = wv.isLoading }
            },
            // ★ F4 FIX: canGoBack/canGoForward 전용 KVO (즉각 반영)
            webView.observe(\.canGoBack) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.tab.canGoBack = wv.canGoBack }
            },
            webView.observe(\.canGoForward) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.tab.canGoForward = wv.canGoForward }
            }
        ]
        objc_setAssociatedObject(self, &Self.kvoKey, obs, .OBJC_ASSOCIATION_RETAIN)

        // ★ 스크롤 방향 감지 (주소바 축소/확장)
        webView.scrollView.delegate = self
    }

    func removeObservers(from webView: WKWebView) {
        objc_setAssociatedObject(self, &Self.kvoKey, nil, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - Scroll Direction (주소바 축소/확장)
extension WebViewCoordinator: UIScrollViewDelegate {
    private static var lastOffsetKey: UInt8 = 0

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let currentOffset = scrollView.contentOffset.y
        let lastOffset = (objc_getAssociatedObject(self, &Self.lastOffsetKey) as? CGFloat) ?? 0
        let delta = currentOffset - lastOffset
        objc_setAssociatedObject(self, &Self.lastOffsetKey, currentOffset, .OBJC_ASSOCIATION_RETAIN)

        // 최소 이동량 8pt 이상일 때만 반응 (떨림 방지)
        guard abs(delta) > 8 else { return }
        // 맨 위에서는 항상 확장
        if currentOffset <= 0 {
            NotificationCenter.default.post(name: .toolbarScrollDirection, object: false) // expand
            return
        }
        // 아래로 스크롤 → 축소, 위로 스크롤 → 확장
        NotificationCenter.default.post(name: .toolbarScrollDirection, object: delta > 0) // true = compact
    }
}

extension Notification.Name {
    static let toolbarScrollDirection = Notification.Name("toolbarScrollDirection")
}
