// UI/Browser/BrowserContainerView.swift
import SwiftUI
import WebKit

struct BrowserContainerView: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(PrivacyEngine.self) private var privacyEngine
    @Environment(MediaDownloadManager.self) private var downloadManager
    @Environment(VaultManager.self) private var vaultManager
    @Environment(VPNManager.self) private var vpnManager
    @Environment(DIContainer.self) private var container

    @State private var addressText = ""
    @State private var showDownloadSheet = false
    @State private var showVault = false
    @State private var showSettings = false
    @State private var showVPN = false
    @State private var showPrivacyReport = false
    @State private var showTabGrid = false
    @State private var latestMedia: DetectedMedia?
    @State private var showMediaSnackbar = false
    @State private var webViewRef: WKWebView?

    var body: some View {
        VStack(spacing: 0) {
            if let url = tabManager.activeTab?.url, url.scheme == "http" {
                InsecureConnectionBanner(url: url)
            }
            addressBar
            tabBar
            ZStack(alignment: .bottom) {
                webArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showMediaSnackbar, let media = latestMedia {
                    snackbar(media).padding(.horizontal, 12).padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            toolbar
        }
        .background(GhostTheme.bg)
        .ignoresSafeArea(.keyboard)
        .onChange(of: tabManager.activeTab?.url) { _, url in addressText = url?.absoluteString ?? "" }
        .onReceive(NotificationCenter.default.publisher(for: .openInNewTab)) { notif in
            if let url = notif.object as? URL {
                tabManager.newTab(url: url)
            }
        }
        .sheet(isPresented: $showDownloadSheet) { DownloadSheetView(media: latestMedia) }
        .sheet(isPresented: $showVault) { VaultView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showVPN) { VPNView() }
        .sheet(isPresented: $showPrivacyReport) { PrivacyReportSheet(tab: tabManager.activeTab) }
        .sheet(isPresented: $showTabGrid) { TabGridView() }
    }

    private var addressBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { showPrivacyReport = true } label: {
                    Image(systemName: tabManager.activeTab?.isSecure == true ? "lock.fill" : "lock.open.fill")
                        .font(.caption)
                        .foregroundStyle(tabManager.activeTab?.isSecure == true ? GhostTheme.success : GhostTheme.danger)
                }
                TextField("검색어 또는 주소 입력", text: $addressText)
                    .textFieldStyle(.plain).font(.subheadline).foregroundStyle(.white)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onSubmit { navigateTo(addressText) }
                if !addressText.isEmpty {
                    Button {
                        if tabManager.activeTab?.isLoading == true { webViewRef?.stopLoading() }
                        else { addressText = "" }
                    } label: {
                        Image(systemName: tabManager.activeTab?.isLoading == true ? "xmark" : "xmark.circle.fill")
                            .font(.caption).foregroundStyle(Color.gray)
                    }
                }
                Menu {
                    Button { tabManager.newTab() } label: { Label("새 탭", systemImage: "plus.square") }
                    Button { tabManager.newTab(isPrivate: true) } label: { Label("프라이빗 탭", systemImage: "lock.square") }
                    Divider()
                    Button { showVault = true } label: { Label("보관함", systemImage: "lock.shield.fill") }
                    Button { showDownloadSheet = true } label: { Label("다운로드", systemImage: "arrow.down.circle") }
                    Divider()
                    Button { showVPN = true } label: { Label("VPN", systemImage: "shield.fill") }
                    Button { showSettings = true } label: { Label("설정", systemImage: "gearshape.fill") }
                    Divider()
                    Button(role: .destructive) { tabManager.closeAllTabs() } label: { Label("모든 탭 닫기", systemImage: "xmark.square") }
                } label: {
                    Image(systemName: "ellipsis").font(.body).foregroundStyle(Color.gray)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glass(12).padding(.horizontal, 8).padding(.top, 4)
            if tabManager.activeTab?.isLoading == true {
                GeometryReader { geo in
                    Rectangle().fill(GhostTheme.gradient)
                        .frame(width: geo.size.width * (tabManager.activeTab?.loadProgress ?? 0), height: 2)
                }.frame(height: 2)
            }
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabManager.tabs) { tab in
                    TabPill(tab: tab, isActive: tab.id == tabManager.activeTabID,
                            onTap: { tabManager.switchTo(tab) }, onClose: { tabManager.closeTab(tab) })
                }
                Button { tabManager.newTab() } label: {
                    Image(systemName: "plus").font(.caption2).foregroundStyle(Color.gray)
                        .frame(width: 28, height: 28).glass(8)
                }
            }.padding(.horizontal, 8).padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var webArea: some View {
        if let tab = tabManager.activeTab {
            if tab.url == nil {
                NewTabPage { navigateTo($0) }
            } else {
                BrowserWebView(tab: tab, privacyEngine: privacyEngine,
                    onMediaDetected: { media in
                        latestMedia = media
                        withAnimation { showMediaSnackbar = true }
                        Task { try? await Task.sleep(for: .seconds(6)); withAnimation { showMediaSnackbar = false } }
                    }, webViewRef: $webViewRef)
                .id(tab.id)
            }
        }
    }

    private func snackbar(_ media: DetectedMedia) -> some View {
        Button { showDownloadSheet = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "film.fill").foregroundStyle(GhostTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("미디어 감지됨").font(.caption.weight(.semibold)).foregroundStyle(.white)
                    Text("\(media.type.rawValue) · \(media.quality)").font(.caption2).foregroundStyle(Color.gray)
                }
                Spacer()
                Text("저장 ▸").font(.caption.weight(.bold)).foregroundStyle(GhostTheme.accent)
            }.padding(12).glass(14)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            tbtn("chevron.left", tabManager.activeTab?.canGoBack == true) { webViewRef?.goBack() }
            tbtn("chevron.right", tabManager.activeTab?.canGoForward == true) { webViewRef?.goForward() }
            tbtn("arrow.down.circle", true) { showDownloadSheet = true }
            Button { showTabGrid = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "square.on.square").font(.system(size: 18)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 40)
                    if tabManager.tabs.count > 1 {
                        Text("\(tabManager.tabs.count)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 16, height: 16).background(GhostTheme.accent, in: Circle()).offset(x: -12, y: 2)
                    }
                }
            }
            tbtn("lock.shield.fill", true) { showVault = true }
        }.padding(.vertical, 6).padding(.bottom, 4).background(GhostTheme.surface)
    }

    private func tbtn(_ icon: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(on ? .white : .white.opacity(0.3))
                .frame(maxWidth: .infinity).frame(height: 40)
        }.disabled(!on)
    }

    private func navigateTo(_ input: String) {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let url: URL
        if t.hasPrefix("http://") || t.hasPrefix("https://"), let u = URL(string: t) { url = u }
        else if t.contains(".") && !t.contains(" "), let u = URL(string: "https://\(t)") { url = u }
        else {
            let enc = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t
            guard let u = URL(string: "\(container.settingsStore.searchEngineURL)\(enc)") else { return }
            url = u
        }
        tabManager.activeTab?.url = url
        webViewRef?.load(URLRequest(url: url))
        addressText = url.absoluteString
    }
}

struct TabPill: View {
    let tab: Tab; let isActive: Bool; let onTap: () -> Void; let onClose: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            if tab.isPrivate { Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(GhostTheme.accentAlt) }
            Text(tab.displayTitle).font(.caption2).foregroundStyle(isActive ? .white : Color.gray).lineLimit(1).frame(maxWidth: 100)
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.gray.opacity(0.5)) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(isActive ? .white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isActive ? GhostTheme.accent.opacity(0.3) : .clear, lineWidth: 0.5))
        .onTapGesture(perform: onTap)
    }
}

struct NewTabPage: View {
    let onNavigate: (String) -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer().frame(height: 60)
                Image(systemName: "globe").font(.system(size: 48)).foregroundStyle(GhostTheme.accent.opacity(0.6))
                Text("GhostStream").font(.title.bold()).foregroundStyle(.white)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                    ql("Google", "magnifyingglass", "https://google.com")
                    ql("YouTube", "play.rectangle.fill", "https://youtube.com")
                    ql("GitHub", "chevron.left.forwardslash.chevron.right", "https://github.com")
                    ql("Naver", "n.circle.fill", "https://naver.com")
                    ql("Reddit", "bubble.left.fill", "https://reddit.com")
                    ql("Twitter", "at", "https://x.com")
                    ql("Wiki", "book.fill", "https://wikipedia.org")
                    ql("DDG", "shield.fill", "https://duckduckgo.com")
                }.padding(.horizontal)
                Spacer()
            }
        }.background(GhostTheme.bg)
    }
    private func ql(_ n: String, _ i: String, _ u: String) -> some View {
        Button { onNavigate(u) } label: {
            VStack(spacing: 6) {
                Image(systemName: i).font(.title3).foregroundStyle(GhostTheme.accent).frame(width: 50, height: 50).glass(14)
                Text(n).font(.caption2).foregroundStyle(Color.gray)
            }
        }
    }
}
