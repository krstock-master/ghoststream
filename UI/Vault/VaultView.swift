// UI/Vault/VaultView.swift
// GhostStream - Encrypted media vault with biometric auth

import SwiftUI
import AVKit

struct VaultView: View {
    @Environment(VaultManager.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: VaultFilter = .all
    @State private var searchText = ""
    @State private var selectedItem: VaultItem?
    @State private var playingURL: URL?
    @State private var showDeleteAlert = false
    @State private var deleteTarget: VaultItem?
    @State private var errorMessage: String?
    @State private var showError = false

    enum VaultFilter: String, CaseIterable {
        case all = "전체"
        case video = "영상"
        case gif = "GIF"
        case other = "기타"
    }

    var body: some View {
        NavigationStack {
            Group {
                if vault.isUnlocked {
                    unlockedContent
                } else {
                    lockedContent
                }
            }
            .background(GhostTheme.bg)
            .navigationTitle("🔒 보관함")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if vault.isUnlocked {
                            Button { vault.lock() } label: {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(GhostTheme.danger)
                            }
                        }
                        Button("닫기") { dismiss() }
                            .foregroundStyle(GhostTheme.accent)
                    }
                }
            }
            .alert("삭제", isPresented: $showDeleteAlert) {
                Button("삭제", role: .destructive) {
                    if let item = deleteTarget {
                        Task {
                            try? await vault.delete(item: item)
                        }
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("이 파일을 영구적으로 삭제하시겠습니까?")
            }
            .alert("오류", isPresented: $showError) {
                Button("확인") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .fullScreenCover(item: $playingURL) { url in
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Locked State
    private var lockedContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(GhostTheme.accentAlt)

            Text("보관함이 잠겨있습니다")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text("Face ID 또는 패스코드로 잠금 해제")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    do {
                        try await vault.unlock()
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            } label: {
                Label("잠금 해제", systemImage: "faceid")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(GhostTheme.accent, in: Capsule())
            }
            .a11yButton("Face ID로 보관함 잠금 해제", hint: "Face ID 또는 패스코드로 인증합니다")

            Spacer()
        }
    }

    // MARK: - Unlocked Content
    private var unlockedContent: some View {
        VStack(spacing: 0) {
            // Stats bar
            HStack {
                Text("\(filteredItems.count) 파일")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(GhostTheme.accent)
                Spacer()
                Text(vault.totalSize)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Filter tabs
            Picker("", selection: $selectedFilter) {
                ForEach(VaultFilter.allCases, id: \.self) { f in
                    Text("\(f.rawValue) \(countFor(f))").tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // File grid
            ScrollView {
                if filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("보관함이 비어있습니다")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(filteredItems) { item in
                            vaultCell(item)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func vaultCell(_ item: VaultItem) -> some View {
        Button {
            Task {
                do {
                    let url = try await vault.decrypt(item: item)
                    if item.mediaType == .video {
                        playingURL = url
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.05))
                        .frame(height: 100)
                    Image(systemName: item.icon)
                        .font(.title2)
                        .foregroundStyle(item.mediaType == .video ? GhostTheme.accent : GhostTheme.accentAlt)
                }

                VStack(spacing: 2) {
                    Text(item.originalName)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(item.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(4)
            }
            .glass(10)
        }
        .contextMenu {
            Button { Task { try? await shareItem(item) } } label: { Label("공유", systemImage: "square.and.arrow.up") }
            Button { Task { try? await exportItem(item) } } label: { Label("내보내기", systemImage: "arrow.up.doc") }
            Divider()
            Button(role: .destructive) { deleteTarget = item; showDeleteAlert = true } label: { Label("삭제", systemImage: "trash") }
        }
    }

    // MARK: - Helpers

    private var filteredItems: [VaultItem] {
        switch selectedFilter {
        case .all: return vault.items
        case .video: return vault.items.filter { $0.mediaType == .video }
        case .gif: return vault.items.filter { $0.mediaType == .gif }
        case .other: return vault.items.filter { $0.mediaType == .other }
        }
    }

    private func countFor(_ filter: VaultFilter) -> String {
        "(\(filter == .all ? vault.items.count : vault.items.filter { $0.mediaType.rawValue == filter.rawValue.lowercased() }.count))"
    }

    private func shareItem(_ item: VaultItem) async throws {
        let url = try await vault.export(item: item)
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = windowScene.windows.first?.rootViewController {
            root.present(activityVC, animated: true)
        }
    }

    private func exportItem(_ item: VaultItem) async throws {
        _ = try await vault.export(item: item)
    }
}

// URL conformance for fullScreenCover
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
