// VPN/VPNManager.swift
// GhostStream - WireGuard VPN management layer

import Foundation
import NetworkExtension

@Observable
final class VPNManager: @unchecked Sendable {
    var status: VPNStatus = .disconnected
    var selectedServer: VPNServer?
    var servers: [VPNServer] = VPNServer.defaultServers
    var connectionDuration: TimeInterval = 0
    var bytesIn: Int64 = 0
    var bytesOut: Int64 = 0
    var error: String?

    private var statusObserver: Any?
    private var timer: Timer?

    init() {
        observeVPNStatus()
    }

    // MARK: - Connection

    func connect(to server: VPNServer) async {
        selectedServer = server
        status = .connecting
        error = nil

        do {
            let manager = try await loadOrCreateManager()

            let tunnelProto = NETunnelProviderProtocol()
            tunnelProto.providerBundleIdentifier = "com.ghoststream.browser.vpn"
            tunnelProto.serverAddress = server.address
            tunnelProto.providerConfiguration = [
                "wgConfig": server.wireGuardConfig
            ]

            manager.protocolConfiguration = tunnelProto
            manager.localizedDescription = "GhostStream VPN"
            manager.isEnabled = true

            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()

            guard let session = manager.connection as? NETunnelProviderSession else {
                self.error = "VPN 세션 생성 실패"
                status = .disconnected
                return
            }
            try session.startTunnel()

            status = .connected
            startTimer()
        } catch {
            self.error = error.localizedDescription
            status = .disconnected
        }
    }

    func disconnect() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            for manager in managers {
                manager.connection.stopVPNTunnel()
            }
            status = .disconnected
            stopTimer()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggle() async {
        if status == .connected {
            await disconnect()
        } else if let server = selectedServer ?? servers.first {
            await connect(to: server)
        }
    }

    // MARK: - Manager

    private func loadOrCreateManager() async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let existing = managers.first { return existing }
        return NETunnelProviderManager()
    }

    // MARK: - Status Observation

    private func observeVPNStatus() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let connection = notification.object as? NEVPNConnection else { return }
            self?.updateStatus(from: connection.status)
        }
    }

    private func updateStatus(from neStatus: NEVPNStatus) {
        switch neStatus {
        case .connected: status = .connected
        case .connecting: status = .connecting
        case .disconnected: status = .disconnected
        case .disconnecting: status = .disconnecting
        case .reasserting: status = .connecting
        case .invalid: status = .disconnected
        @unknown default: status = .disconnected
        }
    }

    // MARK: - Timer

    private func startTimer() {
        connectionDuration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.connectionDuration += 1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        connectionDuration = 0
    }

    var formattedDuration: String {
        let h = Int(connectionDuration) / 3600
        let m = Int(connectionDuration) % 3600 / 60
        let s = Int(connectionDuration) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    deinit {
        if let obs = statusObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}

// MARK: - Models

enum VPNStatus: String {
    case disconnected = "연결 안 됨"
    case connecting = "연결 중…"
    case connected = "연결됨"
    case disconnecting = "연결 해제 중…"

    var color: String {
        switch self {
        case .disconnected: "#FF6B6B"
        case .connecting: "#FECA57"
        case .connected: "#1DD1A1"
        case .disconnecting: "#FECA57"
        }
    }

    var icon: String {
        switch self {
        case .disconnected: "shield.slash.fill"
        case .connecting: "shield.lefthalf.filled"
        case .connected: "shield.checkered"
        case .disconnecting: "shield.lefthalf.filled"
        }
    }
}

struct VPNServer: Identifiable, Hashable {
    let id: String
    let name: String
    let country: String
    let flag: String
    let address: String
    let isPro: Bool
    let ping: Int // ms

    var wireGuardConfig: String {
        // Placeholder - real config from server API
        """
        [Interface]
        PrivateKey = <generated_at_runtime>
        Address = 10.0.0.2/32
        DNS = 1.1.1.1

        [Peer]
        PublicKey = <server_public_key>
        Endpoint = \(address):51820
        AllowedIPs = 0.0.0.0/0, ::/0
        PersistentKeepalive = 25
        """
    }

    static let defaultServers: [VPNServer] = [
        VPNServer(id: "jp-1", name: "Tokyo", country: "Japan", flag: "🇯🇵", address: "vpn-jp.ghoststream.io", isPro: false, ping: 35),
        VPNServer(id: "us-1", name: "Los Angeles", country: "USA", flag: "🇺🇸", address: "vpn-us-west.ghoststream.io", isPro: false, ping: 120),
        VPNServer(id: "de-1", name: "Frankfurt", country: "Germany", flag: "🇩🇪", address: "vpn-de.ghoststream.io", isPro: false, ping: 180),
        VPNServer(id: "is-1", name: "Reykjavik", country: "Iceland", flag: "🇮🇸", address: "vpn-is.ghoststream.io", isPro: true, ping: 200),
        VPNServer(id: "sg-1", name: "Singapore", country: "Singapore", flag: "🇸🇬", address: "vpn-sg.ghoststream.io", isPro: true, ping: 60),
        VPNServer(id: "kr-1", name: "Seoul", country: "South Korea", flag: "🇰🇷", address: "vpn-kr.ghoststream.io", isPro: true, ping: 10),
        VPNServer(id: "ch-1", name: "Zurich", country: "Switzerland", flag: "🇨🇭", address: "vpn-ch.ghoststream.io", isPro: true, ping: 190),
        VPNServer(id: "pa-1", name: "Panama City", country: "Panama", flag: "🇵🇦", address: "vpn-pa.ghoststream.io", isPro: true, ping: 210),
    ]
}
