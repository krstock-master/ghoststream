// Media/MediaDownloadManager.swift
// GhostStream - Multi-format media download engine

import Foundation
import AVFoundation
import SwiftUI

@Observable
final class MediaDownloadManager: NSObject, @unchecked Sendable {
    var downloads: [MediaDownload] = []
    var completedDownloads: [MediaDownload] = []

    private let vaultManager: VaultManager
    private var urlSession: URLSession?
    private var taskMap: [Int: String] = [:]
    private var hlsTaskMap: [UUID: Task<Void, Never>] = [:]

    // Injected from BrowserWebView when a download starts (cookie forwarding)
    var cookieStorage: HTTPCookieStorage = .shared

    init(vaultManager: VaultManager) {
        self.vaultManager = vaultManager
        super.init()

        // Foreground session — sideloaded apps cannot use background sessions
        // (background entitlements are stripped by Sideloadly/TrollStore)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    // MARK: - Download API

    func download(media: DetectedMedia, saveToVault: Bool = true) {
        let dl = MediaDownload(media: media, saveToVault: saveToVault)
        downloads.insert(dl, at: 0)

        switch media.type {
        case .hls:
            startHLSDownload(dl)
        case .mp4, .webm:
            startDirectDownload(dl)
        case .gif:
            startDirectDownload(dl)
        case .blob:
            // Already saved locally, just move to vault
            dl.state = .completed
            dl.progress = 1.0
            dl.localURL = media.url
            if saveToVault {
                Task { await moveToVault(dl) }
            }
            completedDownloads.insert(dl, at: 0)
        }
    }

    func pause(_ dl: MediaDownload) {
        guard let taskID = dl.sessionTaskID else { return }
        urlSession?.getAllTasks { tasks in
            tasks.first { $0.taskIdentifier == taskID }?.suspend()
        }
        dl.state = .paused
    }

    func resume(_ dl: MediaDownload) {
        guard let taskID = dl.sessionTaskID else { return }
        urlSession?.getAllTasks { tasks in
            tasks.first { $0.taskIdentifier == taskID }?.resume()
        }
        dl.state = .downloading
    }

    func cancel(_ dl: MediaDownload) {
        guard let taskID = dl.sessionTaskID else { return }
        urlSession?.getAllTasks { tasks in
            tasks.first { $0.taskIdentifier == taskID }?.cancel()
        }
        dl.state = .cancelled
        downloads.removeAll { $0.id == dl.id }
    }

    func retry(_ dl: MediaDownload) {
        downloads.removeAll { $0.id == dl.id }
        download(media: dl.media, saveToVault: dl.saveToVault)
    }

    // MARK: - Direct Download (MP4/GIF)

    private func startDirectDownload(_ dl: MediaDownload) {
        var request = URLRequest(url: dl.media.url)
        request.setValue(dl.media.referer, forHTTPHeaderField: "Referer")
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        // Forward cookies from WKWebView session
        if let cookies = cookieStorage.cookies(for: dl.media.url), !cookies.isEmpty {
            let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let task = urlSession?.downloadTask(with: request)
        dl.sessionTaskID = task?.taskIdentifier
        dl.state = .downloading
        if let t = task {
            taskMap[t.taskIdentifier] = dl.id.uuidString
            t.resume()
        }
    }

    // MARK: - HLS Download (Foreground Custom Parser)

    private func startHLSDownload(_ dl: MediaDownload) {
        dl.state = .downloading

        let hlsTask = Task {
            do {
                let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

                // Step 1: Download the m3u8 playlist
                var request = URLRequest(url: dl.media.url)
                request.setValue(ua, forHTTPHeaderField: "User-Agent")
                request.setValue(dl.media.referer, forHTTPHeaderField: "Referer")
                if let cookies = cookieStorage.cookies(for: dl.media.url), !cookies.isEmpty {
                    request.setValue(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
                }

                guard let session = urlSession else {
                    dl.state = .failed; dl.error = "URLSession 없음"; return
                }

                let (data, _) = try await session.data(for: request)
                guard let playlist = String(data: data, encoding: .utf8) else {
                    dl.state = .failed; dl.error = "m3u8 파싱 실패"; return
                }

                // Step 2: If master playlist, find best quality media playlist
                var mediaPlaylistURL = dl.media.url
                if playlist.contains("#EXT-X-STREAM-INF") {
                    if let bestURL = parseMasterPlaylist(playlist, baseURL: dl.media.url) {
                        mediaPlaylistURL = bestURL
                        // Re-download media playlist
                        var mediaReq = URLRequest(url: mediaPlaylistURL)
                        mediaReq.setValue(ua, forHTTPHeaderField: "User-Agent")
                        mediaReq.setValue(dl.media.referer, forHTTPHeaderField: "Referer")
                        if let cookies = cookieStorage.cookies(for: mediaPlaylistURL), !cookies.isEmpty {
                            mediaReq.setValue(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
                        }
                        let (mediaData, _) = try await session.data(for: mediaReq)
                        guard let mediaPlaylist = String(data: mediaData, encoding: .utf8) else {
                            dl.state = .failed; dl.error = "미디어 플레이리스트 파싱 실패"; return
                        }
                        try await downloadTSSegments(mediaPlaylist, baseURL: mediaPlaylistURL, dl: dl, ua: ua)
                    } else {
                        dl.state = .failed; dl.error = "마스터 플레이리스트에서 미디어 URL 추출 실패"; return
                    }
                } else if playlist.contains("#EXTINF") {
                    // Already a media playlist
                    try await downloadTSSegments(playlist, baseURL: mediaPlaylistURL, dl: dl, ua: ua)
                } else {
                    // Not a valid m3u8 — try as direct download fallback
                    startDirectDownload(dl)
                    return
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        dl.state = .failed
                        dl.error = "HLS 다운로드 실패: \(error.localizedDescription)"
                    }
                }
            }
        }
        hlsTaskMap[dl.id] = hlsTask
    }

    private func parseMasterPlaylist(_ playlist: String, baseURL: URL) -> URL? {
        let lines = playlist.components(separatedBy: .newlines)
        var bestBandwidth = 0
        var bestURI: String?

        for i in 0..<lines.count {
            let line = lines[i]
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                // Parse BANDWIDTH
                if let bwRange = line.range(of: "BANDWIDTH="),
                   let bwEnd = line[bwRange.upperBound...].firstIndex(where: { $0 == "," || $0 == "\n" || $0 == "\r" }) {
                    let bwStr = String(line[bwRange.upperBound..<bwEnd])
                    let bw = Int(bwStr) ?? 0
                    if bw > bestBandwidth {
                        bestBandwidth = bw
                        // Next non-comment line is the URI
                        if i + 1 < lines.count {
                            let uri = lines[i + 1].trimmingCharacters(in: .whitespaces)
                            if !uri.isEmpty && !uri.hasPrefix("#") {
                                bestURI = uri
                            }
                        }
                    }
                } else if i + 1 < lines.count {
                    // No bandwidth, just use first stream
                    let uri = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if !uri.isEmpty && !uri.hasPrefix("#") && bestURI == nil {
                        bestURI = uri
                    }
                }
            }
        }

        guard let uri = bestURI else { return nil }
        if uri.hasPrefix("http") { return URL(string: uri) }
        return URL(string: uri, relativeTo: baseURL)?.absoluteURL
    }

    private func downloadTSSegments(_ playlist: String, baseURL: URL, dl: MediaDownload, ua: String) async throws {
        let lines = playlist.components(separatedBy: .newlines)
        var segmentURLs: [URL] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if let segURL = trimmed.hasPrefix("http") ? URL(string: trimmed) : URL(string: trimmed, relativeTo: baseURL)?.absoluteURL {
                segmentURLs.append(segURL)
            }
        }

        guard !segmentURLs.isEmpty else {
            await MainActor.run { dl.state = .failed; dl.error = "TS 세그먼트를 찾을 수 없습니다" }
            return
        }

        let totalSegments = segmentURLs.count
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("hls_\(dl.id.uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var downloadedFiles: [URL] = []

        // Download segments sequentially (3 concurrent)
        for (index, segURL) in segmentURLs.enumerated() {
            guard !Task.isCancelled else { throw CancellationError() }

            var segReq = URLRequest(url: segURL)
            segReq.setValue(ua, forHTTPHeaderField: "User-Agent")
            segReq.setValue(dl.media.referer, forHTTPHeaderField: "Referer")
            if let cookies = cookieStorage.cookies(for: segURL), !cookies.isEmpty {
                segReq.setValue(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
            }

            let (segData, _) = try await urlSession!.data(for: segReq)
            let segFile = tempDir.appendingPathComponent(String(format: "seg_%05d.ts", index))
            try segData.write(to: segFile)
            downloadedFiles.append(segFile)

            await MainActor.run {
                dl.progress = Double(index + 1) / Double(totalSegments)
                dl.bytesDownloaded = Int64(downloadedFiles.reduce(0) { $0 + (try? Data(contentsOf: $1).count ?? 0) })
            }
        }

        // Merge TS segments into single file
        await MainActor.run { dl.state = .converting }

        let mergedTS = tempDir.appendingPathComponent("merged.ts")
        FileManager.default.createFile(atPath: mergedTS.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: mergedTS)
        for tsFile in downloadedFiles {
            let data = try Data(contentsOf: tsFile)
            fileHandle.write(data)
        }
        fileHandle.closeFile()

        // Export TS → MP4 using AVAssetExportSession
        let safeName = "\(dl.media.title.prefix(40))_\(Int(Date().timeIntervalSince1970))"
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let mp4URL = Self.downloadDirectory.appendingPathComponent("\(safeName).mp4")

        let asset = AVURLAsset(url: mergedTS)
        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preset = presets.contains(AVAssetExportPresetPassthrough) ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality

        if let exportSession = AVAssetExportSession(asset: asset, presetName: preset) {
            if FileManager.default.fileExists(atPath: mp4URL.path) {
                try? FileManager.default.removeItem(at: mp4URL)
            }
            exportSession.outputURL = mp4URL
            exportSession.outputFileType = .mp4
            exportSession.shouldOptimizeForNetworkUse = true

            await exportSession.export()

            if exportSession.status == .completed {
                await MainActor.run {
                    dl.localURL = mp4URL
                    dl.hlsConversionStatus = "MP4 변환 완료"
                    dl.state = .completed
                    dl.progress = 1.0
                    self.downloads.removeAll { $0.id == dl.id }
                    self.completedDownloads.insert(dl, at: 0)
                    NotificationCenter.default.post(name: .downloadCompleted, object: dl.media.title)
                }
            } else {
                // Fallback: keep merged TS as playable file
                let tsDestURL = Self.downloadDirectory.appendingPathComponent("\(safeName).ts")
                try? FileManager.default.moveItem(at: mergedTS, to: tsDestURL)
                await MainActor.run {
                    dl.localURL = tsDestURL
                    dl.hlsConversionStatus = "TS 저장 (변환 실패)"
                    dl.state = .completed
                    dl.progress = 1.0
                    self.downloads.removeAll { $0.id == dl.id }
                    self.completedDownloads.insert(dl, at: 0)
                    NotificationCenter.default.post(name: .downloadCompleted, object: dl.media.title)
                }
            }
        } else {
            // No export session — keep TS
            let tsDestURL = Self.downloadDirectory.appendingPathComponent("\(safeName).ts")
            try? FileManager.default.moveItem(at: mergedTS, to: tsDestURL)
            await MainActor.run {
                dl.localURL = tsDestURL
                dl.state = .completed
                dl.progress = 1.0
                self.downloads.removeAll { $0.id == dl.id }
                self.completedDownloads.insert(dl, at: 0)
            }
        }

        // Cleanup temp dir
        try? FileManager.default.removeItem(at: tempDir)

        if dl.saveToVault { Task { await moveToVault(dl) } }
    }

    // MARK: - Post-Download

    private func moveToVault(_ dl: MediaDownload) async {
        guard let url = dl.localURL else { return }
        do {
            try await vaultManager.store(fileURL: url, originalName: dl.media.title)
            // Keep original file so user can still play from Downloads
            // File will be in both Downloads (playable) and Vault (encrypted)
        } catch {
            dl.error = "Vault 저장 실패: \(error.localizedDescription)"
        }
    }

    private func find(byTaskID id: Int) -> MediaDownload? {
        guard let dlID = taskMap[id] else { return nil }
        return downloads.first { $0.id.uuidString == dlID }
    }

    // MARK: - File Locations

    static var downloadDirectory: URL {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("Downloads")
        }
        let dir = documentsDir.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - URLSessionDownloadDelegate
extension MediaDownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let dl = find(byTaskID: downloadTask.taskIdentifier) else { return }

        let ext = dl.media.type == .gif ? "gif" : "mp4"
        let fileName = "\(dl.media.title.prefix(50))_\(Int(Date().timeIntervalSince1970)).\(ext)"
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let dest = Self.downloadDirectory.appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            dl.localURL = dest
            dl.state = .completed
            dl.progress = 1.0
            downloads.removeAll { $0.id == dl.id }
            completedDownloads.insert(dl, at: 0)
            NotificationCenter.default.post(name: .downloadCompleted, object: dl.media.title)
            if dl.saveToVault { Task { await moveToVault(dl) } }
        } catch {
            dl.state = .failed
            dl.error = error.localizedDescription
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let dl = find(byTaskID: downloadTask.taskIdentifier) else { return }
        dl.bytesDownloaded = totalBytesWritten
        dl.totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 0
        dl.progress = dl.totalBytes > 0 ? Double(totalBytesWritten) / Double(dl.totalBytes) : 0
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error = error, let dl = find(byTaskID: task.taskIdentifier) else { return }
        if (error as NSError).code != NSURLErrorCancelled {
            dl.state = .failed
            dl.error = error.localizedDescription
        }
    }
}

// MARK: - URLSession Auth Challenge
extension MediaDownloadManager {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Accept all certificates for sideloaded app (no cert pinning in URLSession)
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - Download Model
@Observable
final class MediaDownload: Identifiable, @unchecked Sendable {
    let id = UUID()
    let media: DetectedMedia
    let saveToVault: Bool
    var state: DownloadState = .pending
    var progress: Double = 0
    var bytesDownloaded: Int64 = 0
    var totalBytes: Int64 = 0
    var localURL: URL?
    var error: String?
    var sessionTaskID: Int?
    let startDate = Date()

    init(media: DetectedMedia, saveToVault: Bool) {
        self.media = media
        self.saveToVault = saveToVault
    }

    var hlsConversionStatus: String?

    var formattedProgress: String {
        if state == .converting { return "변환 중..." }
        return "\(Int(progress * 100))%"
    }
    var formattedSpeed: String {
        let elapsed = Date.now.timeIntervalSince(startDate)
        guard elapsed > 0, bytesDownloaded > 0 else { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(Double(bytesDownloaded) / elapsed), countStyle: .file) + "/s"
    }

    enum DownloadState: String {
        case pending, downloading, paused, converting, completed, failed, cancelled
    }
}
