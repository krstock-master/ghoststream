// UI/Components/DownloadSheetView.swift
// GhostStream - Media download options + active downloads list

import SwiftUI

struct DownloadSheetView: View {
    let media: DetectedMedia?
    @Environment(MediaDownloadManager.self) private var downloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedQuality: String = "720p"
    @State private var saveToVault: Bool = true
    @State private var selectedSegment: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedSegment) {
                    Text("새 다운로드").tag(0)
                    Text("진행 중 (\(downloadManager.downloads.count))").tag(1)
                    Text("완료").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                ScrollView {
                    switch selectedSegment {
                    case 0: newDownloadContent
                    case 1: activeDownloadsContent
                    default: completedContent
                    }
                }
            }
            .background(GhostTheme.bg)
            .navigationTitle("다운로드")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(GhostTheme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - New Download
    @ViewBuilder
    private var newDownloadContent: some View {
        if let media = media {
            VStack(spacing: 16) {
                // Media info
                HStack(spacing: 12) {
                    Image(systemName: media.type == .gif ? "photo.fill" : "film.fill")
                        .font(.title2)
                        .foregroundStyle(GhostTheme.accent)
                        .frame(width: 50, height: 50)
                        .glass(12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(media.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text("\(media.type.rawValue) · \(media.quality)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let size = media.estimatedSize {
                            Text(size).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }
                .padding()
                .glass()

                // Quality selection (for HLS)
                if media.type == .hls {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("화질 선택")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)

                        ForEach(["1080p", "720p", "480p"], id: \.self) { q in
                            Button {
                                selectedQuality = q
                            } label: {
                                HStack {
                                    Image(systemName: selectedQuality == q ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(selectedQuality == q ? GhostTheme.accent : .tertiary)
                                    Text(q)
                                        .foregroundStyle(.white)
                                    if q == "720p" {
                                        Text("권장")
                                            .font(.caption2)
                                            .foregroundStyle(GhostTheme.accent)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(GhostTheme.accent.opacity(0.15), in: Capsule())
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .glass()
                            }
                        }
                    }
                }

                // Save location
                VStack(alignment: .leading, spacing: 8) {
                    Text("저장 위치")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)

                    Button { saveToVault = true } label: {
                        saveOption("🔒 잠금 보관함 (암호화)", selected: saveToVault)
                    }
                    Button { saveToVault = false } label: {
                        saveOption("📁 파일 앱", selected: !saveToVault)
                    }
                }

                // Download button
                Button {
                    downloadManager.download(media: media, saveToVault: saveToVault)
                    selectedSegment = 1
                } label: {
                    Text("저장 시작")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(GhostTheme.accent, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        } else {
            VStack(spacing: 16) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
                Text("감지된 미디어 없음")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("웹페이지에서 영상이나 GIF가 감지되면\n여기에 표시됩니다.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 60)
        }
    }

    private func saveOption(_ text: String, selected: Bool) -> some View {
        HStack {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(selected ? GhostTheme.accent : .tertiary)
            Text(text).foregroundStyle(.white)
            Spacer()
        }
        .padding(12)
        .glass()
    }

    // MARK: - Active Downloads
    private var activeDownloadsContent: some View {
        VStack(spacing: 8) {
            if downloadManager.downloads.isEmpty {
                Text("진행 중인 다운로드 없음")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 60)
            } else {
                ForEach(downloadManager.downloads) { dl in
                    DownloadProgressRow(download: dl)
                }
            }
        }
        .padding()
    }

    // MARK: - Completed
    private var completedContent: some View {
        VStack(spacing: 8) {
            if downloadManager.completedDownloads.isEmpty {
                Text("완료된 다운로드 없음")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.top, 60)
            } else {
                ForEach(downloadManager.completedDownloads) { dl in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(GhostTheme.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dl.media.title).font(.subheadline).foregroundStyle(.white).lineLimit(1)
                            Text(dl.media.type.rawValue).font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if dl.saveToVault {
                            Image(systemName: "lock.fill").font(.caption).foregroundStyle(GhostTheme.accentAlt)
                        }
                    }
                    .padding(12)
                    .glass()
                }
            }
        }
        .padding()
    }
}

// MARK: - Download Progress Row
struct DownloadProgressRow: View {
    @Bindable var download: MediaDownload
    @Environment(MediaDownloadManager.self) private var manager

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(download.media.title).font(.subheadline).foregroundStyle(.white).lineLimit(1)
                    Text("\(download.media.type.rawValue) · \(download.formattedProgress)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(download.formattedSpeed).font(.caption2.monospacedDigit()).foregroundStyle(GhostTheme.accent)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.1)).frame(height: 4)
                    RoundedRectangle(cornerRadius: 3).fill(GhostTheme.gradient)
                        .frame(width: geo.size.width * download.progress, height: 4)
                        .animation(.linear, value: download.progress)
                }
            }
            .frame(height: 4)

            HStack(spacing: 12) {
                if download.state == .downloading {
                    Button("일시정지") { manager.pause(download) }
                    Button("취소") { manager.cancel(download) }.foregroundStyle(.red)
                } else if download.state == .paused {
                    Button("재개") { manager.resume(download) }
                } else if download.state == .failed {
                    Text(download.error ?? "오류").font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("재시도") { manager.retry(download) }
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(GhostTheme.accent)
        }
        .padding(12)
        .glass()
    }
}
