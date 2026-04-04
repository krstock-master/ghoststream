// Browser/TabManager.swift
// GhostStream - Tab management with per-tab cookie isolation

import SwiftUI
import WebKit

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
    var thumbnail: UIImage? // ★ 탭 썸네일 미리보기

    // Group support (Vivaldi-style tab stacking)
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
        await dataStore.removeData(
            ofTypes: types,
            modifiedSince: .distantPast
        )
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
        let tabID = tab.id

        // ★ 마지막 탭: 새 탭 먼저 생성
        if tabs.count <= 1 {
            let newT = Tab(url: nil, sharedStore: sharedDataStore)
            tabs.insert(newT, at: 0)
            activeTabID = newT.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                Task { await tab.purge() }
                self?.tabs.removeAll { $0.id == tabID }
            }
            return
        }

        // ★ 활성 탭 닫기: 먼저 전환 후 제거
        if activeTabID == tabID {
            if let idx = tabs.firstIndex(where: { $0.id == tabID }) {
                let nextIdx = idx > 0 ? idx - 1 : 1
                if nextIdx < tabs.count {
                    activeTabID = tabs[nextIdx].id
                }
            }
        }

        // ★ 비동기 제거 (ForEach 업데이트 충돌 방지)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            Task { await tab.purge() }
            self?.tabs.removeAll { $0.id == tabID }
        }
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

// MARK: - Detected Media
struct DetectedMedia: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let type: MediaType
    let quality: String
    let title: String
    let referer: String
    let thumbnail: URL?
    let estimatedSize: String?

    enum MediaType: String {
        case mp4 = "MP4"
        case hls = "HLS"
        case gif = "GIF"
        case blob = "Blob"
        case webm = "WebM"
        case image = "Image"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: DetectedMedia, rhs: DetectedMedia) -> Bool {
        lhs.url == rhs.url
    }
}
