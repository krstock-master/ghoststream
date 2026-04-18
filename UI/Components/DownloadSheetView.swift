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
                Text("클립보드의 URL이 자동으로 붙여넣기됩니다")
            }
        }
    }

    // MARK: - Downloads Tab (Active + Completed)
    @ViewBuilder
    private var downloadsTab: some View {
        // Active downloads section
        if !dm.downloads.isEmpty {
            HStack {
                Text("진행 중").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(dm.downloads.count)개").font(.system(size: 12)).foregroundStyle(.secondary)
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
                Text("완료").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    var count = 0
                    for dl in dm.completedDownloads {
                        guard let url = dl.localURL else { continue }
                        let ext = url.pathExtension.lowercased()
                        let isMedia = ["mp4","m4v","mov","webm","jpg","jpeg","png","webp","heic","gif"].contains(ext)
                        if isMedia && !savedToGallery.contains(dl.id.uuidString) {
                            saveToGallery(url: url, type: dl.media.type)
                            savedToGallery.insert(dl.id.uuidString)
                            count += 1
                        }
                    }
                    NotificationCenter.default.post(name: .downloadCompleted,
                        object: "✅ \(count)개 갤러리 저장 완료")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.badge.arrow.down")
                        Text("모두 저장")
                    }.font(.system(size: 12, weight: .semibold)).foregroundStyle(.teal)
                }
                Button {
                    dm.completedDownloads.removeAll()
                    NotificationCenter.default.post(name: .downloadCompleted,
                        object: "🗑 목록 삭제 완료")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("모두 삭제")
                    }.font(.system(size: 12, weight: .semibold)).foregroundStyle(.red)
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
                        }
                    }
                }
                // Action buttons
                if let url = dl.localURL {
                    // ★ F3 FIX: 영상/이미지는 downloadDidFinish에서 자동 갤러리 저장됨
                    let ext = url.pathExtension.lowercased()
                    let autoSaved = ["mp4","m4v","mov","webm","jpg","jpeg","png","webp","heic","gif"].contains(ext)

                    HStack(spacing: 10) {
                        Button {
                            if !autoSaved {
                                saveToGallery(url: url, type: dl.media.type)
                            }
                            savedToGallery.insert(dl.id.uuidString)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: (autoSaved || savedToGallery.contains(dl.id.uuidString)) ? "checkmark" : "photo.badge.arrow.down")
                                Text((autoSaved || savedToGallery.contains(dl.id.uuidString)) ? "저장됨" : "갤러리 저장")
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
                                        NotificationCenter.default.post(name: .downloadCompleted, object: "🔒 보안 폴더에 저장 완료")
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
                Text("\(files.count)개 파일").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    var count = 0
                    for url in files {
                        let ext = url.pathExtension.lowercased()
                        if ["mp4","m4v","mov","webm","jpg","jpeg","png","webp","heic","gif"].contains(ext) {
                            saveToGallery(url: url, type: detectType(url))
                            count += 1
                        }
                    }
                    // ★ 토스트 피드백
                    NotificationCenter.default.post(name: .downloadCompleted,
                        object: "✅ \(count)개 파일 갤러리 저장 완료")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.badge.arrow.down")
                        Text("모두 저장")
                    }.font(.system(size: 12, weight: .semibold)).foregroundStyle(.teal)
                }
                Button {
                    for url in files {
                        try? FileManager.default.removeItem(at: url)
                    }
                    fileListRefresh = UUID()
                    NotificationCenter.default.post(name: .downloadCompleted,
                        object: "🗑 모든 파일 삭제 완료")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("모두 삭제")
                    }.font(.system(size: 12, weight: .semibold)).foregroundStyle(.red)
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
                        }
                    }
                    Button { openFile(url, type: detectType(url)) } label: {
                        Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(.teal)
                    }
                    // ★ 개별 삭제 버튼
                    Button {
                        try? FileManager.default.removeItem(at: url)
                        fileListRefresh = UUID()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary.opacity(0.5))
                    }
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
                                    Text("갤러리로")
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

    private func saveToGallery(url: URL, type: DetectedMedia.MediaType) {
        let ext = url.pathExtension.lowercased()
        let isVideoFile = ["mp4","m4v","mov","webm"].contains(ext)
        let isImageFile = ["jpg","jpeg","png","webp","heic","gif"].contains(ext)

        // Step 1: if .movpkg, export to .mp4 first, then recursively save
        if ext == "movpkg" {
            exportMovpkgThenSave(movpkgURL: url, type: type)
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .downloadFailed, object: "사진 앱 접근 권한이 필요합니다")
                }
                return
            }

            if isVideoFile {
                // Check file exists and has content before saving
                guard FileManager.default.fileExists(atPath: url.path),
                      (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0 > 0 else {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .downloadFailed, object: "파일이 비어있거나 존재하지 않습니다")
                    }
                    return
                }
                // Use PHPhotoLibrary for better error handling
                PHPhotoLibrary.shared().performChanges({
                    let req = PHAssetCreationRequest.forAsset()
                    req.addResource(with: .video, fileURL: url, options: nil)
                }) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            NotificationCenter.default.post(name: .downloadCompleted, object: "갤러리에 저장 완료")
                        } else {
                            // Fallback to UIKit API
                            UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
                            NotificationCenter.default.post(name: .downloadCompleted, object: "갤러리에 저장됨")
                        }
                    }
                }
            } else if isImageFile {
                if ext == "gif", let data = try? Data(contentsOf: url) {
                    // GIF via PHPhotoLibrary to preserve animation
                    PHPhotoLibrary.shared().performChanges({
                        let req = PHAssetCreationRequest.forAsset()
                        req.addResource(with: .photo, data: data, options: nil)
                    }) { success, error in
                        DispatchQueue.main.async {
                            if success {
                                NotificationCenter.default.post(name: .downloadCompleted, object: "GIF 갤러리에 저장 완료")
                            } else {
                                NotificationCenter.default.post(name: .downloadFailed, object: error?.localizedDescription ?? "GIF 저장 실패")
                            }
                        }
                    }
                } else if let image = UIImage(contentsOfFile: url.path) {
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetCreationRequest.forAsset().addResource(with: .photo, data: image.pngData() ?? Data(), options: nil)
                    }) { success, error in
                        DispatchQueue.main.async {
                            if success {
                                NotificationCenter.default.post(name: .downloadCompleted, object: "이미지 갤러리에 저장 완료")
                            } else {
                                NotificationCenter.default.post(name: .downloadFailed, object: error?.localizedDescription ?? "이미지 저장 실패")
                            }
                        }
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
        let destCopy = dest
        exp.exportAsynchronously {
            guard exp.status == .completed else { return }
            DispatchQueue.main.async {
                UISaveVideoAtPathToSavedPhotosAlbum(destCopy.path, nil, nil, nil)
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
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            await MainActor.run {
                NotificationCenter.default.post(name: .downloadFailed,
                    object: "갤러리 삭제를 위해 '모든 사진 접근' 권한이 필요합니다.\n설정 → GhostStream → 사진 → '전체 접근 허용'")
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

        // ★ 2차: ID 추적 실패 시 최근 에셋에서 파일 크기 매칭
        if toDelete.isEmpty {
            let ext = (filename as NSString).pathExtension.lowercased()
            let isVideo = ["mp4", "m4v", "mov", "webm"].contains(ext)
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 5
            let tenMinutesAgo = Date().addingTimeInterval(-600)
            fetchOptions.predicate = NSPredicate(format: "creationDate > %@", tenMinutesAgo as NSDate)

            let assets = PHAsset.fetchAssets(with: isVideo ? .video : .image, options: fetchOptions)
            // 파일명 매칭 시도
            let normalizedName = filename.lowercased().replacingOccurrences(of: " ", with: "_")
            assets.enumerateObjects { asset, _, _ in
                let resources = PHAssetResource.assetResources(for: asset)
                for r in resources {
                    let orig = r.originalFilename.lowercased().replacingOccurrences(of: " ", with: "_")
                    if orig == normalizedName || orig.contains((filename as NSString).deletingPathExtension.lowercased()) {
                        toDelete.append(asset)
                        return
                    }
                }
            }
            // 최종 폴백: 가장 최근 에셋
            if toDelete.isEmpty, let latest = assets.firstObject {
                toDelete.append(latest)
            }
        }

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
                    object: "📸 갤러리에 내보내기 완료: \(item.originalName)")
            }
        } catch {
            await MainActor.run {
                NotificationCenter.default.post(name: .downloadFailed,
                    object: "갤러리 내보내기 실패: \(error.localizedDescription)")
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
