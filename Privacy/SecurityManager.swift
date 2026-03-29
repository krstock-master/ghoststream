// Privacy/SecurityManager.swift
// GhostStream - Jailbreak detection + Certificate Pinning

import Foundation
import UIKit
import Security
import CommonCrypto

// MARK: - Jailbreak Detection
enum JailbreakDetector {

    static var isJailbroken: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return checkSuspiciousPaths()
            || checkSuspiciousApps()
            || checkWriteAccess()
            || checkDylibs()
        #endif
    }

    private static func checkSuspiciousPaths() -> Bool {
        let paths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/usr/bin/ssh",
            "/var/lib/cydia",
            "/private/var/stash",
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static func checkSuspiciousApps() -> Bool {
        let schemes = ["cydia://", "sileo://", "zbra://", "filza://"]
        return schemes.contains { scheme in
            guard let u = URL(string: scheme) else { return false }
            return UIApplication.shared.canOpenURL(u)
        }
    }

    private static func checkWriteAccess() -> Bool {
        let testPath = "/private/jailbreak_test_\(UUID().uuidString)"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            return false
        }
    }

    private static func checkDylibs() -> Bool {
        let suspiciousLibs = ["SubstrateLoader", "MobileSubstrate", "TweakInject", "libhooker"]
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
}

// MARK: - Certificate Pinning
final class CertificatePinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {

    private let pinnedHashes: [String: [String]] = [
        "api.ghoststream.io": [
            "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",
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

        var secResult = SecTrustResultType.invalid
        SecTrustEvaluate(serverTrust, &secResult)
        guard secResult == .unspecified || secResult == .proceed else {
            return (.cancelAuthenticationChallenge, nil)
        }

        let certCount = SecTrustGetCertificateCount(serverTrust)
        for i in 0..<certCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, i) else { continue }
            let certData = SecCertificateCopyData(certificate) as Data
            var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            certData.withUnsafeBytes { ptr in
                _ = CC_SHA256(ptr.baseAddress, CC_LONG(certData.count), &hash)
            }
            let hashBase64 = Data(hash).base64EncodedString()
            if pinnedKeys.contains(hashBase64) {
                return (.useCredential, URLCredential(trust: serverTrust))
            }
        }
        return (.cancelAuthenticationChallenge, nil)
    }
}

// MARK: - Network Security
enum NetworkSecurity {
    static func makePinnedSession(identifier: String? = nil) -> URLSession {
        let config: URLSessionConfiguration
        if let id = identifier {
            config = .background(withIdentifier: id)
        } else {
            config = .default
        }
        return URLSession(configuration: config, delegate: CertificatePinningDelegate(), delegateQueue: nil)
    }

    static func isInsecure(url: URL) -> Bool {
        return url.scheme == "http"
    }
}
