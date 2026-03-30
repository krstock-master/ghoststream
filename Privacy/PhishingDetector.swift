// Privacy/PhishingDetector.swift
// GhostStream — 규칙 기반 피싱/악성 URL 탐지 (Phase 1: 서버 통신 없음)
import Foundation

enum PhishingRisk: String {
    case safe = "safe"
    case suspicious = "suspicious"
    case phishing = "phishing"
}

final class PhishingDetector {
    static let shared = PhishingDetector()

    // 의심 TLD 목록
    private let suspiciousTLDs: Set<String> = [
        "xyz", "top", "club", "info", "online", "site", "website",
        "space", "fun", "icu", "buzz", "gq", "ml", "tk", "cf", "ga",
        "pw", "cam", "click", "link", "work", "rest", "fit", "surf"
    ]

    // 피싱에 자주 사용되는 키워드
    private let phishingKeywords: [String] = [
        "login", "signin", "sign-in", "verify", "verification",
        "secure", "security", "account", "update", "confirm",
        "banking", "paypal", "wallet", "password", "credential",
        "suspended", "unusual", "restrict", "locked", "alert"
    ]

    // 정상 대형 사이트 (화이트리스트)
    private let trustedDomains: Set<String> = [
        "google.com", "youtube.com", "facebook.com", "twitter.com", "x.com",
        "instagram.com", "naver.com", "daum.net", "kakao.com",
        "apple.com", "microsoft.com", "github.com", "amazon.com",
        "reddit.com", "wikipedia.org", "stackoverflow.com",
        "netflix.com", "twitch.tv", "linkedin.com", "tiktok.com",
        "challenges.cloudflare.com", "cloudflare.com"
    ]

    /// URL 위험도 판별 (완전 로컬, 비동기 불필요)
    func assess(_ url: URL) -> PhishingRisk {
        guard let host = url.host?.lowercased() else { return .safe }
        let fullURL = url.absoluteString.lowercased()

        // 1. 화이트리스트 검사
        for domain in trustedDomains {
            if host == domain || host.hasSuffix(".\(domain)") {
                return .safe
            }
        }

        var score = 0

        // 2. 의심 TLD 검사
        let tld = host.components(separatedBy: ".").last ?? ""
        if suspiciousTLDs.contains(tld) { score += 2 }

        // 3. IP 주소 사용 여부
        let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
        if host.range(of: ipPattern, options: .regularExpression) != nil { score += 3 }

        // 4. 과도한 서브도메인 (3개 이상)
        let subdomainCount = host.components(separatedBy: ".").count
        if subdomainCount > 3 { score += 1 }
        if subdomainCount > 5 { score += 2 }

        // 5. 피싱 키워드 검사 (URL path에서)
        let path = url.path.lowercased()
        var keywordHits = 0
        for keyword in phishingKeywords {
            if path.contains(keyword) || host.contains(keyword) {
                keywordHits += 1
            }
        }
        if keywordHits >= 2 { score += 2 }
        if keywordHits >= 3 { score += 2 }

        // 6. URL 길이 과도 (100자 이상)
        if fullURL.count > 100 { score += 1 }
        if fullURL.count > 200 { score += 1 }

        // 7. @ 기호 사용 (URL 난독화)
        if fullURL.contains("@") { score += 3 }

        // 8. 대중 브랜드 사칭 검사
        let brandMimicry = ["paypal", "apple", "google", "facebook", "microsoft",
                            "netflix", "amazon", "kakao", "naver", "samsung"]
        for brand in brandMimicry {
            // 브랜드명이 호스트에 있지만 공식 도메인이 아닌 경우
            if host.contains(brand) && !host.hasSuffix("\(brand).com") &&
               !host.hasSuffix("\(brand).net") && !host.hasSuffix("\(brand).co.kr") {
                score += 3
            }
        }

        // 9. 특수문자 과다 (하이픈 4개 이상)
        if host.filter({ $0 == "-" }).count >= 4 { score += 2 }

        // 10. 도메인 엔트로피 (랜덤 문자열 감지)
        let domainPart = host.components(separatedBy: ".").first ?? ""
        if domainPart.count > 15 {
            let consonants = domainPart.filter { !"aeiou0123456789-_.".contains($0) }
            let ratio = Double(consonants.count) / Double(domainPart.count)
            if ratio > 0.7 { score += 2 } // 자음 비율 높으면 랜덤 문자열 가능성
        }

        // 판정
        if score >= 5 { return .phishing }
        if score >= 3 { return .suspicious }
        return .safe
    }
}
