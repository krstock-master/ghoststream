// UI/Components/BookmarkHistoryView.swift
// GhostStream v1.0 — 북마크 & 방문 기록 UI
import SwiftUI

struct BookmarkHistoryView: View {
    @Environment(BookmarkManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var showAddFolder = false
    @State private var newFolderName = ""
    @State private var showClearHistoryAlert = false
    let onNavigate: (URL) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("북마크").tag(0)
                    Text("방문 기록").tag(1)
                }.pickerStyle(.segmented).padding()

                if selectedTab == 0 { bookmarksTab } else { historyTab }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(selectedTab == 0 ? "북마크" : "방문 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
                if selectedTab == 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showAddFolder = true } label: {
                            Image(systemName: "folder.badge.plus").foregroundStyle(.teal)
                        }
                    }
                }
            }
            .alert("새 폴더", isPresented: $showAddFolder) {
                TextField("폴더 이름", text: $newFolderName)
                Button("생성") {
                    if !newFolderName.isEmpty {
                        manager.addFolder(name: newFolderName)
                        newFolderName = ""
                    }
                }
                Button("취소", role: .cancel) { newFolderName = "" }
            }
            .alert("방문 기록 삭제", isPresented: $showClearHistoryAlert) {
                Button("전체 삭제", role: .destructive) { manager.clearHistory() }
                Button("취소", role: .cancel) {}
            } message: { Text("모든 방문 기록이 삭제됩니다.") }
        }
    }

    // MARK: - Bookmarks Tab
    @ViewBuilder
    private var bookmarksTab: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Folders
                if !manager.folders.isEmpty {
                    ForEach(manager.folders) { folder in
                        DisclosureGroup {
                            ForEach(manager.bookmarks(in: folder)) { bm in
                                bookmarkRow(bm)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.fill").foregroundStyle(.teal)
                                Text(folder.name).font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(manager.bookmarks(in: folder).count)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contextMenu {
                            Button(role: .destructive) { manager.removeFolder(folder) } label: {
                                Label("폴더 삭제", systemImage: "trash")
                            }
                        }
                    }
                }

                // Root bookmarks (no folder)
                ForEach(manager.bookmarks(in: nil)) { bm in
                    bookmarkRow(bm)
                }

                if manager.bookmarks.isEmpty {
                    emptyState("북마크 없음", icon: "bookmark", desc: "페이지를 북마크하면 여기에 표시됩니다")
                }
            }.padding(.horizontal)
        }
    }

    private func bookmarkRow(_ bm: Bookmark) -> some View {
        Button {
            onNavigate(bm.url)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bookmark.fill").foregroundStyle(.teal).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bm.title).font(.subheadline).lineLimit(1).foregroundStyle(.primary)
                    Text(bm.url.host ?? bm.url.absoluteString)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .contextMenu {
            Button { UIPasteboard.general.url = bm.url } label: {
                Label("URL 복사", systemImage: "doc.on.doc")
            }
            ShareLink(item: bm.url) { Label("공유", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) { manager.removeBookmark(bm) } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    // MARK: - History Tab
    @ViewBuilder
    private var historyTab: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if manager.history.isEmpty {
                    emptyState("방문 기록 없음", icon: "clock", desc: "웹 페이지를 방문하면 여기에 기록됩니다")
                } else {
                    // 날짜별 그룹
                    ForEach(manager.historyGroupedByDate(), id: \.0) { dateStr, entries in
                        Section {
                            ForEach(entries) { entry in
                                Button {
                                    onNavigate(entry.url)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock").foregroundStyle(.secondary).frame(width: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.title).font(.subheadline).lineLimit(1).foregroundStyle(.primary)
                                            Text(entry.url.host ?? "")
                                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Text(entry.visitDate.formatted(date: .omitted, time: .shortened))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        } header: {
                            Text(dateStr).font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        }
                    }

                    // 전체 삭제 버튼
                    Button(role: .destructive) { showClearHistoryAlert = true } label: {
                        Label("방문 기록 전체 삭제", systemImage: "trash")
                            .font(.subheadline).foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }.padding(.top, 8)
                }
            }.padding(.horizontal)
        }
    }

    private func emptyState(_ text: String, icon: String, desc: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(.secondary)
            Text(text).font(.headline).foregroundStyle(.secondary)
            Text(desc).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.top, 60)
    }
}
