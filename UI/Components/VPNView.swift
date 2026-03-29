// UI/Components/VPNView.swift
// GhostStream - WireGuard VPN connection UI

import SwiftUI

struct VPNView: View {
    @Environment(VPNManager.self) private var vpn
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection status
                    VStack(spacing: 16) {
                        Image(systemName: vpn.status.icon)
                            .font(.system(size: 52))
                            .foregroundStyle(Color(hex: vpn.status.color))
                            .symbolEffect(.pulse, isActive: vpn.status == .connecting)

                        Text(vpn.status.rawValue)
                            .font(.title3.bold())
                            .foregroundStyle(.white)

                        if vpn.status == .connected {
                            Text(vpn.formattedDuration)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        if let server = vpn.selectedServer, vpn.status == .connected {
                            Text("\(server.flag) \(server.name)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // Connect/Disconnect button
                        Button {
                            Task { await vpn.toggle() }
                        } label: {
                            Text(vpn.status == .connected ? "연결 해제" : "연결")
                                .font(.headline)
                                .foregroundStyle(vpn.status == .connected ? .white : .black)
                                .frame(width: 160, height: 48)
                                .background(
                                    vpn.status == .connected ? GhostTheme.danger : GhostTheme.accent,
                                    in: Capsule()
                                )
                        }
                    }
                    .padding()
                    .glass()

                    // Server list
                    VStack(alignment: .leading, spacing: 12) {
                        Text("서버 목록")
                            .font(.headline)
                            .foregroundStyle(.white)

                        // Free servers
                        VStack(alignment: .leading, spacing: 4) {
                            Text("무료")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tertiary)

                            ForEach(vpn.servers.filter { !$0.isPro }) { server in
                                serverRow(server)
                            }
                        }

                        // Pro servers
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Pro")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(GhostTheme.accentAlt)
                                Image(systemName: "crown.fill")
                                    .font(.caption2)
                                    .foregroundStyle(GhostTheme.warning)
                            }

                            ForEach(vpn.servers.filter { $0.isPro }) { server in
                                serverRow(server)
                            }
                        }
                    }

                    // Privacy policy
                    VStack(alignment: .leading, spacing: 8) {
                        Text("프라이버시 정책")
                            .font(.headline)
                            .foregroundStyle(.white)

                        policyRow("🚫", "연결 로그 수집 없음 (No-logs)")
                        policyRow("💾", "RAM-only 서버 (재시작 시 데이터 소멸)")
                        policyRow("🔒", "WireGuard 프로토콜 (최신 암호화)")
                        policyRow("🌍", "14 Eyes 외 관할 서버 우선")
                    }
                    .padding()
                    .glass()

                    if let error = vpn.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(GhostTheme.danger)
                            .padding()
                    }
                }
                .padding()
            }
            .background(GhostTheme.bg)
            .navigationTitle("VPN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(GhostTheme.accent)
                }
            }
        }
    }

    private func serverRow(_ server: VPNServer) -> some View {
        Button {
            Task { await vpn.connect(to: server) }
        } label: {
            HStack(spacing: 12) {
                Text(server.flag)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text(server.country)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(server.ping)ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(server.ping < 50 ? GhostTheme.success : server.ping < 150 ? GhostTheme.warning : GhostTheme.danger)

                if vpn.selectedServer?.id == server.id && vpn.status == .connected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(GhostTheme.success)
                }
            }
            .padding(12)
            .glass()
        }
    }

    private func policyRow(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(emoji)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
