// App/DI/Container.swift
import SwiftUI

@Observable
final class DIContainer: @unchecked Sendable {
    let tabManager: TabManager
    let downloadManager: MediaDownloadManager
    let privacyEngine: PrivacyEngine
    let vaultManager: VaultManager
    let dnsManager: DNSManager
    let contentBlocker: ContentBlockerManager
    let settingsStore: SettingsStore

    init() {
        self.settingsStore = SettingsStore()
        self.contentBlocker = ContentBlockerManager()
        self.dnsManager = DNSManager()
        self.privacyEngine = PrivacyEngine(contentBlocker: contentBlocker)
        self.vaultManager = VaultManager()
        self.downloadManager = MediaDownloadManager(vaultManager: vaultManager)
        self.tabManager = TabManager()
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
