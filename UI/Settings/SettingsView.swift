// UI/Settings/SettingsView.swift
import SwiftUI
import GhostStreamCore
import WebKit

struct SettingsView: View {
    @Environment(DIContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @AppStorage("searchEngine") private var searchEngine = "DuckDuckGo"
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("clearOnExit") private var clearOnExit = false
    // ★ v2.0.5: 개발자 옵션(진단 모드)은 버전 행을 7번 탭해야 노출
    @AppStorage("gs.developerMenuUnlocked") private var developerMenuUnlocked = false
    @State private var versionTapCount = 0
    @State private var showClearAlert = false
    @State private var profileChanged = false

    // ★ v2.0.5 제거된 설정 (백엔드에서 읽지 않던 키 — 표시만 되고 동작하지 않음)
    //   · "주소바 하단 배치" (addressBarPosition) — 주소바는 항상 하단
    //   · "쿠키 배너 자동 거부" (autoDismissCookies) — 항상 켜져 있음 (PrivacyScripts)
    //   · "보안 폴더 자동 잠금" (autoLockVault) — 미구현
    //   · "IP 보호" (RelayManager) — 백엔드 비활성화 중. 재도입 시 Network 팀과 협의

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PrivacyProtectionToggles()
                    NavigationLink { DoHSettingsView() } label: { Label("보안 DNS", systemImage: "network.badge.shield.half.filled") }
                    HStack {
                        Label("차단 규칙", systemImage: "list.bullet.rectangle.portrait"); Spacer()
                        Text("\(container.contentBlocker.ruleCount)개").foregroundStyle(.secondary).font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                } header: { Text("개인정보 보호") } footer: {
                    Text("변경 사항은 새로 여는 탭부터 적용됩니다. 이미 열린 탭은 앱을 다시 시작하면 적용됩니다.")
                }

                // ★ 화면 정보 위장 (UA는 CF 호환을 위해 실제 값 사용)
                Section {
                    HStack {
                        Label("현재 프로필", systemImage: "iphone.gen3"); Spacer()
                        Text(DeviceProfileManager.shared.activeProfile.name)
                            .foregroundStyle(.secondary).font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                    Button {
                        DeviceProfileManager.shared.refreshProfile()
                        profileChanged = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { profileChanged = false }
                        }
                    } label: {
                        HStack {
                            Label("다른 프로필로 변경", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if profileChanged {
                                Label("변경됨", systemImage: "checkmark")
                                    .labelStyle(.titleAndIcon)
                                    .font(.caption).foregroundStyle(.green)
                            }
                        }
                    }
                } header: { Text("기기 위장") } footer: {
                    Text("화면 크기 등 하드웨어 정보를 다른 iPhone처럼 보이게 합니다. 보안 확인(Cloudflare) 호환을 위해 브라우저 버전 정보는 그대로 사용합니다.")
                }

                Section {
                    Picker(selection: $searchEngine) {
                        Text("DuckDuckGo").tag("DuckDuckGo"); Text("Brave Search").tag("Brave")
                        Text("Google").tag("Google"); Text("Naver").tag("Naver")
                    } label: { Label("검색 엔진", systemImage: "magnifyingglass") }
                    Picker(selection: $appTheme) {
                        Text("시스템 설정").tag("system")
                        Text("라이트").tag("light")
                        Text("다크").tag("dark")
                    } label: { Label("테마", systemImage: "circle.lefthalf.filled") }
                } header: { Text("일반") }

                Section {
                    Toggle(isOn: $clearOnExit) {
                        Label("앱을 나갈 때 브라우징 데이터 삭제", systemImage: "clock.arrow.circlepath")
                    }
                    Button(role: .destructive) { showClearAlert = true } label: {
                        Label("브라우징 데이터 삭제", systemImage: "trash").foregroundStyle(.red)
                    }
                } header: { Text("데이터") } footer: {
                    Text("쿠키와 캐시를 삭제합니다. 다운로드한 파일은 유지됩니다. 자동 삭제를 켜면 로그인과 보안 확인(Cloudflare)을 매번 다시 해야 합니다.")
                }

                Section {
                    HStack {
                        Label("버전", systemImage: "info.circle"); Spacer()
                        Text(appVersion).foregroundStyle(.secondary).font(.subheadline)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { handleVersionTap() }
                    .accessibilityElement(children: .combine)
                    NavigationLink { PrivacyPolicyView() } label: { Label("개인정보처리방침", systemImage: "hand.raised") }
                    NavigationLink { LicensesView() } label: { Label("오픈소스 라이선스", systemImage: "doc.text") }
                    if developerMenuUnlocked {
                        NavigationLink { DeveloperOptionsView() } label: {
                            Label("개발자 옵션", systemImage: "wrench.and.screwdriver")
                        }
                    }
                } header: { Text("정보") }
            }
            .navigationTitle("설정").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("완료") { dismiss() }.fontWeight(.semibold) } }
            .alert("브라우징 데이터 삭제", isPresented: $showClearAlert) {
                Button("삭제", role: .destructive) { clearBrowsingData() }
                Button("취소", role: .cancel) {}
            } message: { Text("쿠키, 캐시, 로컬 저장소가 삭제됩니다.") }
        }
    }

    /// 버전 행 7회 탭 → 개발자 옵션 노출 (Android 스타일)
    private func handleVersionTap() {
        guard !developerMenuUnlocked else { return }
        versionTapCount += 1
        if versionTapCount >= 7 {
            withAnimation { developerMenuUnlocked = true }
            versionTapCount = 0
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func clearBrowsingData() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {}
        container.downloadManager.clearSessionData()
        // ★ v2.0.5: 일반 탭이 실제로 쓰는 공유 스토어도 삭제 (기존엔 default만 지워 쿠키가 남음)
        container.tabManager.sharedDataStore.removeData(ofTypes: types, modifiedSince: .distantPast) {
            NotificationCenter.default.post(name: .downloadCompleted, object: "브라우징 데이터를 삭제했습니다")
        }
    }
}

// MARK: - 개발자 옵션 (구 "진단 모드")
// CF(보안 확인) 문제 원인 격리용. 일반 사용자에게는 숨김 — 설정 > 버전 7회 탭으로 노출.
// 토글 동작은 Network/DiagnosticMode.swift API를 그대로 사용한다.
struct DeveloperOptionsView: View {
    @AppStorage("gs.developerMenuUnlocked") private var developerMenuUnlocked = false
    @Environment(\.dismiss) private var dismiss
    @State private var diagRefresh = UUID()
    @State private var needsRestart = false

    var body: some View {
        let _ = diagRefresh // 토글 변경 시 강제 갱신
        List {
            Section {
                Button {
                    DiagnosticMode.disableAll()
                    markChanged()
                } label: {
                    Label("모든 기능 끄기 (순수 브라우저)", systemImage: "power")
                        .foregroundStyle(.orange)
                }
                Button {
                    DiagnosticMode.enableAll()
                    markChanged()
                } label: {
                    Label("모든 기능 켜기 (기본)", systemImage: "checkmark.circle")
                }
            } footer: {
                Text("'모든 기능 끄기' 후 앱을 재시작하고 CF 사이트를 테스트하세요. 통과되면 기능을 하나씩 켜가며 원인을 찾을 수 있습니다.")
            }

            Section {
                diagToggle("광고/트래커 차단", getter: { DiagnosticMode.adBlockEnabled }, setter: { DiagnosticMode.adBlockEnabled = $0 })
                diagToggle("제3자 쿠키 차단", getter: { DiagnosticMode.cookieBlockEnabled }, setter: { DiagnosticMode.cookieBlockEnabled = $0 })
                diagToggle("핑거프린팅 방어", getter: { DiagnosticMode.fingerprintDefenseEnabled }, setter: { DiagnosticMode.fingerprintDefenseEnabled = $0 })
                diagToggle("콘텐츠 스크립트", getter: { DiagnosticMode.contentScriptsEnabled }, setter: { DiagnosticMode.contentScriptsEnabled = $0 })
                diagToggle("리다이렉트/팝업 차단", getter: { DiagnosticMode.redirectBlockEnabled }, setter: { DiagnosticMode.redirectBlockEnabled = $0 })
                diagToggle("CF 자동 처리", getter: { DiagnosticMode.cfHandlingEnabled }, setter: { DiagnosticMode.cfHandlingEnabled = $0 })
                diagToggle("기기 위장 UA", getter: { DiagnosticMode.fakeUserAgentEnabled }, setter: { DiagnosticMode.fakeUserAgentEnabled = $0 })
                diagToggle("네트워크 릴레이(프록시)", getter: { DiagnosticMode.relayEnabled }, setter: { DiagnosticMode.relayEnabled = $0 })
                diagToggle("영구 쿠키 저장", getter: { DiagnosticMode.persistentCookiesEnabled }, setter: { DiagnosticMode.persistentCookiesEnabled = $0 })
            } header: { Text("진단 토글") } footer: {
                if needsRestart {
                    Label("앱을 완전히 종료한 뒤 다시 실행해야 적용됩니다", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button(role: .destructive) {
                    developerMenuUnlocked = false
                    dismiss()
                } label: {
                    Label("개발자 옵션 숨기기", systemImage: "eye.slash")
                }
            } footer: {
                Text("숨겨도 위 설정값은 유지됩니다.")
            }
        }
        .navigationTitle("개발자 옵션").navigationBarTitleDisplayMode(.inline)
    }

    private func markChanged() {
        diagRefresh = UUID()
        needsRestart = true
    }

    private func diagToggle(_ title: String, getter: @escaping () -> Bool, setter: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(
            get: { getter() },
            set: { setter($0); markChanged() }
        )) {
            Text(title).font(.subheadline)
        }
    }
}

// MARK: - 사용자용 보호 토글
// ★ v2.0.5: 기존 "blockAds/blockTrackers/blockFingerprinting" 키는 어디에서도 읽지 않아
//   토글이 실제로 아무 효과가 없었다. 실제 동작을 제어하는 DiagnosticMode 키에 직접 바인딩한다.
//   (키 이름은 Network/DiagnosticMode.swift와 반드시 일치해야 함: diag.adBlock, diag.fingerprint)
//   광고/트래커는 하나의 ContentBlocker 규칙으로 동작하므로 토글도 하나로 합쳤다.
struct PrivacyProtectionToggles: View {
    @AppStorage("diag.adBlock") private var adBlock = true
    @AppStorage("diag.fingerprint") private var fingerprint = true

    var body: some View {
        Toggle(isOn: $adBlock) { Label("광고·트래커 차단", systemImage: "hand.raised.fill") }
        Toggle(isOn: $fingerprint) { Label("핑거프린팅 방어", systemImage: "fingerprint") }
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
        }.navigationTitle("보안 DNS")
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
