// UI/Settings/SettingsView.swift
// GhostStream - Comprehensive settings

import SwiftUI

struct SettingsView: View {
    @Environment(DIContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Privacy
                Section {
                    Toggle("트래커 차단", isOn: Binding(
                        get: { container.settingsStore.blockTrackers },
                        set: { container.settingsStore.blockTrackers = $0 }
                    ))
                    Toggle("핑거프린팅 방어", isOn: Binding(
                        get: { container.settingsStore.blockFingerprinting },
                        set: { container.settingsStore.blockFingerprinting = $0 }
                    ))
                    Toggle("광고 차단", isOn: Binding(
                        get: { container.settingsStore.blockAds },
                        set: { container.settingsStore.blockAds = $0 }
                    ))

                    NavigationLink("DNS over HTTPS") {
                        DoHSettingsView()
                    }

                    HStack {
                        Text("차단 룰 수")
                        Spacer()
                        Text("\(container.contentBlocker.ruleCount)개")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("프라이버시", systemImage: "lock.fill")
                }

                // VPN
                Section {
                    Toggle("VPN 자동 연결", isOn: Binding(
                        get: { container.settingsStore.vpnAutoConnect },
                        set: { container.settingsStore.vpnAutoConnect = $0 }
                    ))
                    Toggle("Kill Switch", isOn: Binding(
                        get: { container.settingsStore.vpnKillSwitch },
                        set: { container.settingsStore.vpnKillSwitch = $0 }
                    ))
                } header: {
                    Label("VPN", systemImage: "shield.fill")
                }

                // Downloads
                Section {
                    Picker("기본 화질", selection: Binding(
                        get: { container.settingsStore.defaultQuality },
                        set: { container.settingsStore.defaultQuality = $0 }
                    )) {
                        Text("1080p").tag("1080p")
                        Text("720p").tag("720p")
                        Text("480p").tag("480p")
                    }

                    Toggle("Vault 자동 잠금", isOn: Binding(
                        get: { container.settingsStore.autoLockVault },
                        set: { container.settingsStore.autoLockVault = $0 }
                    ))
                } header: {
                    Label("다운로드", systemImage: "arrow.down.circle")
                }

                // Appearance
                Section {
                    Toggle("웹 강제 다크모드", isOn: Binding(
                        get: { container.settingsStore.forceDarkWeb },
                        set: { container.settingsStore.forceDarkWeb = $0 }
                    ))

                    Picker("탭바 위치", selection: Binding(
                        get: { container.settingsStore.tabBarPosition },
                        set: { container.settingsStore.tabBarPosition = $0 }
                    )) {
                        Text("상단").tag("top")
                        Text("하단").tag("bottom")
                    }
                } header: {
                    Label("외관", systemImage: "paintpalette.fill")
                }

                // Search
                Section {
                    Picker("기본 검색 엔진", selection: Binding(
                        get: { container.settingsStore.searchEngine },
                        set: { container.settingsStore.searchEngine = $0 }
                    )) {
                        Text("DuckDuckGo").tag("DuckDuckGo")
                        Text("Brave Search").tag("Brave")
                        Text("Google").tag("Google")
                        Text("Naver").tag("Naver")
                    }
                } header: {
                    Label("검색", systemImage: "magnifyingglass")
                }

                // About
                Section {
                    HStack {
                        Text("버전")
                        Spacer()
                        Text("0.1.0 (빌드 1)")
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink("개인정보처리방침") {
                        PrivacyPolicyView()
                    }

                    NavigationLink("오픈소스 라이선스") {
                        LicensesView()
                    }
                } header: {
                    Label("정보", systemImage: "info.circle")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                        .foregroundStyle(GhostTheme.accent)
                }
            }
        }
    }
}

// MARK: - DoH Settings
struct DoHSettingsView: View {
    @Environment(DNSManager.self) private var dns

    var body: some View {
        List {
            ForEach(DNSManager.Provider.allCases) { provider in
                Button {
                    Task { await dns.apply(provider: provider) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: provider.icon)
                            .foregroundStyle(dns.activeProvider == provider ? GhostTheme.accent : Color.gray)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.rawValue)
                                .foregroundStyle(.primary)
                            if !provider.serverURL.isEmpty {
                                Text(provider.serverURL)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        if dns.activeProvider == provider {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(GhostTheme.accent)
                        }
                    }
                }
            }

            if let error = dns.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(GhostTheme.danger)
            }
        }
        .navigationTitle("DNS over HTTPS")
    }
}

// MARK: - Placeholder Views
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("GhostStream 개인정보처리방침")
                    .font(.title2.bold())

                Text("""
                GhostStream은 사용자의 프라이버시를 최우선으로 합니다.

                1. 로컬 온니: 모든 데이터는 기기에만 저장됩니다.
                2. 서버리스: 자체 서버에 어떠한 사용자 데이터도 전송하지 않습니다.
                3. SDK 제로: Firebase, Facebook SDK 등 제3자 분석 도구를 일절 사용하지 않습니다.
                4. 최소 권한: 카메라, 연락처, 위치 권한을 요청하지 않습니다.

                VPN 서비스의 경우 연결 로그를 수집하지 않으며, RAM-only 서버를 운영합니다.
                """)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("개인정보처리방침")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LicensesView: View {
    var body: some View {
        List {
            ForEach(["WireGuardKit", "CryptoKit (Apple)", "WebKit (Apple)"], id: \.self) { lib in
                Text(lib).font(.subheadline)
            }
        }
        .navigationTitle("오픈소스 라이선스")
    }
}
