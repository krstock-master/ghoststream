// Media/MediaDownloadManager.swift
// GhostStream - Multi-format media download engine

import Foundation
import AVFoundation
import SwiftUI
import WebKit

@Observable
final class MediaDownloadManager: NSObject, @unchecked Sendable {
    var downloads: [MediaDownload] = []
    var completedDownloads: [MediaDownload] = []

    // ★ 다운로드 큐 (동시 3개 제한)
    private var pendingQueue: [(DetectedMedia, Bool, [HTTPCookie]?)] = []
    private let maxConcurrent = 3

    private let vaultManager: VaultManager
    var urlSession: URLSession?
    private var taskMap: [Int: String] = [:]
    private var hlsTaskMap: [UUID: Task<Void, Never>] = [:]

    // Injected from BrowserWebView when a download starts (cookie forwarding)
    var cookieStorage: HTTPCookieStorage = .shared

    init(vaultManager: VaultManager) {
        self.vaultManager = vaultManager
        super.init()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        // ★ Enable cookie storage on the session itself
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    // ★ 활성 다운로드 수
    private var activeCount: Int {
        downloads.filter { $0.state == .downloading || $0.state == .converting }.count
    }

    // ★ 큐에서 대기 중인 다운로드 시작
    private func processQueue() {
        while activeCount < maxConcurrent && !pendingQueue.isEmpty {
            let (media, saveToVault, cookies) = pendingQueue.removeFirst()
            if let cookies = cookies {
                downloadWithCookiesInternal(media: media, cookies: cookies, saveToVault: saveToVault)
            } else {
                downloadInternal(media: media, saveToVault: saveToVault)
            }
        }
    }

    // MARK: - Download API

    func download(media: DetectedMedia, saveToVault: Bool = true) {
        if activeCount >= maxConcurrent {
            pendingQueue.append((media, saveToVault, nil))
            NotificationCenter.default.post(name: .downloadCompleted,
                object: "⏳ 대기열에 추가됨 (\(pendingQueue.count)번째)")
            return
        }
        downloadInternal(media: media, saveToVault: saveToVault)
    }

    private func downloadInternal(media: DetectedMedia, saveToVault: Bool) {
        let dl = MediaDownload(media: media, saveToVault: saveToVault)
        downloads.insert(dl, at: 0)

        switch media.type {
        case .hls:
            startHLSDownload(dl)
        case .mp4, .webm, .image:
            startDirectDownload(dl)
        case .gif:
            startDirectDownload(dl)
        case .blob:
            dl.state = .completed
            dl.progress = 1.0
            dl.localURL = media.url
            if saveToVault {
                Task { await moveToVault(dl) }
            }
            completedDownloads.insert(dl, at: 0); processQueue()
        }
    }

    // ★ Download with cookies pre-loaded (called from WebViewCoordinator)
    func downloadWithCookies(media: DetectedMedia, cookies: [HTTPCookie], saveToVault: Bool = false) {
        if activeCount >= maxConcurrent {
            pendingQueue.append((media, saveToVault, cookies))
            NotificationCenter.default.post(name: .downloadCompleted,
                object: "⏳ 대기열에 추가됨 (\(pendingQueue.count)번째)")
            return
        }
        downloadWithCookiesInternal(media: media, cookies: cookies, saveToVault: saveToVault)
    }

    private func downloadWithCookiesInternal(media: DetectedMedia, cookies: [HTTPCookie], saveToVault: Bool) {
        let storage = HTTPCookieStorage.shared
        cookies.forEach { storage.setCookie($0) }
        self.cookieStorage = storage
        downloadInternal(media: media, saveToVault: saveToVault)
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

    // MARK: - Direct Download (MP4/GIF) — 3가지 방안

    private func startDirectDownload(_ dl: MediaDownload) {
        if dl.media.url.scheme == "blob" {
            dl.state = .failed
            dl.error = "blob: URL은 직접 다운로드 불가"
            return
        }

        // ★ Build request with ALL necessary headers + cookies
        var request = URLRequest(url: dl.media.url)
        request.setValue(dl.media.referer, forHTTPHeaderField: "Referer")
        if let refURL = URL(string: dl.media.referer), let host = refURL.host {
            request.setValue("\(refURL.scheme ?? "https")://\(host)", forHTTPHeaderField: "Origin")
        }
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        // ★★★ CRITICAL: Get cookies from ALL sources and set on request ★★★
        var allCookies: [HTTPCookie] = []
        // Source 1: Shared cookie storage (synced from WKWebView)
        if let cookies = cookieStorage.cookies(for: dl.media.url) {
            allCookies.append(contentsOf: cookies)
        }
        // Source 2: HTTPCookieStorage.shared (may differ from cookieStorage)
        if let cookies = HTTPCookieStorage.shared.cookies(for: dl.media.url) {
            for c in cookies where !allCookies.contains(where: { $0.name == c.name && $0.domain == c.domain }) {
                allCookies.append(c)
            }
        }
        // Set cookies directly on request header
        if !allCookies.isEmpty {
            let cookieHeader = allCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        // Also set via HTTPCookieStorage for URLSession automatic handling
        urlSession?.configuration.httpCookieStorage?.setCookies(allCookies, for: dl.media.url, mainDocumentURL: nil)

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
                dl.bytesDownloaded = Int64(downloadedFiles.reduce(0) { $0 + ((try? Data(contentsOf: $1))?.count ?? 0) })
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
                    self.completedDownloads.insert(dl, at: 0); self.processQueue()
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
                    self.completedDownloads.insert(dl, at: 0); self.processQueue()
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
                self.completedDownloads.insert(dl, at: 0); self.processQueue()
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

        // ★ Validate HTTP response
        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            if statusCode < 200 || statusCode >= 400 {
                dl.state = .failed
                dl.error = "서버 응답 오류: HTTP \(statusCode)"
                return
            }

            // Check content-type — reject HTML responses
            let contentType = httpResponse.mimeType?.lowercased() ?? ""
            if contentType.contains("text/html") || contentType.contains("application/json") {
                dl.state = .failed
                dl.error = "다운로드 실패: 서버가 영상 대신 웹페이지를 반환했습니다 (인증 또는 접근 제한)"
                return
            }
        }

        // ★ Validate file size (< 1KB is likely an error)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int) ?? 0
        if fileSize < 1024 {
            dl.state = .failed
            dl.error = "다운로드 실패: 파일 크기가 너무 작습니다 (\(fileSize)B) — URL이 만료되었거나 접근이 차단되었을 수 있습니다"
            return
        }

        // ★ Determine proper file extension from Content-Type + URL
        let ext: String
        if dl.media.type == .gif {
            ext = "gif"
        } else if let mime = (downloadTask.response as? HTTPURLResponse)?.mimeType?.lowercased() {
            switch mime {
            case let m where m.contains("mp4"): ext = "mp4"
            case let m where m.contains("webm"): ext = "webm"
            case let m where m.contains("quicktime") || m.contains("mov"): ext = "mov"
            case let m where m.contains("mpeg"): ext = "mp4"
            case let m where m.contains("gif"): ext = "gif"
            case let m where m.contains("png"): ext = "png"
            case let m where m.contains("jpeg") || m.contains("jpg"): ext = "jpg"
            case let m where m.contains("webp"): ext = "webp"
            case let m where m.contains("octet-stream"):
                // Use URL extension as fallback
                let urlExt = dl.media.url.pathExtension.lowercased()
                ext = ["mp4","webm","mov","gif","png","jpg","jpeg","webp","m4v"].contains(urlExt) ? urlExt : "mp4"
            default:
                let urlExt = dl.media.url.pathExtension.lowercased()
                ext = urlExt.isEmpty ? "mp4" : urlExt
            }
        } else {
            let urlExt = dl.media.url.pathExtension.lowercased()
            ext = urlExt.isEmpty ? "mp4" : urlExt
        }

        // ★ Use Content-Disposition filename if available, otherwise generate
        var fileName: String
        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition"),
           let nameRange = disposition.range(of: "filename=") {
            var name = String(disposition[nameRange.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            if let semiRange = name.range(of: ";") { name = String(name[..<semiRange.lowerBound]) }
            fileName = name
        } else {
            fileName = "\(dl.media.title.prefix(50))_\(Int(Date().timeIntervalSince1970)).\(ext)"
        }
        fileName = fileName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "_")

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
            completedDownloads.insert(dl, at: 0); processQueue()
            NotificationCenter.default.post(name: .downloadCompleted, object: "\(dl.media.title) 다운로드 완료 (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)))")
            if dl.saveToVault { Task { await moveToVault(dl) } }
        } catch {
            dl.state = .failed
            dl.error = "파일 저장 실패: \(error.localizedDescription)"
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
            let nsError = error as NSError
            switch nsError.code {
            case NSURLErrorTimedOut: dl.error = "다운로드 시간 초과 — 네트워크 상태를 확인하세요"
            case NSURLErrorNotConnectedToInternet: dl.error = "인터넷 연결 없음"
            case NSURLErrorNetworkConnectionLost: dl.error = "네트워크 연결 끊김 — 재시도하세요"
            case NSURLErrorSecureConnectionFailed: dl.error = "보안 연결 실패 (SSL)"
            default: dl.error = "다운로드 오류: \(error.localizedDescription)"
            }
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
