// UI/Components/PrivacyDashboardView.swift
import SwiftUI
import GhostStreamCore

struct PrivacyDashboardView: View {
    @Environment(PrivacyEngine.self) private var privacyEngine
    @Environment(DNSManager.self) private var dns
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("blockTrackers") private var blockTrackers = true
    @AppStorage("blockFingerprinting") private var blockFingerprinting = true
    @AppStorage("blockAds") private var blockAds = true

    var body: some View {
        NavigationStack {
            List {
                // Status overview
                Section {
                    HStack {
                        Image(systemName: "shield.checkered").font(.system(size: 36))
                            .foregroundStyle(allEnabled ? .green : .orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(allEnabled ? "보호 활성화됨" : "일부 보호 비활성").font(.headline)
                            Text("\(privacyEngine.contentBlocker.ruleCount)개 차단 규칙 적용 중").font(.caption).foregroundStyle(.gray)
                        }
                        Spacer()
                    }.padding(.vertical, 4)
                }

                // Shields
                Section("보호 기능") {
                    Toggle(isOn: $blockAds) {
                        Label("광고 차단", systemImage: "nosign")
                    }.tint(.green)
                    Toggle(isOn: $blockTrackers) {
                        Label("트래커 차단", systemImage: "eye.slash.fill")
                    }.tint(.green)
                    Toggle(isOn: $blockFingerprinting) {
                        Label("핑거프린팅 방어", systemImage: "hand.raised.fill")
                    }.tint(.green)
                    Toggle(isOn: .constant(true)) {
                        Label("제3자 쿠키 차단", systemImage: "xmark.shield.fill")
                    }.tint(.green).disabled(true)
                    Toggle(isOn: .constant(true)) {
                        Label("탭별 쿠키 격리", systemImage: "lock.square.stack.fill")
                    }.tint(.green).disabled(true)
                }

                // DNS
                Section("Privacy DNS") {
                    ForEach(DNSManager.Provider.allCases) { provider in
                        Button {
                            Task { await dns.apply(provider: provider) }
                        } label: {
                            HStack {
                                Image(systemName: provider.icon)
                                    .foregroundStyle(dns.activeProvider == provider ? .green : .gray)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.rawValue)
                                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                                    if !provider.serverURL.isEmpty {
                                        Text(provider.serverURL).font(.caption).foregroundStyle(.gray)
                                    }
                                }
                                Spacer()
                                if dns.activeProvider == provider {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }

                // Tracking prevention info
                Section("추적 금지") {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Do Not Track 헤더").font(.subheadline)
                            Text("모든 웹 요청에 DNT:1 헤더 전송").font(.caption).foregroundStyle(.gray)
                        }
                    }
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GPC (Global Privacy Control)").font(.subheadline)
                            Text("사이트에 개인정보 판매 금지 요청").font(.caption).foregroundStyle(.gray)
                        }
                    }
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("제로 텔레메트리").font(.subheadline)
                            Text("앱이 어떤 데이터도 외부로 전송하지 않음").font(.caption).foregroundStyle(.gray)
                        }
                    }
                }

                // What's blocked
                Section("차단 대상") {
                    blockRow("Google Analytics", "google-analytics.com")
                    blockRow("Facebook Pixel", "facebook.com/tr")
                    blockRow("DoubleClick Ads", "doubleclick.net")
                    blockRow("Hotjar", "hotjar.com")
                    blockRow("Amplitude", "amplitude.com")
                    blockRow("TikTok Analytics", "analytics.tiktok.com")
                    blockRow("기타 광고·트래커", "콘텐츠 차단 규칙")
                }
            }
            .navigationTitle("프라이버시").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
        }
    }

    private var allEnabled: Bool { blockTrackers && blockFingerprinting && blockAds }

    private func blockRow(_ name: String, _ domain: String) -> some View {
        HStack {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.caption)
            VStack(alignment: .leading) {
                Text(name).font(.subheadline)
                Text(domain).font(.caption).foregroundStyle(.gray)
            }
            Spacer()
            Text("차단됨").font(.caption2).foregroundStyle(.red)
        }
    }
}
