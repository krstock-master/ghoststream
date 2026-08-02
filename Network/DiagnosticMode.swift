// Network/DiagnosticMode.swift
// CF 문제 원인 격리를 위한 진단 모드
// 각 기능을 개별적으로 끄고 켜서 무엇이 CF를 방해하는지 확정

import Foundation

/// 진단용 기능 토글. 모두 켜짐(기본)에서 하나씩 꺼가며 범인을 찾는다.
enum DiagnosticMode {
    /// 광고/트래커 차단 규칙 (ContentBlocker)
    static var adBlockEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "diag.adBlock") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "diag.adBlock") }
    }

    /// 제3자 쿠키 차단
    static var cookieBlockEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "diag.cookieBlock") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "diag.cookieBlock") }
    }

    /// 핑거프린팅 방어 JS 주입
    static var fingerprintDefenseEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "diag.fingerprint") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "diag.fingerprint") }
    }

    /// 미디어 감지/광고 제거 JS 주입 (earlyJS + mainJS)
    static var contentScriptsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "diag.scripts") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "diag.scripts") }
    }

    /// 리다이렉트/팝업 차단 (네비게이션 정책)
    static var redirectBlockEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "diag.redirect") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "diag.redirect") }
    }

    /// CF 자동 처리 (감지 후 스크립트 제거 + reload)
    static var cfHandlingEnabled: Bool {
        // ★ 기본 OFF — CF 챌린지 진행 중 스크립트 제거+reload가 검증을 중단시킴
        get { UserDefaults.standard.object(forKey: "diag.cfHandling") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "diag.cfHandling") }
    }

    /// 기기 위장 UA
    static var fakeUserAgentEnabled: Bool {
        // ★ 기본 OFF — CF가 UA와 실제 엔진을 대조하므로 위장이 봇 신호가 됨
        get { UserDefaults.standard.object(forKey: "diag.fakeUA") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "diag.fakeUA") }
    }

    /// OHTTP 네트워크 릴레이 (프록시)
    static var relayEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "diag.relay") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "diag.relay") }
    }

    /// 영구 쿠키 저장 (끄면 nonPersistent = 재시작 시 쿠키 사라짐)
    static var persistentCookiesEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "diag.persistentCookies") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "diag.persistentCookies") }
    }

    /// 앱 시작 시 1회 실행 — CF를 방해하는 기능을 강제로 끔
    /// (기존 사용자는 UserDefaults에 true가 저장되어 있어 기본값이 적용되지 않음)
    static func applyCFSafetyMigration() {
        let key = "diag.cfSafetyMigration.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        cfHandlingEnabled = false
        fakeUserAgentEnabled = false
        relayEnabled = false
        persistentCookiesEnabled = true
        UserDefaults.standard.set(true, forKey: key)
    }

    /// 모든 기능 끄기 (순수 WKWebView 상태)
    static func disableAll() {
        adBlockEnabled = false
        cookieBlockEnabled = false
        fingerprintDefenseEnabled = false
        contentScriptsEnabled = false
        redirectBlockEnabled = false
        cfHandlingEnabled = false
        fakeUserAgentEnabled = false
        relayEnabled = false
        // 영구 쿠키는 켜둠 (CF clearance 보존에 필요)
        persistentCookiesEnabled = true
    }

    /// 모든 기능 켜기 (기본 상태)
    static func enableAll() {
        adBlockEnabled = true
        cookieBlockEnabled = true
        fingerprintDefenseEnabled = true
        contentScriptsEnabled = true
        redirectBlockEnabled = true
        // CF 안정성을 위해 아래 두 기능은 켜지 않음
        cfHandlingEnabled = false
        fakeUserAgentEnabled = false
        persistentCookiesEnabled = true
    }

    /// 현재 꺼진 기능 목록 (디버그 표시용)
    static var disabledList: [String] {
        var out: [String] = []
        if !adBlockEnabled { out.append("광고차단") }
        if !cookieBlockEnabled { out.append("쿠키차단") }
        if !fingerprintDefenseEnabled { out.append("핑거프린팅") }
        if !contentScriptsEnabled { out.append("콘텐츠JS") }
        if !redirectBlockEnabled { out.append("리다이렉트차단") }
        if !cfHandlingEnabled { out.append("CF자동처리") }
        if !fakeUserAgentEnabled { out.append("UA위장") }
        if relayEnabled { out.append("릴레이ON") }
        if !persistentCookiesEnabled { out.append("임시쿠키") }
        return out
    }
}
