// UI/Browser/BrowserContainerView.swift
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
    @State private var toastMessage: String?
    @State private var toastIsError = false
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Element hide banner
                if isElementHideMode { elementHideBanner }

                // URL bar at TOP when editing (keyboard visible)
                if isAddressEditing { topSearchBar }

                // WebView
                ZStack(alignment: .bottom) {
                    webArea.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if showMediaSnackbar, let media = latestMedia {
                        snackbar(media).padding(.horizontal, 16).padding(.bottom, isAddressEditing ? 12 : 70)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                // Bottom bar (hidden when keyboard is up)
                if !isAddressEditing { bottomBar }
            }
        }
        .background(Color(.systemBackground))
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
        .onReceive(NotificationCenter.default.publisher(for: .downloadCompleted)) { n in
            if let msg = n.object as? String {
                toastIsError = false
                toastMessage = msg
                Task { try? await Task.sleep(for: .seconds(3)); withAnimation { toastMessage = nil } }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .downloadFailed)) { n in
            if let msg = n.object as? String {
                toastIsError = true
                toastMessage = "❌ \(msg)"
                Task { try? await Task.sleep(for: .seconds(4)); withAnimation { toastMessage = nil } }
            }
        }
        .overlay(alignment: .top) {
            if let toast = toastMessage {
                HStack(spacing: 8) {
                    Image(systemName: toastIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toastIsError ? .red : .green)
                    Text(toast).font(.subheadline).lineLimit(2)
                    Spacer()
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 50)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: toastMessage)
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
            Text("숨기려는 요소를 탭하세요").font(.subheadline).foregroundStyle(.white)
            Spacer()
            Button("완료") {
                isElementHideMode = false
                webViewRef?.evaluateJavaScript("window._gsToggleHideMode()")
            }.font(.subheadline.bold()).foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(.white.opacity(0.25), in: Capsule())
        }.padding(.horizontal, 16).padding(.vertical, 10).background(.red)
    }

    // MARK: - Top Search Bar (visible when editing URL)
    private var topSearchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 15))
                TextField("검색어 또는 주소 입력", text: $addressText)
                    .textFieldStyle(.plain).font(.system(size: 16))
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .focused($isURLFieldFocused)
                    .onSubmit { navigateTo(addressText); closeSearch() }
                if !addressText.isEmpty {
                    Button { addressText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color(.tertiarySystemFill)).clipShape(RoundedRectangle(cornerRadius: 12))

            Button("취소") { closeSearch() }
                .font(.system(size: 16)).foregroundStyle(.teal)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.systemBackground))
        .onAppear { isURLFieldFocused = true }
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
            // Progress
            if tabManager.activeTab?.isLoading == true {
                GeometryReader { geo in
                    Rectangle().fill(Color.teal)
                        .frame(width: geo.size.width * (tabManager.activeTab?.loadProgress ?? 0), height: 2)
                }.frame(height: 2)
            }

            // Address bar pill (tap to edit)
            Button { withAnimation(.easeInOut(duration: 0.25)) { isAddressEditing = true; addressText = tabManager.activeTab?.url?.absoluteString ?? "" } } label: {
                HStack(spacing: 8) {
                    Image(systemName: tabManager.activeTab?.isSecure == true ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(tabManager.activeTab?.isSecure == true ? Color.secondary : Color.red)
                    Text(tabManager.activeTab?.url?.host ?? "검색 또는 주소 입력")
                        .font(.system(size: 15)).foregroundStyle(.primary).lineLimit(1)
                    Spacer()
                    if tabManager.activeTab?.isLoading == true {
                        ProgressView().scaleEffect(0.6)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color(.tertiarySystemFill)).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 12).padding(.top, 8)

            // Toolbar: ◁ ▷ Share Downloads Tabs Settings
            HStack(spacing: 0) {
                tbtn("chevron.left", tabManager.activeTab?.canGoBack == true) { webViewRef?.goBack() }
                tbtn("chevron.right", tabManager.activeTab?.canGoForward == true) { webViewRef?.goForward() }

                // Share + Tools menu
                Menu {
                    Section {
                        Button { tabManager.newTab() } label: { Label("새 탭", systemImage: "plus.square") }
                        Button { tabManager.newTab(isPrivate: true) } label: { Label("프라이빗 탭", systemImage: "lock.square") }
                    }
                    Section {
                        Button { webViewRef?.reload() } label: { Label("새로고침", systemImage: "arrow.clockwise") }
                        Button {
                            isElementHideMode = true
                            webViewRef?.evaluateJavaScript("window._gsToggleHideMode()")
                        } label: { Label("방해 요소 가리기", systemImage: "eye.slash") }
                        Button {
                            if let h = tabManager.activeTab?.url?.host { ElementHiderStore.shared.clearRules(for: h); webViewRef?.reload() }
                        } label: { Label("숨긴 요소 복원", systemImage: "eye") }
                    }
                    Section {
                        Button { showPrivacy = true } label: { Label("프라이버시", systemImage: "shield.checkered") }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 18))
                        .frame(maxWidth: .infinity).frame(height: 44)
                }

                // Downloads
                Button { showDownloads = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 18))
                            .frame(maxWidth: .infinity).frame(height: 44)
                        if !downloadManager.downloads.isEmpty || !downloadManager.completedDownloads.isEmpty {
                            Circle().fill(.teal).frame(width: 8, height: 8).offset(x: -14, y: 10)
                        }
                    }
                }

                // Tabs
                Button { showTabGrid = true } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                        Text("\(tabManager.tabs.count)").font(.system(size: 11, weight: .medium))
                    }.frame(maxWidth: .infinity).frame(height: 44)
                }

                // Settings (직접 접근)
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 18))
                        .frame(maxWidth: .infinity).frame(height: 44)
                }
            }
            .padding(.bottom, 4)
        }
        .background(.ultraThinMaterial)
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

    private func closeSearch() {
        withAnimation(.easeInOut(duration: 0.25)) { isAddressEditing = false }
        isURLFieldFocused = false
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
