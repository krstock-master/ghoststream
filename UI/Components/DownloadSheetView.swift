// UI/Components/DownloadsManagerView.swift
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("다운로드 (\(dm.downloads.count + dm.completedDownloads.count))").tag(0)
                    Text("파일").tag(1)
                    Text("보안 폴더").tag(2)
                }.pickerStyle(.segmented).padding()

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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .fullScreenCover(isPresented: $showPlayer) {
                if let url = playerURL {
                    VideoPlayerSheet(url: url, isPresented: $showPlayer)
                }
            }
        }
    }

    // MARK: - Downloads Tab (Active + Completed)
    @ViewBuilder
    private var downloadsTab: some View {
        // Active downloads
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

        // Completed downloads
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
                        }
                    }
                }
                // Action buttons
                if let url = dl.localURL {
                    HStack(spacing: 10) {
                        Button {
                            saveToGallery(url: url, type: dl.media.type)
                            savedToGallery.insert(dl.id.uuidString)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: savedToGallery.contains(dl.id.uuidString) ? "checkmark" : "photo.badge.arrow.down")
                                Text(savedToGallery.contains(dl.id.uuidString) ? "저장됨" : "갤러리 저장")
                            }.font(.caption).foregroundStyle(savedToGallery.contains(dl.id.uuidString) ? .green : .teal)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill)).clipShape(Capsule())
                        }
                        .disabled(savedToGallery.contains(dl.id.uuidString))

                        ShareLink(item: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                Text("공유")
                            }.font(.caption).foregroundStyle(.teal)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill)).clipShape(Capsule())
                        }

                        Button {
                            Task { try? await vault.unlock(); try? await vault.store(fileURL: url, originalName: dl.media.title) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.shield")
                                Text("보안 폴더")
                            }.font(.caption).foregroundStyle(.purple)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill)).clipShape(Capsule())
                        }

                        Spacer()
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
        if files.isEmpty {
            emptyState("저장된 파일 없음", icon: "folder", desc: "다운로드된 파일이 여기에 저장됩니다")
        } else {
            ForEach(files, id: \.absoluteString) { url in
                Button { openFile(url, type: detectType(url)) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: iconFor(url)).foregroundStyle(.teal).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent).font(.subheadline).lineLimit(1).foregroundStyle(.primary)
                            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.circle").foregroundStyle(.teal)
                    }
                    .padding(12).background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .contextMenu {
                    Button { saveToGallery(url: url, type: detectType(url)) } label: { Label("갤러리 저장", systemImage: "photo.badge.arrow.down") }
                    ShareLink(item: url) { Label("공유", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { try? FileManager.default.removeItem(at: url) } label: { Label("삭제", systemImage: "trash") }
                }
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
                                Text(item.formattedSize).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle").foregroundStyle(.purple)
                        }
                        .padding(12).background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
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
        let isPlayable = type == .mp4 || type == .hls || type == .blob
            || ["mp4","m4v","mov","webm","movpkg"].contains(ext)
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

    private func saveToGallery(url: URL, type: DetectedMedia.MediaType) {
        let ext = url.pathExtension.lowercased()
        let isVideoFile = ["mp4","m4v","mov","webm"].contains(ext)
        let isImageFile = ["jpg","jpeg","png","webp","heic","gif"].contains(ext)

        // Step 1: if .movpkg, export to .mp4 first, then recursively save
        if ext == "movpkg" {
            exportMovpkgThenSave(movpkgURL: url, type: type)
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [self] status in
            guard status == .authorized || status == .limited else { return }

            if isVideoFile {
                // UISaveVideoAtPathToSavedPhotosAlbum — most reliable for sideloaded apps
                UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
            } else if isImageFile {
                if let image = UIImage(contentsOfFile: url.path) {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                } else if ext == "gif",
                          let data = try? Data(contentsOf: url) {
                    // GIF via PHPhotoLibrary to preserve animation
                    PHPhotoLibrary.shared().performChanges {
                        let req = PHAssetCreationRequest.forAsset()
                        req.addResource(with: .photo, data: data, options: nil)
                    }
                }
            }
        }
    }

    private func exportMovpkgThenSave(movpkgURL: URL, type: DetectedMedia.MediaType) {
        let asset = AVURLAsset(url: movpkgURL)
        let supported = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preset = supported.contains(AVAssetExportPresetPassthrough)
            ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        guard let exp = AVAssetExportSession(asset: asset, presetName: preset) else { return }
        let dest = movpkgURL.deletingPathExtension().appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        exp.outputURL = dest
        exp.outputFileType = .mp4
        exp.shouldOptimizeForNetworkUse = true
        exp.exportAsynchronously { [weak self] in
            guard exp.status == .completed else { return }
            self?.saveToGallery(url: dest, type: .mp4)
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
        return .mp4
    }

    private func iconFor(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["mp4","m4v","mov","webm"].contains(ext) { return "film" }
        if ext == "gif" { return "photo" }
        if ["png","jpg","jpeg","webp"].contains(ext) { return "photo" }
        return "doc"
    }
}
// MARK: - VideoPlayerSheet
struct VideoPlayerSheet: View {
    let url: URL
    @Binding var isPresented: Bool
    @State private var player: AVPlayer?
    @State private var isReady = false
    @State private var errorMsg: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player, isReady {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if let err = errorMsg {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36)).foregroundStyle(.orange)
                    Text("재생 실패").font(.headline).foregroundStyle(.white)
                    Text(err).font(.caption).foregroundStyle(.gray)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                    Button("닫기") { isPresented = false }
                        .foregroundStyle(.teal)
                }
            } else {
                ProgressView().scaleEffect(1.5).tint(.white)
            }

            // Close button — always on top
            VStack {
                HStack {
                    Button {
                        player?.pause()
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 6)
                    }
                    .padding(.leading, 16)
                    .padding(.top, 52)
                    Spacer()
                }
                Spacer()
            }
        }
        .onAppear { Task { await loadPlayer() } }
        .onDisappear { player?.pause() }
        .gesture(
            DragGesture(minimumDistance: 60, coordinateSpace: .local)
                .onEnded { v in
                    if v.translation.height > 60 {
                        player?.pause()
                        isPresented = false
                    }
                }
        )
        .interactiveDismissDisabled(false)
    }

    @MainActor
    private func loadPlayer() async {
        let ext = url.pathExtension.lowercased()
        let asset: AVURLAsset

        if ext == "movpkg" || ext == "m3u8" {
            // These need AVURLAsset with proper loading
            asset = AVURLAsset(url: url)
        } else {
            // MP4/MOV/GIF — direct
            asset = AVURLAsset(url: url)
        }

        // Check file exists
        if !["http","https"].contains(url.scheme ?? "") {
            guard FileManager.default.fileExists(atPath: url.path) else {
                errorMsg = "파일을 찾을 수 없습니다\n\(url.lastPathComponent)"
                return
            }
        }

        do {
            // Load playable tracks
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if tracks.isEmpty {
                errorMsg = "재생 가능한 트랙 없음\n포맷: \(ext)"
                return
            }
            let item = AVPlayerItem(asset: asset)
            let p = AVPlayer(playerItem: item)
            player = p
            isReady = true
            p.play()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
