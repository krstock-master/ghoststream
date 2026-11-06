// Media/MediaDownloadManager.swift
// GhostStream - Multi-format media download engine
//
// v2.0.5 QA 정리
//  - 모든 상태 변경은 메인 스레드에서만 (@Observable UI 갱신 경합 제거)
//  - URLSession: ephemeral + 전용 메모리 쿠키 저장소 (사생활 탭 쿠키가 HTTPCookieStorage.shared/디스크로 새지 않음)
//  - TLS 인증서 무조건 신뢰 제거 (기본 검증)
//  - 실패/취소 시에도 대기열 진행, 실패는 토스트로 알림
//  - 파일명: Content-Disposition(RFC 5987 한글) / 중복 시 "(1)" / 덮어쓰기 금지
//  - HLS: 마스터 최고 화질, 상대 URL(리다이렉트 기준), AES-128 복호화, fMP4(EXT-X-MAP), BYTERANGE,
//         세그먼트 재시도·동시 4개, 분리 오디오(fMP4) 병합, TS는 시스템 다운로더(AVAssetDownloadTask)→MP4
//  - DASH/MSE(YouTube 등)·blob 은 명확히 "지원 안 함" 처리

import Foundation
import GhostStreamCore
import AVFoundation
import CommonCrypto
import SwiftUI
import WebKit

@Observable
final class MediaDownloadManager: NSObject, @unchecked Sendable {
    var downloads: [MediaDownload] = []
    var completedDownloads: [MediaDownload] = []

    // ★ 다운로드 큐 (동시 3개 제한) — 대기 항목도 downloads 목록에 .pending 으로 보인다
    @ObservationIgnored private var pendingQueue: [MediaDownload] = []
    private let maxConcurrent = 3
    private let hlsSegmentConcurrency = 4
    static let minimumValidFileSize: Int64 = 100

    private let vaultManager: VaultManager
    private let cookieJar: HTTPCookieStorage
    @ObservationIgnored var urlSession: URLSession?
    @ObservationIgnored private var hlsSession: URLSession?
    @ObservationIgnored private var assetSession: AVAssetDownloadURLSession?

    @ObservationIgnored private var taskMap: [Int: UUID] = [:]                 // urlSession taskIdentifier → download id
    @ObservationIgnored private var directTasks: [UUID: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var hlsTaskMap: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var assetTaskMap: [Int: UUID] = [:]            // assetSession taskIdentifier → download id
    @ObservationIgnored private var assetTasks: [UUID: AVAssetDownloadTask] = [:]
    @ObservationIgnored private var assetLocations: [UUID: URL] = [:]
    @ObservationIgnored private var webKitDownloads: [UUID: WKDownload] = [:]
    @ObservationIgnored private var webKitProgressObservers: [UUID: NSKeyValueObservation] = [:]
    @ObservationIgnored private var capturedUserAgent: String?

    /// 하위 호환: WebViewCoordinator가 `dm.cookieStorage = HTTPCookieStorage.shared` 로 쿠키를 넘긴다.
    /// 저장소 자체를 교체하지 않고 쿠키만 전용 메모리 저장소로 복사한다.
    var cookieStorage: HTTPCookieStorage {
        get { cookieJar }
        set {
            guard newValue !== cookieJar, let all = newValue.cookies else { return }
            all.forEach { cookieJar.setCookie($0) }
        }
    }

    init(vaultManager: VaultManager) {
        self.vaultManager = vaultManager
        // ephemeral 구성의 쿠키 저장소 = 프로세스 메모리 전용 (디스크 기록 없음)
        self.cookieJar = URLSessionConfiguration.ephemeral.httpCookieStorage ?? HTTPCookieStorage.shared
        super.init()

        let config = Self.makeConfiguration(cookieJar: cookieJar)
        config.timeoutIntervalForRequest = 60
        // ★ 대용량 파일: 리소스 타임아웃 10분 → 24시간 (느린 회선에서 2GB 영상이 10분에 강제 실패하던 문제)
        config.timeoutIntervalForResource = 60 * 60 * 24
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        let hlsConfig = Self.makeConfiguration(cookieJar: cookieJar)
        hlsConfig.timeoutIntervalForRequest = 30
        hlsConfig.timeoutIntervalForResource = 600
        hlsConfig.httpMaximumConnectionsPerHost = hlsSegmentConcurrency + 2
        hlsSession = URLSession(configuration: hlsConfig) // delegate 없음 → 세그먼트 데이터가 메인 큐를 거치지 않음
    }

    private static func makeConfiguration(cookieJar: HTTPCookieStorage) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = cookieJar
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = true
        return config
    }

    // MARK: - Session data (쿠키 / UA)

    /// WKWebView 쿠키를 전용 저장소로 가져온다 (HTTPCookieStorage.shared 사용 금지)
    func importCookies(_ cookies: [HTTPCookie]) {
        cookies.forEach { cookieJar.setCookie($0) }
    }

    /// Fire 버튼/데이터 삭제 시 호출: 다운로드용 쿠키·UA 캐시 제거
    func clearSessionData() {
        cookieJar.cookies?.forEach { cookieJar.deleteCookie($0) }
        onMain { self.capturedUserAgent = nil }
    }

    /// 실제 WKWebView UA를 캡처해 URLSession/AVAsset 요청에 그대로 사용 (UA 불일치 → CDN/CF 403 방지)
    func updateUserAgent(from webView: WKWebView) {
        onMain {
            MainActor.assumeIsolated {
                if let custom = webView.customUserAgent, !custom.isEmpty {
                    self.capturedUserAgent = custom
                    return
                }
                webView.evaluateJavaScript("navigator.userAgent") { [weak self] result, _ in
                    guard let ua = result as? String, !ua.isEmpty else { return }
                    self?.capturedUserAgent = ua
                }
            }
        }
    }

    private var currentUserAgent: String {
        capturedUserAgent ?? DeviceProfileManager.shared.activeProfile.userAgent
    }

    /// Safari 형식 Accept-Language ("ko-KR,ko;q=0.9")
    static var acceptLanguageHeader: String {
        guard let first = Locale.preferredLanguages.first, !first.isEmpty else { return "en-US,en;q=0.9" }
        var parts = [first]
        if let base = first.split(separator: "-").first.map(String.init), base != first {
            parts.append("\(base);q=0.9")
        }
        return parts.joined(separator: ",")
    }

    private func makeHeaders(referer: String) -> BrowserHeaders {
        var ref: URL?
        if let u = URL(string: referer), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            ref = u
        }
        return BrowserHeaders(userAgent: currentUserAgent, acceptLanguage: Self.acceptLanguageHeader, referer: ref)
    }

    // MARK: - Queue

    private var activeCount: Int {
        downloads.filter { ($0.state == .downloading || $0.state == .converting) && $0.engine != .webKit }.count
    }

    private func processQueue() {
        while activeCount < maxConcurrent && !pendingQueue.isEmpty {
            let next = pendingQueue.removeFirst()
            guard next.state == .pending else { continue } // 대기 중 취소된 항목
            start(next)
        }
    }

    // MARK: - Download API

    func download(media: DetectedMedia, saveToVault: Bool = true) {
        onMain { self.enqueue(media: media, saveToVault: saveToVault) }
    }

    // ★ Download with cookies pre-loaded (called from WebViewCoordinator)
    func downloadWithCookies(media: DetectedMedia, cookies: [HTTPCookie], saveToVault: Bool = false) {
        importCookies(cookies)
        onMain { self.enqueue(media: media, saveToVault: saveToVault) }
    }

    private func enqueue(media: DetectedMedia, saveToVault: Bool) {
        let dl = MediaDownload(media: media, saveToVault: saveToVault)
        downloads.insert(dl, at: 0)
        if let reason = Self.unsupportedReason(for: media) {
            fail(dl, reason)
            return
        }
        if activeCount >= maxConcurrent {
            pendingQueue.append(dl)
            NotificationCenter.default.post(name: .downloadCompleted,
                object: "⏳ 대기열에 추가됨 (\(pendingQueue.count)번째)")
            return
        }
        start(dl)
    }

    private func start(_ dl: MediaDownload) {
        let isPlaylist = dl.media.url.path.lowercased().hasSuffix(".m3u8")
        switch dl.media.type {
        case .hls:
            startHLSDownload(dl)
        case .blob:
            completeBlob(dl)
        case .mp4, .webm, .image, .gif:
            if isPlaylist { startHLSDownload(dl) } else { startDirectDownload(dl) }
        }
    }

    /// 지원하지 않는 소스는 다운로드를 시작하지 않고 이유를 반환 (WebViewCoordinator.startWKDownload 에서도 사용 가능)
    static func unsupportedReason(for media: DetectedMedia) -> String? {
        let url = media.url
        let scheme = url.scheme?.lowercased() ?? ""
        let path = url.path.lowercased()
        let host = url.host?.lowercased() ?? ""
        if media.type == .blob {
            return scheme == "file" ? nil : "스트리밍 전용(blob/MediaSource) 영상은 다운로드할 수 없습니다"
        }
        if scheme == "blob" || scheme == "data" {
            return "스트리밍 전용(blob/MediaSource) 영상은 다운로드할 수 없습니다"
        }
        if !["http", "https"].contains(scheme) {
            return "지원하지 않는 주소 형식입니다 (\(scheme))"
        }
        if path.hasSuffix(".mpd") {
            return "DASH(.mpd) 스트리밍은 지원하지 않습니다"
        }
        if path.hasSuffix(".ts") || path.hasSuffix(".m4s") {
            return "HLS 조각(.ts/.m4s) 하나만 감지되었습니다 — 재생목록(.m3u8)이 필요합니다"
        }
        return nil
    }

    func pause(_ dl: MediaDownload) {
        onMain {
            guard dl.engine == .urlSession, dl.state == .downloading, let task = self.directTasks[dl.id] else { return }
            dl.state = .paused
            task.cancel(byProducingResumeData: { data in
                DispatchQueue.main.async { dl.resumeData = data }
            })
            self.processQueue()
        }
    }

    func resume(_ dl: MediaDownload) {
        onMain {
            guard dl.state == .paused, let session = self.urlSession else { return }
            if let data = dl.resumeData {
                dl.resumeData = nil
                let task = session.downloadTask(withResumeData: data)
                self.register(task, for: dl)
                dl.state = .downloading
                task.resume()
            } else {
                self.startDirectDownload(dl)
            }
        }
    }

    func cancel(_ dl: MediaDownload) {
        onMain {
            dl.state = .cancelled
            if let t = self.directTasks.removeValue(forKey: dl.id) { t.cancel() }
            if let h = self.hlsTaskMap.removeValue(forKey: dl.id) { h.cancel() }
            if let a = self.assetTasks.removeValue(forKey: dl.id) { a.cancel() }
            if let w = self.webKitDownloads.removeValue(forKey: dl.id) {
                MainActor.assumeIsolated { w.cancel { _ in } }
            }
            self.webKitProgressObservers.removeValue(forKey: dl.id)?.invalidate()
            self.pendingQueue.removeAll { $0.id == dl.id }
            self.downloads.removeAll { $0.id == dl.id }
            self.processQueue()
        }
    }

    func retry(_ dl: MediaDownload) {
        onMain {
            self.downloads.removeAll { $0.id == dl.id }
            self.enqueue(media: dl.media, saveToVault: dl.saveToVault)
        }
    }

    // MARK: - WKDownload 연동 (브라우저 세션 다운로드도 목록·진행률·취소 대상)

    /// WebViewCoordinator가 WKDownload를 시작/전환받았을 때 호출하면 다운로드 목록에 진행률과 함께 표시된다.
    @discardableResult
    func trackWebKitDownload(_ download: WKDownload, title: String, sourceURL: URL?) -> MediaDownload {
        let url = sourceURL ?? URL(fileURLWithPath: "/")
        let media = DetectedMedia(url: url, type: Self.mediaType(forExtension: url.pathExtension),
                                  quality: "Browser", title: title, referer: "", thumbnail: nil, estimatedSize: nil)
        let dl = MediaDownload(media: media, saveToVault: false)
        dl.engine = .webKit
        onMain {
            dl.state = .downloading
            self.downloads.insert(dl, at: 0)
            MainActor.assumeIsolated {
                self.webKitDownloads[dl.id] = download
                let observation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak dl] p, _ in
                    let fraction = p.fractionCompleted
                    let done = p.completedUnitCount
                    let total = p.totalUnitCount
                    DispatchQueue.main.async {
                        guard let dl, dl.state == .downloading else { return }
                        dl.progress = fraction
                        dl.bytesDownloaded = done
                        dl.totalBytes = max(total, 0)
                    }
                }
                self.webKitProgressObservers[dl.id] = observation
            }
        }
        return dl
    }

    /// WKDownload 종료 시 호출 (fileURL = 저장된 파일, 실패면 errorMessage)
    func finishWebKitDownload(_ download: WKDownload, fileURL: URL?, errorMessage: String?) {
        onMain {
            guard let id = self.webKitDownloads.first(where: { $0.value === download })?.key else { return }
            self.webKitDownloads.removeValue(forKey: id)
            self.webKitProgressObservers.removeValue(forKey: id)?.invalidate()
            guard let dl = self.downloads.first(where: { $0.id == id }) else { return }
            if let fileURL, errorMessage == nil {
                self.finalizeCompleted(dl, fileURL: fileURL, size: Self.fileSize(fileURL), notify: false)
            } else {
                self.fail(dl, errorMessage ?? "다운로드 실패", notify: false)
            }
        }
    }

    private static func mediaType(forExtension ext: String) -> DetectedMedia.MediaType {
        switch ext.lowercased() {
        case "gif": return .gif
        case "jpg", "jpeg", "png", "webp", "heic", "heif", "avif": return .image
        case "webm": return .webm
        case "m3u8": return .hls
        default: return .mp4
        }
    }

    // MARK: - Direct Download (MP4/WebM/이미지/파일)

    private static let imageAccept = "image/webp,image/avif,image/jxl,image/heic,image/heic-sequence,video/*;q=0.8,image/png,image/svg+xml,image/*;q=0.8,*/*;q=0.5"

    private func startDirectDownload(_ dl: MediaDownload) {
        guard let session = urlSession else { fail(dl, "URLSession 없음"); return }
        let headers = makeHeaders(referer: dl.media.referer)
        let accept = (dl.media.type == .image || dl.media.type == .gif) ? Self.imageAccept : "*/*"
        // ★ Accept-Encoding 수동 지정 금지: 직접 넣으면 URLSession이 자동 해제를 하지 않아 압축된 바이트가 저장될 수 있음
        // ★ Cookie 헤더 수동 지정 금지: 전용 쿠키 저장소가 URL/도메인/경로/Secure 규칙대로 붙이고, 리다이렉트 시 타 도메인 유출도 막는다
        let request = headers.request(for: dl.media.url, accept: accept, corsStyle: false)
        let task = session.downloadTask(with: request)
        register(task, for: dl)
        dl.engine = .urlSession
        dl.state = .downloading
        task.resume()
    }

    private func register(_ task: URLSessionDownloadTask, for dl: MediaDownload) {
        taskMap[task.taskIdentifier] = dl.id
        directTasks[dl.id] = task
        dl.sessionTaskID = task.taskIdentifier
    }

    private func find(byTaskID id: Int) -> MediaDownload? {
        guard let dlID = taskMap[id] else { return nil }
        return downloads.first { $0.id == dlID }
    }

    // MARK: - Blob (JS FileReader 캡처본)

    private func completeBlob(_ dl: MediaDownload) {
        let src = dl.media.url
        guard src.isFileURL, FileManager.default.fileExists(atPath: src.path) else {
            fail(dl, "blob 캡처 파일이 없습니다 (이미 저장되었거나 임시 파일이 삭제됨)")
            return
        }
        let ext = src.pathExtension.isEmpty ? "mp4" : src.pathExtension
        let base = DownloadFileNaming.sanitize(dl.media.title.isEmpty ? "Blob Video" : String(dl.media.title.prefix(60)))
        let dest = DownloadFileNaming.reserveUniqueURL(in: Self.downloadDirectory, filename: "\(base).\(ext)")
        defer { DownloadFileNaming.releaseReservation(dest) }
        do {
            // 임시 디렉터리는 OS가 비울 수 있으므로 Downloads 로 복사
            try FileManager.default.copyItem(at: src, to: dest)
        } catch {
            fail(dl, "blob 저장 실패: \(error.localizedDescription)")
            return
        }
        let size = Self.fileSize(dest)
        // JS 쪽 캡처는 50MB에서 잘린다 (PrivacyScripts earlyJS) → 잘렸을 가능성 표시
        let truncated = size >= 50 * 1024 * 1024
        finalizeCompleted(dl, fileURL: dest, size: size,
                          status: truncated ? "blob 캡처 — 50MB에서 잘려 불완전할 수 있음" : nil)
    }

    // MARK: - Completion helpers (메인 스레드)

    private func fail(_ dl: MediaDownload, _ message: String, notify: Bool = true) {
        onMain {
            guard dl.state != .cancelled else { return }
            dl.state = .failed
            dl.error = message
            self.cleanupTaskRefs(dl)
            if notify {
                NotificationCenter.default.post(name: .downloadFailed, object: message)
            }
            self.processQueue()
        }
    }

    private func finalizeCompleted(_ dl: MediaDownload, fileURL: URL, size: Int64?, status: String? = nil, notify: Bool = true) {
        guard dl.state != .cancelled else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        dl.localURL = fileURL
        if let status { dl.hlsConversionStatus = status }
        dl.state = .completed
        dl.progress = 1.0
        if let size, size > 0 {
            dl.bytesDownloaded = size
            dl.totalBytes = size
        }
        cleanupTaskRefs(dl)
        downloads.removeAll { $0.id == dl.id }
        if !completedDownloads.contains(where: { $0.id == dl.id }) {
            completedDownloads.insert(dl, at: 0)
        }
        processQueue()
        if notify {
            let sizeText = size.map { " (\(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)))" } ?? ""
            NotificationCenter.default.post(name: .downloadCompleted, object: "✅ \(dl.media.title) 다운로드 완료\(sizeText)")
        }
        postProcess(dl, fileURL: fileURL)
    }

    private func cleanupTaskRefs(_ dl: MediaDownload) {
        if let task = directTasks.removeValue(forKey: dl.id) {
            taskMap.removeValue(forKey: task.taskIdentifier)
        }
        hlsTaskMap.removeValue(forKey: dl.id)
        if let a = assetTasks.removeValue(forKey: dl.id) {
            assetTaskMap.removeValue(forKey: a.taskIdentifier)
        }
    }

    /// 이미지 메타데이터 제거(EXIF/GPS) + 보안 폴더 저장 — 메인 스레드 밖에서
    private func postProcess(_ dl: MediaDownload, fileURL: URL) {
        let needsScrub = MetadataScrubber.canScrub(fileURL)
        let toVault = dl.saveToVault
        guard needsScrub || toVault else { return }
        Task.detached(priority: .utility) { [weak self] in
            if needsScrub && !MetadataScrubber.scrubImage(at: fileURL) {
                let msg = "메타데이터(EXIF/GPS) 제거 실패 — 원본 그대로 저장됨"
                await MainActor.run {
                    dl.error = msg
                    NotificationCenter.default.post(name: .downloadFailed, object: "\(dl.media.title): \(msg)")
                }
            }
            if toVault { await self?.moveToVault(dl) }
        }
    }

    private func moveToVault(_ dl: MediaDownload) async {
        guard let url = dl.localURL else { return }
        do {
            // NOTE: VaultManager.store 는 파일 전체를 Data 로 읽는다 (대용량 영상 메모리 위험 — 보고서 참조)
            try await vaultManager.store(fileURL: url, originalName: dl.media.title)
        } catch {
            let msg = "보안 폴더 저장 실패: \(error.localizedDescription)"
            await MainActor.run {
                dl.error = msg
                NotificationCenter.default.post(name: .downloadFailed, object: msg)
            }
        }
    }

    // MARK: - HLS

    private func startHLSDownload(_ dl: MediaDownload) {
        guard let session = hlsSession else { fail(dl, "URLSession 없음"); return }
        dl.engine = .hls
        dl.state = .downloading
        dl.hlsGeneration += 1
        let generation = dl.hlsGeneration
        let headers = makeHeaders(referer: dl.media.referer)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hls_\(dl.id.uuidString)_\(generation)", isDirectory: true)
        let concurrency = hlsSegmentConcurrency
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.runHLS(dl, session: session, headers: headers, tempDir: tempDir, concurrency: concurrency)
            } catch is CancellationError {
                // cancel() 에서 상태 처리
            } catch let e as URLError where e.code == .cancelled {
                // 취소
            } catch let e as HLSError {
                self.fail(dl, e.message)
            } catch {
                self.fail(dl, "HLS 다운로드 실패: \(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: tempDir)
            self.onMain {
                if dl.hlsGeneration == generation { _ = self.hlsTaskMap.removeValue(forKey: dl.id) }
            }
        }
        hlsTaskMap[dl.id] = task
    }

    private func runHLS(_ dl: MediaDownload, session: URLSession, headers: BrowserHeaders,
                        tempDir: URL, concurrency: Int) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 1) 최상위 재생목록 (대용량 파일을 m3u8 로 오인해 통째로 메모리에 올리지 않도록 스트리밍으로 검사)
        let top = try await fetchPlaylist(dl.media.url, headers: headers, session: session)
        guard let topText = top.text, HLSParser.isPlaylist(topText) else {
            // m3u8 이 아님 → 일반 파일 다운로드로 전환
            onMain { if dl.state == .downloading { self.startDirectDownload(dl) } }
            return
        }

        // 2) 마스터 → 최고 BANDWIDTH 변형 선택
        var mediaText = topText
        var mediaBase = top.base
        var audioURL: URL?
        var bestBandwidth = 0
        if topText.contains("#EXT-X-STREAM-INF") {
            let variants = HLSParser.variants(in: topText, base: top.base)
            guard let best = variants.max(by: { $0.bandwidth < $1.bandwidth }) else {
                throw HLSError.malformed("마스터 재생목록에서 화질 목록을 찾을 수 없습니다")
            }
            bestBandwidth = best.bandwidth
            if let group = best.audioGroup {
                audioURL = HLSParser.audioRenditionURL(in: topText, group: group, base: top.base)
            }
            let media = try await fetchPlaylist(best.url, headers: headers, session: session)
            guard let t = media.text, HLSParser.isPlaylist(t) else {
                throw HLSError.malformed("미디어 재생목록을 읽을 수 없습니다")
            }
            mediaText = t
            mediaBase = media.base
        }

        let video = try HLSParser.mediaPlaylist(mediaText, base: mediaBase)
        guard !video.segments.isEmpty else { throw HLSError.malformed("재생목록에 세그먼트가 없습니다") }
        try HLSParser.checkEncryptionSupported(video)
        let isFMP4 = video.initSegment != nil

        // 3) MPEG-TS: AVFoundation 은 로컬 .ts 를 열 수 없어 MP4 로 변환이 불가능하다.
        //    → 시스템 HLS 다운로더(AVAssetDownloadTask, .movpkg) 로 받은 뒤 MP4 로 내보낸다. 실패 시 아래 수동 경로.
        if !isFMP4 && !dl.avAssetAttempted {
            onMain { self.startAVAssetDownload(dl, masterURL: dl.media.url, minBitrate: bestBandwidth, headers: headers) }
            return
        }

        // 4) 수동 세그먼트 다운로드
        var audioPlaylist: HLSMediaPlaylistInfo?
        var warnings: [String] = []
        if !video.hasEndList { warnings.append("라이브 스트림 — 현재 구간만 저장됨") }
        if let audioURL {
            if isFMP4,
               let a = try? await fetchPlaylist(audioURL, headers: headers, session: session),
               let t = a.text, HLSParser.isPlaylist(t),
               let parsed = try? HLSParser.mediaPlaylist(t, base: a.base),
               parsed.initSegment != nil, !parsed.segments.isEmpty,
               (try? HLSParser.checkEncryptionSupported(parsed)) != nil {
                audioPlaylist = parsed
            } else {
                warnings.append("오디오가 별도 트랙이라 병합하지 못함 — 소리가 없을 수 있음")
            }
        }

        let total = video.segments.count + (video.initSegment == nil ? 0 : 1)
            + (audioPlaylist.map { $0.segments.count + 1 } ?? 0)
        let counter = HLSProgressCounter(total: total)

        let videoOut = tempDir.appendingPathComponent(isFMP4 ? "video.mp4" : "video.ts")
        try await downloadSegments(video, to: videoOut, session: session, headers: headers,
                                   dl: dl, counter: counter, concurrency: concurrency)
        var audioOut: URL?
        if let audioPlaylist {
            let out = tempDir.appendingPathComponent("audio.mp4")
            try await downloadSegments(audioPlaylist, to: out, session: session, headers: headers,
                                       dl: dl, counter: counter, concurrency: concurrency)
            audioOut = out
        }
        try Task.checkCancellation()
        onMain { if dl.state == .downloading { dl.state = .converting } }

        let baseName = DownloadFileNaming.sanitize(dl.media.title.isEmpty ? "video" : String(dl.media.title.prefix(60)))
        if isFMP4 {
            let dest = DownloadFileNaming.reserveUniqueURL(in: Self.downloadDirectory, filename: baseName + ".mp4")
            defer { DownloadFileNaming.releaseReservation(dest) }
            let status = try await Self.finalizeFMP4(video: videoOut, audio: audioOut, dest: dest)
            let size = Self.fileSize(dest)
            let finalStatus = ([status] + warnings).joined(separator: " · ")
            onMain { self.finalizeCompleted(dl, fileURL: dest, size: size, status: finalStatus) }
        } else {
            // TS 수동 경로(시스템 다운로더 실패 후): 원본 TS 보존. 앱 내 재생·사진 저장은 불가 → 명시적으로 알림
            let dest = DownloadFileNaming.reserveUniqueURL(in: Self.downloadDirectory, filename: baseName + ".ts")
            defer { DownloadFileNaming.releaseReservation(dest) }
            try fm.moveItem(at: videoOut, to: dest)
            let size = Self.fileSize(dest)
            let status = (["TS 원본 저장 (MP4 변환 불가 — 앱 재생·사진 저장 불가, 공유 → VLC 등에서 열기)"] + warnings)
                .joined(separator: " · ")
            onMain {
                self.finalizeCompleted(dl, fileURL: dest, size: size, status: status)
                NotificationCenter.default.post(name: .downloadFailed,
                    object: "\(dl.media.title): MP4 변환 실패 — TS 파일로 저장했습니다 (사진 앱 저장 불가)")
            }
        }
    }

    /// 재생목록 가져오기: 응답이 영상 파일이거나 8MB를 넘으면 본문을 읽지 않고 중단
    private func fetchPlaylist(_ url: URL, headers: BrowserHeaders, session: URLSession) async throws
        -> (text: String?, base: URL) {
        let limit = 8_000_000
        var lastError: Error = URLError(.unknown)
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                let (bytes, response) = try await session.bytes(for: headers.request(for: url, corsStyle: true))
                let base = response.url ?? url
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    bytes.task.cancel()
                    if [401, 403, 404, 410].contains(http.statusCode) { throw HLSError.http(http.statusCode) }
                    lastError = HLSError.http(http.statusCode)
                } else {
                    let mime = response.mimeType?.lowercased() ?? ""
                    if (mime.hasPrefix("video/") && !mime.contains("mpegurl")) || response.expectedContentLength > Int64(limit) {
                        bytes.task.cancel()
                        return (nil, base)
                    }
                    var data = Data()
                    for try await byte in bytes {
                        data.append(byte)
                        if data.count > limit {
                            bytes.task.cancel()
                            return (nil, base)
                        }
                    }
                    return (String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1), base)
                }
            } catch let e as HLSError {
                throw e
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
            if attempt < 2 { try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 700_000_000) }
        }
        throw lastError
    }

    /// 세그먼트/키 요청: 일시 오류는 최대 3회 재시도 (403/404/410 은 즉시 실패)
    private func fetch(_ request: URLRequest, session: URLSession, attempts: Int = 3) async throws -> (Data, URLResponse) {
        var lastError: Error = URLError(.unknown)
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return (data, response) }
                if (200..<300).contains(http.statusCode) { return (data, response) }
                if [401, 403, 404, 410].contains(http.statusCode) { throw HLSError.http(http.statusCode) }
                lastError = HLSError.http(http.statusCode)
            } catch let e as HLSError {
                throw e
            } catch is CancellationError {
                throw CancellationError()
            } catch let e as URLError where e.code == .cancelled {
                throw e
            } catch {
                lastError = error
            }
            if attempt < attempts - 1 { try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 700_000_000) }
        }
        throw lastError
    }

    private func fetchSegment(_ seg: HLSSegmentInfo, session: URLSession, headers: BrowserHeaders,
                              keys: HLSKeyCache) async throws -> Data {
        let (data, _) = try await fetch(headers.request(for: seg.url, range: seg.range, corsStyle: true), session: session)
        var body = data
        if let range = seg.range, Int64(body.count) > range.length {
            // 서버가 Range 를 무시하고 전체를 준 경우 해당 구간만 잘라 쓴다
            let lo = Int(range.offset)
            let hi = Int(range.offset + range.length)
            guard lo >= 0, hi <= body.count else { throw HLSError.malformed("바이트 범위 응답이 올바르지 않습니다") }
            body = body.subdata(in: lo..<hi)
        }
        if let key = seg.key, key.method == "AES-128", let keyURL = key.uri {
            let keyData = try await keys.key(for: keyURL) {
                try await self.fetch(headers.request(for: keyURL, corsStyle: true), session: session).0
            }
            let iv = key.iv ?? HLSParser.ivFromSequence(seg.sequence)
            guard let plain = HLSCrypto.aes128CBCDecrypt(body, key: keyData, iv: iv) else {
                throw HLSError.malformed("AES-128 복호화 실패 (키 또는 IV 불일치)")
            }
            body = plain
        }
        return body
    }

    /// 동시 N개씩 받아 순서대로 파일에 이어 쓴다 (세그먼트 단위로만 메모리 사용)
    private func downloadSegments(_ playlist: HLSMediaPlaylistInfo, to output: URL, session: URLSession,
                                  headers: BrowserHeaders, dl: MediaDownload, counter: HLSProgressCounter,
                                  concurrency: Int) async throws {
        let fm = FileManager.default
        guard fm.createFile(atPath: output.path, contents: nil) else {
            throw HLSError.malformed("임시 파일을 만들 수 없습니다 (저장 공간 확인)")
        }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let keys = HLSKeyCache()

        if let initSeg = playlist.initSegment {
            let data = try await fetchSegment(initSeg, session: session, headers: headers, keys: keys)
            try handle.write(contentsOf: data) // 디스크 부족 시 예외(throw) — 구 write(_:) 는 크래시
            report(counter.advance(bytes: data.count), to: dl)
        }

        let segments = playlist.segments
        var start = 0
        while start < segments.count {
            try Task.checkCancellation()
            let end = min(start + concurrency, segments.count)
            let batch = Array(segments[start..<end])
            let results = try await withThrowingTaskGroup(of: (Int, Data).self) { group -> [Int: Data] in
                for seg in batch {
                    group.addTask {
                        let d = try await self.fetchSegment(seg, session: session, headers: headers, keys: keys)
                        return (seg.index, d)
                    }
                }
                var collected: [Int: Data] = [:]
                for try await (index, data) in group { collected[index] = data }
                return collected
            }
            for seg in batch {
                guard let data = results[seg.index] else { throw HLSError.malformed("세그먼트 누락") }
                try handle.write(contentsOf: data)
                report(counter.advance(bytes: data.count), to: dl)
            }
            start = end
        }
    }

    private func report(_ snapshot: (progress: Double, bytes: Int64), to dl: MediaDownload) {
        onMain {
            guard dl.state == .downloading else { return }
            dl.progress = snapshot.progress
            dl.bytesDownloaded = snapshot.bytes
        }
    }

    /// fMP4 → (분리 오디오 병합) → passthrough 로 일반 MP4 (moov 앞쪽, 사진 앱 호환)
    private static func finalizeFMP4(video: URL, audio: URL?, dest: URL) async throws -> String {
        let videoAsset = AVURLAsset(url: video)
        var exportAsset: AVAsset = videoAsset
        var merged = false
        if let audio {
            do {
                let audioAsset = AVURLAsset(url: audio)
                let composition = AVMutableComposition()
                let duration = try await videoAsset.load(.duration)
                let vTracks = try await videoAsset.loadTracks(withMediaType: .video)
                let aTracks = try await audioAsset.loadTracks(withMediaType: .audio)
                if let v = vTracks.first,
                   let ct = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try ct.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: v, at: .zero)
                    ct.preferredTransform = try await v.load(.preferredTransform)
                }
                if let a = aTracks.first,
                   let ct = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    let audioDuration = try await audioAsset.load(.duration)
                    try ct.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)),
                                           of: a, at: .zero)
                    merged = true
                }
                if merged { exportAsset = composition }
            } catch {
                merged = false
            }
        }
        if await export(exportAsset, to: dest) {
            if audio != nil && !merged { return "MP4 변환 완료 · 오디오 병합 실패(무음일 수 있음)" }
            return "MP4 변환 완료"
        }
        // 변환 실패: 조각 MP4 그대로 보존 (AVPlayer 재생 가능, 사진 앱은 거부할 수 있음)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: video, to: dest)
        return audio == nil ? "fMP4 저장 (MP4 변환 실패 — 사진 앱 저장이 안 될 수 있음)"
                            : "fMP4 영상만 저장 (오디오 병합 실패)"
    }

    private static func export(_ asset: AVAsset, to dest: URL) async -> Bool {
        for preset in [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality] {
            guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            try? FileManager.default.removeItem(at: dest)
            exporter.outputURL = dest
            exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse = true
            await exporter.export()
            if exporter.status == .completed { return true }
        }
        try? FileManager.default.removeItem(at: dest)
        return false
    }

    // MARK: - HLS (MPEG-TS) → AVAssetDownloadTask

    private func makeAssetSession() -> AVAssetDownloadURLSession {
        if let s = assetSession { return s }
        // 백그라운드 URLSession 은 별도 entitlement 가 필요 없다 (사이드로드 OK).
        // 앱 재실행 시 이벤트 전달(handleEventsForBackgroundURLSession)은 App 쪽 미구현 → 포그라운드 기준 동작.
        let cfg = URLSessionConfiguration.background(withIdentifier: "com.ghoststream.hls.avasset")
        cfg.isDiscretionary = false
        cfg.sessionSendsLaunchEvents = false
        let s = AVAssetDownloadURLSession(configuration: cfg, assetDownloadDelegate: self, delegateQueue: .main)
        assetSession = s
        // 이전 실행에서 남은 고아 작업 정리
        s.getAllTasks { tasks in
            DispatchQueue.main.async {
                for t in tasks where self.assetTaskMap[t.taskIdentifier] == nil { t.cancel() }
            }
        }
        return s
    }

    private func startAVAssetDownload(_ dl: MediaDownload, masterURL: URL, minBitrate: Int, headers: BrowserHeaders) {
        guard dl.state == .downloading else { return }
        dl.avAssetAttempted = true
        dl.engine = .avAsset
        var httpHeaders: [String: String] = ["Accept-Language": headers.acceptLanguage]
        if let ref = headers.refererValue(for: masterURL) { httpHeaders["Referer"] = ref }
        let options: [String: Any] = [
            AVURLAssetHTTPCookiesKey: cookieJar.cookies(for: masterURL) ?? [],
            AVURLAssetHTTPUserAgentKey: headers.userAgent,
            "AVURLAssetHTTPHeaderFieldsKey": httpHeaders, // 비공개 키 (사이드로드 빌드 전용)
        ]
        let asset = AVURLAsset(url: masterURL, options: options)
        var taskOptions: [String: Any] = [:]
        if minBitrate > 0 { taskOptions[AVAssetDownloadTaskMinimumRequiredMediaBitrateKey] = minBitrate }
        let session = makeAssetSession()
        guard let task = session.makeAssetDownloadTask(asset: asset, assetTitle: String(dl.media.title.prefix(60)),
                                                       assetArtworkData: nil, options: taskOptions) else {
            startHLSDownload(dl) // 수동 경로로
            return
        }
        assetTaskMap[task.taskIdentifier] = dl.id
        assetTasks[dl.id] = task
        dl.hlsConversionStatus = "HLS(TS) — 시스템 다운로더 사용"
        task.resume()
    }

    private func handleAssetCompletion(_ task: URLSessionTask, error: Error?) {
        guard let id = assetTaskMap.removeValue(forKey: task.taskIdentifier) else { return }
        assetTasks.removeValue(forKey: id)
        let location = assetLocations.removeValue(forKey: id)
        guard let dl = downloads.first(where: { $0.id == id }), dl.state == .downloading else {
            if let location { try? FileManager.default.removeItem(at: location) }
            return
        }
        if let error {
            if let location { try? FileManager.default.removeItem(at: location) }
            dl.hlsConversionStatus = "시스템 다운로더 실패(\(error.localizedDescription)) → 수동 다운로드"
            startHLSDownload(dl)
            return
        }
        guard let location else {
            startHLSDownload(dl)
            return
        }
        dl.state = .converting
        let baseName = DownloadFileNaming.sanitize(dl.media.title.isEmpty ? "video" : String(dl.media.title.prefix(60)))
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let dest = DownloadFileNaming.reserveUniqueURL(in: Self.downloadDirectory, filename: baseName + ".mp4")
            let ok = await Self.export(AVURLAsset(url: location), to: dest)
            DownloadFileNaming.releaseReservation(dest)
            try? FileManager.default.removeItem(at: location)
            if ok {
                let size = Self.fileSize(dest)
                self.onMain { self.finalizeCompleted(dl, fileURL: dest, size: size, status: "MP4 변환 완료") }
            } else {
                self.onMain {
                    guard dl.state == .converting else { return }
                    dl.hlsConversionStatus = "movpkg → MP4 변환 실패 → 수동 다운로드"
                    self.startHLSDownload(dl)
                }
            }
        }
    }

    // MARK: - Utilities

    private func onMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread { body() } else { DispatchQueue.main.async(execute: body) }
    }

    static func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func message(for error: NSError) -> String {
        switch error.code {
        case NSURLErrorTimedOut: return "다운로드 시간 초과 — 네트워크 상태를 확인하세요"
        case NSURLErrorNotConnectedToInternet: return "인터넷 연결 없음"
        case NSURLErrorNetworkConnectionLost: return "네트워크 연결 끊김 — 재시도하세요"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid,
             NSURLErrorServerCertificateHasUnknownRoot:
            return "보안 연결 실패 (인증서 오류)"
        case NSURLErrorCannotWriteToFile, NSURLErrorCannotCreateFile:
            return "저장 공간이 부족하거나 파일을 쓸 수 없습니다"
        default: return "다운로드 오류: \(error.localizedDescription)"
        }
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

// MARK: - URLSessionDownloadDelegate (delegateQueue = .main)
extension MediaDownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard session === urlSession, let dl = find(byTaskID: downloadTask.taskIdentifier) else { return }
        // location 은 이 메서드가 반환되면 삭제되므로 검증·이동을 여기서 끝낸다
        let response = downloadTask.response

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            fail(dl, "서버 응답 오류: HTTP \(http.statusCode)")
            return
        }

        let mime = response?.mimeType?.lowercased() ?? ""
        let urlExt = dl.media.url.pathExtension.lowercased()
        let wantsMarkup = ["html", "htm", "json", "xml"].contains(urlExt)
        if !wantsMarkup && (mime.contains("text/html") || mime == "application/json"
                            || DownloadFileNaming.looksLikeHTML(fileAt: location)) {
            fail(dl, "다운로드 실패: 서버가 파일 대신 웹페이지/오류 응답을 반환했습니다 (로그인·만료·접근 제한)")
            return
        }

        let fileSize = Self.fileSize(location)
        if fileSize < Self.minimumValidFileSize {
            fail(dl, "다운로드 실패: 파일 크기가 너무 작습니다 (\(fileSize)B) — URL 만료 또는 접근 차단")
            return
        }

        let preferTitle = dl.media.type == .mp4 || dl.media.type == .webm || dl.media.type == .hls
        let name = DownloadFileNaming.resolveFilename(response: response, suggested: response?.suggestedFilename,
                                                      title: dl.media.title,
                                                      sourceURL: response?.url ?? dl.media.url,
                                                      preferTitle: preferTitle)
        let dest = DownloadFileNaming.reserveUniqueURL(in: Self.downloadDirectory, filename: name)
        defer { DownloadFileNaming.releaseReservation(dest) }
        do {
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            fail(dl, "파일 저장 실패: \(error.localizedDescription)")
            return
        }
        finalizeCompleted(dl, fileURL: dest, size: fileSize)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard session === urlSession, let dl = find(byTaskID: downloadTask.taskIdentifier) else { return }
        dl.bytesDownloaded = totalBytesWritten
        dl.totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 0
        dl.progress = dl.totalBytes > 0 ? Double(totalBytesWritten) / Double(dl.totalBytes) : 0
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let assetSession, session === assetSession {
            handleAssetCompletion(task, error: error)
            return
        }
        guard session === urlSession, let dl = find(byTaskID: task.taskIdentifier) else { return }
        taskMap.removeValue(forKey: task.taskIdentifier)
        guard let error else { return } // 성공은 didFinishDownloadingTo 에서 처리
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return } // pause / cancel
        if let data = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data { dl.resumeData = data }
        fail(dl, Self.message(for: ns))
    }
    // ★ 인증서 무조건 신뢰(didReceive challenge → .useCredential) 핸들러 제거: 시스템 기본 TLS 검증 사용
}

// MARK: - AVAssetDownloadDelegate (MPEG-TS HLS)
extension MediaDownloadManager: AVAssetDownloadDelegate {
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, willDownloadTo location: URL) {
        guard let id = assetTaskMap[assetDownloadTask.taskIdentifier] else { return }
        assetLocations[id] = location
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = assetTaskMap[assetDownloadTask.taskIdentifier] else {
            try? FileManager.default.removeItem(at: location)
            return
        }
        assetLocations[id] = location
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange,
                    totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        guard let id = assetTaskMap[assetDownloadTask.taskIdentifier],
              let dl = downloads.first(where: { $0.id == id }), dl.state == .downloading else { return }
        let expected = CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
        guard expected.isFinite, expected > 0 else { return }
        let loaded = loadedTimeRanges.reduce(0.0) { $0 + CMTimeGetSeconds($1.timeRangeValue.duration) }
        dl.progress = min(1, loaded / expected)
        dl.bytesDownloaded = assetDownloadTask.countOfBytesReceived
    }
}

// MARK: - Request headers (WKWebView 와 같은 형태로)

struct BrowserHeaders: Sendable {
    let userAgent: String
    let acceptLanguage: String
    let referer: URL?

    /// 브라우저 기본 Referrer-Policy(strict-origin-when-cross-origin) 흉내: 교차 출처는 origin 만 보낸다
    func refererValue(for url: URL) -> String? {
        guard let ref = referer else { return nil }
        if Self.sameOrigin(ref, url) {
            var comps = URLComponents(url: ref, resolvingAgainstBaseURL: false)
            comps?.fragment = nil
            return comps?.string ?? ref.absoluteString
        }
        if ref.scheme?.lowercased() == "https" && url.scheme?.lowercased() == "http" { return nil } // 다운그레이드
        return Self.origin(of: ref).map { $0 + "/" }
    }

    func request(for url: URL, accept: String = "*/*", range: HLSByteRange? = nil, corsStyle: Bool = false) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        r.setValue(accept, forHTTPHeaderField: "Accept")
        r.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        if let value = refererValue(for: url) { r.setValue(value, forHTTPHeaderField: "Referer") }
        // hls.js 등은 XHR/fetch 로 요청 → 교차 출처면 Origin 이 붙는다. <video src> 직접 재생은 Origin 없음.
        if corsStyle, let ref = referer, !Self.sameOrigin(ref, url), let origin = Self.origin(of: ref) {
            r.setValue(origin, forHTTPHeaderField: "Origin")
        }
        if let range {
            r.setValue("bytes=\(range.offset)-\(range.offset + range.length - 1)", forHTTPHeaderField: "Range")
        }
        return r
    }

    private static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    private static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme?.lowercased() == b.scheme?.lowercased() && a.host?.lowercased() == b.host?.lowercased() && a.port == b.port
    }
}

// MARK: - HLS model / parser

struct HLSByteRange: Hashable, Sendable {
    let length: Int64
    let offset: Int64
}

struct HLSKeyInfo: Hashable, Sendable {
    let method: String
    let uri: URL?
    let iv: Data?
    let keyFormat: String?
}

struct HLSSegmentInfo: Sendable {
    let index: Int
    let url: URL
    let range: HLSByteRange?
    let key: HLSKeyInfo?
    let sequence: Int
}

struct HLSMediaPlaylistInfo: Sendable {
    var segments: [HLSSegmentInfo] = []
    var initSegment: HLSSegmentInfo?
    var hasEndList = false
}

struct HLSVariant: Sendable {
    let url: URL
    let bandwidth: Int
    let audioGroup: String?
}

enum HLSError: Error {
    case http(Int)
    case malformed(String)
    case unsupported(String)

    var message: String {
        switch self {
        case .http(let code):
            switch code {
            case 401, 403: return "HLS 다운로드 실패: 접근 거부(HTTP \(code)) — 로그인/토큰 만료 또는 Referer 제한"
            case 404, 410: return "HLS 다운로드 실패: 영상이 없거나 만료됨(HTTP \(code))"
            default: return "HLS 다운로드 실패: 서버 오류(HTTP \(code))"
            }
        case .malformed(let m): return "HLS 다운로드 실패: \(m)"
        case .unsupported(let m): return "HLS 다운로드 불가: \(m)"
        }
    }
}

enum HLSParser {
    static func isPlaylist(_ text: String) -> Bool {
        text.contains("#EXTM3U") || text.contains("#EXTINF") || text.contains("#EXT-X-STREAM-INF")
    }

    /// `KEY=VALUE,KEY="quoted, value"` 속성 목록 파싱
    static func attributes(_ s: Substring) -> [String: String] {
        var result: [String: String] = [:]
        var key = ""
        var value = ""
        var inKey = true
        var inQuotes = false
        for ch in s {
            if inKey {
                if ch == "=" { inKey = false } else if ch != "," { key.append(ch) }
                continue
            }
            if ch == "\"" { inQuotes.toggle(); continue }
            if ch == "," && !inQuotes {
                result[key.trimmingCharacters(in: .whitespaces).uppercased()] = value
                key = ""
                value = ""
                inKey = true
                continue
            }
            value.append(ch)
        }
        if !key.isEmpty { result[key.trimmingCharacters(in: .whitespaces).uppercased()] = value }
        return result
    }

    static func resolve(_ raw: String, base: URL) -> URL? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let u = URL(string: t, relativeTo: base) { return u.absoluteURL }
        if let encoded = t.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let u = URL(string: encoded, relativeTo: base) { return u.absoluteURL }
        return nil
    }

    static func variants(in text: String, base: URL) -> [HLSVariant] {
        var out: [HLSVariant] = []
        var pending: [String: String]?
        let tag = "#EXT-X-STREAM-INF:"
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix(tag) {
                pending = attributes(line.dropFirst(tag.count))
            } else if line.hasPrefix("#") {
                continue
            } else if let attrs = pending {
                if let u = resolve(line, base: base) {
                    // BANDWIDTH 우선 (AVERAGE-BANDWIDTH 와 혼동하지 않음 — 정확한 키로 조회)
                    let bw = Int(attrs["BANDWIDTH"] ?? "") ?? Int(attrs["AVERAGE-BANDWIDTH"] ?? "") ?? 0
                    out.append(HLSVariant(url: u, bandwidth: bw, audioGroup: attrs["AUDIO"]))
                }
                pending = nil
            }
        }
        return out
    }

    static func audioRenditionURL(in text: String, group: String, base: URL) -> URL? {
        var fallback: URL?
        let tag = "#EXT-X-MEDIA:"
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(tag) else { continue }
            let a = attributes(line.dropFirst(tag.count))
            guard a["TYPE"] == "AUDIO", a["GROUP-ID"] == group,
                  let uri = a["URI"], let u = resolve(uri, base: base) else { continue }
            if a["DEFAULT"] == "YES" { return u }
            if fallback == nil { fallback = u }
        }
        return fallback
    }

    static func mediaPlaylist(_ text: String, base: URL) throws -> HLSMediaPlaylistInfo {
        var info = HLSMediaPlaylistInfo()
        var mediaSequence = 0
        var position = 0
        var currentKey: HLSKeyInfo?
        var pendingRange: (length: Int64, offset: Int64?)?
        var lastRangeEnd: [URL: Int64] = [:]
        var maps: Set<String> = []

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                let v = line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count).trimmingCharacters(in: .whitespaces)
                mediaSequence = Int(v) ?? 0
            } else if line.hasPrefix("#EXT-X-KEY:") {
                let a = attributes(line.dropFirst("#EXT-X-KEY:".count))
                let method = (a["METHOD"] ?? "NONE").uppercased()
                if method == "NONE" {
                    currentKey = nil
                } else {
                    currentKey = HLSKeyInfo(method: method,
                                            uri: a["URI"].flatMap { resolve($0, base: base) },
                                            iv: a["IV"].flatMap { hexIV($0) },
                                            keyFormat: a["KEYFORMAT"])
                }
            } else if line.hasPrefix("#EXT-X-MAP:") {
                let a = attributes(line.dropFirst("#EXT-X-MAP:".count))
                guard let uri = a["URI"], let u = resolve(uri, base: base) else {
                    throw HLSError.malformed("EXT-X-MAP 에 URI 가 없습니다")
                }
                let range = a["BYTERANGE"].flatMap { parseByteRange($0) }
                    .map { HLSByteRange(length: $0.length, offset: $0.offset ?? 0) }
                maps.insert(u.absoluteString + (range.map { "@\($0.offset)" } ?? ""))
                if info.initSegment == nil {
                    info.initSegment = HLSSegmentInfo(index: -1, url: u, range: range, key: currentKey, sequence: mediaSequence)
                }
            } else if line.hasPrefix("#EXT-X-BYTERANGE:") {
                pendingRange = parseByteRange(String(line.dropFirst("#EXT-X-BYTERANGE:".count)))
            } else if line.hasPrefix("#EXT-X-ENDLIST") {
                info.hasEndList = true
            } else if line.hasPrefix("#") {
                continue
            } else {
                guard let u = resolve(line, base: base) else { continue }
                var range: HLSByteRange?
                if let pr = pendingRange {
                    let offset = pr.offset ?? lastRangeEnd[u] ?? 0
                    range = HLSByteRange(length: pr.length, offset: offset)
                    lastRangeEnd[u] = offset + pr.length
                    pendingRange = nil
                }
                info.segments.append(HLSSegmentInfo(index: info.segments.count, url: u, range: range,
                                                    key: currentKey, sequence: mediaSequence + position))
                position += 1
            }
        }
        if maps.count > 1 {
            throw HLSError.unsupported("구간마다 초기화 섹션(EXT-X-MAP)이 바뀌는 스트림은 지원하지 않습니다")
        }
        return info
    }

    static func checkEncryptionSupported(_ playlist: HLSMediaPlaylistInfo) throws {
        let keys = (playlist.segments.compactMap { $0.key }) + (playlist.initSegment?.key.map { [$0] } ?? [])
        for key in keys {
            let format = key.keyFormat?.lowercased() ?? "identity"
            guard key.method == "AES-128", format == "identity" else {
                throw HLSError.unsupported("DRM/SAMPLE-AES 암호화 영상은 지원하지 않습니다 (METHOD=\(key.method))")
            }
            guard let uri = key.uri, ["http", "https"].contains(uri.scheme?.lowercased() ?? "") else {
                throw HLSError.unsupported("암호화 키 주소를 사용할 수 없습니다")
            }
        }
    }

    static func parseByteRange(_ s: String) -> (length: Int64, offset: Int64?)? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: "@")
        guard let first = parts.first, let length = Int64(first), length > 0 else { return nil }
        let offset = parts.count > 1 ? Int64(parts[1]) : nil
        return (length, offset)
    }

    /// IV=0x... → 16바이트 (짧으면 앞쪽 0 패딩)
    static func hexIV(_ s: String) -> Data? {
        var hex = s.trimmingCharacters(in: .whitespaces).lowercased()
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        if hex.count % 2 == 1 { hex = "0" + hex }
        var bytes: [UInt8] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        if bytes.count < 16 { bytes = [UInt8](repeating: 0, count: 16 - bytes.count) + bytes }
        return bytes.count == 16 ? Data(bytes) : nil
    }

    /// IV 미지정 시: 미디어 시퀀스 번호(빅엔디언 128bit)
    static func ivFromSequence(_ n: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        var v = UInt64(truncatingIfNeeded: n)
        for i in 0..<8 {
            bytes[15 - i] = UInt8(v & 0xFF)
            v >>= 8
        }
        return Data(bytes)
    }
}

enum HLSCrypto {
    static func aes128CBCDecrypt(_ data: Data, key: Data, iv: Data) -> Data? {
        guard key.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128, !data.isEmpty else { return nil }
        let capacity = data.count + kCCBlockSizeAES128
        var out = Data(count: capacity)
        var moved = 0
        let status: CCCryptorStatus = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyPtr.baseAddress, kCCKeySizeAES128, ivPtr.baseAddress,
                                inPtr.baseAddress, data.count, outPtr.baseAddress, capacity, &moved)
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess) else { return nil }
        out.removeSubrange(moved..<out.count)
        return out
    }
}

/// 키는 세그먼트마다 다시 받지 않는다 (같은 URI 캐시)
actor HLSKeyCache {
    private var cache: [URL: Data] = [:]

    func key(for url: URL, fetch: @Sendable () async throws -> Data) async throws -> Data {
        if let k = cache[url] { return k }
        let k = try await fetch()
        guard k.count == 16 else {
            throw HLSError.unsupported("암호화 키 형식이 올바르지 않습니다 (\(k.count)바이트)")
        }
        cache[url] = k
        return k
    }
}

/// 진행률 카운터 (downloadSegments 의 순차 쓰기 루프에서만 접근)
final class HLSProgressCounter: @unchecked Sendable {
    private let total: Int
    private var done = 0
    private var bytes: Int64 = 0

    init(total: Int) { self.total = max(total, 1) }

    func advance(bytes count: Int) -> (progress: Double, bytes: Int64) {
        done += 1
        bytes += Int64(count)
        return (min(1, Double(done) / Double(total)), bytes)
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

    // 내부 처리용
    @ObservationIgnored var engine: Engine = .urlSession
    @ObservationIgnored var resumeData: Data?
    @ObservationIgnored var avAssetAttempted = false
    @ObservationIgnored var hlsGeneration = 0

    init(media: DetectedMedia, saveToVault: Bool) {
        self.media = media
        self.saveToVault = saveToVault
    }

    var hlsConversionStatus: String?
    var savedAssetID: String? // ★ 갤러리 저장 시 PHAsset localIdentifier (정확한 삭제용)

    /// 진행 중 목록 UI 가 이 문자열만 표시하므로 실패/대기/일시정지도 여기서 드러낸다
    var formattedProgress: String {
        switch state {
        case .converting: return "변환 중..."
        case .pending: return "대기 중"
        case .paused: return "일시정지 \(Int(progress * 100))%"
        case .failed: return "실패: \(error ?? "알 수 없는 오류")"
        case .cancelled: return "취소됨"
        default: return "\(Int(progress * 100))%"
        }
    }
    var formattedSpeed: String {
        guard state == .downloading else { return "" }
        let elapsed = Date.now.timeIntervalSince(startDate)
        guard elapsed > 0, bytesDownloaded > 0 else { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(Double(bytesDownloaded) / elapsed), countStyle: .file) + "/s"
    }

    enum DownloadState: String {
        case pending, downloading, paused, converting, completed, failed, cancelled
    }

    enum Engine {
        case urlSession, hls, avAsset, webKit
    }
}
