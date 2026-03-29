// Browser/WebViewManager.swift
import SwiftUI
import WebKit

final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, @unchecked Sendable {
    let tab: Tab
    let privacyEngine: PrivacyEngine
    let onMediaDetected: (DetectedMedia) -> Void

    init(tab: Tab, privacyEngine: PrivacyEngine, onMediaDetected: @escaping (DetectedMedia) -> Void) {
        self.tab = tab
        self.privacyEngine = privacyEngine
        self.onMediaDetected = onMediaDetected
    }

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
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        tab.isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        tab.isLoading = false
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if let host = url.host, let pageHost = tab.url?.host, host != pageHost {
            tab.privacyReport.thirdPartyDomains.insert(host)
        }
        let ext = url.pathExtension.lowercased()
        if ["mp4", "m4v", "mov", "webm"].contains(ext) {
            let media = DetectedMedia(url: url, type: .mp4, quality: "Direct",
                title: url.deletingPathExtension().lastPathComponent, referer: tab.url?.absoluteString ?? "",
                thumbnail: nil, estimatedSize: nil)
            onMediaDetected(media)
        } else if ext == "m3u8" {
            let media = DetectedMedia(url: url, type: .hls, quality: "Auto",
                title: url.deletingPathExtension().lastPathComponent, referer: tab.url?.absoluteString ?? "",
                thumbnail: nil, estimatedSize: nil)
            onMediaDetected(media)
        }
        return .allow
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "mediaFound":
            guard let dict = message.body as? [String: Any],
                  let sources = dict["sources"] as? [[String: Any]],
                  let referer = dict["referer"] as? String else { return }
            let pageTitle = (dict["title"] as? String) ?? "Media"
            let thumb = (dict["thumb"] as? String).flatMap { URL(string: $0) }
            for source in sources {
                guard let urlStr = source["url"] as? String, let url = URL(string: urlStr) else { continue }
                let typeStr = (source["type"] as? String) ?? "mp4"
                let type: DetectedMedia.MediaType = typeStr == "hls" ? .hls : typeStr == "gif" ? .gif : .mp4
                let label = (source["label"] as? String) ?? "default"
                let media = DetectedMedia(url: url, type: type, quality: label, title: pageTitle,
                    referer: referer, thumbnail: thumb, estimatedSize: nil)
                if !tab.detectedMedia.contains(media) {
                    tab.detectedMedia.append(media)
                    onMediaDetected(media)
                }
            }
        case "blobCapture":
            guard let dict = message.body as? [String: Any],
                  let dataURL = dict["data"] as? String,
                  let mimeType = dict["mimeType"] as? String,
                  let dataRange = dataURL.range(of: ","),
                  let data = Data(base64Encoded: String(dataURL[dataRange.upperBound...])) else { return }
            let ext = mimeType.contains("mp4") ? "mp4" : "webm"
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("blob_\(UUID().uuidString).\(ext)")
            try? data.write(to: tmpURL)
            let media = DetectedMedia(url: tmpURL, type: .blob, quality: "Blob", title: "Blob Video",
                referer: tab.url?.absoluteString ?? "", thumbnail: nil,
                estimatedSize: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
            tab.detectedMedia.append(media)
            onMediaDetected(media)
        case "privacyEvent":
            guard let dict = message.body as? [String: Any], let event = dict["event"] as? String else { return }
            switch event {
            case "fingerprint_attempt": tab.privacyReport.fingerprintAttempts += 1
            case "tracker_blocked": tab.privacyReport.trackersBlocked += 1
            case "ad_blocked": tab.privacyReport.adsBlocked += 1
            default: break
            }
        default: break
        }
    }
}

enum WebViewConfigurator {
    static func makeConfiguration(for tab: Tab, privacyEngine: PrivacyEngine, coordinator: WebViewCoordinator) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = tab.dataStore
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let uc = WKUserContentController()
        uc.add(coordinator, name: "mediaFound")
        uc.add(coordinator, name: "blobCapture")
        uc.add(coordinator, name: "privacyEvent")
        if let fp = privacyEngine.fingerprintDefenseScript {
            uc.addUserScript(WKUserScript(source: fp, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        uc.addUserScript(WKUserScript(source: Self.mediaDetectorJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController = uc
        // Apply content blocking rules
        Task { @MainActor in
            await privacyEngine.contentBlocker.applyRules(to: uc)
        }
        return config
    }

    static let mediaDetectorJS = """
    (function(){
    function scan(){
      document.querySelectorAll("video").forEach(function(v){
        var s=[];
        if(v.src)s.push({url:v.src,type:v.src.includes(".m3u8")?"hls":"mp4",label:"default"});
        v.querySelectorAll("source").forEach(function(src){
          if(src.src)s.push({url:src.src,type:src.src.includes(".m3u8")?"hls":"mp4",label:src.getAttribute("label")||"default"});
        });
        if(s.length>0)window.webkit.messageHandlers.mediaFound.postMessage({sources:s,title:document.title,referer:location.href,thumb:v.poster||null});
      });
      document.querySelectorAll("img").forEach(function(img){
        if(img.src&&(img.src.endsWith(".gif")||img.src.includes(".gif?")))
          window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:img.src,type:"gif",label:"GIF"}],title:img.alt||"GIF",referer:location.href,thumb:null});
      });
      if(typeof jwplayer!=="undefined"){
        document.querySelectorAll("[id]").forEach(function(el){
          try{var p=jwplayer(el.id);if(!p||!p.getState)return;
            function ex(){var item=p.getPlaylistItem()||{};var ss=(item.sources||[]).map(function(s){return{url:s.file,type:s.file&&s.file.includes(".m3u8")?"hls":"mp4",label:s.label||"default"};});
              if(ss.length>0)window.webkit.messageHandlers.mediaFound.postMessage({sources:ss,title:item.title||document.title,referer:location.href,thumb:item.image||null});}
            p.on("ready",ex);p.on("playlistItem",ex);if(p.getState()!=="idle")ex();
          }catch(e){}
        });
      }
    }
    var _xo=XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open=function(m,u){if(typeof u==="string"&&u.includes(".m3u8"))window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:u,type:"hls",label:"HLS"}],title:document.title,referer:location.href,thumb:null});return _xo.apply(this,arguments);};
    var _f=window.fetch;
    window.fetch=function(i){var u=typeof i==="string"?i:(i&&i.url?i.url:"");if(u.includes(".m3u8"))window.webkit.messageHandlers.mediaFound.postMessage({sources:[{url:u,type:"hls",label:"HLS"}],title:document.title,referer:location.href,thumb:null});return _f.apply(this,arguments);};
    var _co=URL.createObjectURL.bind(URL);
    URL.createObjectURL=function(b){var u=_co(b);if(b&&b.type&&b.type.startsWith("video/")){var r=new FileReader();r.onload=function(e){window.webkit.messageHandlers.blobCapture.postMessage({data:e.target.result,mimeType:b.type});};r.readAsDataURL(b);}return u;};
    new MutationObserver(function(){scan();}).observe(document.body||document.documentElement,{childList:true,subtree:true});
    setTimeout(scan,1000);setTimeout(scan,3000);
    })();
    """
}
