// Privacy/PrivacyEngine.swift
// GhostStream - Privacy orchestration layer

import Foundation
import WebKit

@Observable
final class PrivacyEngine: @unchecked Sendable {
    let contentBlocker: ContentBlockerManager
    var isEnabled: Bool = true
    var totalTrackersBlocked: Int {
        didSet { UserDefaults.standard.set(totalTrackersBlocked, forKey: "gs_totalTrackers") }
    }
    var totalAdsBlocked: Int {
        didSet { UserDefaults.standard.set(totalAdsBlocked, forKey: "gs_totalAds") }
    }
    var totalFingerprintDefenses: Int {
        didSet { UserDefaults.standard.set(totalFingerprintDefenses, forKey: "gs_totalFP") }
    }

    init(contentBlocker: ContentBlockerManager) {
        self.contentBlocker = contentBlocker
        self.totalTrackersBlocked = UserDefaults.standard.integer(forKey: "gs_totalTrackers")
        self.totalAdsBlocked = UserDefaults.standard.integer(forKey: "gs_totalAds")
        self.totalFingerprintDefenses = UserDefaults.standard.integer(forKey: "gs_totalFP")
    }

    // MARK: - Fingerprint Defense JS

    var fingerprintDefenseScript: String? {
        guard isEnabled else { return nil }
        return Self.buildFingerprintDefenseJS(profile: DeviceProfileManager.shared.activeProfile)
    }

    // MARK: - Complete Fingerprint Defense (11-vector, 프로필 기반)

    static func buildFingerprintDefenseJS(profile: DeviceProfile) -> String {
        return """
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
        
        // 1. Canvas 노이즈 (세션 고정 시드)
        var _seed = \(Int.random(in: 1000...9999));
        function seededRand(i) { var x = Math.sin(_seed + i) * 10000; return x - Math.floor(x); }
        var _getCtx = HTMLCanvasElement.prototype.getContext;
        HTMLCanvasElement.prototype.getContext = function(type) {
            var ctx = _getCtx.apply(this, arguments);
            if (!ctx || type !== "2d") return ctx;
            var _getImageData = ctx.getImageData.bind(ctx);
            ctx.getImageData = function(x, y, w, h) {
                notifyNative("fingerprint_attempt");
                var d = _getImageData(x, y, w, h);
                for (var i = 0; i < d.data.length; i += 4) {
                    d.data[i] ^= seededRand(i) > 0.5 ? 1 : 0;
                    d.data[i+1] ^= seededRand(i+1) > 0.5 ? 1 : 0;
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
                        arr[i] += (seededRand(i) - 0.5) * 0.0001;
                    }
                };
                return node;
            };
        }
        
        // 4. Font Enumeration 방어
        var _measureText = CanvasRenderingContext2D.prototype.measureText;
        CanvasRenderingContext2D.prototype.measureText = function(text) {
            var result = _measureText.call(this, text);
            var w = result.width;
            Object.defineProperty(result, "width", {
                get: function() { return Math.round(w * 100) / 100; }
            });
            return result;
        };
        
        // 5. Navigator 속성 고정 (프로필 기반 — UA와 일관)
        try {
            Object.defineProperties(navigator, {
                plugins: { get: function() { return []; } },
                languages: { get: function() { return ["ko-KR", "ko", "en-US", "en"]; } },
                hardwareConcurrency: { get: function() { return \(profile.hardwareConcurrency); } },
                deviceMemory: { get: function() { return 4; } },
                maxTouchPoints: { get: function() { return \(profile.maxTouchPoints); } },
            });
        } catch(e) {}
        
        // 6. Screen 속성 고정 (프로필 기반 — UA와 일관)
        try {
            Object.defineProperties(screen, {
                width: { get: function() { return \(profile.screenWidth); } },
                height: { get: function() { return \(profile.screenHeight); } },
                availWidth: { get: function() { return \(profile.screenWidth); } },
                availHeight: { get: function() { return \(profile.screenHeight); } },
                colorDepth: { get: function() { return 24; } },
                pixelDepth: { get: function() { return 24; } },
            });
            Object.defineProperty(window, "devicePixelRatio", {
                get: function() { return \(profile.pixelRatio); }
            });
        } catch(e) {}
        
        // 7. 고정밀 타이머 해상도 저하
        var _now = performance.now.bind(performance);
        performance.now = function() {
            return Math.round(_now());
        };
        
        // 8. Battery API 차단
        if (navigator.getBattery) {
            navigator.getBattery = function() {
                return Promise.reject(new Error("Battery API disabled"));
            };
        }
        
        // ★ 9. WebRTC IP 누출 차단
        try {
            var _RTCPeer = window.RTCPeerConnection || window.webkitRTCPeerConnection;
            if (_RTCPeer) {
                window.RTCPeerConnection = function(config) {
                    notifyNative("fingerprint_attempt");
                    if (config && config.iceServers) {
                        config.iceServers = []; // STUN/TURN 서버 제거 → 로컬 IP 노출 차단
                    }
                    return new _RTCPeer(config);
                };
                window.RTCPeerConnection.prototype = _RTCPeer.prototype;
                if (window.webkitRTCPeerConnection) window.webkitRTCPeerConnection = window.RTCPeerConnection;
            }
        } catch(e) {}
        
        // ★ 10. NetworkInformation API 스푸핑
        try {
            if (navigator.connection) {
                Object.defineProperties(navigator.connection, {
                    effectiveType: { get: function() { return "4g"; } },
                    downlink: { get: function() { return 10; } },
                    rtt: { get: function() { return 50; } },
                    saveData: { get: function() { return false; } },
                });
            }
        } catch(e) {}
        
        // ★ 11. Speech Synthesis 핑거프린트 방어
        try {
            if (window.speechSynthesis && window.speechSynthesis.getVoices) {
                var _getVoices = window.speechSynthesis.getVoices.bind(window.speechSynthesis);
                window.speechSynthesis.getVoices = function() {
                    notifyNative("fingerprint_attempt");
                    return []; // 빈 배열 반환 → 음성 목록 기반 핑거프린팅 차단
                };
            }
        } catch(e) {}
    })();
    """
    }
}
