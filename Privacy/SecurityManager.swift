// Privacy/SecurityManager.swift
// GhostStream - Jailbreak detection + Certificate Pinning + Security hardening

import Foundation
import UIKit
import Security

// MARK: - Jailbreak Detection
enum JailbreakDetector {

    /// 포괄적인 탈옥 감지 (6단계 검증)
    static var isJailbroken: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return checkSuspiciousPaths()
            || checkSuspiciousApps()
            || checkWriteAccess()
            || checkSymbolicLinks()
            || checkDylibs()
            || checkFork()
        #endif
    }

    // 1. Cydia/Sileo 등 탈옥 앱 경로 확인
    private static func checkSuspiciousPaths() -> Bool {
        let paths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/usr/bin/ssh",
            "/var/cache/apt",
            "/var/lib/cydia",
            "/var/log/syslog",
            "/usr/libexec/cydia",
            "/private/var/stash",
            "/private/var/mobile/Library/SBSettings/Themes",
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    // 2. URL scheme으로 탈옥 앱 설치 확인
    private static func checkSuspiciousApps() -> Bool {
        let schemes = [
            "cydia://package/com.example.package",
            "sileo://package/com.example.package",
            "zbra://packages/com.example.package",
            "filza://",
        ]
        return schemes.contains { url in
            guard let u = URL(string: url) else { return false }
            return UIApplication.shared.canOpenURL(u)
        }
    }

    // 3. 시스템 디렉토리 쓰기 권한 확인
    private static func checkWriteAccess() -> Bool {
        let testPath = "/private/jailbreak_test_\(UUID().uuidString)"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true // 쓰기 가능 = 탈옥
        } catch {
            return false
        }
    }

    // 4. 심볼릭 링크 확인
    private static func checkSymbolicLinks() -> Bool {
        let paths = ["/var/lib/undecimus/apt", "/Applications", "/Library/Ringtones", "/Library/Wallpaper"]
        return paths.contains { path in
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            return attrs?[.type] as? FileAttributeType == .typeSymbolicLink
        }
    }

    // 5. 주입된 dylib 확인
    private static func checkDylibs() -> Bool {
        let suspiciousLibs = ["SubstrateLoader", "SubstrateInserter", "SubstrateBootstrap",
                              "MobileSubstrate", "TweakInject", "libhooker", "substitute"]
        let count = _dyld_image_count()
        for i in 0..<count {
            if let name = _dyld_get_image_name(i) {
                let imageName = String(cString: name)
                if suspiciousLibs.contains(where: { imageName.contains($0) }) {
                    return true
                }
            }
        }
        return false
    }

    // 6. fork() 시스템 콜 확인 (sandbox 우회)
    private static func checkFork() -> Bool {
        let pid = fork()
        if pid >= 0 {
            // fork 성공 = sandbox 미적용 = 탈옥
            if pid > 0 { kill(pid, SIGTERM) }
            return true
        }
        return false
    }
}

// MARK: - Certificate Pinning Manager
final class CertificatePinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {

    /// 고정할 도메인별 공개키 해시 (SHA-256 base64)
    private let pinnedHashes: [String: [String]] = [
        // GhostStream API 서버 (실제 배포 시 교체)
        "api.ghoststream.io": [
            "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",  // Primary pin
            "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=",  // Backup pin
        ],
        // VPN config 서버
        "vpn.ghoststream.io": [
            "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD=",
        ],
    ]

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?)
    {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let pinnedKeys = pinnedHashes[challenge.protectionSpace.host] else {
            return (.performDefaultHandling, nil)
        }

        // TLS 인증서 체인 검증
        var secResult = SecTrustResultType.invalid
        SecTrustEvaluate(serverTrust, &secResult)
        guard secResult == .unspecified || secResult == .proceed else {
            return (.cancelAuthenticationChallenge, nil)
        }

        // 공개키 해시 비교
        let certCount = SecTrustGetCertificateCount(serverTrust)
        for i in 0..<certCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, i) else { continue }
            let publicKeyData = SecCertificateCopyData(certificate) as Data

            // SHA-256 해시 계산
            var hash = [UInt8](repeating: 0, count: 32)
            publicKeyData.withUnsafeBytes { ptr in
                _ = CC_SHA256(ptr.baseAddress, CC_LONG(publicKeyData.count), &hash)
            }
            let hashBase64 = Data(hash).base64EncodedString()

            if pinnedKeys.contains(hashBase64) {
                return (.useCredential, URLCredential(trust: serverTrust))
            }
        }

        // 핀 매치 실패 → 연결 거부
        return (.cancelAuthenticationChallenge, nil)
    }
}

// CC_SHA256 bridge
import CommonCrypto

// MARK: - Network Security Configuration
enum NetworkSecurity {

    /// Pinning이 적용된 URLSession 생성
    static func makePinnedSession(identifier: String? = nil) -> URLSession {
        let config: URLSessionConfiguration
        if let id = identifier {
            config = .background(withIdentifier: id)
        } else {
            config = .default
        }
        return URLSession(configuration: config, delegate: CertificatePinningDelegate(), delegateQueue: nil)
    }

    /// HTTP URL 경고 (ATS AllowsArbitraryLoads 보완)
    static func isInsecure(url: URL) -> Bool {
        return url.scheme == "http"
    }
}
