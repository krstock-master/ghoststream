// UI/Browser/BrowserContainerView.swift
// GhostStream v0.8.0 — Chrome/Brave hybrid UI
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
                if isElementHideMode { elementHideBanner }
                if isAddressEditing { topSearchBar }
                webArea.frame(maxWidth: .infinity, maxHeight: .infinity)
                if !isAddressEditing { bottomToolbar }
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
                latestMedia = media
                withAnimation { showMediaSnackbar = true }
                Task { try? await Task.sleep(for: .seconds(3)); withAnimation { showMediaSnackbar = false } }

                // ★ Route through WKWebView notification → coordinator handles startWKDownload
                NotificationCenter.default.post(name: .wkDownloadRequested, object: media)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .downloadCompleted)) { n in
            if let msg = n.object as? String {
                toastIsError = false; toastMessage = msg
                Task { try? await Task.sleep(for: .seconds(3)); withAnimation { toastMessage = nil } }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .downloadFailed)) { n in
            if let msg = n.object as? String {
                toastIsError = true; toastMessage = msg
                Task { try? await Task.sleep(for: .seconds(4)); withAnimation { toastMessage = nil } }
            }
        }
        .overlay(alignment: .top) {
            if let toast = toastMessage {
                HStack(spacing: 10) {
                    Image(systemName: toastIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toastIsError ? .red : .green).font(.system(size: 18))
                    Text(toast).font(.subheadline.weight(.medium)).lineLimit(2)
                    Spacer()
                    Button { withAnimation { toastMessage = nil } } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                .padding(.horizontal, 16).padding(.top, 54)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: toastMessage)
            }
        }
        .overlay(alignment: .bottom) {
            if showMediaSnackbar, let media = latestMedia {
                snackbar(media).padding(.horizontal, 16).padding(.bottom, isAddressEditing ? 12 : 130)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.35), value: showMediaSnackbar)
            }
        }
        .sheet(isPresented: $showDownloads) { DownloadsManagerView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPrivacy) { PrivacyDashboardView() }
        .sheet(isPresented: $showTabGrid) { TabGridView() }
    }

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
                .font(.system(size: 16, weight: .medium)).foregroundStyle(.teal)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.systemBackground))
        .onAppear { isURLFieldFocused = true }
    }

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

    private func snackbar(_ media: DetectedMedia) -> some View {
        Button {
            // ★ WKDownload 경로로 — URLSession 대신 브라우저 세션 사용
            NotificationCenter.default.post(name: .wkDownloadRequested, object: media)
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
            .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
        }
    }

    // MARK: - Bottom Toolbar (Chrome/Brave)
    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            if tabManager.activeTab?.isLoading == true {
                GeometryReader { geo in
                    Rectangle().fill(LinearGradient(colors: [.teal, .cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * (tabManager.activeTab?.loadProgress ?? 0), height: 2.5)
                        .animation(.easeInOut(duration: 0.2), value: tabManager.activeTab?.loadProgress)
                }.frame(height: 2.5)
            }
            // Address bar pill
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isAddressEditing = true
                    addressText = tabManager.activeTab?.url?.absoluteString ?? ""
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: tabManager.activeTab?.isSecure == true ? "lock.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tabManager.activeTab?.isSecure == true ? .green : .orange)
                        .frame(width: 18)
                    Text(tabManager.activeTab?.url?.host ?? "검색 또는 주소 입력")
                        .font(.system(size: 15)).foregroundStyle(.primary).lineLimit(1)
                    Spacer()
                    if let rpt = tabManager.activeTab?.privacyReport,
                       (rpt.adsBlocked + rpt.trackersBlocked) > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "shield.checkered").font(.system(size: 10, weight: .semibold))
                            Text("\(rpt.adsBlocked + rpt.trackersBlocked)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.green.opacity(0.12), in: Capsule())
                    }
                    if tabManager.activeTab?.isLoading == true {
                        ProgressView().scaleEffect(0.55)
                    } else if tabManager.activeTab?.url != nil {
                        Button { webViewRef?.reload() } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(Color(.tertiarySystemFill)).clipShape(RoundedRectangle(cornerRadius: 26))
            }
            .padding(.horizontal, 14).padding(.top, 8)
            // 5-button bar: ← → ⬇️ □ ⋯
            HStack(spacing: 0) {
                // ★ Fix 6: 뒤로가기 — disabled 대신 opacity로 처리 (터치 영역 유지)
                Button {
                    webViewRef?.goBack()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium))
                        .foregroundStyle(tabManager.activeTab?.canGoBack == true ? Color.primary : Color.primary.opacity(0.2))
                        .frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
                }

                // 앞으로가기
                Button {
                    webViewRef?.goForward()
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 18, weight: .medium))
                        .foregroundStyle(tabManager.activeTab?.canGoForward == true ? Color.primary : Color.primary.opacity(0.2))
                        .frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
                }

                // ★ Fix 4: 다운로드 버튼 (FAB 대체 → 하단 바에 배지)
                Button { showDownloads = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 18, weight: .medium))
                            .frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
                        if downloadManager.downloads.count + downloadManager.completedDownloads.count > 0 {
                            Text("\(downloadManager.downloads.count + downloadManager.completedDownloads.count)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(.red, in: Circle())
                                .offset(x: -10, y: 8)
                        }
                    }
                }

                // 탭
                Button { showTabGrid = true } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5.5).stroke(Color.primary.opacity(0.55), lineWidth: 1.5).frame(width: 22, height: 22)
                        Text("\(tabManager.tabs.count)").font(.system(size: 12, weight: .semibold, design: .rounded))
                    }.frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
                }

                // 메뉴 (⋯)
                Menu {
                    Section("탭") {
                        Button { tabManager.newTab() } label: { Label("새 탭", systemImage: "plus.square") }
                        Button { tabManager.newTab(isPrivate: true) } label: { Label("프라이빗 탭", systemImage: "lock.square") }
                    }
                    Section("도구") {
                        Button { webViewRef?.reload() } label: { Label("새로고침", systemImage: "arrow.clockwise") }
                        Button { isElementHideMode = true; webViewRef?.evaluateJavaScript("window._gsToggleHideMode()") } label: { Label("요소 가리기", systemImage: "eye.slash") }
                        Button { if let h = tabManager.activeTab?.url?.host { ElementHiderStore.shared.clearRules(for: h); webViewRef?.reload() } } label: { Label("숨긴 요소 복원", systemImage: "eye") }
                    }
                    Section {
                        Button { showPrivacy = true } label: { Label("프라이버시 리포트", systemImage: "shield.checkered") }
                        Button { showSettings = true } label: { Label("설정", systemImage: "gearshape") }
                    }
                    if let url = tabManager.activeTab?.url {
                        Section { ShareLink(item: url) { Label("페이지 공유", systemImage: "square.and.arrow.up") } }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 18, weight: .medium))
                        .frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
                }
            }.padding(.bottom, 2)
        }.background(.ultraThinMaterial)
    }

    // MARK: - Helpers (removed old tBtn — inlined above for fix 6)

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
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer().frame(height: 50)

                // Logo
                VStack(spacing: 6) {
                    Text("\u{1F47B}").font(.system(size: 52))
                    Text("GhostStream")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                }

                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary).font(.system(size: 15))
                    TextField("검색어 또는 주소 입력", text: $searchText)
                        .textFieldStyle(.plain).font(.system(size: 16))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isSearchFocused)
                        .onSubmit { onNavigate(searchText); searchText = "" }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 24)

                // Quick links
                VStack(alignment: .leading, spacing: 12) {
                    Text("자주 방문").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary).padding(.leading, 4)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 18) {
                        ql("Google", "magnifyingglass", .blue, "https://google.com")
                        ql("YouTube", "play.rectangle.fill", .red, "https://youtube.com")
                        ql("네이버", "n.circle.fill", .green, "https://naver.com")
                        ql("Twitter", "at", .cyan, "https://x.com")
                        ql("디시인사이드", "bubble.left.fill", .orange, "https://dcinside.com")
                        ql("인스타", "camera.fill", .purple, "https://instagram.com")
                        ql("Reddit", "r.circle.fill", .orange, "https://reddit.com")
                        ql("GitHub", "chevron.left.forwardslash.chevron.right", .gray, "https://github.com")
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }.background(Color(.systemBackground))
    }

    private func ql(_ n: String, _ i: String, _ c: Color, _ u: String) -> some View {
        Button { onNavigate(u) } label: {
            VStack(spacing: 8) {
                Image(systemName: i).font(.system(size: 22, weight: .medium)).foregroundStyle(c)
                    .frame(width: 52, height: 52).background(c.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text(n).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
