// Browser/BrowserWebView.swift
import SwiftUI
import WebKit

struct BrowserWebView: UIViewRepresentable {
    let tab: Tab
    let privacyEngine: PrivacyEngine
    let downloadManager: MediaDownloadManager
    let onMediaDetected: (DetectedMedia) -> Void
    @Binding var webViewRef: WKWebView?

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(tab: tab, privacyEngine: privacyEngine, onMediaDetected: onMediaDetected)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WebViewConfigurator.makeConfiguration(for: tab, privacyEngine: privacyEngine, coordinator: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.downloadManager = downloadManager
        context.coordinator.observeWebView(webView)
        // Forward WKWebView cookies → downloadManager for authenticated HLS streams
        context.coordinator.webView = webView
        DispatchQueue.main.async { webViewRef = webView }
        if let url = tab.url { webView.load(URLRequest(url: url)) }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: WebViewCoordinator) {
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
            }
        ]
        objc_setAssociatedObject(self, &Self.kvoKey, obs, .OBJC_ASSOCIATION_RETAIN)
    }

    func removeObservers(from webView: WKWebView) {
        objc_setAssociatedObject(self, &Self.kvoKey, nil, .OBJC_ASSOCIATION_RETAIN)
    }
}
