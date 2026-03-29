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
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

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
        let headers: [String: String] = [
            "Referer": dl.media.referer,
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"
        ]

        let asset = AVURLAsset(
            url: dl.media.url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )

        // Select bitrate based on quality preference
        let bitrate: Int = switch dl.media.quality {
        case "1080p": 4_000_000
        case "720p": 2_000_000
        case "480p": 1_000_000
        default: 2_000_000
        }

        if let task = hlsSession?.makeAssetDownloadTask(
            asset: asset,
            assetTitle: "gs_\(Int(Date().timeIntervalSince1970))",
            assetArtworkData: nil,
            options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: bitrate]
        ) {
            dl.sessionTaskID = task.taskIdentifier
            dl.state = .downloading
            taskMap[task.taskIdentifier] = dl.id.uuidString
            task.resume()
        } else {
            dl.state = .failed
            dl.error = "HLS 다운로드 태스크 생성 실패"
        }
    }

    // MARK: - Post-Download

    private func moveToVault(_ dl: MediaDownload) async {
        guard let url = dl.localURL else { return }
        do {
            try await vaultManager.store(fileURL: url, originalName: dl.media.title)
            try? FileManager.default.removeItem(at: url)
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
            fatalError("Documents directory unavailable")
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
            try FileManager.default.moveItem(at: location, to: dest)
            dl.localURL = dest
            dl.state = .completed
            dl.progress = 1.0
            completedDownloads.insert(dl, at: 0)

            if dl.saveToVault {
                Task { await moveToVault(dl) }
            }
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
        dl.localURL = location
        dl.state = .completed
        dl.progress = 1.0
        completedDownloads.insert(dl, at: 0)

        if dl.saveToVault {
            Task { await moveToVault(dl) }
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

    var formattedProgress: String { "\(Int(progress * 100))%" }
    var formattedSpeed: String {
        let elapsed = Date.now.timeIntervalSince(startDate)
        guard elapsed > 0, bytesDownloaded > 0 else { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(Double(bytesDownloaded) / elapsed), countStyle: .file) + "/s"
    }

    enum DownloadState: String {
        case pending, downloading, paused, completed, failed, cancelled
    }
}
