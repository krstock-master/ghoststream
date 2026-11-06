// Network/RelayManager.swift
// GhostStream - 네트워크 릴레이 (OHTTP) IP 보호
// VPN 없이 사용자 IP를 목적지 서버로부터 숨김

import Foundation
import Network
import WebKit

/// 네트워크 릴레이 (iOS 17+ ProxyConfiguration) — ★ v2.0.5부터 비활성(숨김)
///
/// 정직성 메모: 이 기능은 실제로 동작한 적이 없다.
/// - `relay.privaterelay.fastly.com`은 우리가 운영하거나 계약한 릴레이가 아니며, 인증 없이
///   쓸 수 있는 공개 MASQUE 릴레이로 확인된 적이 없다 (Private Relay 홉은 Apple 인증 필요).
/// - `allowFailover = true` 때문에 릴레이 연결이 실패하면 조용히 직접 연결로 돌아가,
///   사용자는 "IP 보호 켜짐"을 보지만 실제 IP가 그대로 노출됐다.
/// - "연결 테스트"도 URLSession.shared(WebView와 다른 네트워크 경로)로 ipify를 조회해
///   릴레이 여부를 검증하지 못했다.
/// 실제로 운영되는 릴레이(MASQUE/HTTP3 CONNECT, 인증 포함)가 생기기 전까지
/// `isAvailable = false`로 UI에서 숨기고 어떤 경로로도 적용되지 않게 한다.
@Observable
final class RelayManager: @unchecked Sendable {
    static let shared = RelayManager()

    /// 실제로 작동하는 릴레이가 준비되기 전까지 false. (UI 노출 여부도 이 값으로 결정)
    static let isAvailable = false

    enum RelayProvider: String, CaseIterable {
        case disabled = "사용 안 함"
        case fastly = "Fastly Relay"
        case custom = "직접 설정"

        var relayURL: String {
            switch self {
            case .disabled: return ""
            case .fastly: return ""  // ★ 공개 릴레이 아님 — 가짜 URL 제거 (v2.0.5)
            case .custom: return ""
            }
        }
    }

    // AppStorage 대신 UserDefaults 직접 사용 (Observable 호환)
    var activeProvider: RelayProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: "relayProvider") ?? RelayProvider.disabled.rawValue
            return RelayProvider(rawValue: raw) ?? .disabled
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "relayProvider")
        }
    }

    var customRelayURL: String {
        get { UserDefaults.standard.string(forKey: "customRelayURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "customRelayURL") }
    }

    var isEnabled: Bool { Self.isAvailable && activeProvider != .disabled }

    /// 현재 설정에 맞는 ProxyConfiguration을 생성합니다.
    /// nil을 반환하면 릴레이 미사용 (직접 연결).
    @available(iOS 17.0, *)
    func makeProxyConfiguration() -> ProxyConfiguration? {
        guard isEnabled else { return nil }

        let urlString: String
        switch activeProvider {
        case .disabled: return nil
        case .fastly: urlString = activeProvider.relayURL
        case .custom:
            guard !customRelayURL.isEmpty else { return nil }
            urlString = customRelayURL
        }

        guard !urlString.isEmpty, let url = URL(string: urlString) else { return nil }

        // HTTP/3 릴레이 홉 생성
        let relayEndpoint = NWEndpoint.url(url)
        let relayHop = ProxyConfiguration.RelayHop(http3RelayEndpoint: relayEndpoint)
        var config = ProxyConfiguration(relayHops: [relayHop])
        // ★ 중요: allowFailover = true
        // 릴레이 서버가 실패하면 직접 연결로 대체 → 페이지는 항상 열림
        // (false면 릴레이 실패 시 페이지가 아예 로드 안 됨)
        config.allowFailover = true
        return config
    }

    /// WebView 설정에 릴레이를 적용합니다.
    /// ★ 릴레이가 꺼져 있으면 proxyConfigurations를 아예 건드리지 않습니다.
    ///   (빈 배열을 명시적으로 설정하면 WebKit 네트워크 스택에 영향을 줄 수 있음)
    @available(iOS 17.0, *)
    func applyRelay(to dataStore: WKWebsiteDataStore) {
        guard isEnabled, let proxyConfig = makeProxyConfiguration() else {
            return  // 아무것도 하지 않음 = 순수 기본 네트워크 경로
        }
        dataStore.proxyConfigurations = [proxyConfig]
    }

    /// 릴레이 연결 상태를 테스트합니다 (IP 확인).
    /// 릴레이가 실제로 작동하는지 확인하려면 릴레이 IP와 직접 IP를 비교.
    func testConnection() async -> (success: Bool, ip: String?) {
        // ipify로 현재 외부 IP 확인
        guard let url = URL(string: "https://api.ipify.org?format=text") else {
            return (false, nil)
        }
        do {
            // 캐시 무시하고 최신 IP 조회
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)
            let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (ip != nil, ip)
        } catch {
            return (false, nil)
        }
    }
}
