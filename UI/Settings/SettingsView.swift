// UI/Settings/SettingsView.swift
import SwiftUI
import WebKit

struct SettingsView: View {
    @Environment(DIContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @AppStorage("blockTrackers") private var blockTrackers = true
    @AppStorage("blockFingerprinting") private var blockFingerprinting = true
    @AppStorage("blockAds") private var blockAds = true
    @AppStorage("defaultQuality") private var defaultQuality = "720p"
    @AppStorage("autoLockVault") private var autoLockVault = true
    @AppStorage("searchEngine") private var searchEngine = "DuckDuckGo"
    @AppStorage("autoSaveToGallery") private var autoSaveToGallery = true
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("addressBarPosition") private var addressBarBottom = true
    @AppStorage("autoDismissCookies") private var autoDismissCookies = true
    @State private var showClearAlert = false

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

                // ★ 위장 프로필 정보
                Section {
                    HStack {
                        Label("위장 기기", systemImage: "iphone.gen3"); Spacer()
                        Text(DeviceProfileManager.shared.activeProfile.name)
                            .foregroundStyle(.secondary).font(.subheadline)
                    }
                    HStack {
                        Label("방어 벡터", systemImage: "shield.lefthalf.filled"); Spacer()
                        Text("11개").foregroundStyle(.secondary).font(.subheadline)
                    }
                    Button {
                        DeviceProfileManager.shared.refreshProfile()
                        NotificationCenter.default.post(name: .downloadCompleted, object: "새 위장 프로필로 전환됨: \(DeviceProfileManager.shared.activeProfile.name)")
                    } label: {
                        Label("프로필 갱신", systemImage: "arrow.triangle.2.circlepath")
                    }
                } header: { Text("핑거프린트 위장") } footer: { Text("세션마다 대중적인 iPhone 모델로 위장하여 기기 식별을 차단합니다.") }

                Section {
                    Toggle(isOn: $autoSaveToGallery) { Label("다운로드 후 자동 갤러리 저장", systemImage: "photo.badge.arrow.down") }
                    Picker(selection: $defaultQuality) {
                        Text("1080p").tag("1080p"); Text("720p").tag("720p"); Text("480p").tag("480p"); Text("자동").tag("Auto")
                    } label: { Label("기본 화질", systemImage: "dial.medium") }
                    Toggle(isOn: $autoLockVault) { Label("보안 폴더 자동 잠금", systemImage: "lock.shield") }
                } header: { Text("다운로드 & 저장") } footer: { Text("다운로드 완료 시 자동으로 사진 앱에 저장됩니다.") }

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
                    Button(role: .destructive) { showClearAlert = true } label: {
                        Label("브라우징 데이터 삭제", systemImage: "trash").foregroundStyle(.red)
                    }
                } header: { Text("데이터 관리") } footer: { Text("쿠키, 캐시를 삭제합니다. 다운로드 파일은 유지.") }

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
                policyItem("5", "탭 격리", "각 탭의 쿠키는 서로 격리됩니다.")
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
