// UI/Components/DownloadSheetView.swift
import SwiftUI

struct DownloadSheetView: View {
    let media: DetectedMedia?
    @Environment(MediaDownloadManager.self) private var downloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedQuality = "720p"
    @State private var saveToVault = true
    @State private var selectedSegment = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedSegment) {
                    Text("새 다운로드").tag(0)
                    Text("진행 중 (\(downloadManager.downloads.count))").tag(1)
                    Text("완료").tag(2)
                }.pickerStyle(.segmented).padding()

                ScrollView {
                    switch selectedSegment {
                    case 0: newDownloadView
                    case 1: activeView
                    default: completedView
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("다운로드").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() }.foregroundStyle(.teal) } }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var newDownloadView: some View {
        if let media = media {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: media.type == .gif ? "photo.fill" : "film.fill")
                        .font(.title2).foregroundStyle(.teal)
                        .frame(width: 50, height: 50).glass(12)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(media.title).font(.headline).foregroundStyle(.white).lineLimit(2)
                        Text("\(media.type.rawValue) · \(media.quality)").font(.caption).foregroundStyle(Color.gray)
                    }
                    Spacer()
                }.padding().glass()

                if media.type == .hls {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("화질 선택").font(.subheadline.weight(.medium)).foregroundStyle(.white)
                        ForEach(["1080p", "720p", "480p"], id: \.self) { q in
                            Button { selectedQuality = q } label: {
                                HStack {
                                    Image(systemName: selectedQuality == q ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(selectedQuality == q ? .teal : Color.gray.opacity(0.5))
                                    Text(q).foregroundStyle(.white)
                                    if q == "720p" {
                                        Text("권장").font(.caption2).foregroundStyle(.teal)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(.teal.opacity(0.15), in: Capsule())
                                    }
                                    Spacer()
                                }.padding(12).glass()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("저장 위치").font(.subheadline.weight(.medium)).foregroundStyle(.white)
                    Button { saveToVault = true } label: { saveLoc("🔒 잠금 보관함 (암호화)", saveToVault) }
                    Button { saveToVault = false } label: { saveLoc("📁 파일 앱 (Documents)", !saveToVault) }
                }

                Button {
                    downloadManager.download(media: media, saveToVault: saveToVault)
                    selectedSegment = 1
                } label: {
                    Text("저장 시작").font(.headline).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(.teal, in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding()
        } else {
            VStack(spacing: 16) {
                Image(systemName: "arrow.down.circle").font(.system(size: 44)).foregroundStyle(Color.gray)
                Text("감지된 미디어 없음").font(.headline).foregroundStyle(Color.gray)
                Text("웹페이지에서 영상이나 GIF가 감지되면 여기에 표시됩니다.")
                    .font(.caption).foregroundStyle(Color.gray).multilineTextAlignment(.center)
            }.padding(.top, 60)
        }
    }

    private func saveLoc(_ text: String, _ selected: Bool) -> some View {
        HStack {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(selected ? .teal : Color.gray.opacity(0.5))
            Text(text).foregroundStyle(.white).font(.subheadline)
            Spacer()
        }.padding(12).glass()
    }

    private var activeView: some View {
        VStack(spacing: 8) {
            if downloadManager.downloads.isEmpty {
                Text("진행 중인 다운로드 없음").font(.subheadline).foregroundStyle(Color.gray).padding(.top, 60)
            } else {
                ForEach(downloadManager.downloads) { dl in
                    DLRow(download: dl)
                }
            }
        }.padding()
    }

    private var completedView: some View {
        VStack(spacing: 8) {
            if downloadManager.completedDownloads.isEmpty {
                Text("완료된 다운로드 없음").font(.subheadline).foregroundStyle(Color.gray).padding(.top, 60)
            } else {
                ForEach(downloadManager.completedDownloads) { dl in
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dl.media.title).font(.subheadline).foregroundStyle(.white).lineLimit(1)
                                Text(dl.media.type.rawValue).font(.caption).foregroundStyle(Color.gray)
                            }
                            Spacer()
                            if dl.saveToVault {
                                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.tealAlt)
                            }
                        }
                        if let url = dl.localURL {
                            HStack(spacing: 12) {
                                ShareLink(item: url) {
                                    Label("공유", systemImage: "square.and.arrow.up")
                                        .font(.caption).foregroundStyle(.teal)
                                }
                                if !dl.saveToVault {
                                    Button {
                                        openFile(url)
                                    } label: {
                                        Label("열기", systemImage: "play.circle")
                                            .font(.caption).foregroundStyle(.teal)
                                    }
                                }
                                Spacer()
                                Text(url.lastPathComponent).font(.caption2).foregroundStyle(Color.gray).lineLimit(1)
                            }
                        }
                    }.padding(12).glass()
                }
            }
        }.padding()
    }

    private func openFile(_ url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        root.present(vc, animated: true)
    }
}

struct DLRow: View {
    @Bindable var download: MediaDownload
    @Environment(MediaDownloadManager.self) private var manager
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(download.media.title).font(.subheadline).foregroundStyle(.white).lineLimit(1)
                    Text("\(download.media.type.rawValue) · \(download.formattedProgress)")
                        .font(.caption).foregroundStyle(Color.gray)
                }
                Spacer()
                Text(download.formattedSpeed).font(.caption2.monospacedDigit()).foregroundStyle(.teal)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.1)).frame(height: 4)
                    RoundedRectangle(cornerRadius: 3).fill(Color.teal)
                        .frame(width: geo.size.width * download.progress, height: 4)
                }
            }.frame(height: 4)
            HStack(spacing: 12) {
                if download.state == .downloading {
                    Button("일시정지") { manager.pause(download) }.font(.caption).foregroundStyle(.orange)
                    Button("취소") { manager.cancel(download) }.font(.caption).foregroundStyle(.red)
                } else if download.state == .paused {
                    Button("재개") { manager.resume(download) }.font(.caption).foregroundStyle(.teal)
                } else if download.state == .failed {
                    Text(download.error ?? "오류").font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("재시도") { manager.retry(download) }.font(.caption).foregroundStyle(.teal)
                }
                Spacer()
            }
        }.padding(12).glass()
    }
}
