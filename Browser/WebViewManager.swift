// Browser/WebViewManager.swift
// GhostStream - WKWebView configuration with privacy + media detection

import SwiftUI
import WebKit

// MARK: - WebView Coordinator (Delegate Hub)
final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, @unchecked Sendable {
    let tab: Tab
    let privacyEngine: PrivacyEngine
    let onMediaDetected: (DetectedMedia) -> Void

    init(tab: Tab, privacyEngine: PrivacyEngine, onMediaDetected: @escaping (DetectedMedia) -> Void) {
        self.tab = tab
        self.privacyEngine = privacyEngine
        self.onMediaDetected = onMediaDetected
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        tab.isLoading = true
        tab.isSecure = webView.url?.scheme == "https"
        tab.privacyReport.isHTTPS = tab.isSecure
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tab.isLoading = false
        tab.title = webView.title ?? ""
        tab.url = webView.url
        tab.canGoBack = webView.canGoBack
        tab.canGoForward = webView.canGoForward

        // Extract favicon
        webView.evaluateJavaScript("""
            (function() {
                var link = document.querySelector("link[rel*='icon']");
                return link ? link.href : null;
            })()
        """) { result, _ in
            // favicon URL stored for display
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        tab.isLoading = false
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }

        // Track third-party domains
        if let host = url.host, let pageHost = tab.url?.host, host != pageHost {
            tab.privacyReport.thirdPartyDomains.insert(host)
        }

        // Direct media URL detection (mp4, m3u8 in address bar)
        let ext = url.pathExtension.lowercased()
        if ["mp4", "m4v", "mov", "webm"].contains(ext) {
            let media = DetectedMedia(
                url: url, type: .mp4, quality: "Direct",
                title: url.lastPathComponent,
                referer: tab.url?.absoluteString ?? "",
                thumbnail: nil, estimatedSize: nil
            )
            onMediaDetected(media)
        } else if ext == "m3u8" {
            let media = DetectedMedia(
                url: url, type: .hls, quality: "Auto",
                title: url.lastPathComponent,
                referer: tab.url?.absoluteString ?? "",
                thumbnail: nil, estimatedSize: nil
            )
            onMediaDetected(media)
        }

        return .allow
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Open target="_blank" links in same tab
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // JavaScript alert/confirm/prompt
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        // Handled by SwiftUI alert
    }

    // MARK: - WKScriptMessageHandler (JS → Native bridge)

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "mediaFound":
            handleMediaFound(message.body)

        case "blobCapture":
            handleBlobCapture(message.body)

        case "privacyEvent":
            handlePrivacyEvent(message.body)

        default:
            break
        }
    }

    // MARK: - Media Detection Handlers

    private func handleMediaFound(_ body: Any) {
        guard let dict = body as? [String: Any],
              let sources = dict["sources"] as? [[String: Any]],
              let title = dict["title"] as? String,
              let referer = dict["referer"] as? String else { return }

        let thumb = (dict["thumb"] as? String).flatMap { URL(string: $0) }

        for source in sources {
            guard let urlStr = source["url"] as? String,
                  let url = URL(string: urlStr) else { continue }

            let typeStr = (source["type"] as? String) ?? "mp4"
            let type: DetectedMedia.MediaType = typeStr == "hls" ? .hls : .mp4
            let label = (source["label"] as? String) ?? "default"

            let media = DetectedMedia(
                url: url, type: type, quality: label,
                title: title, referer: referer,
                thumbnail: thumb, estimatedSize: nil
            )

            if !tab.detectedMedia.contains(media) {
                tab.detectedMedia.append(media)
                onMediaDetected(media)
            }
        }
    }

    private func handleBlobCapture(_ body: Any) {
        guard let dict = body as? [String: Any],
              let dataURL = dict["data"] as? String,
              let mimeType = dict["mimeType"] as? String else { return }

        // Save blob data to temp file
        if let dataRange = dataURL.range(of: ","),
           let data = Data(base64Encoded: String(dataURL[dataRange.upperBound...])) {
            let ext = mimeType.contains("mp4") ? "mp4" : "webm"
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("blob_\(UUID().uuidString).\(ext)")
            try? data.write(to: tmpURL)

            let media = DetectedMedia(
                url: tmpURL, type: .blob, quality: "Blob",
                title: "Blob Video", referer: tab.url?.absoluteString ?? "",
                thumbnail: nil, estimatedSize: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            )
            tab.detectedMedia.append(media)
            onMediaDetected(media)
        }
    }

    private func handlePrivacyEvent(_ body: Any) {
        guard let dict = body as? [String: Any],
              let event = dict["event"] as? String else { return }

        switch event {
        case "fingerprint_attempt":
            tab.privacyReport.fingerprintAttempts += 1
        case "tracker_blocked":
            tab.privacyReport.trackersBlocked += 1
        case "ad_blocked":
            tab.privacyReport.adsBlocked += 1
        default:
            break
        }
    }
}

// MARK: - WebView Configuration Builder

enum WebViewConfigurator {
    /// Build a fully configured WKWebViewConfiguration for a tab
    static func makeConfiguration(
        for tab: Tab,
        privacyEngine: PrivacyEngine,
        coordinator: WebViewCoordinator
    ) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = tab.dataStore
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let userContent = WKUserContentController()

        // Register JS → Native message handlers
        userContent.add(coordinator, name: "mediaFound")
        userContent.add(coordinator, name: "blobCapture")
        userContent.add(coordinator, name: "privacyEvent")

        // Inject fingerprint defense JS
        if let fpScript = privacyEngine.fingerprintDefenseScript {
            let script = WKUserScript(
                source: fpScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            userContent.addUserScript(script)
        }

        // Inject media detector JS
        if let mdScript = loadBundledJS("MediaDetector") {
            let script = WKUserScript(
                source: mdScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            userContent.addUserScript(script)
        }

        config.userContentController = userContent

        // Apply content blocking rules
        Task { @MainActor in
            await privacyEngine.contentBlocker.applyRules(to: userContent)
        }

        return config
    }

    private static func loadBundledJS(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let content = try? String(contentsOf: url) else {
            // Fallback: return inline script
            return InlineScripts.mediaDetector
        }
        return content
    }
}

// MARK: - Inline JS Fallbacks
enum InlineScripts {
    static let mediaDetector = """
    (function() {
        "use strict";
        
        // HTML5 <video> scanner
        function scanVideoElements() {
            document.querySelectorAll("video").forEach(function(v) {
                var sources = [];
                if (v.src) sources.push({ url: v.src, type: v.src.includes(".m3u8") ? "hls" : "mp4", label: "default" });
                v.querySelectorAll("source").forEach(function(s) {
                    if (s.src) sources.push({ url: s.src, type: s.src.includes(".m3u8") ? "hls" : "mp4", label: s.getAttribute("label") || "default" });
                });
                if (sources.length > 0) {
                    window.webkit.messageHandlers.mediaFound.postMessage({
                        sources: sources,
                        title: document.title,
                        referer: location.href,
                        thumb: v.poster || null
                    });
                }
            });
        }
        
        // GIF scanner
        function scanGIFs() {
            document.querySelectorAll("img").forEach(function(img) {
                if (img.src && (img.src.endsWith(".gif") || img.src.includes(".gif?"))) {
                    window.webkit.messageHandlers.mediaFound.postMessage({
                        sources: [{ url: img.src, type: "gif", label: "GIF" }],
                        title: img.alt || "GIF",
                        referer: location.href,
                        thumb: null
                    });
                }
            });
        }
        
        // XHR/fetch intercept for m3u8
        var _origOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
            if (typeof url === "string" && url.includes(".m3u8")) {
                window.webkit.messageHandlers.mediaFound.postMessage({
                    sources: [{ url: url, type: "hls", label: "HLS" }],
                    title: document.title,
                    referer: location.href,
                    thumb: null
                });
            }
            return _origOpen.apply(this, arguments);
        };
        
        var _origFetch = window.fetch;
        window.fetch = function(input) {
            var url = typeof input === "string" ? input : (input && input.url ? input.url : "");
            if (url.includes(".m3u8")) {
                window.webkit.messageHandlers.mediaFound.postMessage({
                    sources: [{ url: url, type: "hls", label: "HLS" }],
                    title: document.title,
                    referer: location.href,
                    thumb: null
                });
            }
            return _origFetch.apply(this, arguments);
        };
        
        // Blob URL capture
        var _createObj = URL.createObjectURL.bind(URL);
        URL.createObjectURL = function(blob) {
            var url = _createObj(blob);
            if (blob && blob.type && blob.type.startsWith("video/")) {
                var reader = new FileReader();
                reader.onload = function(e) {
                    window.webkit.messageHandlers.blobCapture.postMessage({
                        data: e.target.result,
                        mimeType: blob.type
                    });
                };
                reader.readAsDataURL(blob);
            }
            return url;
        };
        
        // JW Player detection
        function detectJWPlayer() {
            if (typeof jwplayer === "undefined") return;
            document.querySelectorAll("[id]").forEach(function(el) {
                try {
                    var p = jwplayer(el.id);
                    if (!p || !p.getState) return;
                    function extract() {
                        var item = p.getPlaylistItem() || {};
                        var sources = (item.sources || []).map(function(s) {
                            return { url: s.file, type: s.file && s.file.includes(".m3u8") ? "hls" : "mp4", label: s.label || "default", height: s.height || 0 };
                        });
                        if (sources.length > 0) {
                            window.webkit.messageHandlers.mediaFound.postMessage({
                                sources: sources,
                                title: item.title || document.title,
                                referer: location.href,
                                thumb: item.image || null
                            });
                        }
                    }
                    p.on("ready", extract);
                    p.on("playlistItem", extract);
                    if (p.getState() !== "idle") extract();
                } catch(e) {}
            });
        }
        
        // MutationObserver for dynamic content
        var observer = new MutationObserver(function() {
            scanVideoElements();
            scanGIFs();
            if (typeof jwplayer !== "undefined") detectJWPlayer();
        });
        observer.observe(document.body || document.documentElement, { childList: true, subtree: true });
        
        // Initial scan
        setTimeout(function() {
            scanVideoElements();
            scanGIFs();
            detectJWPlayer();
        }, 1000);
    })();
    """;
}
