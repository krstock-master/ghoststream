// UI/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @Environment(DIContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @AppStorage("blockTrackers") private var blockTrackers = true
    @AppStorage("blockFingerprinting") private var blockFingerprinting = true
    @AppStorage("blockAds") private var blockAds = true
    @AppStorage("vpnAutoConnect") private var vpnAutoConnect = false
    @AppStorage("vpnKillSwitch") private var vpnKillSwitch = false
    @AppStorage("defaultQuality") private var defaultQuality = "720p"
    @AppStorage("autoLockVault") private var autoLockVault = true
    @AppStorage("forceDarkWeb") private var forceDarkWeb = false
    @AppStorage("tabBarPosition") private var tabBarPosition = "top"
    @AppStorage("searchEngine") private var searchEngine = "DuckDuckGo"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("트래커 차단", isOn: $blockTrackers)
                    Toggle("핑거프린팅 방어", isOn: $blockFingerprinting)
                    Toggle("광고 차단", isOn: $blockAds)
                    NavigationLink("DNS over HTTPS") { DoHSettingsView() }
                    HStack {
                        Text("차단 룰 수")
                        Spacer()
                        Text("\(container.contentBlocker.ruleCount)개").foregroundStyle(Color.gray)
                    }
                } header: { Label("프라이버시", systemImage: "lock.fill") }

                Section {
                    Toggle("VPN 자동 연결", isOn: $vpnAutoConnect)
                    Toggle("Kill Switch", isOn: $vpnKillSwitch)
                } header: { Label("VPN", systemImage: "shield.fill") }

                Section {
                    Picker("기본 화질", selection: $defaultQuality) {
                        Text("1080p").tag("1080p")
                        Text("720p").tag("720p")
                        Text("480p").tag("480p")
                    }
                    Toggle("Vault 자동 잠금", isOn: $autoLockVault)
                } header: { Label("다운로드", systemImage: "arrow.down.circle") }

                Section {
                    Toggle("웹 강제 다크모드", isOn: $forceDarkWeb)
                    Picker("탭바 위치", selection: $tabBarPosition) {
                        Text("상단").tag("top")
                        Text("하단").tag("bottom")
                    }
                } header: { Label("외관", systemImage: "paintpalette.fill") }

                Section {
                    Picker("기본 검색 엔진", selection: $searchEngine) {
                        Text("DuckDuckGo").tag("DuckDuckGo")
                        Text("Brave Search").tag("Brave")
                        Text("Google").tag("Google")
                        Text("Naver").tag("Naver")
                    }
                } header: { Label("검색", systemImage: "magnifyingglass") }

                Section {
                    HStack {
                        Text("버전"); Spacer()
                        Text("0.2.0").foregroundStyle(Color.gray)
                    }
                    NavigationLink("개인정보처리방침") { PrivacyPolicyView() }
                    NavigationLink("오픈소스 라이선스") { LicensesView() }
                } header: { Label("정보", systemImage: "info.circle") }
            }
            .navigationTitle("설정").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.foregroundStyle(GhostTheme.accent)
                }
            }
        }
    }
}

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
                            Text(provider.rawValue).foregroundStyle(.primary)
                            if !provider.serverURL.isEmpty {
                                Text(provider.serverURL).font(.caption).foregroundStyle(Color.gray)
                            }
                        }
                        Spacer()
                        if dns.activeProvider == provider {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(GhostTheme.accent)
                        }
                    }
                }
            }
            if let error = dns.error {
                Text(error).font(.caption).foregroundStyle(GhostTheme.danger)
            }
        }
        .navigationTitle("DNS over HTTPS")
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("GhostStream 개인정보처리방침").font(.title2.bold())
                Text("GhostStream은 사용자의 프라이버시를 최우선으로 합니다.\n\n1. 로컬 온니: 모든 데이터는 기기에만 저장됩니다.\n2. 서버리스: 자체 서버에 어떠한 사용자 데이터도 전송하지 않습니다.\n3. SDK 제로: Firebase, Facebook SDK 등 제3자 분석 도구를 일절 사용하지 않습니다.\n4. 최소 권한: 카메라, 연락처, 위치 권한을 요청하지 않습니다.\n\nVPN 서비스의 경우 연결 로그를 수집하지 않으며, RAM-only 서버를 운영합니다.")
                    .font(.subheadline).foregroundStyle(Color.gray)
            }.padding()
        }
        .navigationTitle("개인정보처리방침").navigationBarTitleDisplayMode(.inline)
    }
}

struct LicensesView: View {
    var body: some View {
        List {
            ForEach(["WireGuardKit (MIT)", "CryptoKit (Apple)", "WebKit (Apple)", "CommonCrypto (Apple)"], id: \.self) { lib in
                Text(lib).font(.subheadline)
            }
        }
        .navigationTitle("오픈소스 라이선스")
    }
}
