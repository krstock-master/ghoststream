// Browser/TabManager.swift
// GhostStream - Tab management with per-tab cookie isolation

import SwiftUI
import WebKit
import GhostStreamCore

// MARK: - Tab Model
@Observable
final class Tab: Identifiable, @unchecked Sendable {
    let id: UUID
    let isPrivate: Bool
    let dataStore: WKWebsiteDataStore
    var title: String = "새 탭"
    var url: URL?
    var favicon: UIImage?
    var isLoading: Bool = false
    var loadProgress: Double = 0
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var isSecure: Bool = false
    var detectedMedia: [DetectedMedia] = []
    var privacyReport: PrivacyReport = PrivacyReport()
    var thumbnail: UIImage?

    // ★ 각 탭이 자체 WKWebView 소유 (탭 전환 시 재생성 방지)
    var webView: WKWebView?

    // Group support
    var groupID: UUID?
    var groupName: String?

    init(isPrivate: Bool = false, url: URL? = nil, sharedStore: WKWebsiteDataStore? = nil) {
        self.id = UUID()
        self.isPrivate = isPrivate
        self.url = url
        // ★ F5 FIX: 일반 탭은 공유 스토어 사용 (CF 쿠키 공유)
        // 프라이빗 탭만 개별 격리 스토어 사용
        if isPrivate {
            self.dataStore = WKWebsiteDataStore.nonPersistent()
        } else {
            self.dataStore = sharedStore ?? WKWebsiteDataStore.nonPersistent()
        }
    }

    var displayTitle: String {
        if title.isEmpty || title == "새 탭" {
            return url?.host ?? "새 탭"
        }
        return title
    }

    var displayURL: String {
        url?.absoluteString ?? ""
    }

    /// 탭 닫기 시 모든 데이터 즉시 삭제
    func purge() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await dataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
        await MainActor.run { webView = nil }
    }
}

// MARK: - Tab Manager
@Observable
final class TabManager: @unchecked Sendable {
    var tabs: [Tab] = []
    var activeTabID: UUID?
    var showTabGrid: Bool = false

    // Tab groups
    var groups: [TabGroup] = []

    // ★ F5: 일반 탭 공유 쿠키 스토어 (CF clearance 쿠키 공유)
    let sharedDataStore = WKWebsiteDataStore.nonPersistent()

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }

    var activeTabIndex: Int? {
        tabs.firstIndex { $0.id == activeTabID }
    }

    init() {
        let initial = Tab(url: nil, sharedStore: sharedDataStore)
        tabs = [initial]
        activeTabID = initial.id
    }

    // MARK: - Tab Operations

    @discardableResult
    func newTab(url: URL? = nil, isPrivate: Bool = false, switchTo: Bool = true) -> Tab {
        let tab = Tab(isPrivate: isPrivate, url: url, sharedStore: isPrivate ? nil : sharedDataStore)
        tabs.append(tab)
        if switchTo {
            activeTabID = tab.id
        }
        return tab
    }

    func closeTab(_ tab: Tab) {
        guard let idx = tabs.firstIndex(where: { $0.id == tab.id }) else { return }

        
        if tabs.count <= 1 {
            // 마지막 탭: 새 탭으로 교체
            let newT = Tab(url: nil, sharedStore: sharedDataStore)
            tabs[idx] = newT
            activeTabID = newT.id
            Task { await tab.purge() }
            return
        }

        // 활성 탭을 닫는 경우 인접 탭으로 전환
        if activeTabID == tab.id {
            let nextIdx = idx > 0 ? idx - 1 : min(idx + 1, tabs.count - 1)
            activeTabID = tabs[nextIdx].id
        }

        tabs.remove(at: idx)
        Task { await tab.purge() }
    }

    func switchTo(_ tab: Tab) {
        activeTabID = tab.id
    }

    func closeAllTabs() {
        for tab in tabs {
            Task { await tab.purge() }
        }
        tabs.removeAll()
        newTab()
    }

    // MARK: - Tab Groups (Vivaldi-style stacking)

    func groupTabs(_ tabIDs: [UUID], name: String) {
        let groupID = UUID()
        let group = TabGroup(id: groupID, name: name, tabIDs: tabIDs)
        groups.append(group)
        for tab in tabs where tabIDs.contains(tab.id) {
            tab.groupID = groupID
            tab.groupName = name
        }
    }

    func ungroupTab(_ tab: Tab) {
        guard let gid = tab.groupID else { return }
        tab.groupID = nil
        tab.groupName = nil
        if let idx = groups.firstIndex(where: { $0.id == gid }) {
            groups[idx].tabIDs.removeAll { $0 == tab.id }
            if groups[idx].tabIDs.isEmpty {
                groups.remove(at: idx)
            }
        }
    }
}

struct TabGroup: Identifiable {
    let id: UUID
    var name: String
    var tabIDs: [UUID]
}

// MARK: - Privacy Report (per-tab)
struct PrivacyReport {
    var trackersBlocked: Int = 0
    var adsBlocked: Int = 0
    var fingerprintAttempts: Int = 0
    var thirdPartyDomains: Set<String> = []
    var isHTTPS: Bool = false
    var tlsVersion: String = ""

    var score: Int {
        var s = 0
        s += isHTTPS ? 20 : 0
        s += max(0, 30 - trackersBlocked * 3)
        s += max(0, 20 - fingerprintAttempts * 7)
        s += max(0, 15 - adsBlocked)
        s += max(0, 15 - max(0, thirdPartyDomains.count - 3) * 5)
        return min(100, max(0, s))
    }
}

// DetectedMedia → GhostStreamCore.SharedTypes
