// Browser/BookmarkManager.swift
// GhostStream v1.0 — 북마크 + 방문 기록 (UserDefaults 기반, SwiftData 불필요)
import Foundation
import SwiftUI

// MARK: - Models

struct Bookmark: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var url: URL
    var favicon: String? // SF Symbol name
    var dateAdded: Date
    var folderID: UUID?

    init(title: String, url: URL, favicon: String? = nil, folderID: UUID? = nil) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.favicon = favicon
        self.dateAdded = .now
        self.folderID = folderID
    }
}

struct BookmarkFolder: Identifiable, Codable {
    let id: UUID
    var name: String
    var dateCreated: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.dateCreated = .now
    }
}

struct HistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var url: URL
    var visitDate: Date

    init(title: String, url: URL) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.visitDate = .now
    }
}

// MARK: - Manager

@Observable
final class BookmarkManager: @unchecked Sendable {
    var bookmarks: [Bookmark] = []
    var folders: [BookmarkFolder] = []
    var history: [HistoryEntry] = []

    private let bookmarksKey = "gs_bookmarks"
    private let foldersKey = "gs_bookmark_folders"
    private let historyKey = "gs_history"

    init() {
        loadBookmarks()
        loadFolders()
        loadHistory()
    }

    // MARK: - Bookmarks

    func addBookmark(title: String, url: URL, folderID: UUID? = nil) {
        guard !bookmarks.contains(where: { $0.url == url }) else { return }
        let bm = Bookmark(title: title, url: url, folderID: folderID)
        bookmarks.insert(bm, at: 0)
        saveBookmarks()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }

    func isBookmarked(url: URL) -> Bool {
        bookmarks.contains { $0.url == url }
    }

    func toggleBookmark(title: String, url: URL) {
        if let existing = bookmarks.first(where: { $0.url == url }) {
            removeBookmark(existing)
        } else {
            addBookmark(title: title, url: url)
        }
    }

    func bookmarks(in folder: BookmarkFolder?) -> [Bookmark] {
        bookmarks.filter { $0.folderID == folder?.id }
    }

    // MARK: - Folders

    func addFolder(name: String) {
        let folder = BookmarkFolder(name: name)
        folders.append(folder)
        saveFolders()
    }

    func removeFolder(_ folder: BookmarkFolder) {
        // 폴더 내 북마크를 루트로 이동
        for i in bookmarks.indices where bookmarks[i].folderID == folder.id {
            bookmarks[i].folderID = nil
        }
        folders.removeAll { $0.id == folder.id }
        saveFolders()
        saveBookmarks()
    }

    // MARK: - History

    func addHistory(title: String, url: URL) {
        // 같은 URL은 최신으로 갱신
        history.removeAll { $0.url == url }
        let entry = HistoryEntry(title: title, url: url)
        history.insert(entry, at: 0)
        // 최대 500건 유지
        if history.count > 500 { history = Array(history.prefix(500)) }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func historyForToday() -> [HistoryEntry] {
        let calendar = Calendar.current
        return history.filter { calendar.isDateInToday($0.visitDate) }
    }

    func historyGroupedByDate() -> [(String, [HistoryEntry])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let grouped = Dictionary(grouping: history) { entry in
            formatter.string(from: entry.visitDate)
        }
        return grouped.sorted { lhs, rhs in
            (lhs.value.first?.visitDate ?? .distantPast) > (rhs.value.first?.visitDate ?? .distantPast)
        }
    }

    // MARK: - Persistence

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }

    private func loadBookmarks() {
        if let data = UserDefaults.standard.data(forKey: bookmarksKey),
           let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = decoded
        }
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: foldersKey)
        }
    }

    private func loadFolders() {
        if let data = UserDefaults.standard.data(forKey: foldersKey),
           let decoded = try? JSONDecoder().decode([BookmarkFolder].self, from: data) {
            folders = decoded
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            history = decoded
        }
    }
}
