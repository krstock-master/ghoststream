// UI/Browser/BrowserContainerView.swift
// GhostStream - Main browser interface (Vivaldi-style)

import SwiftUI
import WebKit

struct BrowserContainerView: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(PrivacyEngine.self) private var privacyEngine
    @Environment(MediaDownloadManager.self) private var downloadManager
    @Environment(VaultManager.self) private var vaultManager
    @Environment(VPNManager.self) private var vpnManager
    @Environment(DIContainer.self) private var container

    @State private var addressText: String = ""
    @State private var isAddressFocused: Bool = false
    @State private var showMenu: Bool = false
    @State private var showPrivacyReport: Bool = false
    @State private var showDownloadSheet: Bool = false
    @State private var showVault: Bool = false
    @State private var showSettings: Bool = false
    @State private var showVPN: Bool = false
    @State private var latestMedia: DetectedMedia?
    @State private var showMediaSnackbar: Bool = false
    @State private var webViewRef: WKWebView?
    @State private var showJailbreakWarning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                // iPad regular: 탭을 사이드바로 이동 (Vivaldi 스타일)
                HStack(spacing: 0) {
                    // 사이드 탭 패널
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(tabManager.tabs) { tab in
                                    TabPill(tab: tab, isActive: tab.id == tabManager.activeTabID) {
                                        tabManager.switchTo(tab)
                                    } onClose: {
                                        tabManager.closeTab(tab)
                                    }
                                }
                            }
                            .padding(8)
                        }
                        Button { tabManager.newTab() } label: {
                            Image(systemName: "plus")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .a11yButton("새 탭")
                    }
                    .frame(width: 160)
                    .background(GhostTheme.surface)

                    Divider().overlay(Color.white.opacity(0.06))

                    // 메인 콘텐츠
                    compactLayout
                }
            }
        }
        .background(GhostTheme.bg)
        .sheet(isPresented: $showMenu) { BrowserMenuView() }
        .sheet(isPresented: $showPrivacyReport) { PrivacyReportSheet(tab: tabManager.activeTab) }
        .sheet(isPresented: $showDownloadSheet) { DownloadSheetView(media: latestMedia) }
        .sheet(isPresented: $showVault) { VaultView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showVPN) { VPNView() }
        .sheet(isPresented: .init(get: { tabManager.showTabGrid }, set: { tabManager.showTabGrid = $0 })) {
            TabGridView()
        }
        .sheet(isPresented: $showJailbreakWarning) {
            JailbreakWarningView(isPresented: $showJailbreakWarning)
        }
        .onAppear {
            if JailbreakDetector.isJailbroken {
                showJailbreakWarning = true
            }
        }
    }

    // MARK: - Compact Layout (iPhone / iPad main content)

    private var compactLayout: some View {
        VStack(spacing: 0) {
            if let url = tabManager.activeTab?.url {
                InsecureConnectionBanner(url: url)
            }
            addressBar
            if isCompact { tabBar }

            ZStack(alignment: .bottom) {
                webViewArea
                if showMediaSnackbar, let media = latestMedia {
                    mediaSnackbar(media)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
            bottomToolbar
        }
    }

    // MARK: - Address Bar

    private var addressBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Lock icon
                Button { showPrivacyReport = true } label: {
                    Image(systemName: tabManager.activeTab?.isSecure == true ? "lock.fill" : "lock.open.fill")
                        .font(.caption)
                        .foregroundStyle(tabManager.activeTab?.isSecure == true ? GhostTheme.success : GhostTheme.danger)
                }
                .a11yButton(
                    tabManager.activeTab?.isSecure == true ? "보안 연결" : "비보안 연결",
                    hint: "프라이버시 리포트를 봅니다"
                )

                // Address field
                TextField("검색어 또는 주소 입력", text: $addressText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { navigateTo(addressText) }

                // Clear / Reload
                if !addressText.isEmpty {
                    Button {
                        if tabManager.activeTab?.isLoading == true {
                            webViewRef?.stopLoading()
                        } else {
                            addressText = ""
                        }
                    } label: {
                        Image(systemName: tabManager.activeTab?.isLoading == true ? "xmark" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Menu
                Button { showMenu = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glass(12)
            .padding(.horizontal, 8)
            .padding(.top, 4)

            // Progress bar
            if tabManager.activeTab?.isLoading == true {
                GeometryReader { geo in
                    Rectangle()
                        .fill(GhostTheme.gradient)
                        .frame(width: geo.size.width * (tabManager.activeTab?.loadProgress ?? 0), height: 2)
                        .animation(.linear, value: tabManager.activeTab?.loadProgress)
                }
                .frame(height: 2)
            }
        }
        .onChange(of: tabManager.activeTab?.url) { _, url in
            addressText = url?.absoluteString ?? ""
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabManager.tabs) { tab in
                    TabPill(tab: tab, isActive: tab.id == tabManager.activeTabID) {
                        tabManager.switchTo(tab)
                    } onClose: {
                        tabManager.closeTab(tab)
                    }
                }

                // New tab button
                Button {
                    tabManager.newTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .glass(8)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - WebView Area

    @ViewBuilder
    private var webViewArea: some View {
        if let tab = tabManager.activeTab {
            if tab.url == nil {
                NewTabPage { url in
                    navigateTo(url)
                }
            } else {
                BrowserWebView(
                    tab: tab,
                    privacyEngine: privacyEngine,
                    onMediaDetected: { media in
                        latestMedia = media
                        withAnimation(reduceMotion ? nil : .spring) { showMediaSnackbar = true }
                        Task {
                            try? await Task.sleep(for: .seconds(8))
                            withAnimation(reduceMotion ? nil : .default) { showMediaSnackbar = false }
                        }
                    },
                    webViewRef: $webViewRef
                )
                .id(tab.id)
            }
        } else {
            Color.clear
        }
    }

    // MARK: - Media Snackbar

    private func mediaSnackbar(_ media: DetectedMedia) -> some View {
        Button {
            showDownloadSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: media.type == .gif ? "photo.fill" : "film.fill")
                    .foregroundStyle(GhostTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("미디어 감지됨")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(media.type.rawValue) · \(media.quality)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("저장 ▸")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GhostTheme.accent)
            }
            .padding(12)
            .glass(14)
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            toolbarButton("chevron.left", enabled: tabManager.activeTab?.canGoBack == true, label: "뒤로 가기") {
                webViewRef?.goBack()
            }
            toolbarButton("chevron.right", enabled: tabManager.activeTab?.canGoForward == true, label: "앞으로 가기") {
                webViewRef?.goForward()
            }
            toolbarButton("arrow.down.circle\(downloadManager.downloads.isEmpty ? "" : ".fill")", enabled: true, label: "다운로드") {
                showDownloadSheet = true
            }
            toolbarButton("square.on.square", enabled: true, label: "탭 목록") {
                tabManager.showTabGrid = true
            }
            .overlay(alignment: .topTrailing) {
                if tabManager.tabs.count > 1 {
                    Text("\(tabManager.tabs.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(GhostTheme.accent, in: Circle())
                        .offset(x: 8, y: -4)
                }
            }
            toolbarButton("lock.shield.fill", enabled: true, label: "보관함") {
                showVault = true
            }
        }
        .padding(.vertical, 6)
        .padding(.bottom, 4)
        .background(GhostTheme.surface)
    }

    private func toolbarButton(_ icon: String, enabled: Bool, label: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(enabled ? .white : .white.opacity(0.3))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .disabled(!enabled)
        .a11yButton(label.isEmpty ? icon : label)
    }

    // MARK: - Navigation

    private func navigateTo(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let url: URL
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            url = URL(string: trimmed) ?? URL(string: "https://\(trimmed)")!
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            url = URL(string: "https://\(trimmed)")!
        } else {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            url = URL(string: "\(container.settingsStore.searchEngineURL)\(encoded)")!
        }

        if tabManager.activeTab?.url == nil {
            tabManager.activeTab?.url = url
        }
        webViewRef?.load(URLRequest(url: url))
        addressText = url.absoluteString
    }
}

// MARK: - Tab Pill

struct TabPill: View {
    let tab: Tab
    let isActive: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if tab.isPrivate {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(GhostTheme.accentAlt)
            }

            Text(tab.displayTitle)
                .font(.caption2)
                .foregroundStyle(isActive ? Color.white : Color.secondary)
                .lineLimit(1)
                .frame(maxWidth: 100)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? .white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? GhostTheme.accent.opacity(0.3) : .clear, lineWidth: 0.5)
        )
        .onTapGesture(perform: onTap)
    }
}

// MARK: - New Tab Page

struct NewTabPage: View {
    let onNavigate: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer().frame(height: 60)

                Image(systemName: "ghost")
                    .font(.system(size: 48))
                    .foregroundStyle(GhostTheme.accent.opacity(0.6))

                Text("GhostStream")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                // Quick links
                VStack(spacing: 12) {
                    Text("빠른 바로가기")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        quickLink("Google", icon: "magnifyingglass", url: "https://google.com")
                        quickLink("YouTube", icon: "play.rectangle.fill", url: "https://youtube.com")
                        quickLink("GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com")
                        quickLink("Reddit", icon: "bubble.left.and.bubble.right.fill", url: "https://reddit.com")
                        quickLink("Naver", icon: "n.circle.fill", url: "https://naver.com")
                        quickLink("Twitter", icon: "at", url: "https://x.com")
                        quickLink("Wikipedia", icon: "book.fill", url: "https://wikipedia.org")
                        quickLink("DuckDuckGo", icon: "shield.fill", url: "https://duckduckgo.com")
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
        }
        .background(GhostTheme.bg)
    }

    private func quickLink(_ name: String, icon: String, url: String) -> some View {
        Button { onNavigate(url) } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(GhostTheme.accent)
                    .frame(width: 50, height: 50)
                    .glass(14)
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
