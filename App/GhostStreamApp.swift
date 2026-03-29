// App/GhostStreamApp.swift
// GhostStream - Privacy Media Browser

import SwiftUI

@main
struct GhostStreamApp: App {
    @State private var container = DIContainer()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showJailbreakAlert = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    BrowserContainerView()
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .environment(container)
            .environment(container.tabManager)
            .environment(container.downloadManager)
            .environment(container.privacyEngine)
            .environment(container.vaultManager)
            .environment(container.dnsManager)
            .environment(container.vpnManager)
            // Theme controlled by user settings
            .onAppear {
                if JailbreakDetector.isJailbroken {
                    showJailbreakAlert = true
                }
            }
            .alert("보안 경고", isPresented: $showJailbreakAlert) {
                Button("계속 사용", role: .destructive) {}
            } message: {
                Text("이 기기는 탈옥 상태로 감지되었습니다. Vault 보안이 약화될 수 있습니다.")
            }
        }
    }
}
