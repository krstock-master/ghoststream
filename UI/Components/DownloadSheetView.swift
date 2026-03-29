// UI/Components/DownloadsManagerView.swift
// File manager for downloaded media (replaces vault)
import SwiftUI
import AVKit
import QuickLook

struct DownloadsManagerView: View {
    @Environment(MediaDownloadManager.self) private var dm
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSegment = 0
    @State private var playerURL: URL?
    @State private var showPlayer = false
    @State private var previewURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedSegment) {
                    Text("진행 중 (\(dm.downloads.count))").tag(0)
                    Text("완료 (\(dm.completedDownloads.count))").tag(1)
                    Text("파일").tag(2)
                }.pickerStyle(.segmented).padding()

                ScrollView {
                    LazyVStack(spacing: 8) {
                        switch selectedSegment {
                        case 0: activeDownloads
                        case 1: completedDownloads
                        default: savedFiles
                        }
                    }.padding(.horizontal)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("다운로드").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .fullScreenCover(isPresented: $showPlayer) {
                if let url = playerURL {
                    ZStack(alignment: .topTrailing) {
                        VideoPlayer(player: AVPlayer(url: url)).ignoresSafeArea()
                        Button { showPlayer = false } label: {
                            Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white).padding()
                        }
                    }.background(Color.black.ignoresSafeArea())
                }
            }
        }
    }

    @ViewBuilder
    private var activeDownloads: some View {
        if dm.downloads.isEmpty {
            emptyState("진행 중인 다운로드 없음", icon: "arrow.down.circle")
        } else {
            ForEach(dm.downloads) { dl in
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: dl.media.type == .gif ? "photo" : "film")
                            .foregroundStyle(.teal).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dl.media.title).font(.subheadline).lineLimit(1)
                            Text("\(dl.formattedProgress) · \(dl.media.type.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(dl.formattedSpeed).font(.caption2.monospacedDigit()).foregroundStyle(.teal)
                    }
                    ProgressView(value: dl.progress).tint(.teal)
                }
                .padding(12).background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private var completedDownloads: some View {
        if dm.completedDownloads.isEmpty {
            emptyState("완료된 다운로드 없음", icon: "checkmark.circle")
        } else {
            ForEach(dm.completedDownloads) { dl in
                Button {
                    if let url = dl.localURL { openFile(url, type: dl.media.type) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dl.media.title).font(.subheadline).lineLimit(1).foregroundStyle(.primary)
                            Text(dl.media.type.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if dl.localURL != nil {
                            Image(systemName: "play.circle").foregroundStyle(.teal)
                        }
                    }
                    .padding(12).background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    @ViewBuilder
    private var savedFiles: some View {
        let files = getDownloadedFiles()
        if files.isEmpty {
            emptyState("저장된 파일 없음", icon: "folder")
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
                    .padding(12).background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .contextMenu {
                    ShareLink(item: url) { Label("공유", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) {
                        try? FileManager.default.removeItem(at: url)
                    } label: { Label("삭제", systemImage: "trash") }
                }
            }
        }
    }

    private func emptyState(_ text: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(.secondary)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.top, 60)
    }

    private func openFile(_ url: URL, type: DetectedMedia.MediaType) {
        if type == .mp4 || type == .hls || type == .blob {
            playerURL = url; showPlayer = true
        } else {
            // Share sheet for images/gifs
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController {
                root.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
            }
        }
    }

    private func getDownloadedFiles() -> [URL] {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads")
        return (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles)) ?? []
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
