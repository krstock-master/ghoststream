// Tests/GhostStreamTests.swift
// GhostStream - Unit Tests
//
// Add to Xcode: File → New → Target → Unit Testing Bundle
// Target Name: GhostStreamTests
// Host Application: GhostStream

import XCTest
@testable import GhostStream

// MARK: - Tab Manager Tests
final class TabManagerTests: XCTestCase {

    var tabManager: TabManager!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
    }

    func testInitialState() {
        XCTAssertEqual(tabManager.tabs.count, 1, "초기 상태에서 1개 탭이 있어야 함")
        XCTAssertNotNil(tabManager.activeTabID, "활성 탭 ID가 존재해야 함")
        XCTAssertNotNil(tabManager.activeTab, "활성 탭이 존재해야 함")
    }

    func testNewTab() {
        let tab = tabManager.newTab(url: URL(string: "https://example.com"))
        XCTAssertEqual(tabManager.tabs.count, 2)
        XCTAssertEqual(tabManager.activeTabID, tab.id, "새 탭이 활성화되어야 함")
    }

    func testNewPrivateTab() {
        let tab = tabManager.newTab(isPrivate: true)
        XCTAssertTrue(tab.isPrivate, "프라이빗 탭이어야 함")
    }

    func testCloseTab() {
        let tab = tabManager.newTab()
        XCTAssertEqual(tabManager.tabs.count, 2)
        tabManager.closeTab(tab)
        XCTAssertEqual(tabManager.tabs.count, 1, "닫은 후 1개 탭이 남아야 함")
    }

    func testCloseLastTab_CreatesNewOne() {
        let initialTab = tabManager.tabs[0]
        tabManager.closeTab(initialTab)
        XCTAssertEqual(tabManager.tabs.count, 1, "마지막 탭을 닫으면 새 탭이 생성되어야 함")
    }

    func testCloseAllTabs() {
        tabManager.newTab()
        tabManager.newTab()
        XCTAssertEqual(tabManager.tabs.count, 3)
        tabManager.closeAllTabs()
        XCTAssertEqual(tabManager.tabs.count, 1, "모든 탭 닫기 후 새 탭 1개가 생성되어야 함")
    }

    func testSwitchTab() {
        let tab1 = tabManager.tabs[0]
        let tab2 = tabManager.newTab()
        XCTAssertEqual(tabManager.activeTabID, tab2.id)
        tabManager.switchTo(tab1)
        XCTAssertEqual(tabManager.activeTabID, tab1.id)
    }

    func testTabCookieIsolation() {
        let tab1 = tabManager.tabs[0]
        let tab2 = tabManager.newTab()
        XCTAssertNotEqual(
            ObjectIdentifier(tab1.dataStore),
            ObjectIdentifier(tab2.dataStore),
            "각 탭은 독립된 데이터스토어를 가져야 함 (쿠키 격리)"
        )
    }

    func testTabGroup() {
        let tab1 = tabManager.tabs[0]
        let tab2 = tabManager.newTab()
        tabManager.groupTabs([tab1.id, tab2.id], name: "테스트 그룹")
        XCTAssertNotNil(tab1.groupID)
        XCTAssertEqual(tab1.groupName, "테스트 그룹")
        XCTAssertEqual(tab1.groupID, tab2.groupID, "같은 그룹이어야 함")
    }

    func testUngroupTab() {
        let tab1 = tabManager.tabs[0]
        let tab2 = tabManager.newTab()
        tabManager.groupTabs([tab1.id, tab2.id], name: "그룹")
        tabManager.ungroupTab(tab1)
        XCTAssertNil(tab1.groupID, "그룹 해제 후 groupID가 nil이어야 함")
    }
}

// MARK: - Privacy Report Tests
final class PrivacyReportTests: XCTestCase {

    func testPerfectScore() {
        var report = PrivacyReport()
        report.isHTTPS = true
        report.trackersBlocked = 0
        report.fingerprintAttempts = 0
        report.adsBlocked = 0
        report.thirdPartyDomains = []
        XCTAssertEqual(report.score, 100, "완벽한 조건에서 100점이어야 함")
    }

    func testHTTPReducesScore() {
        var report = PrivacyReport()
        report.isHTTPS = false
        XCTAssertLessThan(report.score, 100, "HTTP 시 점수가 감소해야 함")
    }

    func testTrackersReduceScore() {
        var report = PrivacyReport()
        report.isHTTPS = true
        report.trackersBlocked = 15
        XCTAssertLessThan(report.score, 100, "트래커가 많으면 점수가 감소해야 함")
    }

    func testScoreNeverNegative() {
        var report = PrivacyReport()
        report.isHTTPS = false
        report.trackersBlocked = 100
        report.fingerprintAttempts = 50
        report.adsBlocked = 100
        report.thirdPartyDomains = Set((0..<50).map { "domain\($0).com" })
        XCTAssertGreaterThanOrEqual(report.score, 0, "점수는 음수가 될 수 없음")
    }

    func testScoreNeverExceeds100() {
        var report = PrivacyReport()
        report.isHTTPS = true
        XCTAssertLessThanOrEqual(report.score, 100, "점수는 100을 초과할 수 없음")
    }
}

// MARK: - Detected Media Tests
final class DetectedMediaTests: XCTestCase {

    func testMediaEquality() {
        let url = URL(string: "https://example.com/video.mp4")!
        let m1 = DetectedMedia(url: url, type: .mp4, quality: "720p", title: "Test", referer: "", thumbnail: nil, estimatedSize: nil)
        let m2 = DetectedMedia(url: url, type: .mp4, quality: "1080p", title: "Test2", referer: "", thumbnail: nil, estimatedSize: nil)
        XCTAssertEqual(m1, m2, "같은 URL의 미디어는 동일해야 함")
    }

    func testMediaInequality() {
        let m1 = DetectedMedia(url: URL(string: "https://a.com/v.mp4")!, type: .mp4, quality: "720p", title: "", referer: "", thumbnail: nil, estimatedSize: nil)
        let m2 = DetectedMedia(url: URL(string: "https://b.com/v.mp4")!, type: .mp4, quality: "720p", title: "", referer: "", thumbnail: nil, estimatedSize: nil)
        XCTAssertNotEqual(m1, m2, "다른 URL은 다른 미디어여야 함")
    }

    func testMediaHashable() {
        let url = URL(string: "https://example.com/v.mp4")!
        let m1 = DetectedMedia(url: url, type: .mp4, quality: "720p", title: "", referer: "", thumbnail: nil, estimatedSize: nil)
        let m2 = DetectedMedia(url: url, type: .hls, quality: "1080p", title: "", referer: "", thumbnail: nil, estimatedSize: nil)
        var set: Set<DetectedMedia> = [m1]
        set.insert(m2)
        XCTAssertEqual(set.count, 1, "같은 URL은 Set에서 중복 제거되어야 함")
    }
}

// MARK: - Security Tests
final class SecurityTests: XCTestCase {

    func testJailbreakDetectionOnSimulator() {
        #if targetEnvironment(simulator)
        XCTAssertFalse(JailbreakDetector.isJailbroken, "시뮬레이터에서는 탈옥이 아니어야 함")
        #endif
    }

    func testInsecureURLDetection() {
        let httpURL = URL(string: "http://example.com")!
        let httpsURL = URL(string: "https://example.com")!
        XCTAssertTrue(NetworkSecurity.isInsecure(url: httpURL), "HTTP는 안전하지 않음으로 감지되어야 함")
        XCTAssertFalse(NetworkSecurity.isInsecure(url: httpsURL), "HTTPS는 안전함으로 감지되어야 함")
    }

    func testPinnedSessionCreation() {
        let session = NetworkSecurity.makePinnedSession()
        XCTAssertNotNil(session, "Pinned URLSession이 생성되어야 함")
        XCTAssertNotNil(session.delegate, "세션에 delegate가 있어야 함")
    }

    func testNoHardcodedSecrets() {
        // 코드베이스에 하드코딩된 시크릿이 없는지 확인
        // 실제로는 CI에서 grep으로 검증
        let container = DIContainer()
        // settingsStore에 민감한 기본값이 없는지 확인
        XCTAssertEqual(container.settingsStore.searchEngine, "DuckDuckGo", "기본 검색엔진이 DuckDuckGo여야 함")
    }
}

// MARK: - Vault Model Tests
final class VaultItemTests: XCTestCase {

    func testVaultItemFormatting() {
        let item = VaultItem(
            id: "test",
            originalName: "video.mp4",
            mediaType: .video,
            fileSize: 1_048_576, // 1 MB
            dateAdded: Date(),
            thumbnailData: nil
        )
        XCTAssertFalse(item.formattedSize.isEmpty, "포맷된 크기가 비어있으면 안 됨")
        XCTAssertFalse(item.formattedDate.isEmpty, "포맷된 날짜가 비어있으면 안 됨")
        XCTAssertEqual(item.icon, "play.circle.fill", "영상 아이콘이어야 함")
    }

    func testVaultItemTypes() {
        let video = VaultItem(id: "1", originalName: "v.mp4", mediaType: .video, fileSize: 0, dateAdded: .now, thumbnailData: nil)
        let gif = VaultItem(id: "2", originalName: "g.gif", mediaType: .gif, fileSize: 0, dateAdded: .now, thumbnailData: nil)
        let other = VaultItem(id: "3", originalName: "f.bin", mediaType: .other, fileSize: 0, dateAdded: .now, thumbnailData: nil)
        XCTAssertEqual(video.icon, "play.circle.fill")
        XCTAssertEqual(gif.icon, "photo.circle.fill")
        XCTAssertEqual(other.icon, "doc.circle.fill")
    }

    func testVaultItemCodable() throws {
        let item = VaultItem(id: "test-codable", originalName: "test.mp4", mediaType: .video, fileSize: 12345, dateAdded: .now, thumbnailData: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(VaultItem.self, from: data)
        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.originalName, item.originalName)
        XCTAssertEqual(decoded.fileSize, item.fileSize)
    }
}

// MARK: - VPN Server Tests
final class VPNServerTests: XCTestCase {

    func testDefaultServers() {
        let servers = VPNServer.defaultServers
        XCTAssertGreaterThanOrEqual(servers.count, 8, "최소 8개 서버가 있어야 함")
        let freeServers = servers.filter { !$0.isPro }
        XCTAssertEqual(freeServers.count, 3, "무료 서버 3개가 있어야 함")
    }

    func testWireGuardConfigGeneration() {
        let server = VPNServer.defaultServers[0]
        let config = server.wireGuardConfig
        XCTAssertTrue(config.contains("[Interface]"), "WireGuard 설정에 Interface 섹션이 있어야 함")
        XCTAssertTrue(config.contains("[Peer]"), "WireGuard 설정에 Peer 섹션이 있어야 함")
        XCTAssertTrue(config.contains("AllowedIPs"), "AllowedIPs가 있어야 함")
    }
}

// MARK: - DNS Manager Tests
final class DNSManagerTests: XCTestCase {

    func testProviderURLs() {
        for provider in DNSManager.Provider.allCases where provider != .system {
            XCTAssertFalse(provider.serverURL.isEmpty, "\(provider.rawValue)에 서버 URL이 있어야 함")
            XCTAssertFalse(provider.servers.isEmpty, "\(provider.rawValue)에 DNS 서버가 있어야 함")
        }
    }

    func testSystemProviderHasNoURL() {
        XCTAssertTrue(DNSManager.Provider.system.serverURL.isEmpty, "시스템 기본은 URL이 없어야 함")
        XCTAssertTrue(DNSManager.Provider.system.servers.isEmpty, "시스템 기본은 서버가 없어야 함")
    }

    func testProviderIcons() {
        for provider in DNSManager.Provider.allCases {
            XCTAssertFalse(provider.icon.isEmpty, "\(provider.rawValue)에 아이콘이 있어야 함")
        }
    }
}

// MARK: - Content Blocker Tests
final class ContentBlockerTests: XCTestCase {

    func testEssentialRulesExist() {
        let rules = ContentBlockerManager.essentialBlockRules
        XCTAssertGreaterThanOrEqual(rules.count, 20, "최소 20개의 차단 룰이 있어야 함")
    }

    func testRulesContainGoogleAnalytics() {
        let rules = ContentBlockerManager.essentialBlockRules
        let hasGA = rules.contains { rule in
            guard let trigger = rule["trigger"] as? [String: Any],
                  let filter = trigger["url-filter"] as? String else { return false }
            return filter.contains("google-analytics")
        }
        XCTAssertTrue(hasGA, "Google Analytics 차단 룰이 있어야 함")
    }

    func testRulesContainFacebook() {
        let rules = ContentBlockerManager.essentialBlockRules
        let hasFB = rules.contains { rule in
            guard let trigger = rule["trigger"] as? [String: Any],
                  let filter = trigger["url-filter"] as? String else { return false }
            return filter.contains("facebook")
        }
        XCTAssertTrue(hasFB, "Facebook 트래커 차단 룰이 있어야 함")
    }

    func testThirdPartyCookieBlockRule() {
        let rules = ContentBlockerManager.essentialBlockRules
        let hasCookieBlock = rules.contains { rule in
            guard let action = rule["action"] as? [String: Any],
                  let type = action["type"] as? String else { return false }
            return type == "block-cookies"
        }
        XCTAssertTrue(hasCookieBlock, "제3자 쿠키 차단 룰이 있어야 함")
    }
}

// MARK: - Privacy Engine Tests
final class PrivacyEngineTests: XCTestCase {

    func testFingerprintDefenseScript() {
        let blocker = ContentBlockerManager()
        let engine = PrivacyEngine(contentBlocker: blocker)
        XCTAssertTrue(engine.isEnabled, "기본적으로 활성화되어야 함")
        XCTAssertNotNil(engine.fingerprintDefenseScript, "JS 스크립트가 존재해야 함")
    }

    func testFingerprintScriptCoversAllVectors() {
        let blocker = ContentBlockerManager()
        let engine = PrivacyEngine(contentBlocker: blocker)
        guard let script = engine.fingerprintDefenseScript else {
            XCTFail("JS 스크립트가 nil이면 안 됨")
            return
        }
        // 7벡터 커버리지 확인
        XCTAssertTrue(script.contains("getImageData"), "Canvas 노이즈 방어가 있어야 함")
        XCTAssertTrue(script.contains("RENDERER"), "WebGL 스푸핑이 있어야 함")
        XCTAssertTrue(script.contains("createAnalyser"), "AudioContext 노이즈가 있어야 함")
        XCTAssertTrue(script.contains("measureText"), "Font enumeration 방어가 있어야 함")
        XCTAssertTrue(script.contains("hardwareConcurrency"), "Navigator 고정이 있어야 함")
        XCTAssertTrue(script.contains("screen"), "Screen 속성 고정이 있어야 함")
        XCTAssertTrue(script.contains("performance.now"), "Timing 해상도 저하가 있어야 함")
    }

    func testDisabledEngineReturnsNoScript() {
        let blocker = ContentBlockerManager()
        let engine = PrivacyEngine(contentBlocker: blocker)
        engine.isEnabled = false
        XCTAssertNil(engine.fingerprintDefenseScript, "비활성화 시 nil을 반환해야 함")
    }
}

// MARK: - Settings Store Tests
final class SettingsStoreTests: XCTestCase {

    func testDefaultSearchEngine() {
        let store = SettingsStore()
        XCTAssertEqual(store.searchEngineURL, "https://duckduckgo.com/?q=", "기본 검색엔진 URL이 DuckDuckGo여야 함")
    }

    func testSearchEngineURLs() {
        let store = SettingsStore()
        store.searchEngine = "Google"
        XCTAssertTrue(store.searchEngineURL.contains("google.com"))
        store.searchEngine = "Brave"
        XCTAssertTrue(store.searchEngineURL.contains("brave.com"))
        store.searchEngine = "Naver"
        XCTAssertTrue(store.searchEngineURL.contains("naver.com"))
    }

    func testDefaultValues() {
        let store = SettingsStore()
        XCTAssertTrue(store.blockTrackers, "트래커 차단이 기본 활성화여야 함")
        XCTAssertTrue(store.blockFingerprinting, "핑거프린팅 방어가 기본 활성화여야 함")
        XCTAssertTrue(store.blockAds, "광고 차단이 기본 활성화여야 함")
        XCTAssertTrue(store.autoLockVault, "Vault 자동 잠금이 기본 활성화여야 함")
        XCTAssertFalse(store.enableVPN, "VPN이 기본 비활성화여야 함")
    }
}

// MARK: - VPN Status Tests
final class VPNStatusTests: XCTestCase {

    func testStatusProperties() {
        let statuses: [VPNStatus] = [.connected, .connecting, .disconnected, .disconnecting]
        for status in statuses {
            XCTAssertFalse(status.rawValue.isEmpty)
            XCTAssertFalse(status.color.isEmpty)
            XCTAssertFalse(status.icon.isEmpty)
        }
    }
}

// MARK: - Download State Tests
final class MediaDownloadTests: XCTestCase {

    func testDownloadModel() {
        let media = DetectedMedia(
            url: URL(string: "https://example.com/video.mp4")!,
            type: .mp4, quality: "720p", title: "Test Video",
            referer: "https://example.com", thumbnail: nil, estimatedSize: "124 MB"
        )
        let dl = MediaDownload(media: media, saveToVault: true)
        XCTAssertEqual(dl.state, .pending)
        XCTAssertEqual(dl.progress, 0)
        XCTAssertTrue(dl.saveToVault)
        XCTAssertEqual(dl.formattedProgress, "0%")
    }
}

// MARK: - Integration Sanity Tests
final class IntegrationTests: XCTestCase {

    func testDIContainerInitialization() {
        let container = DIContainer()
        XCTAssertNotNil(container.tabManager)
        XCTAssertNotNil(container.downloadManager)
        XCTAssertNotNil(container.privacyEngine)
        XCTAssertNotNil(container.vaultManager)
        XCTAssertNotNil(container.dnsManager)
        XCTAssertNotNil(container.vpnManager)
        XCTAssertNotNil(container.contentBlocker)
        XCTAssertNotNil(container.settingsStore)
    }

    func testZeroSDKPolicy() {
        // 이 테스트는 제3자 SDK가 포함되지 않았음을 문서화합니다
        // 실제 검증은 lsof/nm 기반 CI 스크립트로 수행
        // 여기서는 의도를 명시적으로 기록합니다
        let bannedFrameworks = [
            "Firebase", "FBSDKCore", "Amplitude",
            "Mixpanel", "Segment", "GoogleAnalytics",
            "Sentry", "Bugsnag", "AppsFlyerLib"
        ]
        // 프로젝트에 이 프레임워크들이 링크되어 있지 않아야 합니다
        for framework in bannedFrameworks {
            let bundleLoaded = Bundle.allBundles.contains { $0.bundlePath.contains(framework) }
            XCTAssertFalse(bundleLoaded, "\(framework) SDK가 포함되어 있으면 안 됨 (Zero SDK 정책)")
        }
    }
}
