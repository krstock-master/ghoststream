// UI/Components/PrivacyDashboardView.swift
import SwiftUI
import GhostStreamCore

struct PrivacyDashboardView: View {
    @Environment(PrivacyEngine.self) private var privacyEngine
    @Environment(DNSManager.self) private var dns
    @Environment(\.dismiss) private var dismiss
    // ★ v2.0.5: 실제 동작을 제어하는 DiagnosticMode 키에 바인딩 (구 blockAds/blockTrackers/blockFingerprinting 키는 미사용)
    @AppStorage("diag.adBlock") private var adBlock = true
    @AppStorage("diag.fingerprint") private var fingerprint = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // ★ 실시간 차단 현황 카드
                    shieldCard

                    // ★ 이번 세션 상세
                    sessionStats

                    // ★ 보호 토글
                    protectionToggles

                    // ★ DNS 상태
                    dnsStatus
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("보호 현황").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() }.foregroundStyle(.teal) } }
        }
    }

    // MARK: - Shield Card
    private var shieldCard: some View {
        VStack(spacing: 12) {
            Image(systemName: allEnabled ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(allEnabled ? .green : .orange)
                .accessibilityHidden(true)

            Text(allEnabled ? "보호 중" : "일부 보호 꺼짐")
                .font(.title3.bold())

            let total = privacyEngine.totalAdsBlocked + privacyEngine.totalTrackersBlocked + privacyEngine.totalFingerprintDefenses
            Text("총 \(total)건의 위협을 차단했습니다")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.panel))
    }

    // MARK: - Session Stats
    private var sessionStats: some View {
        VStack(spacing: 0) {
            HStack {
                Text("차단 현황").font(.subheadline.bold())
                Spacer()
            }.padding(.horizontal, 16).padding(.top, 12)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCell(
                    icon: "nosign",
                    count: privacyEngine.totalAdsBlocked,
                    label: "광고",
                    color: .red
                )
                statCell(
                    icon: "eye.slash.fill",
                    count: privacyEngine.totalTrackersBlocked,
                    label: "트래커",
                    color: .orange
                )
                statCell(
                    icon: "hand.raised.fill",
                    count: privacyEngine.totalFingerprintDefenses,
                    label: "핑거프린팅",
                    color: .purple
                )
            }
            .padding(12)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.panel))
    }

    private func statCell(icon: String, count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.title2.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.card))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Protection Toggles
    private var protectionToggles: some View {
        VStack(spacing: 0) {
            HStack {
                Text("보호 기능").font(.subheadline.bold())
                Spacer()
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)

            VStack(spacing: 1) {
                toggleRow("광고·트래커 차단", "nosign", $adBlock, .red)
                toggleRow("핑거프린팅 방어", "hand.raised.fill", $fingerprint, .purple)
                infoRow("쿠키 배너 자동 거부", "xmark.shield.fill", .teal)
                infoRow("사용 데이터 수집 안 함", "antenna.radiowaves.left.and.right.slash", .green)
            }
            .padding(.horizontal, 12).padding(.bottom, 4)

            Text("변경 사항은 새로 여는 탭부터 적용됩니다.")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.panel))
    }

    private func toggleRow(_ title: String, _ icon: String, _ binding: Binding<Bool>, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 24)
            Text(title).font(.subheadline)
            Spacer()
            Toggle("", isOn: binding).labelsHidden().tint(.green)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private func infoRow(_ title: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 24)
            Text(title).font(.subheadline)
            Spacer()
            Text("항상 켜짐").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - DNS
    private var dnsStatus: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DNS 보호").font(.subheadline.bold())
                Spacer()
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)

            HStack(spacing: 12) {
                let encrypted = !dns.activeProvider.serverURL.isEmpty
                Image(systemName: "network.badge.shield.half.filled").foregroundStyle(.teal).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dns.activeProvider.rawValue).font(.subheadline)
                    Text(encrypted ? "암호화된 DNS 사용 중" : "암호화되지 않음 · 설정에서 변경")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                // ★ v2.0.5: 시스템 기본 DNS일 때도 초록 체크가 표시되던 문제 수정
                Image(systemName: encrypted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(encrypted ? .green : .orange).font(.caption)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .accessibilityElement(children: .combine)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.panel))
    }

    private var allEnabled: Bool { adBlock && fingerprint }
}
