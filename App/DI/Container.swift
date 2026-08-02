// App/DI/Container.swift
import SwiftUI
import GhostStreamCore

@Observable
final class DIContainer: @unchecked Sendable {
    let tabManager: TabManager
    let downloadManager: MediaDownloadManager
    let privacyEngine: PrivacyEngine
    let vaultManager: VaultManager
    let dnsManager: DNSManager
    let contentBlocker: ContentBlockerManager
    let settingsStore: SettingsStore
    let bookmarkManager: BookmarkManager

    init() {
        // ★ CF 안정성: 문제되는 기능을 1회 강제 해제
        DiagnosticMode.applyCFSafetyMigration()
        self.settingsStore = SettingsStore()
        self.contentBlocker = ContentBlockerManager()
        self.dnsManager = DNSManager()
        self.privacyEngine = PrivacyEngine(contentBlocker: contentBlocker)
        self.vaultManager = VaultManager()
        self.downloadManager = MediaDownloadManager(vaultManager: vaultManager)
        self.tabManager = TabManager()
        self.bookmarkManager = BookmarkManager()
        // ★ 광고 차단 규칙 앱 시작 시 즉시 컴파일 (WebView 생성 전에 완료)
        Task {
            await contentBlocker.compile()
            // 원격 필터(대규모 광고 도메인) 백그라운드 다운로드 후 재컴파일
            await contentBlocker.downloadLatestRules()
        }
    }
}

// MARK: - Settings Store
@Observable
final class SettingsStore: @unchecked Sendable {
    @ObservationIgnored @AppStorage("searchEngine") var searchEngine: String = "DuckDuckGo"
    @ObservationIgnored @AppStorage("blockTrackers") var blockTrackers: Bool = true
    @ObservationIgnored @AppStorage("blockFingerprinting") var blockFingerprinting: Bool = true
    @ObservationIgnored @AppStorage("blockAds") var blockAds: Bool = true
    @ObservationIgnored @AppStorage("dohProvider") var dohProvider: String = "cloudflare"
    @ObservationIgnored @AppStorage("defaultQuality") var defaultQuality: String = "720p"
    @ObservationIgnored @AppStorage("autoLockVault") var autoLockVault: Bool = true
    @ObservationIgnored @AppStorage("forceDarkWeb") var forceDarkWeb: Bool = false

    var searchEngineURL: String {
        switch searchEngine {
        case "Google": return "https://www.google.com/search?q="
        case "Brave": return "https://search.brave.com/search?q="
        case "Naver": return "https://search.naver.com/search.naver?query="
        default: return "https://duckduckgo.com/?q="
        }
    }
}
