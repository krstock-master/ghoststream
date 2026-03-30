// Tests/GhostStreamTests.swift
import XCTest
import GhostStreamCore
@testable import GhostStream

// MARK: - Tab Manager Tests
final class TabManagerTests: XCTestCase {
    func testNewTab() {
        let manager = TabManager()
        XCTAssertEqual(manager.tabs.count, 1, "초기 탭 1개")
        let _ = manager.newTab()
        XCTAssertEqual(manager.tabs.count, 2, "탭 추가 후 2개")
    }

    func testPrivateTab() {
        let manager = TabManager()
        let tab = manager.newTab(isPrivate: true)
        XCTAssertTrue(tab.isPrivate, "프라이빗 탭이어야 함")
    }

    func testCloseTab() {
        let manager = TabManager()
        let tab = manager.newTab()
        manager.closeTab(tab)
        XCTAssertEqual(manager.tabs.count, 1, "탭 닫기 후 1개")
    }

    func testCloseAllTabs() {
        let manager = TabManager()
        let _ = manager.newTab()
        let _ = manager.newTab()
        manager.closeAllTabs()
        XCTAssertEqual(manager.tabs.count, 1, "모든 탭 닫기 후 최소 1개")
    }

    func testSwitchTab() {
        let manager = TabManager()
        let tab2 = manager.newTab()
        manager.switchTo(tab2)
        XCTAssertEqual(manager.activeTabID, tab2.id, "활성 탭이 변경되어야 함")
    }
}

// MARK: - Security Tests
final class SecurityTests: XCTestCase {
    func testJailbreakDetection() {
        #if targetEnvironment(simulator)
        XCTAssertFalse(JailbreakDetector.isJailbroken, "시뮬레이터에서는 탈옥 미감지")
        #endif
    }

    func testNetworkSecurityInsecure() {
        let http = URL(string: "http://example.com")!
        let https = URL(string: "https://example.com")!
        XCTAssertTrue(NetworkSecurity.isInsecure(url: http), "HTTP는 insecure")
        XCTAssertFalse(NetworkSecurity.isInsecure(url: https), "HTTPS는 secure")
    }
}

// MARK: - Privacy Engine Tests
final class PrivacyEngineTests: XCTestCase {
    func testFingerprintDefenseScript() {
        let blocker = ContentBlockerManager()
        let engine = PrivacyEngine(contentBlocker: blocker)
        XCTAssertNotNil(engine.fingerprintDefenseScript, "핑거프린트 방어 스크립트가 있어야 함")
        XCTAssertTrue(engine.fingerprintDefenseScript!.contains("canvas"), "Canvas 핑거프린트 방어 포함")
    }

    func testContentBlockerRuleCount() {
        let blocker = ContentBlockerManager()
        XCTAssertGreaterThan(blocker.ruleCount, 0, "차단 규칙이 1개 이상")
    }
}

// MARK: - Vault Tests
final class VaultTests: XCTestCase {
    func testVaultInitialState() {
        let vault = VaultManager()
        XCTAssertFalse(vault.isUnlocked, "Vault는 초기 잠금 상태")
        XCTAssertEqual(vault.items.count, 0, "초기 아이템 0개")
    }
}

// MARK: - DNS Tests
final class DNSTests: XCTestCase {
    func testProvidersList() {
        let providers = DNSManager.Provider.allCases
        XCTAssertGreaterThan(providers.count, 2, "DNS 제공자가 3개 이상")
    }

    func testProviderIcons() {
        for provider in DNSManager.Provider.allCases {
            XCTAssertFalse(provider.icon.isEmpty, "\(provider.rawValue)에 아이콘 필요")
        }
    }
}

// MARK: - Settings Tests
final class SettingsTests: XCTestCase {
    func testDefaultSearchEngine() {
        let store = SettingsStore()
        XCTAssertEqual(store.searchEngine, "DuckDuckGo", "기본 검색엔진이 DuckDuckGo여야 함")
    }

    func testSearchURL() {
        let store = SettingsStore()
        XCTAssertTrue(store.searchEngineURL.contains("duckduckgo"), "DuckDuckGo URL")
    }

    func testDefaultsSecure() {
        let store = SettingsStore()
        XCTAssertTrue(store.blockTrackers, "트래커 차단 기본 활성화")
        XCTAssertTrue(store.blockFingerprinting, "핑거프린팅 방어 기본 활성화")
        XCTAssertTrue(store.blockAds, "광고 차단 기본 활성화")
    }
}

// MARK: - Container Tests
final class ContainerTests: XCTestCase {
    func testContainerInit() {
        let container = DIContainer()
        XCTAssertNotNil(container.tabManager)
        XCTAssertNotNil(container.downloadManager)
        XCTAssertNotNil(container.privacyEngine)
        XCTAssertNotNil(container.vaultManager)
        XCTAssertNotNil(container.dnsManager)
        XCTAssertNotNil(container.contentBlocker)
        XCTAssertNotNil(container.settingsStore)
    }
}

// MARK: - Element Hider Tests
final class ElementHiderTests: XCTestCase {
    func testAddAndRetrieveRule() {
        let store = ElementHiderStore.shared
        store.addRule("#test-ad", for: "example.com")
        let rules = store.rules(for: "example.com")
        XCTAssertTrue(rules.contains("#test-ad"), "규칙이 저장되어야 함")
        store.clearRules(for: "example.com")
        XCTAssertEqual(store.rules(for: "example.com").count, 0, "규칙이 삭제되어야 함")
    }
}
