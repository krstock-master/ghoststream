// Privacy/PrivacyEngine.swift
// GhostStream - Privacy orchestration layer

import Foundation
import WebKit

@Observable
final class PrivacyEngine: @unchecked Sendable {
    let contentBlocker: ContentBlockerManager
    var isEnabled: Bool = true
    var totalTrackersBlocked: Int = 0
    var totalAdsBlocked: Int = 0
    var totalFingerprintDefenses: Int = 0

    init(contentBlocker: ContentBlockerManager) {
        self.contentBlocker = contentBlocker
    }

    // MARK: - Fingerprint Defense JS

    var fingerprintDefenseScript: String? {
        guard isEnabled else { return nil }
        return Self.fingerprintDefenseJS
    }

    // MARK: - Complete Fingerprint Defense (7-vector)

    private static let fingerprintDefenseJS = """
    (function() {
        "use strict";
        
        // ── Cloudflare bypass: if CF challenge page set a bypass flag,
        //    skip ALL fingerprint spoofing so CF sees a real browser profile.
        try {
            if (sessionStorage.getItem('__gs_cf_bypass') === '1') {
                sessionStorage.removeItem('__gs_cf_bypass');
                return; // exit immediately – no spoofing on CF pages
            }
        } catch(e) {}
        
        // Also skip on known CF challenge domains
        var _host = location.hostname;
        if (_host === 'challenges.cloudflare.com' || _host === 'cloudflare.com') return;
        
        function notifyNative(event) {
            try {
                window.webkit.messageHandlers.privacyEvent.postMessage({ event: event });
            } catch(e) {}
        }
        
        // 1. Canvas 노이즈
        var _getCtx = HTMLCanvasElement.prototype.getContext;
        HTMLCanvasElement.prototype.getContext = function(type) {
            var ctx = _getCtx.apply(this, arguments);
            if (!ctx || type !== "2d") return ctx;
            var _getImageData = ctx.getImageData.bind(ctx);
            ctx.getImageData = function(x, y, w, h) {
                notifyNative("fingerprint_attempt");
                var d = _getImageData(x, y, w, h);
                for (var i = 0; i < d.data.length; i += 4) {
                    d.data[i] ^= Math.random() > 0.5 ? 1 : 0;
                    d.data[i+1] ^= Math.random() > 0.5 ? 1 : 0;
                }
                return d;
            };
            var _toDataURL = this.toDataURL.bind(this);
            this.toDataURL = function() {
                notifyNative("fingerprint_attempt");
                return _toDataURL.apply(this, arguments);
            };
            return ctx;
        };
        
        // 2. WebGL 스푸핑
        var _getParam = WebGLRenderingContext.prototype.getParameter;
        WebGLRenderingContext.prototype.getParameter = function(p) {
            if (p === this.RENDERER) { notifyNative("fingerprint_attempt"); return "Apple GPU"; }
            if (p === this.VENDOR) { notifyNative("fingerprint_attempt"); return "Apple Inc."; }
            return _getParam.call(this, p);
        };
        if (typeof WebGL2RenderingContext !== "undefined") {
            var _getParam2 = WebGL2RenderingContext.prototype.getParameter;
            WebGL2RenderingContext.prototype.getParameter = function(p) {
                if (p === this.RENDERER) { notifyNative("fingerprint_attempt"); return "Apple GPU"; }
                if (p === this.VENDOR) { notifyNative("fingerprint_attempt"); return "Apple Inc."; }
                return _getParam2.call(this, p);
            };
        }
        
        // 3. AudioContext 노이즈
        if (typeof AudioContext !== "undefined") {
            var _createAnalyser = AudioContext.prototype.createAnalyser;
            AudioContext.prototype.createAnalyser = function() {
                var node = _createAnalyser.call(this);
                var _getFloat = node.getFloatFrequencyData.bind(node);
                node.getFloatFrequencyData = function(arr) {
                    _getFloat(arr);
                    notifyNative("fingerprint_attempt");
                    for (var i = 0; i < arr.length; i++) {
                        arr[i] += (Math.random() - 0.5) * 0.0001;
                    }
                };
                return node;
            };
        }
        
        // 4. Font Enumeration 방어
        var _measureText = CanvasRenderingContext2D.prototype.measureText;
        CanvasRenderingContext2D.prototype.measureText = function(text) {
            var result = _measureText.call(this, text);
            // 미세한 노이즈를 추가하여 폰트 목록 추론 차단
            var w = result.width;
            Object.defineProperty(result, "width", {
                get: function() { return Math.round(w * 100) / 100; }
            });
            return result;
        };
        
        // 5. Navigator 속성 고정 (일반 iPhone 프로필)
        try {
            Object.defineProperties(navigator, {
                plugins: { get: function() { return []; } },
                languages: { get: function() { return ["ko-KR", "ko", "en-US", "en"]; } },
                hardwareConcurrency: { get: function() { return 4; } },
                deviceMemory: { get: function() { return 4; } },
                maxTouchPoints: { get: function() { return 5; } },
            });
        } catch(e) {}
        
        // 6. Screen 속성 고정
        try {
            Object.defineProperties(screen, {
                width: { get: function() { return 390; } },
                height: { get: function() { return 844; } },
                availWidth: { get: function() { return 390; } },
                availHeight: { get: function() { return 844; } },
                colorDepth: { get: function() { return 24; } },
                pixelDepth: { get: function() { return 24; } },
            });
            Object.defineProperty(window, "devicePixelRatio", {
                get: function() { return 3; }
            });
        } catch(e) {}
        
        // 7. 고정밀 타이머 해상도 저하
        var _now = performance.now.bind(performance);
        performance.now = function() {
            return Math.round(_now());  // 1ms 단위로 반올림
        };
        
        // Bonus: Battery API 차단
        if (navigator.getBattery) {
            navigator.getBattery = function() {
                return Promise.reject(new Error("Battery API disabled"));
            };
        }
    })();
    """
}
