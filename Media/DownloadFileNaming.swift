// Media/DownloadFileNaming.swift
// GhostStream - 다운로드 파일명 결정 / 중복 회피 / 응답 검증 공용 헬퍼
// (URLSession 경로와 WKDownload 경로가 같은 규칙을 쓰도록 한 곳에 모음)

import Foundation
import UniformTypeIdentifiers

enum DownloadFileNaming {

    // MARK: - Content-Disposition (RFC 6266 / RFC 5987)

    /// Content-Disposition 헤더에서 파일명 추출. filename*(RFC 5987, UTF-8 한글 등)을 filename보다 우선한다.
    static func filename(fromContentDisposition header: String) -> String? {
        let params = parameters(of: header)
        if let ext = params["filename*"], let decoded = decodeRFC5987(ext), !decoded.isEmpty {
            return decoded
        }
        if let plain = params["filename"], !plain.isEmpty {
            var name = plain
            if name.contains("%"), let decoded = name.removingPercentEncoding { name = decoded }
            return repairLatin1Mojibake(name)
        }
        return nil
    }

    /// `attachment; filename="a;b.zip"; filename*=UTF-8''%ED%95%9C.zip` → 소문자 키 딕셔너리 (따옴표 안의 ; 는 구분자로 보지 않음)
    private static func parameters(of header: String) -> [String: String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        for ch in header {
            if escaped { current.append(ch); escaped = false; continue }
            if ch == "\\" && inQuotes { escaped = true; continue }
            if ch == "\"" { inQuotes.toggle(); current.append(ch); continue }
            if ch == ";" && !inQuotes { parts.append(current); current = ""; continue }
            current.append(ch)
        }
        parts.append(current)

        var result: [String: String] = [:]
        for part in parts {
            guard let eq = part.firstIndex(of: "=") else { continue }
            let key = part[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var value = part[part.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            if result[key] == nil { result[key] = value }
        }
        return result
    }

    /// RFC 5987: charset'lang'pct-encoded
    private static func decodeRFC5987(_ value: String) -> String? {
        let pieces = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        guard pieces.count == 3 else { return value.removingPercentEncoding }
        let charset = pieces[0].lowercased()
        let encoded = String(pieces[2])
        if charset == "utf-8" || charset.isEmpty {
            return encoded.removingPercentEncoding
        }
        guard let bytes = percentDecodedBytes(encoded) else { return nil }
        let encoding: String.Encoding = (charset == "iso-8859-1" || charset == "latin1") ? .isoLatin1 : .utf8
        return String(data: Data(bytes), encoding: encoding)
    }

    private static func percentDecodedBytes(_ s: String) -> [UInt8]? {
        let src = Array(s.utf8)
        var out: [UInt8] = []
        var i = 0
        while i < src.count {
            if src[i] == 0x25 { // '%'
                guard i + 2 < src.count,
                      let hex = String(bytes: src[(i + 1)...(i + 2)], encoding: .ascii),
                      let b = UInt8(hex, radix: 16) else { return nil }
                out.append(b)
                i += 3
            } else {
                out.append(src[i])
                i += 1
            }
        }
        return out
    }

    /// CFNetwork/WebKit은 헤더의 비ASCII 바이트를 Latin-1로 해석한다.
    /// RFC를 지키지 않고 raw UTF-8 한글을 filename= 에 넣는 서버가 많아 "í\u{95}\u{9c}..." 처럼 깨지므로 복원한다.
    static func repairLatin1Mojibake(_ s: String) -> String {
        let scalars = s.unicodeScalars
        guard scalars.contains(where: { $0.value >= 0x80 }),
              scalars.allSatisfy({ $0.value <= 0xFF }) else { return s }
        let bytes = scalars.map { UInt8($0.value) }
        return String(data: Data(bytes), encoding: .utf8) ?? s
    }

    // MARK: - Sanitize

    /// 경로 성분·제어문자·금지문자 제거, 숨김파일 방지, UTF-8 바이트 길이 제한(확장자 보존)
    static func sanitize(_ raw: String, maxBytes: Int = 200) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last {
            name = String(last)
        }
        let illegal = CharacterSet(charactersIn: ":/\\?*|\"<>").union(.controlCharacters).union(.newlines)
        name = name.unicodeScalars.map { illegal.contains($0) ? "_" : String($0) }.joined()
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "download" }

        if name.utf8.count > maxBytes {
            var ext = (name as NSString).pathExtension
            if ext.utf8.count > 16 { ext = "" }
            var base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
            let extBytes = ext.isEmpty ? 0 : ext.utf8.count + 1
            while base.utf8.count + extBytes > maxBytes && !base.isEmpty { base.removeLast() }
            if base.isEmpty { base = "download" }
            name = ext.isEmpty ? base : base + "." + ext
        }
        return name
    }

    // MARK: - MIME → extension

    static func preferredExtension(forMIME mime: String?) -> String? {
        guard let raw = mime?.lowercased().split(separator: ";").first else { return nil }
        let m = raw.trimmingCharacters(in: .whitespaces)
        guard !m.isEmpty else { return nil }
        switch m {
        case "application/octet-stream", "binary/octet-stream", "application/force-download",
             "application/x-download", "application/download", "application/unknown":
            return nil
        case "video/mp4": return "mp4"
        case "video/mp2t": return "ts"
        case "video/quicktime": return "mov"
        case "video/x-m4v": return "m4v"
        case "video/webm": return "webm"
        case "video/mpeg": return "mpg"
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/mp4", "audio/x-m4a", "audio/m4a": return "m4a"
        case "audio/aac": return "aac"
        case "image/jpeg", "image/jpg", "image/pjpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/avif": return "avif"
        case "image/heic", "image/heif": return "heic"
        case "application/pdf": return "pdf"
        case "application/zip", "application/x-zip-compressed": return "zip"
        case "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "audio/x-mpegurl": return "m3u8"
        case "application/x-hwp", "application/haansofthwp", "application/vnd.hancom.hwp": return "hwp"
        default:
            return UTType(mimeType: m)?.preferredFilenameExtension
        }
    }

    /// 이름에 그럴듯한 확장자가 없으면 MIME → URL 순으로 확장자를 붙인다
    static func ensureExtension(_ name: String, mime: String?, sourceURL: URL?) -> String {
        let current = (name as NSString).pathExtension
        if !current.isEmpty, current.count <= 5, current.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return name
        }
        let urlExt = sourceURL?.pathExtension.lowercased() ?? ""
        let validURLExt = !urlExt.isEmpty && urlExt.count <= 5 && urlExt.allSatisfy({ $0.isLetter || $0.isNumber })
        if let ext = preferredExtension(forMIME: mime) ?? (validURLExt ? urlExt : nil) {
            return name + "." + ext
        }
        return name
    }

    /// 최종 파일명 결정 규칙 (두 다운로드 경로 공통)
    ///  1) Content-Disposition (filename* 우선)  2) preferTitle이면 페이지 제목
    ///  3) 시스템 suggestedFilename  4) URL 마지막 경로  5) 제목/“download”
    static func resolveFilename(response: URLResponse?, suggested: String?, title: String,
                                sourceURL: URL?, preferTitle: Bool) -> String {
        var candidate: String?
        if let cd = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") {
            candidate = filename(fromContentDisposition: cd)
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate == nil, preferTitle, !cleanTitle.isEmpty {
            candidate = String(cleanTitle.prefix(80))
        }
        if candidate == nil, let s = suggested, !s.isEmpty, s.lowercased() != "unknown" {
            candidate = repairLatin1Mojibake(s)
        }
        if candidate == nil, let last = sourceURL?.lastPathComponent, !last.isEmpty, last != "/" {
            candidate = last.removingPercentEncoding ?? last
        }
        if candidate == nil {
            candidate = cleanTitle.isEmpty ? "download" : String(cleanTitle.prefix(80))
        }
        let named = ensureExtension(candidate ?? "download", mime: response?.mimeType, sourceURL: sourceURL)
        return sanitize(named)
    }

    // MARK: - Unique destination (덮어쓰기 금지)

    private static let reservationLock = NSLock()
    private static var reserved: Set<String> = []

    /// 같은 이름이 있으면 "이름 (1).ext" 형태로 비어 있는 경로를 예약한다.
    /// 동시에 시작된 두 다운로드가 같은 경로를 받지 않도록 예약 집합을 둔다. 끝나면 releaseReservation 호출.
    static func reserveUniqueURL(in dir: URL, filename: String) -> URL {
        reservationLock.lock()
        defer { reservationLock.unlock() }
        let fm = FileManager.default
        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        var candidate = dir.appendingPathComponent(filename)
        var n = 1
        while fm.fileExists(atPath: candidate.path) || reserved.contains(candidate.path) {
            let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = dir.appendingPathComponent(name)
            n += 1
        }
        reserved.insert(candidate.path)
        return candidate
    }

    static func releaseReservation(_ url: URL) {
        reservationLock.lock()
        reserved.remove(url.path)
        reservationLock.unlock()
    }

    // MARK: - Response sniffing

    /// 파일 앞부분이 HTML(로그인/오류/CF 페이지)인지 검사 — MIME이 octet-stream으로 위장된 경우 대비
    static func looksLikeHTML(fileAt url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 512), !head.isEmpty else { return false }
        guard let text = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1) else { return false }
        let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
        let t = text.trimmingCharacters(in: trimSet).lowercased()
        return t.hasPrefix("<!doctype html") || t.hasPrefix("<html") || t.hasPrefix("<head")
            || (t.hasPrefix("<?xml") && t.contains("<html"))
    }
}
