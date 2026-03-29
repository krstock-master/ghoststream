// UI/Browser/BrowserContainerView.swift
// Safari iOS 15+ style: bottom address bar, swipe tabs
import SwiftUI
import WebKit

struct BrowserContainerView: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(PrivacyEngine.self) private var privacyEngine
    @Environment(MediaDownloadManager.self) private var downloadManager
    @Environment(DIContainer.self) private var container

    @State private var addressText = ""
    @State private var showDownloads = false
    @State private var showSettings = false
    @State private var showPrivacy = false
    @State private var showTabGrid = false
    @State private var latestMedia: DetectedMedia?
    @State private var showMediaSnackbar = false
    @State private var webViewRef: WKWebView?
    @State private var isElementHideMode = false
    @State private var isAddressEditing = false

    var body: some View {
        VStack(spacing: 0) {
            // Element hide mode banner
            if isElementHideMode { elementHideBanner }

            // WebView fills ALL available space
            ZStack(alignment: .bottom) {
                webArea.frame(maxWidth: .infinity, maxHeight: .infinity)
                if showMediaSnackbar, let media = latestMedia {
                    snackbar(media).padding(.horizontal, 16).padding(.bottom, 70)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Safari-style bottom bar
            bottomBar
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(.keyboard)
        .onChange(of: tabManager.activeTab?.url) { _, url in
            if !isAddressEditing { addressText = url?.absoluteString ?? "" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openInNewTab)) { n in
            if let url = n.object as? URL { tabManager.newTab(url: url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startImmediateDownload)) { n in
            if let media = n.object as? DetectedMedia {
                downloadManager.download(media: media, saveToVault: false)
                latestMedia = media
                withAnimation { showMediaSnackbar = true }
                Task { try? await Task.sleep(for: .seconds(3)); withAnimation { showMediaSnackbar = false } }
            }
        }
        .sheet(isPresented: $showDownloads) { DownloadsManagerView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPrivacy) { PrivacyDashboardView() }
        .sheet(isPresented: $showTabGrid) { TabGridView() }
    }

    // MARK: - Element Hide Banner
    private var elementHideBanner: some View {
        HStack {
            Image(systemName: "eye.slash.fill").foregroundStyle(.white)
            Text("숨기려는 요소를 탭하세요").font(.caption).foregroundStyle(.white)
            Spacer()
            Button("완료") {
                isElementHideMode = false
                webViewRef?.evaluateJavaScript("window._gsToggleHideMode()")
            }.font(.caption.bold()).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(.white.opacity(0.25), in: Capsule())
        }.padding(.horizontal, 12).padding(.vertical, 8).background(.red)
    }

    // MARK: - Web Area
    @ViewBuilder
    private var webArea: some View {
        if let tab = tabManager.activeTab {
            if tab.url == nil {
                NewTabPage { navigateTo($0) }
            } else {
                BrowserWebView(tab: tab, privacyEngine: privacyEngine, downloadManager: downloadManager,
                    onMediaDetected: { media in
                        latestMedia = media
                        withAnimation { showMediaSnackbar = true }
                        Task { try? await Task.sleep(for: .seconds(5)); withAnimation { showMediaSnackbar = false } }
                    }, webViewRef: $webViewRef).id(tab.id)
            }
        }
    }

    // MARK: - Snackbar
    private func snackbar(_ media: DetectedMedia) -> some View {
        Button {
            downloadManager.download(media: media, saveToVault: false)
            withAnimation { showMediaSnackbar = false }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.teal).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.title).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text("\(media.type.rawValue) · \(media.quality)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("저장").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(.teal).clipShape(Capsule())
            }.padding(14)
            .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Safari-Style Bottom Bar
    private var bottomBar: some View {
        VStack(spacing: 0) {
            // Progress bar
            if tabManager.activeTab?.isLoading == true {
                GeometryReader { geo in
                    Rectangle().fill(Color.teal)
                        .frame(width: geo.size.width * (tabManager.activeTab?.loadProgress ?? 0), height: 2)
                }.frame(height: 2)
            }

            // Address bar (Safari-style pill)
            HStack(spacing: 8) {
                if !isAddressEditing {
                    // Compact mode: show domain only
                    Button { withAnimation { isAddressEditing = true } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tabManager.activeTab?.isSecure == true ? "lock.fill" : "lock.open.fill")
                                .font(.system(size: 10)).foregroundStyle(tabManager.activeTab?.isSecure == true ? Color.secondary : Color.red)
                            Text(tabManager.activeTab?.url?.host ?? "검색 또는 주소 입력")
                                .font(.system(size: 14)).foregroundStyle(.primary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    // Edit mode: full URL text field
                    HStack(spacing: 6) {
                        TextField("검색 또는 주소 입력", text: $addressText)
                            .textFieldStyle(.plain).font(.system(size: 14))
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .onSubmit { navigateTo(addressText); withAnimation { isAddressEditing = false } }
                        Button { withAnimation { isAddressEditing = false } } label: {
                            Text("취소").font(.system(size: 14)).foregroundStyle(.teal)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill)).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 12).padding(.top, 8)

            // Toolbar buttons
            HStack(spacing: 0) {
                tbtn("chevron.left", tabManager.activeTab?.canGoBack == true) { webViewRef?.goBack() }
                tbtn("chevron.right", tabManager.activeTab?.canGoForward == true) { webViewRef?.goForward() }
                
                // Share / Actions menu
                Menu {
                    Section("탭") {
                        Button { tabManager.newTab() } label: { Label("새 탭", systemImage: "plus.square") }
                        Button { tabManager.newTab(isPrivate: true) } label: { Label("프라이빗 탭", systemImage: "lock.square") }
                    }
                    Section("도구") {
                        Button { showDownloads = true } label: { Label("다운로드", systemImage: "arrow.down.circle") }
                        Button {
                            isElementHideMode = true
                            webViewRef?.evaluateJavaScript("window._gsToggleHideMode()")
                        } label: { Label("방해 요소 가리기", systemImage: "eye.slash") }
                        Button {
                            if let h = tabManager.activeTab?.url?.host { ElementHiderStore.shared.clearRules(for: h); webViewRef?.reload() }
                        } label: { Label("숨긴 요소 복원", systemImage: "eye") }
                        Button { webViewRef?.reload() } label: { Label("새로고침", systemImage: "arrow.clockwise") }
                    }
                    Section {
                        Button { showPrivacy = true } label: { Label("프라이버시", systemImage: "shield.checkered") }
                        Button { showSettings = true } label: { Label("설정", systemImage: "gearshape") }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 18))
                        .frame(maxWidth: .infinity).frame(height: 44)
                }

                // Downloads badge
                Button { showDownloads = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 18))
                            .frame(maxWidth: .infinity).frame(height: 44)
                        if !downloadManager.downloads.isEmpty {
                            Circle().fill(.teal).frame(width: 8, height: 8).offset(x: -14, y: 10)
                        }
                    }
                }

                // Tab grid
                Button { showTabGrid = true } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                        Text("\(tabManager.tabs.count)").font(.system(size: 11, weight: .medium))
                    }.frame(maxWidth: .infinity).frame(height: 44)
                }
            }
            .padding(.bottom, 2)
        }
        .background(Color(.systemBackground))
    }

    private func tbtn(_ icon: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(on ? Color.primary : Color.primary.opacity(0.2))
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

// MARK: - New Tab Page
struct NewTabPage: View {
    let onNavigate: (String) -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 80)
                Image(systemName: "globe").font(.system(size: 44, weight: .thin)).foregroundStyle(.teal)
                Text("GhostStream").font(.system(size: 22, weight: .semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 20) {
                    ql("Google", "magnifyingglass", "https://google.com")
                    ql("YouTube", "play.rectangle.fill", "https://youtube.com")
                    ql("Naver", "n.circle.fill", "https://naver.com")
                    ql("GitHub", "chevron.left.forwardslash.chevron.right", "https://github.com")
                }.padding(.horizontal, 24)
                Spacer()
            }
        }.background(Color(.systemBackground))
    }
    private func ql(_ n: String, _ i: String, _ u: String) -> some View {
        Button { onNavigate(u) } label: {
            VStack(spacing: 6) {
                Image(systemName: i).font(.system(size: 20)).foregroundStyle(.teal)
                    .frame(width: 48, height: 48)
                    .background(Color(.tertiarySystemFill)).clipShape(RoundedRectangle(cornerRadius: 12))
                Text(n).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}
