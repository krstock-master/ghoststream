// UI/Components/DownloadsManagerView.swift
import GhostStreamCore
import SwiftUI
import AVKit
import AVFoundation
import Photos

struct DownloadsManagerView: View {
    @Environment(MediaDownloadManager.self) private var dm
    @Environment(VaultManager.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var playerURL: URL?
    @State private var showPlayer = false
    @State private var savedToGallery: Set<String> = []
    @State private var showVaultAuth = false

    @State private var showURLInput = false
    @State private var pasteURL = ""
    @State private var fileListRefresh = UUID() // ★ 파일 목록 갱신 트리거
    @State private var showDeleteAllFilesConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text("다운로드")
                    }.tag(0)
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("파일")
                    }.tag(1)
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield")
                        Text("보안 폴더")
                    }.tag(2)
                }.pickerStyle(.segmented).padding(.horizontal).padding(.top, 12)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        switch selectedTab {
                        case 0: downloadsTab
                        case 1: filesTab
                        default: vaultTab
                        }
                    }.padding(.horizontal)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("다운로드").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // ★ 방법 3: URL 직접 입력 다운로드
                    Button {
                        // Auto-paste from clipboard
                        if let clip = UIPasteboard.general.string,
                           (clip.hasPrefix("http://") || clip.hasPrefix("https://")) {
                            pasteURL = clip
                        } else {
                            pasteURL = ""
                        }
                        showURLInput = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.teal)
                    }
                    .accessibilityLabel("URL로 다운로드")
                }
                ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } }
            }
            .sheet(isPresented: $showPlayer) {
                if let url = playerURL {
                    VideoPlayerSheet(url: url, isPresented: $showPlayer)
                }
            }
            .alert("URL 다운로드", isPresented: $showURLInput) {
                TextField("영상 URL 붙여넣기", text: $pasteURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("다운로드") {
                    let trimmed = pasteURL.trimmingCharacters(in: .whitespaces)
                    if let url = URL(string: trimmed),
                       (url.scheme == "http" || url.scheme == "https") {
                        // ★ WKDownload 경로로 요청
                        let media = DetectedMedia(url: url, type: trimmed.contains(".m3u8") ? .hls : .mp4,
                            quality: "URL", title: url.deletingPathExtension().lastPathComponent,
                            referer: "", thumbnail: nil, estimatedSize: nil)
                        NotificationCenter.default.post(name: .wkDownloadRequested, object: media)
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("클립보드에 URL이 있으면 자동으로 붙여넣습니다")
            }
            .alert("모든 파일 삭제", isPresented: $showDeleteAllFilesConfirm) {
                Button("삭제", role: .destructive) {
                    for url in getDownloadedFiles() {
                        try? FileManager.default.removeItem(at: url)
                    }
                    fileListRefresh = UUID()
                    NotificationCenter.default.post(name: .downloadCompleted, object: "모든 파일을 삭제했습니다")
                }
                Button("취소", role: .cancel) {}
            } message: { Text("기기에 저장된 다운로드 파일이 모두 삭제됩니다. 되돌릴 수 없습니다.") }
        }
    }

    // MARK: - Downloads Tab (Active + Completed)
    @ViewBuilder
    private var downloadsTab: some View {
        // Active downloads section
        if !dm.downloads.isEmpty {
            HStack {
                Text("진행 중").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(dm.downloads.count)개").font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)
        }
        ForEach(dm.downloads) { dl in
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: dl.state == .converting ? "arrow.triangle.2.circlepath" : "arrow.down.circle")
                        .foregroundStyle(dl.state == .converting ? .orange : .teal)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dl.media.title).font(.subheadline).lineLimit(1)
                        Text("\(dl.state == .converting ? "MP4 변환 중..." : dl.formattedProgress) · \(dl.media.type.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if dl.state == .converting {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text(dl.formattedSpeed).font(.caption2.monospacedDigit()).foregroundStyle(.teal)
                    }
                }
                ProgressView(value: dl.state == .converting ? nil : dl.progress).tint(dl.state == .converting ? .orange : .teal)
            }
            .padding(12).background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
        }

        // Completed downloads section
        if !dm.completedDownloads.isEmpty {
            HStack(spacing: 12) {
                Text("완료").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    // ★ v2.0.5: 실제 성공 개수 집계 (사진 앱 미지원 형식 제외, 이미 저장한 것 제외)
                    let targets = dm.completedDownloads.filter { dl in
                        guard let url = dl.localURL else { return false }
                        return Self.isPhotosCompatible(url) && !savedToGallery.contains(dl.id.uuidString)
                    }
                    let skipped = dm.completedDownloads.count - targets.count
                    guard !targets.isEmpty else {
                        NotificationCenter.default.post(name: .downloadFailed, object: "사진 앱에 저장할 새 항목이 없습니다")
                        return
                    }
                    let group = DispatchGroup()
                    var ok = 0
                    for dl in targets {
                        guard let url = dl.localURL else { continue }
                        group.enter()
                        saveToGallery(url: url, type: dl.media.type) { success in
                            if success { ok += 1; savedToGallery.insert(dl.id.uuidString) }
                            group.leave()
                        }
                    }
                    group.notify(queue: .main) {
                        let fail = targets.count - ok
                        var msg = "\(ok)개를 사진 앱에 저장했습니다"
                        if fail > 0 { msg += " · \(fail)개 실패" }
                        if skipped > 0 { msg += " · \(skipped)개 제외(미지원/저장됨)" }
                        NotificationCenter.default.post(name: fail > 0 ? .downloadFailed : .downloadCompleted, object: msg)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.badge.arrow.down")
                        Text("모두 저장")
                    }.font(.caption.weight(.semibold)).foregroundStyle(.teal)
                }
                Button {
                    dm.completedDownloads.removeAll()
                    NotificationCenter.default.post(name: .downloadCompleted,
                        object: "목록을 지웠습니다 (파일은 유지)")
                } label: {
                    // ★ v2.0.5: 파일은 지우지 않고 목록만 비우므로 문구 명확화
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                        Text("목록 지우기")
                    }.font(.caption.weight(.semibold)).foregroundStyle(.red)
                }
            }.padding(.top, 12)
        }
        ForEach(dm.completedDownloads) { dl in
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dl.media.title).font(.subheadline).lineLimit(1)
                        HStack(spacing: 4) {
                            Text(dl.media.type.rawValue).font(.caption).foregroundStyle(.secondary)
                            if let status = dl.hlsConversionStatus {
                                Text("·").font(.caption).foregroundStyle(.secondary)
                                Text(status.contains("완료") ? "MP4" : "movpkg")
                                    .font(.caption)
                                    .foregroundStyle(status.contains("완료") ? .green : .orange)
                            }
                        }
                    }
                    Spacer()
                    if let url = dl.localURL {
                        Button { openFile(url, type: dl.media.type) } label: {
                            Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.teal)
                                .frame(minWidth: DS.minTapTarget, minHeight: DS.minTapTarget)
                        }
                        .accessibilityLabel("열기")
                    }
                }
                // Action buttons
                if let url = dl.localURL {
                    // ★ v2.0.5: 자동 저장 경로는 없음 → 실제로 저장한 항목만 '저장됨'
                    let autoSaved = false

                    HStack(spacing: 10) {
                        Button {
                            saveToGallery(url: url, type: dl.media.type) { success in
                                if success { savedToGallery.insert(dl.id.uuidString) }
                                NotificationCenter.default.post(name: success ? .downloadCompleted : .downloadFailed,
                                    object: success ? "사진 앱에 저장했습니다" : "사진 앱에 저장하지 못했습니다")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: (autoSaved || savedToGallery.contains(dl.id.uuidString)) ? "checkmark" : "photo.badge.arrow.down")
                                Text((autoSaved || savedToGallery.contains(dl.id.uuidString)) ? "저장됨" : "사진에 저장")
                            }.font(.caption).foregroundStyle((autoSaved || savedToGallery.contains(dl.id.uuidString)) ? .green : .teal)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill)).clipShape(Capsule())
                        }
                        .disabled(autoSaved || savedToGallery.contains(dl.id.uuidString))

                        ShareLink(item: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                Text("공유")
                            }.font(.caption).foregroundStyle(.teal)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill)).clipShape(Capsule())
                        }

                        Button {
                            Task {
                                do {
                                    try await vault.unlock()
                                    try await vault.store(fileURL: url, originalName: dl.media.title)
                                    // ★ 보안폴더 저장 후 원본 파일 삭제
                                    try? FileManager.default.removeItem(at: url)
                                    // ★ 갤러리(PHAsset)에서도 삭제 (권한 요청 포함, 자체 토스트 발송)
                                    await Self.deleteFromPhotoLibrary(filename: url.lastPathComponent)
                                    await MainActor.run {
                                        dm.completedDownloads.removeAll { $0.id == dl.id }
                                        NotificationCenter.default.post(name: .downloadCompleted, object: "보안 폴더에 저장했습니다")
                                    }
                                } catch {
                                    await MainActor.run {
                                        NotificationCenter.default.post(name: .downloadFailed, object: "보안 폴더 저장 실패: \(error.localizedDescription)")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.shield")
                                Text("보안 폴더")
                            }.font(.caption).foregroundStyle(.purple)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill)).clipShape(Capsule())
                        }

                        Spacer()

                        // ★ 삭제 버튼
                        Button(role: .destructive) {
                            if let url = dl.localURL {
                                try? FileManager.default.removeItem(at: url)
                            }
                            dm.completedDownloads.removeAll { $0.id == dl.id }
                        } label: {
                            Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill)).clipShape(Capsule())
                        }
                        .accessibilityLabel("파일 삭제")
                    }
                }
            }
            .padding(12).background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
        }

        if dm.downloads.isEmpty && dm.completedDownloads.isEmpty {
            emptyState("다운로드 없음", icon: "arrow.down.circle", desc: "웹에서 영상이나 사진을 다운로드하면 여기에 표시됩니다")
        }
    }

    // MARK: - Files Tab
    @ViewBuilder
    private var filesTab: some View {
        let files = getDownloadedFiles()
        let _ = fileListRefresh
        if files.isEmpty {
            emptyState("저장된 파일 없음", icon: "folder", desc: "다운로드된 파일이 여기에 저장됩니다")
        } else {
            // ★ 헤더: 파일 수 + 모두 갤러리 저장 + 모두 삭제
            HStack(spacing: 12) {
                Text("\(files.count)개 파일").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    // ★ v2.0.5: 이미 사진 앱에 저장한 파일은 건너뜀(중복 방지) + 실제 결과 집계
                    let targets = files.filter {
                        Self.isPhotosCompatible($0) && GalleryAssetTracker.shared.assetID(for: $0.lastPathComponent) == nil
                    }
                    guard !targets.isEmpty else {
                        NotificationCenter.default.post(name: .downloadFailed, object: "사진 앱에 저장할 새 파일이 없습니다")
                        return
                    }
                    let group = DispatchGroup()
                    var ok = 0
                    for url in targets {
                        group.enter()
                        saveToGallery(url: url, type: detectType(url)) { success in
                            if success { ok += 1 }
                            group.leave()
                        }
                    }
                    group.notify(queue: .main) {
                        let fail = targets.count - ok
                        let msg = fail > 0 ? "\(ok)개 저장 · \(fail)개 실패" : "\(ok)개 파일을 사진 앱에 저장했습니다"
                        NotificationCenter.default.post(name: fail > 0 ? .downloadFailed : .downloadCompleted, object: msg)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.badge.arrow.down")
                        Text("모두 저장")
                    }.font(.caption.weight(.semibold)).foregroundStyle(.teal)
                }
                Button {
                    showDeleteAllFilesConfirm = true   // ★ v2.0.5: 되돌릴 수 없는 삭제 → 확인
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("모두 삭제")
                    }.font(.caption.weight(.semibold)).foregroundStyle(.red)
                }
            }.padding(.vertical, 4)

            ForEach(files, id: \.absoluteString) { url in
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                HStack(spacing: 12) {
                    Image(systemName: iconFor(url)).foregroundStyle(.teal).font(.system(size: 20)).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).font(.subheadline).lineLimit(1).foregroundStyle(.primary)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    let ext = url.pathExtension.lowercased()
                    if ["mp4","m4v","mov","webm","jpg","jpeg","png","webp","heic","gif"].contains(ext) {
                        Button { saveToGallery(url: url, type: detectType(url)) } label: {
                            Image(systemName: "photo.badge.arrow.down").foregroundStyle(.teal)
                                .frame(minWidth: 36, minHeight: DS.minTapTarget)
                        }
                        .accessibilityLabel("사진 앱에 저장")
                    }
                    Button { openFile(url, type: detectType(url)) } label: {
                        Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(.teal)
                            .frame(minWidth: 36, minHeight: DS.minTapTarget)
                    }
                    .accessibilityLabel("열기")
                    // ★ 개별 삭제 버튼
                    Button {
                        try? FileManager.default.removeItem(at: url)
                        fileListRefresh = UUID()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            .frame(minWidth: 36, minHeight: DS.minTapTarget)
                    }
                    .accessibilityLabel("파일 삭제")
                }
                .padding(12).background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Vault Tab (보안 폴더)
    @ViewBuilder
    private var vaultTab: some View {
        if !vault.isUnlocked {
            VStack(spacing: 16) {
                Spacer().frame(height: 40)
                Image(systemName: "lock.shield.fill").font(.system(size: 48)).foregroundStyle(.purple)
                Text("보안 폴더").font(.title3.weight(.semibold))
                Text("Face ID로 잠금 해제하세요").font(.subheadline).foregroundStyle(.secondary)
                Button {
                    Task { do { try await vault.unlock() } catch {} }
                } label: {
                    Label("잠금 해제", systemImage: "faceid").font(.headline).foregroundStyle(.white)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(.purple, in: Capsule())
                }
                Spacer()
            }.frame(maxWidth: .infinity)
        } else {
            if vault.items.isEmpty {
                emptyState("보안 폴더 비어있음", icon: "lock.shield", desc: "다운로드 완료 후 '보안 폴더' 버튼으로 파일을 암호화 저장하세요")
            } else {
                ForEach(vault.items) { item in
                    VStack(spacing: 0) {
                        Button {
                            Task {
                                if let url = try? await vault.decrypt(item: item) {
                                    await MainActor.run { playerURL = url; showPlayer = true }
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.fill").foregroundStyle(.purple).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.originalName).font(.subheadline).lineLimit(1).foregroundStyle(.primary)
                                    HStack(spacing: 6) {
                                        Text(item.formattedSize).font(.caption).foregroundStyle(.secondary)
                                        Text("·").foregroundStyle(.secondary)
                                        Text(item.formattedDate).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "play.circle").foregroundStyle(.purple)
                            }
                            .padding(12)
                        }

                        // ★ 보안폴더 액션 버튼 (눈에 보이게)
                        HStack(spacing: 10) {
                            // 갤러리로 내보내기
                            Button {
                                Task {
                                    do {
                                        let url = try await vault.decrypt(item: item)
                                        await Self.exportVaultItemToGallery(url: url, item: item)
                                    } catch {
                                        await MainActor.run {
                                            NotificationCenter.default.post(name: .downloadFailed, object: "복호화 실패")
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "photo.badge.arrow.down")
                                    Text("사진으로")
                                }.font(.caption).foregroundStyle(.teal)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill)).clipShape(Capsule())
                            }

                            // 공유
                            Button {
                                Task {
                                    if let url = try? await vault.decrypt(item: item) {
                                        await MainActor.run {
                                            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                               let root = scene.windows.first?.rootViewController {
                                                root.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("공유")
                                }.font(.caption).foregroundStyle(.teal)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill)).clipShape(Capsule())
                            }

                            Spacer()

                            // 삭제
                            Button(role: .destructive) {
                                Task {
                                    try? await vault.delete(item: item)
                                    await MainActor.run {
                                        NotificationCenter.default.post(name: .downloadCompleted, object: "보안 폴더에서 삭제됨")
                                    }
                                }
                            } label: {
                                Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color(.tertiarySystemFill)).clipShape(Capsule())
                            }
                            .accessibilityLabel("보안 폴더에서 삭제")
                        }
                        .padding(.horizontal, 12).padding(.bottom, 10)
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Helpers
    private func emptyState(_ text: String, icon: String, desc: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(.secondary)
            Text(text).font(.headline).foregroundStyle(.secondary)
            Text(desc).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.top, 60)
    }

    private func openFile(_ url: URL, type: DetectedMedia.MediaType) {
        let ext = url.pathExtension.lowercased()
        let isPlayable = type == .mp4 || type == .hls || type == .blob || type == .webm
            || ["mp4","m4v","mov","webm","movpkg","ts"].contains(ext)
        let isImage = type == .image || type == .gif
            || ["png","jpg","jpeg","webp","heic","gif"].contains(ext)

        if isImage {
            // Share image instead of trying to play it
            if let s = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let r = s.windows.first?.rootViewController {
                r.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
            }
            return
        }

        if isPlayable {
            // movpkg: use AVPlayer directly (iOS can play .movpkg natively)
            // mp4/mov: direct play
            // If file doesn't exist (export failed), try the download folder fallback
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                playerURL = url; showPlayer = true
            } else {
                // File missing - try to find any matching file in Downloads
                let dir = MediaDownloadManager.downloadDirectory
                if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
                   let match = files.first(where: { $0.lastPathComponent.contains(url.deletingPathExtension().lastPathComponent.prefix(20)) }) {
                    playerURL = match; showPlayer = true
                }
            }
        } else {
            if let s = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let r = s.windows.first?.rootViewController {
                r.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
            }
        }
    }

    /// 사진 앱이 받아들이는 형식인지 (webm/ts/mkv 등은 Photos가 거부)
    static func isPhotosCompatible(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["jpg","jpeg","png","webp","heic","heif","gif"].contains(ext) { return true }
        if ["mp4","m4v","mov"].contains(ext) { return UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(url.path) }
        if ext == "movpkg" { return true }
        return false
    }

    /// ★ v2.0.5: 결과를 completion으로 보고 (completion이 nil이면 개별 토스트).
    ///   - 이미지는 원본 파일 그대로 추가 (pngData 재인코딩 금지 → 방향/용량/애니메이션 보존)
    ///   - 생성된 PHAsset ID를 GalleryAssetTracker에 기록 → 보안 폴더 이동 시 그 에셋만 삭제
    private func saveToGallery(url: URL, type: DetectedMedia.MediaType, completion: ((Bool) -> Void)? = nil) {
        let ext = url.pathExtension.lowercased()
        let report: (Bool, String) -> Void = { ok, msg in
            DispatchQueue.main.async {
                if let completion { completion(ok); return }
                NotificationCenter.default.post(name: ok ? .downloadCompleted : .downloadFailed, object: msg)
            }
        }
        if ext == "movpkg" {
            exportMovpkgThenSave(movpkgURL: url, type: type, completion: completion)
            return
        }
        guard Self.isPhotosCompatible(url) else {
            report(false, "사진 앱이 지원하지 않는 형식입니다 (.\(ext)) — 파일 앱에서 열어 주세요")
            return
        }
        guard FileManager.default.fileExists(atPath: url.path),
              ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) > 0 else {
            report(false, "파일이 비어있거나 존재하지 않습니다")
            return
        }
        let isVideo = ["mp4","m4v","mov"].contains(ext)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                report(false, "사진 앱 접근 권한이 필요합니다")
                return
            }
            var assetID: String?
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: isVideo ? .video : .photo, fileURL: url, options: nil)
                assetID = req.placeholderForCreatedAsset?.localIdentifier
            }) { success, error in
                if success, let assetID {
                    DispatchQueue.main.async {
                        GalleryAssetTracker.shared.track(filename: url.lastPathComponent, assetID: assetID)
                    }
                }
                report(success, success ? "사진 앱에 저장했습니다"
                                        : (error?.localizedDescription ?? "사진 앱 저장 실패"))
            }
        }
    }

    private func exportMovpkgThenSave(movpkgURL: URL, type: DetectedMedia.MediaType, completion: ((Bool) -> Void)? = nil) {
        let fail: () -> Void = {
            DispatchQueue.main.async {
                if let completion { completion(false); return }
                NotificationCenter.default.post(name: .downloadFailed, object: "영상 변환(MP4) 실패 — 사진 앱에 저장하지 못했습니다")
            }
        }
        let asset = AVURLAsset(url: movpkgURL)
        let supported = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preset = supported.contains(AVAssetExportPresetPassthrough)
            ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        guard let exp = AVAssetExportSession(asset: asset, presetName: preset) else { fail(); return }
        let dest = movpkgURL.deletingPathExtension().appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        exp.outputURL = dest
        exp.outputFileType = .mp4
        exp.shouldOptimizeForNetworkUse = true
        let destCopy = dest
        exp.exportAsynchronously {
            guard exp.status == .completed else { fail(); return }
            DispatchQueue.main.async {
                saveToGallery(url: destCopy, type: type, completion: completion)
            }
        }
    }

    private func getDownloadedFiles() -> [URL] {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads")
        return (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)) ?? []
    }

    private func detectType(_ url: URL) -> DetectedMedia.MediaType {
        let ext = url.pathExtension.lowercased()
        if ["mp4","m4v","mov","webm"].contains(ext) { return .mp4 }
        if ext == "gif" { return .gif }
        if ["png","jpg","jpeg","webp","heic"].contains(ext) { return .image }
        return .mp4
    }

    private func iconFor(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["mp4","m4v","mov","webm"].contains(ext) { return "film" }
        if ext == "gif" { return "photo" }
        if ["png","jpg","jpeg","webp"].contains(ext) { return "photo" }
        return "doc"
    }

    // ★ 보안폴더 이동 시 갤러리에서 해당 파일 삭제
    static func deleteFromPhotoLibrary(filename: String) async {
        // 이 앱이 사진 앱에 저장한 기록이 없으면 아무것도 지우지 않음 (전체 사진 권한도 요청하지 않음)
        let tracked = await MainActor.run { GalleryAssetTracker.shared.assetID(for: filename) }
        guard tracked != nil else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            await MainActor.run {
                NotificationCenter.default.post(name: .downloadFailed,
                    object: "사진 앱에서 지우려면 '모든 사진 접근' 권한이 필요합니다.\n설정 → GhostStream → 사진 → '전체 접근 허용'")
            }
            return
        }

        var toDelete: [PHAsset] = []

        // ★ 1차: 추적된 PHAsset ID로 정확 삭제 (가장 신뢰)
        if let trackedID = GalleryAssetTracker.shared.assetID(for: filename) {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [trackedID], options: nil)
            if let asset = result.firstObject {
                toDelete.append(asset)
            }
            GalleryAssetTracker.shared.remove(filename: filename)
        }

        // ★ v2.0.5: 추적된 에셋(이 앱이 저장한 것)만 삭제한다.
        //   이전의 '최근 10분 에셋' 폴백은 사용자가 직접 찍은 사진을 지울 수 있어 제거.
        guard !toDelete.isEmpty else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(toDelete as NSFastEnumeration)
            }
        } catch {
            // iOS가 삭제 확인 팝업에서 사용자가 거부한 경우 — 무시
        }
    }

    // ★ 보안폴더 → 갤러리 내보내기
    static func exportVaultItemToGallery(url: URL, item: VaultItem) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            await MainActor.run {
                NotificationCenter.default.post(name: .downloadFailed, object: "사진 앱 접근 권한이 필요합니다")
            }
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                let ext = (item.originalName as NSString).pathExtension.lowercased()
                let isVideo = ["mp4", "m4v", "mov", "webm"].contains(ext)
                if isVideo {
                    req.addResource(with: .video, fileURL: url, options: nil)
                } else if let data = try? Data(contentsOf: url) {
                    req.addResource(with: .photo, data: data, options: nil)
                }
            }
            await MainActor.run {
                NotificationCenter.default.post(name: .downloadCompleted,
                    object: "사진 앱으로 내보냈습니다: \(item.originalName)")
            }
        } catch {
            await MainActor.run {
                NotificationCenter.default.post(name: .downloadFailed,
                    object: "사진 앱으로 내보내기 실패: \(error.localizedDescription)")
            }
        }
    }
}
// MARK: - VideoPlayerSheet
struct VideoPlayerSheet: View {
    let url: URL
    @Binding var isPresented: Bool
    @State private var player: AVPlayer?
    @State private var isReady = false
    @State private var errorMsg: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let player, isReady {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else if let err = errorMsg {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40)).foregroundStyle(.orange)
                        Text("재생 실패").font(.headline).foregroundStyle(.white)
                        Text(err).font(.caption).foregroundStyle(.gray)
                            .multilineTextAlignment(.center).padding(.horizontal, 24)
                        Button("닫기") { cleanupAndDismiss() }
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24).padding(.vertical, 10)
                            .background(.teal, in: Capsule())
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(1.5).tint(.white)
                        Text("로딩 중...").font(.caption).foregroundStyle(.gray)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        cleanupAndDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.5), radius: 4)
                    }
                    .accessibilityLabel("닫기")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear {
            // ★ F4 FIX: 영상 재생 중 브라우저 뒤로가기 방지
            Task { await loadPlayer() }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .interactiveDismissDisabled(false)
        .presentationDragIndicator(.visible)
        .presentationDetents([.large]) // ★ F4: 전체화면 고정 (스와이프 충돌 방지)
    }

    private func cleanupAndDismiss() {
        player?.pause()
        player = nil
        isPresented = false
    }

    @MainActor
    private func loadPlayer() async {
        let ext = url.pathExtension.lowercased()

        // Check file exists for local files
        if !["http","https"].contains(url.scheme ?? "") {
            guard FileManager.default.fileExists(atPath: url.path) else {
                errorMsg = "파일을 찾을 수 없습니다\n\(url.lastPathComponent)"
                isLoading = false
                return
            }
        }

        // For movpkg: try export to mp4 first, then play
        if ext == "movpkg" {
            do {
                let mp4URL = try await exportMovpkgToMP4(url)
                let p = AVPlayer(url: mp4URL)
                player = p
                isReady = true
                isLoading = false
                p.play()
            } catch {
                // Fallback: try direct AVPlayer on movpkg
                let asset = AVURLAsset(url: url)
                do {
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    if !tracks.isEmpty {
                        let p = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                        player = p
                        isReady = true
                        p.play()
                    } else {
                        errorMsg = "재생 가능한 트랙 없음 (movpkg)"
                    }
                } catch {
                    errorMsg = "movpkg 재생 실패: \(error.localizedDescription)"
                }
                isLoading = false
            }
            return
        }

        // Standard video files
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if tracks.isEmpty {
                // For audio files, try audio tracks
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                if audioTracks.isEmpty {
                    errorMsg = "재생 가능한 트랙 없음\n포맷: \(ext)"
                    isLoading = false
                    return
                }
            }
            let item = AVPlayerItem(asset: asset)
            let p = AVPlayer(playerItem: item)
            player = p
            isReady = true
            isLoading = false
            p.play()
        } catch {
            errorMsg = error.localizedDescription
            isLoading = false
        }
    }

    private func exportMovpkgToMP4(_ movpkgURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: movpkgURL)
        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preset = presets.contains(AVAssetExportPresetPassthrough)
            ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw NSError(domain: "GhostStream", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export session 생성 실패"])
        }
        let dest = movpkgURL.deletingPathExtension().appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: dest.path) {
            // Already exported, just return
            return dest
        }
        session.outputURL = dest
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        await session.export()
        if session.status == .completed {
            return dest
        } else {
            throw session.error ?? NSError(domain: "GhostStream", code: -2, userInfo: [NSLocalizedDescriptionKey: "MP4 변환 실패"])
        }
    }
}
