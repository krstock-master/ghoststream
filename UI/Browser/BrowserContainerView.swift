// UI/Browser/BrowserContainerView.swift
import SwiftUI
import WebKit

struct BrowserContainerView: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(PrivacyEngine.self) private var privacyEngine
    @Environment(MediaDownloadManager.self) private var downloadManager
    @Environment(VaultManager.self) private var vaultManager
    @Environment(DIContainer.self) private var container

    @State private var addressText = ""
    @State private var showDownloadSheet = false
    @State private var showVault = false
    @State private var showSettings = false
    @State private var showPrivacy = false
    @State private var showPrivacyReport = false
    @State private var showTabGrid = false
    @State private var latestMedia: DetectedMedia?
    @State private var showMediaSnackbar = false
    @State private var webViewRef: WKWebView?
    @State private var isElementHideMode = false

    var body: some View {
        VStack(spacing: 0) {
            if let url = tabManager.activeTab?.url, url.scheme == "http" {
                InsecureConnectionBanner(url: url)
            }
            if isElementHideMode { elementHideBanner }
            addressBar
            tabBar
            ZStack(alignment: .bottom) {
                webArea.frame(maxWidth: .infinity, maxHeight: .infinity)
                if showMediaSnackbar, let media = latestMedia {
                    snackbar(media).padding(.horizontal, 16).padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            toolbar
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(.keyboard)
        .onChange(of: tabManager.activeTab?.url) { _, url in addressText = url?.absoluteString ?? "" }
        .onReceive(NotificationCenter.default.publisher(for: .openInNewTab)) { n in
            if let url = n.object as? URL { tabManager.newTab(url: url) }
        }
        .sheet(isPresented: $showDownloadSheet) { DownloadSheetView(media: latestMedia) }
        .sheet(isPresented: $showVault) { VaultView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPrivacy) { PrivacyDashboardView() }
        .sheet(isPresented: $showPrivacyReport) { PrivacyReportSheet(tab: tabManager.activeTab) }
        .sheet(isPresented: $showTabGrid) { TabGridView() }
    }

    private var elementHideBanner: some View {
        HStack {
            Image(systemName: "eye.slash.fill").foregroundStyle(.white)
            Text("요소 가리기 모드 — 숨기려는 요소를 탭하세요").font(.caption).foregroundStyle(.white)
            Spacer()
            Button("완료") {
                isElementHideMode = false
                webViewRef?.evaluateJavaScript("window._gsToggleHideMode()")
            }.font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 4)
            .background(.white.opacity(0.2), in: Capsule())
        }.padding(.horizontal, 12).padding(.vertical, 8).background(.red)
    }

    // Safari-style address bar with system colors
    private var addressBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { showPrivacyReport = true } label: {
                    Image(systemName: tabManager.activeTab?.isSecure == true ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(tabManager.activeTab?.isSecure == true ? .green : .red)
                }
                TextField("검색어 또는 주소 입력", text: $addressText)
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onSubmit { navigateTo(addressText) }
                if tabManager.activeTab?.isLoading == true {
                    ProgressView().scaleEffect(0.7)
                } else if !addressText.isEmpty {
                    Button { addressText = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
                Menu {
                    Section("탭") {
                        Button { tabManager.newTab() } label: { Label("새 탭", systemImage: "plus.square") }
                        Button { tabManager.newTab(isPrivate: true) } label: { Label("프라이빗 탭", systemImage: "lock.square") }
                    }
                    Section("도구") {
                        Button { showDownloadSheet = true } label: { Label("다운로드", systemImage: "arrow.down.circle") }
                        Button { showVault = true } label: { Label("보관함", systemImage: "lock.shield.fill") }
                        Button {
                            isElementHideMode = true
                            webViewRef?.evaluateJavaScript("window._gsToggleHideMode()")
                        } label: { Label("방해 요소 가리기", systemImage: "eye.slash") }
                        Button {
                            if let h = tabManager.activeTab?.url?.host { ElementHiderStore.shared.clearRules(for: h); webViewRef?.reload() }
                        } label: { Label("숨긴 요소 복원", systemImage: "eye") }
                    }
                    Section("보안") {
                        Button { showPrivacy = true } label: { Label("프라이버시 대시보드", systemImage: "shield.checkered") }
                        Button { showSettings = true } label: { Label("설정", systemImage: "gearshape.fill") }
                    }
                    Section { Button(role: .destructive) { tabManager.closeAllTabs() } label: { Label("모든 탭 닫기", systemImage: "xmark.square") } }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 18)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 8).padding(.vertical, 6)

            if tabManager.activeTab?.isLoading == true {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 1).fill(Color.teal)
                        .frame(width: geo.size.width * (tabManager.activeTab?.loadProgress ?? 0), height: 2)
                }.frame(height: 2).padding(.horizontal, 8)
            }
        }.background(Color(.systemBackground))
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabManager.tabs) { tab in
                    TabPill(tab: tab, isActive: tab.id == tabManager.activeTabID,
                            onTap: { tabManager.switchTo(tab) }, onClose: { tabManager.closeTab(tab) })
                }
                Button { tabManager.newTab() } label: {
                    Image(systemName: "plus").font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.tertiarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }.padding(.horizontal, 8).padding(.vertical, 2)
        }.background(Color(.systemBackground))
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
                    }, webViewRef: $webViewRef).id(tab.id)
            }
        }
    }

    private func snackbar(_ media: DetectedMedia) -> some View {
        Button { showDownloadSheet = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "film.fill").foregroundStyle(.teal).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("미디어 감지됨").font(.subheadline.weight(.medium))
                    Text("\(media.type.rawValue) · \(media.quality)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("저장").font(.subheadline.weight(.semibold)).foregroundStyle(.teal)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.teal.opacity(0.15)).clipShape(Capsule())
            }.padding(14)
            .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            tbtn("chevron.left", tabManager.activeTab?.canGoBack == true) { webViewRef?.goBack() }
            tbtn("chevron.right", tabManager.activeTab?.canGoForward == true) { webViewRef?.goForward() }
            tbtn("arrow.down.circle\(downloadManager.downloads.isEmpty ? "" : ".fill")", true) { showDownloadSheet = true }
            Button { showTabGrid = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.5), lineWidth: 1.5).frame(width: 22, height: 22)
                    Text("\(tabManager.tabs.count)").font(.system(size: 12, weight: .medium))
                }.frame(maxWidth: .infinity).frame(height: 44)
            }
            tbtn("lock.shield", true) { showVault = true }
        }.padding(.bottom, 4).background(Color(.systemBackground))
    }

    private func tbtn(_ icon: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(on ? Color.primary : Color.primary.opacity(0.25))
                .frame(maxWidth: .infinity).frame(height: 44)
        }.disabled(!on)
    }

    private func navigateTo(_ input: String) {
        let t = input.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return }
        let url: URL
        if t.hasPrefix("http://") || t.hasPrefix("https://"), let u = URL(string: t) { url = u }
        else if t.contains(".") && !t.contains(" "), let u = URL(string: "https://\(t)") { url = u }
        else {
            let enc = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t
            guard let u = URL(string: "\(container.settingsStore.searchEngineURL)\(enc)") else { return }; url = u
        }
        tabManager.activeTab?.url = url; webViewRef?.load(URLRequest(url: url)); addressText = url.absoluteString
    }
}

struct TabPill: View {
    let tab: Tab; let isActive: Bool; let onTap: () -> Void; let onClose: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            if tab.isPrivate { Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.purple) }
            Text(tab.displayTitle).font(.system(size: 12)).foregroundStyle(isActive ? Color.primary : .secondary).lineLimit(1).frame(maxWidth: 90)
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(isActive ? Color(.tertiarySystemBackground) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(perform: onTap)
    }
}

struct NewTabPage: View {
    let onNavigate: (String) -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer().frame(height: 50)
                Image(systemName: "globe").font(.system(size: 44, weight: .thin)).foregroundStyle(.teal)
                Text("GhostStream").font(.system(size: 24, weight: .semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 20) {
                    ql("Google", "magnifyingglass", "https://google.com")
                    ql("YouTube", "play.rectangle.fill", "https://youtube.com")
                    ql("GitHub", "chevron.left.forwardslash.chevron.right", "https://github.com")
                    ql("Naver", "n.circle.fill", "https://naver.com")
                    ql("Reddit", "bubble.left.fill", "https://reddit.com")
                    ql("Twitter", "at", "https://x.com")
                    ql("Wiki", "book.fill", "https://wikipedia.org")
                    ql("DDG", "shield.fill", "https://duckduckgo.com")
                }.padding(.horizontal, 24)
                Spacer()
            }
        }.background(Color(.systemBackground))
    }
    private func ql(_ n: String, _ i: String, _ u: String) -> some View {
        Button { onNavigate(u) } label: {
            VStack(spacing: 8) {
                Image(systemName: i).font(.system(size: 22)).foregroundStyle(.teal)
                    .frame(width: 52, height: 52)
                    .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
                Text(n).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}
