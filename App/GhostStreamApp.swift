// App/GhostStreamApp.swift
import SwiftUI

@main
struct GhostStreamApp: App {
    @State private var container = DIContainer()
    @State private var showJailbreakAlert = false
    @AppStorage("appTheme") private var appTheme = "system" // system, light, dark

    var body: some Scene {
        WindowGroup {
            BrowserContainerView()
                .environment(container)
                .environment(container.tabManager)
                .environment(container.downloadManager)
                .environment(container.privacyEngine)
                .environment(container.vaultManager)
                .environment(container.dnsManager)
                .environment(container.contentBlocker)
                .preferredColorScheme(colorScheme)
                .onAppear {
                    if JailbreakDetector.isJailbroken { showJailbreakAlert = true }
                }
                .alert("보안 경고", isPresented: $showJailbreakAlert) {
                    Button("계속 사용", role: .destructive) {}
                } message: {
                    Text("이 기기는 탈옥 상태로 감지되었습니다. Vault 보안이 약화될 수 있습니다.")
                }
        }
    }

    private var colorScheme: ColorScheme? {
        switch appTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil // system
        }
    }
}
