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
            VStack(spacing: 0) {
                if vault.isUnlocked {
                    unlockedView
                } else {
                    lockedView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("보관함").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if vault.isUnlocked {
                        Button { vault.lock() } label: { Image(systemName: "lock.fill").foregroundStyle(.red) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .onAppear { if vault.isUnlocked { Task { await vault.reload() } } }
            .alert("삭제", isPresented: $showDeleteAlert) {
                Button("삭제", role: .destructive) { if let i = deleteTarget { Task { try? await vault.delete(item: i) } } }
                Button("취소", role: .cancel) {}
            } message: { Text("이 파일을 삭제하시겠습니까?") }
            .alert("오류", isPresented: $showError) { Button("확인") {} } message: { Text(errorMessage ?? "") }
            .fullScreenCover(isPresented: $showPlayer) {
                ZStack(alignment: .topTrailing) {
                    if let url = playerURL {
                        VideoPlayer(player: AVPlayer(url: url)).ignoresSafeArea()
                    } else {
                        Color.black.ignoresSafeArea()
                        Text("파일을 불러올 수 없습니다").foregroundStyle(.white)
                    }
                    Button { showPlayer = false; playerURL = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white).padding()
                    }
                }.background(Color.black.ignoresSafeArea())
            }
        }
    }

    private var lockedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield.fill").font(.system(size: 50)).foregroundStyle(.purple)
            Text("보관함이 잠겨있습니다").font(.title3.weight(.semibold))
            Text("Face ID 또는 패스코드로 잠금 해제").font(.subheadline).foregroundStyle(.secondary)
            Button {
                Task {
                    do { try await vault.unlock() }
                    catch { errorMessage = error.localizedDescription; showError = true }
                }
            } label: {
                Label("잠금 해제", systemImage: "faceid").font(.headline).foregroundStyle(.white)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(.teal, in: Capsule())
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unlockedView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(filteredItems.count) 파일").font(.subheadline.monospacedDigit()).foregroundStyle(.teal)
                Spacer()
                Text(vault.totalSize).font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal).padding(.vertical, 8)

            Picker("", selection: $selectedFilter) {
                Text("전체").tag(0); Text("영상").tag(1); Text("GIF").tag(2); Text("기타").tag(3)
            }.pickerStyle(.segmented).padding(.horizontal)

            ScrollView {
                if filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(.secondary)
                        Text("비어있습니다").font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(filteredItems) { item in cell(item) }
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
                    await MainActor.run { playerURL = url; showPlayer = true }
                } catch {
                    await MainActor.run { errorMessage = error.localizedDescription; showError = true }
                }
            }
        } label: {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 90)
                    .overlay { Image(systemName: item.icon).font(.title3).foregroundStyle(.teal) }
                VStack(spacing: 2) {
                    Text(item.originalName).font(.caption2).lineLimit(1)
                    Text(item.formattedSize).font(.caption2).foregroundStyle(.secondary)
                }.padding(4)
            }
            .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { deleteTarget = item; showDeleteAlert = true } label: { Label("삭제", systemImage: "trash") }
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
