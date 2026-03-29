// UI/Vault/VaultView.swift
import SwiftUI
import AVKit

struct VaultView: View {
    @Environment(VaultManager.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter = 0
    @State private var deleteTarget: VaultItem?
    @State private var showDeleteAlert = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var playerURL: URL?
    @State private var showPlayer = false

    var body: some View {
        NavigationStack {
            Group {
                if vault.isUnlocked { unlockedView } else { lockedView }
            }
            .background(GhostTheme.bg)
            .navigationTitle("보관함").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if vault.isUnlocked {
                            Button { vault.lock() } label: {
                                Image(systemName: "lock.fill").foregroundStyle(GhostTheme.danger)
                            }
                        }
                        Button("닫기") { dismiss() }.foregroundStyle(GhostTheme.accent)
                    }
                }
            }
            .alert("삭제", isPresented: $showDeleteAlert) {
                Button("삭제", role: .destructive) {
                    guard let item = deleteTarget else { return }
                    Task { try? await vault.delete(item: item) }
                }
                Button("취소", role: .cancel) {}
            } message: { Text("이 파일을 삭제하시겠습니까?") }
            .alert("오류", isPresented: $showError) { Button("확인") {} } message: { Text(errorMessage ?? "") }
            .fullScreenCover(isPresented: $showPlayer) {
                if let url = playerURL {
                    ZStack(alignment: .topTrailing) {
                        VideoPlayer(player: AVPlayer(url: url))
                            .ignoresSafeArea()
                        Button { showPlayer = false } label: {
                            Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white)
                                .padding()
                        }
                    }.background(Color.black)
                }
            }
        }
    }

    private var lockedView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield.fill").font(.system(size: 60)).foregroundStyle(GhostTheme.accentAlt)
            Text("보관함이 잠겨있습니다").font(.title3.bold()).foregroundStyle(.white)
            Text("Face ID 또는 패스코드로 잠금 해제").font(.subheadline).foregroundStyle(Color.gray)
            Button {
                Task {
                    do { try await vault.unlock() }
                    catch { errorMessage = error.localizedDescription; showError = true }
                }
            } label: {
                Label("잠금 해제", systemImage: "faceid").font(.headline).foregroundStyle(.black)
                    .padding(.horizontal, 32).padding(.vertical, 14)
                    .background(GhostTheme.accent, in: Capsule())
            }
            Spacer()
        }
    }

    private var unlockedView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(filteredItems.count) 파일").font(.subheadline.monospacedDigit()).foregroundStyle(GhostTheme.accent)
                Spacer()
                Text(vault.totalSize).font(.caption).foregroundStyle(Color.gray)
            }.padding(.horizontal).padding(.vertical, 8)

            Picker("", selection: $selectedFilter) {
                Text("전체 \(vault.items.count)").tag(0)
                Text("영상").tag(1)
                Text("GIF").tag(2)
                Text("기타").tag(3)
            }.pickerStyle(.segmented).padding(.horizontal)

            ScrollView {
                if filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(Color.gray)
                        Text("비어있습니다").font(.subheadline).foregroundStyle(Color.gray)
                    }.padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(filteredItems) { item in
                            cell(item)
                        }
                    }.padding()
                }
            }
        }
    }

    private func cell(_ item: VaultItem) -> some View {
        Button {
            Task {
                do {
                    let url = try await vault.decrypt(item: item)
                    if item.mediaType == .video {
                        playerURL = url
                        showPlayer = true
                    }
                } catch {
                    errorMessage = "파일 열기 실패: \(error.localizedDescription)"
                    showError = true
                }
            }
        } label: {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(item.mediaType == .video ? GhostTheme.accent.opacity(0.08) : GhostTheme.accentAlt.opacity(0.08))
                    .frame(height: 100)
                    .overlay {
                        Image(systemName: item.icon).font(.title2)
                            .foregroundStyle(item.mediaType == .video ? GhostTheme.accent : GhostTheme.accentAlt)
                    }
                VStack(spacing: 2) {
                    Text(item.originalName).font(.caption2).foregroundStyle(.white).lineLimit(1)
                    Text(item.formattedSize).font(.caption2).foregroundStyle(Color.gray)
                }.padding(4)
            }
            .glass(10)
        }
        .contextMenu {
            Button(role: .destructive) { deleteTarget = item; showDeleteAlert = true } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    private var filteredItems: [VaultItem] {
        switch selectedFilter {
        case 1: return vault.items.filter { $0.mediaType == .video }
        case 2: return vault.items.filter { $0.mediaType == .gif }
        case 3: return vault.items.filter { $0.mediaType == .other }
        default: return vault.items
        }
    }
}
