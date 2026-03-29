// Browser/BrowserWebView.swift
// GhostStream - UIViewRepresentable wrapper for WKWebView

import SwiftUI
import WebKit

struct BrowserWebView: UIViewRepresentable {
    let tab: Tab
    let privacyEngine: PrivacyEngine
    let onMediaDetected: (DetectedMedia) -> Void
    @Binding var webViewRef: WKWebView?

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(tab: tab, privacyEngine: privacyEngine, onMediaDetected: onMediaDetected)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WebViewConfigurator.makeConfiguration(
            for: tab,
            privacyEngine: privacyEngine,
            coordinator: context.coordinator
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
        webView.isInspectable = true
        #endif

        // Custom user agent
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

        // KVO for progress and title
        context.coordinator.observeWebView(webView)

        DispatchQueue.main.async {
            webViewRef = webView
        }

        // Load initial URL or new tab page
        if let url = tab.url {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Navigation handled via commands, not re-render
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: WebViewCoordinator) {
        coordinator.removeObservers(from: webView)
    }
}

// MARK: - KVO Observation Extension
extension WebViewCoordinator {
    private static var progressObservation: UInt8 = 0
    private static var titleObservation: UInt8 = 0

    func observeWebView(_ webView: WKWebView) {
        let progressObs = webView.observe(\.estimatedProgress, options: .new) { [weak self] wv, _ in
            DispatchQueue.main.async {
                self?.tab.loadProgress = wv.estimatedProgress
            }
        }
        let titleObs = webView.observe(\.title, options: .new) { [weak self] wv, _ in
            DispatchQueue.main.async {
                self?.tab.title = wv.title ?? ""
            }
        }
        let urlObs = webView.observe(\.url, options: .new) { [weak self] wv, _ in
            DispatchQueue.main.async {
                self?.tab.url = wv.url
                self?.tab.isSecure = wv.url?.scheme == "https"
                self?.tab.canGoBack = wv.canGoBack
                self?.tab.canGoForward = wv.canGoForward
            }
        }
        let loadingObs = webView.observe(\.isLoading, options: .new) { [weak self] wv, _ in
            DispatchQueue.main.async {
                self?.tab.isLoading = wv.isLoading
            }
        }

        objc_setAssociatedObject(self, &Self.progressObservation, [progressObs, titleObs, urlObs, loadingObs], .OBJC_ASSOCIATION_RETAIN)
    }

    func removeObservers(from webView: WKWebView) {
        objc_setAssociatedObject(self, &Self.progressObservation, nil, .OBJC_ASSOCIATION_RETAIN)
    }
}
