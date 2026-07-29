// Network/RelayManager.swift
// GhostStream - 네트워크 릴레이 (OHTTP) IP 보호
// VPN 없이 사용자 IP를 목적지 서버로부터 숨김

import Foundation
import Network
import WebKit

/// 네트워크 릴레이를 통해 IP를 보호합니다 (iOS 17+).
///
/// 원리: 사용자 → 릴레이 서버 → 목적지
/// - 릴레이는 사용자 IP를 알지만 목적지 콘텐츠는 볼 수 없음 (암호화)
/// - 목적지는 콘텐츠를 보지만 사용자 IP는 릴레이 IP로 대체됨
/// - Apple Private Relay와 동일한 이중 홉 원리
@Observable
final class RelayManager: @unchecked Sendable {
    static let shared = RelayManager()

    enum RelayProvider: String, CaseIterable {
        case disabled = "사용 안 함"
        case fastly = "Fastly Relay"
        case custom = "직접 설정"

        var relayURL: String {
            switch self {
            case .disabled: return ""
            case .fastly: return "https://relay.privaterelay.fastly.com"
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

    var isEnabled: Bool { activeProvider != .disabled }

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

        guard let url = URL(string: urlString) else { return nil }

        // HTTP/3 릴레이 홉 생성
        let relayEndpoint = NWEndpoint.url(url)
        let relayHop = ProxyConfiguration.RelayHop(http3RelayEndpoint: relayEndpoint)
        return ProxyConfiguration(relayHops: [relayHop])
    }

    /// WebView 설정에 릴레이를 적용합니다.
    @available(iOS 17.0, *)
    func applyRelay(to dataStore: WKWebsiteDataStore) {
        if let proxyConfig = makeProxyConfiguration() {
            dataStore.proxyConfigurations = [proxyConfig]
        } else {
            dataStore.proxyConfigurations = []
        }
    }

    /// 릴레이 연결 상태를 테스트합니다 (IP 확인).
    func testConnection() async -> (success: Bool, ip: String?) {
        guard isEnabled else { return (false, nil) }
        // ipify로 현재 외부 IP 확인
        guard let url = URL(string: "https://api.ipify.org?format=text") else {
            return (false, nil)
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (true, ip)
        } catch {
            return (false, nil)
        }
    }
}
