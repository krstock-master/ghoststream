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
    private var hlsSession: AVAssetDownloadURLSession?
    private var taskMap: [Int: String] = [:]

    // Injected from BrowserWebView when a download starts (cookie forwarding)
    var cookieStorage: HTTPCookieStorage = .shared

    init(vaultManager: VaultManager) {
        self.vaultManager = vaultManager
        super.init()

        // Standard download session
        let config = URLSessionConfiguration.background(withIdentifier: "com.ghoststream.media.bg")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        // HLS download session
        let hlsConfig = URLSessionConfiguration.background(withIdentifier: "com.ghoststream.hls.bg")
        hlsConfig.isDiscretionary = false
        hlsConfig.sessionSendsLaunchEvents = true
        hlsSession = AVAssetDownloadURLSession(
            configuration: hlsConfig,
            assetDownloadDelegate: self,
            delegateQueue: .main
        )
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

    // MARK: - HLS Download

    private func startHLSDownload(_ dl: MediaDownload) {
        // First try AVAssetDownloadTask (native HLS download → .movpkg → auto-convert to .mp4)
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        var cookieHeader = ""
        if let cookies = cookieStorage.cookies(for: dl.media.url), !cookies.isEmpty {
            cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
        var headers: [String: String] = [
            "Referer": dl.media.referer,
            "User-Agent": ua,
            "Origin": dl.media.referer.isEmpty ? "" : {
                guard let u = URL(string: dl.media.referer), let h = u.host else { return "" }
                return (u.scheme ?? "https") + "://" + h
            }()
        ]
        if !cookieHeader.isEmpty { headers["Cookie"] = cookieHeader }

        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: dl.media.url, options: options)

        let bitrate: Int
        switch dl.media.quality {
        case let q where q.contains("1080"): bitrate = 4_000_000
        case let q where q.contains("720"):  bitrate = 2_000_000
        case let q where q.contains("480"):  bitrate = 1_000_000
        default:                              bitrate = 2_500_000
        }

        guard let task = hlsSession?.makeAssetDownloadTask(
            asset: asset,
            assetTitle: "gs_\(Int(Date().timeIntervalSince1970))",
            assetArtworkData: nil,
            options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: bitrate]
        ) else {
            dl.state = .failed
            dl.error = "HLS 세션 생성 실패 – m3u8 URL을 직접 재생해 보세요"
            return
        }

        dl.sessionTaskID = task.taskIdentifier
        dl.state = .downloading
        taskMap[task.taskIdentifier] = dl.id.uuidString
        task.resume()
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

// MARK: - AVAssetDownloadDelegate
extension MediaDownloadManager: AVAssetDownloadDelegate {
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let dl = find(byTaskID: assetDownloadTask.taskIdentifier) else { return }

        // Stage 1: move .movpkg to persistent storage
        let destDir = Self.downloadDirectory
        let safeName = "\(dl.media.title.prefix(40))_\(Int(Date().timeIntervalSince1970))"
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let movpkgDest = destDir.appendingPathComponent("\(safeName).movpkg")

        do {
            if FileManager.default.fileExists(atPath: movpkgDest.path) {
                try FileManager.default.removeItem(at: movpkgDest)
            }
            try FileManager.default.moveItem(at: location, to: movpkgDest)
        } catch {
            // Fallback: use original temp location
            dl.localURL = location
            dl.state = .completed
            dl.progress = 1.0
            DispatchQueue.main.async { self.completedDownloads.insert(dl, at: 0) }
            return
        }

        // Stage 2: export .movpkg → .mp4 (so it's playable & gallery-saveable)
        dl.state = .converting
        exportToMP4(from: movpkgDest, safeName: safeName, dl: dl)
    }

    // MARK: HLS → MP4 export
    private func exportToMP4(from movpkgURL: URL, safeName: String, dl: MediaDownload) {
        let asset = AVURLAsset(url: movpkgURL)
        // Try low-overhead PassThrough first, then HighestQuality
        let preset: String
        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        if presets.contains(AVAssetExportPresetPassthrough) {
            preset = AVAssetExportPresetPassthrough
        } else if presets.contains(AVAssetExportPresetHighestQuality) {
            preset = AVAssetExportPresetHighestQuality
        } else {
            preset = AVAssetExportPresetMediumQuality
        }
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            // AVAssetExportSession unavailable – keep .movpkg as-is
            dl.localURL = movpkgURL
            dl.hlsConversionStatus = "MP4 변환 불가 (movpkg로 저장)"
            dl.state = .completed
            dl.progress = 1.0
            DispatchQueue.main.async { self.completedDownloads.insert(dl, at: 0) }
            return
        }

        let mp4URL = Self.downloadDirectory.appendingPathComponent("\(safeName).mp4")
        if FileManager.default.fileExists(atPath: mp4URL.path) {
            try? FileManager.default.removeItem(at: mp4URL)
        }

        exportSession.outputURL = mp4URL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                if exportSession.status == .completed {
                    try? FileManager.default.removeItem(at: movpkgURL)
                    dl.localURL = mp4URL
                    dl.hlsConversionStatus = "MP4 변환 완료"
                } else {
                    // PassThrough failed for this stream — keep .movpkg (AVPlayer can play it)
                    dl.localURL = movpkgURL
                    dl.hlsConversionStatus = "movpkg 저장됨"
                }
                dl.state = .completed
                dl.progress = 1.0
                // Move from active → completed list
                self.downloads.removeAll { $0.id == dl.id }
                self.completedDownloads.insert(dl, at: 0)
                NotificationCenter.default.post(name: .downloadCompleted, object: dl.media.title)
                if dl.saveToVault { Task { await self.moveToVault(dl) } }
            }
        }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    didLoad timeRange: CMTimeRange,
                    totalTimeRangesLoaded: [NSValue],
                    timeRangeExpectedToLoad: CMTimeRange) {
        guard let dl = find(byTaskID: assetDownloadTask.taskIdentifier) else { return }
        let loaded = totalTimeRangesLoaded.reduce(0.0) {
            $0 + CMTimeGetSeconds($1.timeRangeValue.duration)
        }
        let expected = CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
        dl.progress = expected > 0 ? loaded / expected : 0
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
