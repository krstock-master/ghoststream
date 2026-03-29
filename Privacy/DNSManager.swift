// Privacy/DNSManager.swift
// GhostStream - DNS over HTTPS configuration

import Foundation
import NetworkExtension

@Observable
final class DNSManager: @unchecked Sendable {
    var activeProvider: Provider = .cloudflare
    var isConfigured: Bool = false
    var error: String?

    enum Provider: String, CaseIterable, Identifiable {
        case cloudflare = "Cloudflare (1.1.1.1)"
        case quad9 = "Quad9 (9.9.9.9)"
        case nextdns = "NextDNS"
        case google = "Google (8.8.8.8)"
        case system = "시스템 기본"

        var id: String { rawValue }

        var serverURL: String {
            switch self {
            case .cloudflare: return "https://cloudflare-dns.com/dns-query"
            case .quad9: return "https://dns.quad9.net/dns-query"
            case .nextdns: return "https://dns.nextdns.io"
            case .google: return "https://dns.google/dns-query"
            case .system: return ""
            }
        }

        var servers: [String] {
            switch self {
            case .cloudflare: return ["1.1.1.1", "1.0.0.1"]
            case .quad9: return ["9.9.9.9", "149.112.112.112"]
            case .nextdns: return ["45.90.28.0", "45.90.30.0"]
            case .google: return ["8.8.8.8", "8.8.4.4"]
            case .system: return []
            }
        }

        var icon: String {
            switch self {
            case .cloudflare: return "cloud.fill"
            case .quad9: return "shield.fill"
            case .nextdns: return "arrow.triangle.branch"
            case .google: return "magnifyingglass"
            case .system: return "gear"
            }
        }
    }

    func apply(provider: Provider) async {
        activeProvider = provider
        error = nil

        guard provider != .system else {
            await removeConfiguration()
            return
        }

        do {
            let settings = NEDNSOverHTTPSSettings(servers: provider.servers)
            settings.serverURL = URL(string: provider.serverURL)

            let manager = NEDNSSettingsManager.shared()
            manager.dnsSettings = settings
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            isConfigured = true
        } catch {
            self.error = error.localizedDescription
            isConfigured = false
        }
    }

    private func removeConfiguration() async {
        do {
            let manager = NEDNSSettingsManager.shared()
            manager.dnsSettings = nil
            try await manager.saveToPreferences()
            isConfigured = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
