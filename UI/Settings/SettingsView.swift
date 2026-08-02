// UI/Settings/SettingsView.swift
import SwiftUI
import GhostStreamCore
import WebKit

struct SettingsView: View {
    @Environment(DIContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @AppStorage("blockTrackers") private var blockTrackers = true
    @AppStorage("blockFingerprinting") private var blockFingerprinting = true
    @AppStorage("blockAds") private var blockAds = true
    @AppStorage("autoLockVault") private var autoLockVault = true
    @AppStorage("searchEngine") private var searchEngine = "DuckDuckGo"
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("clearOnExit") private var clearOnExit = false
    @AppStorage("addressBarPosition") private var addressBarBottom = true
    @AppStorage("autoDismissCookies") private var autoDismissCookies = true
    @State private var showClearAlert = false
    @State private var profileChanged = false
    @State private var relayRefresh = UUID()
    @State private var relayTesting = false
    @State private var relayTestIP: String?
    @State private var diagRefresh = UUID()
    @State private var needsRestart = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $blockAds) { Label("광고 차단", systemImage: "eye.slash") }
                    Toggle(isOn: $blockTrackers) { Label("트래커 차단", systemImage: "hand.raised.fill") }
                    Toggle(isOn: $blockFingerprinting) { Label("핑거프린팅 방어", systemImage: "fingerprint") }
                    NavigationLink { DoHSettingsView() } label: { Label("Privacy DNS (DoH)", systemImage: "network.badge.shield.half.filled") }
                    HStack {
                        Label("차단 규칙", systemImage: "list.bullet.rectangle.portrait"); Spacer()
                        Text("\(container.contentBlocker.ruleCount)개").foregroundStyle(.secondary).font(.subheadline)
                    }
                } header: { Text("프라이버시 & 보안") } footer: { Text("광고, 트래커, 핑거프린팅을 차단합니다.") }

                // ★ 기기 위장 (DeviceProfile)
                Section {
                    HStack {
                        Label("현재 기기", systemImage: "iphone.gen3"); Spacer()
                        Text(DeviceProfileManager.shared.activeProfile.name)
                            .foregroundStyle(.teal).font(.subheadline)
                    }
                    Button {
                        DeviceProfileManager.shared.refreshProfile()
                        profileChanged = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { profileChanged = false }
                        }
                    } label: {
                        HStack {
                            Label("다른 기기로 변경", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if profileChanged {
                                Text("✅ \(DeviceProfileManager.shared.activeProfile.name)")
                                    .font(.caption).foregroundStyle(.green)
                            }
                        }
                    }
                } header: { Text("기기 위장") } footer: {
                    Text("웹사이트에 다른 iPhone 모델로 보이게 합니다. 변경 후 새 탭에서 적용됩니다.")
                }

                // ★ IP 보호 (네트워크 릴레이)
                Section {
                    Toggle(isOn: Binding(
                        get: { RelayManager.shared.isEnabled },
                        set: { on in
                            RelayManager.shared.activeProvider = on ? .fastly : .disabled
                            relayRefresh = UUID()
                        }
                    )) {
                        Label("IP 주소 보호", systemImage: "network.badge.shield.half.filled")
                    }
                    if RelayManager.shared.isEnabled {
                        Button {
                            relayTesting = true
                            Task {
                                let result = await RelayManager.shared.testConnection()
                                await MainActor.run {
                                    relayTesting = false
                                    relayTestIP = result.ip
                                }
                            }
                        } label: {
                            HStack {
                                Label("연결 테스트", systemImage: "checkmark.circle")
                                Spacer()
                                if relayTesting {
                                    ProgressView().scaleEffect(0.8)
                                } else if let ip = relayTestIP {
                                    Text(ip).font(.caption).foregroundStyle(.green)
                                }
                            }
                        }
                    }
                } header: { Text("IP 보호") } footer: {
                    Text("네트워크 릴레이를 통해 접속하여 웹사이트가 실제 IP를 볼 수 없게 합니다. VPN과 유사하지만 브라우저 트래픽만 보호합니다. iOS 17 이상 필요.")
                }

                Section {
                    Toggle(isOn: $autoLockVault) { Label("보안 폴더 자동 잠금", systemImage: "lock.shield") }
                } header: { Text("보안 폴더") }

                Section {
                    Picker(selection: $searchEngine) {
                        Text("DuckDuckGo").tag("DuckDuckGo"); Text("Brave Search").tag("Brave")
                        Text("Google").tag("Google"); Text("Naver").tag("Naver")
                    } label: { Label("검색 엔진", systemImage: "magnifyingglass") }
                    Picker(selection: $appTheme) {
                        Text("시스템 설정").tag("system")
                        Text("라이트 모드").tag("light")
                        Text("다크 모드").tag("dark")
                    } label: { Label("테마", systemImage: "circle.lefthalf.filled") }
                    // ★ 주소바 위치
                    Toggle(isOn: $addressBarBottom) {
                        Label("주소바 하단 배치", systemImage: "rectangle.bottomhalf.inset.filled")
                    }
                    // ★ 쿠키 배너 자동 거부
                    Toggle(isOn: $autoDismissCookies) {
                        Label("쿠키 배너 자동 거부", systemImage: "xmark.shield")
                    }
                } header: { Text("검색 & 브라우저") }

                Section {
                    Toggle(isOn: $clearOnExit) {
                        Label("앱 종료 시 자동 삭제", systemImage: "clock.arrow.circlepath")
                    }
                    Button(role: .destructive) { showClearAlert = true } label: {
                        Label("브라우징 데이터 삭제", systemImage: "trash").foregroundStyle(.red)
                    }
                } header: { Text("데이터 관리") } footer: {
                    Text("쿠키, 캐시를 삭제합니다. 다운로드 파일은 유지됩니다. 자동 삭제를 켜면 앱을 나갈 때마다 쿠키가 지워지지만, 로그인과 보안 확인(Cloudflare)을 매번 다시 해야 합니다.")
                }

                // ★ 진단 모드 — CF 문제 원인 격리용
                Section {
                    Button {
                        DiagnosticMode.disableAll()
                        diagRefresh = UUID()
                        needsRestart = true
                    } label: {
                        Label("모든 기능 끄기 (순수 브라우저)", systemImage: "power")
                            .foregroundStyle(.orange)
                    }
                    Button {
                        DiagnosticMode.enableAll()
                        diagRefresh = UUID()
                        needsRestart = true
                    } label: {
                        Label("모든 기능 켜기 (기본)", systemImage: "checkmark.circle")
                    }
                    diagToggle("광고/트래커 차단", DiagnosticMode.adBlockEnabled) { DiagnosticMode.adBlockEnabled = $0 }
                    diagToggle("제3자 쿠키 차단", DiagnosticMode.cookieBlockEnabled) { DiagnosticMode.cookieBlockEnabled = $0 }
                    diagToggle("핑거프린팅 방어", DiagnosticMode.fingerprintDefenseEnabled) { DiagnosticMode.fingerprintDefenseEnabled = $0 }
                    diagToggle("콘텐츠 스크립트", DiagnosticMode.contentScriptsEnabled) { DiagnosticMode.contentScriptsEnabled = $0 }
                    diagToggle("리다이렉트/팝업 차단", DiagnosticMode.redirectBlockEnabled) { DiagnosticMode.redirectBlockEnabled = $0 }
                    diagToggle("CF 자동 처리", DiagnosticMode.cfHandlingEnabled) { DiagnosticMode.cfHandlingEnabled = $0 }
                    diagToggle("기기 위장 UA", DiagnosticMode.fakeUserAgentEnabled) { DiagnosticMode.fakeUserAgentEnabled = $0 }
                    diagToggle("네트워크 릴레이(프록시)", DiagnosticMode.relayEnabled) { DiagnosticMode.relayEnabled = $0 }
                    diagToggle("영구 쿠키 저장", DiagnosticMode.persistentCookiesEnabled) { DiagnosticMode.persistentCookiesEnabled = $0 }
                    if needsRestart {
                        Text("⚠️ 앱을 완전히 종료 후 다시 실행해야 적용됩니다")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } header: { Text("진단 모드") } footer: {
                    Text("CF(보안 확인) 문제 원인을 찾기 위한 기능입니다. '모든 기능 끄기' 후 앱을 재시작하고 CF 사이트를 테스트하세요. 통과되면 기능을 하나씩 켜가며 범인을 찾을 수 있습니다.")
                }

                Section {
                    HStack {
                        Label("버전", systemImage: "info.circle"); Spacer()
                        Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (빌드 \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                            .foregroundStyle(.secondary).font(.subheadline)
                    }
                    NavigationLink { PrivacyPolicyView() } label: { Label("개인정보처리방침", systemImage: "hand.raised") }
                    NavigationLink { LicensesView() } label: { Label("오픈소스 라이선스", systemImage: "doc.text") }
                } header: { Text("정보") }
            }
            .navigationTitle("설정").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("완료") { dismiss() }.fontWeight(.semibold) } }
            .alert("브라우징 데이터 삭제", isPresented: $showClearAlert) {
                Button("삭제", role: .destructive) { clearBrowsingData() }
                Button("취소", role: .cancel) {}
            } message: { Text("쿠키, 캐시, 로컬 스토리지가 삭제됩니다.") }
        }
    }

    private func diagToggle(_ title: String, _ value: Bool, _ setter: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(
            get: { value },
            set: { setter($0); diagRefresh = UUID(); needsRestart = true }
        )) {
            Text(title).font(.subheadline)
        }
    }

    private func clearBrowsingData() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
            NotificationCenter.default.post(name: .downloadCompleted, object: "브라우징 데이터 삭제 완료")
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
                        Image(systemName: provider.icon).foregroundStyle(dns.activeProvider == provider ? .green : .gray).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.rawValue).foregroundStyle(.primary)
                            if !provider.serverURL.isEmpty { Text(provider.serverURL).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if dns.activeProvider == provider { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                }
            }
        }.navigationTitle("Privacy DNS")
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                policyItem("1", "로컬 전용", "모든 데이터는 기기에만 저장됩니다.")
                policyItem("2", "서버리스", "자체 서버 없음. 사용자 데이터 미수집.")
                policyItem("3", "SDK 제로", "Firebase, Facebook SDK 등 미사용.")
                policyItem("4", "최소 권한", "카메라, 연락처, 위치 권한 미요청.")
                policyItem("5", "프라이빗 탭 격리", "프라이빗 탭은 메모리에만 저장되어 닫으면 사라집니다. 일반 탭은 로그인 유지를 위해 쿠키를 공유하며, Fire 버튼으로 언제든 삭제할 수 있습니다.")
                policyItem("6", "AES-256 암호화", "보안 폴더 파일은 AES-256-GCM 암호화.")
            }.padding()
        }.navigationTitle("개인정보처리방침").navigationBarTitleDisplayMode(.inline)
    }
    private func policyItem(_ num: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(num).font(.headline).foregroundStyle(.teal)
                .frame(width: 28, height: 28).background(.teal.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(desc).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct LicensesView: View {
    var body: some View {
        List {
            ForEach(["WebKit (Apple)", "CryptoKit (Apple)", "CommonCrypto (Apple)", "SwiftUI (Apple)"], id: \.self) { Text($0) }
        }.navigationTitle("오픈소스 라이선스")
    }
}
