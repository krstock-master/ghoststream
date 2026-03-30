// Privacy/ContentBlockerManager.swift
// GhostStream - WKContentRuleList-based tracker/ad blocking
// v2.0: Korean ad networks + CSS element hiding + auto-update

import Foundation
import WebKit

@Observable
final class ContentBlockerManager: @unchecked Sendable {
    var isCompiled: Bool = false
    var ruleCount: Int = 0
    var totalTrackersBlocked: Int = 0
    var totalAdsBlocked: Int = 0
    private var compiledRuleLists: [WKContentRuleList] = []

    init() {
        Task { await compile() }
    }

    // MARK: - Compile Rules

    func compile() async {
        compiledRuleLists.removeAll()
        var totalRules = 0

        // 1. Main ad blocking rules (global + Korean)
        let mainRules = Self.globalAdRules + Self.koreanAdRules
        if let list = await compileRuleList(id: "ghoststream.main", rules: mainRules) {
            compiledRuleLists.append(list)
            totalRules += mainRules.count
        }

        // 2. CSS Element Hiding rules (Korean sites)
        let cssRules = Self.koreanCSSHidingRules
        if let list = await compileRuleList(id: "ghoststream.css", rules: cssRules) {
            compiledRuleLists.append(list)
            totalRules += cssRules.count
        }

        // 3. Tracker blocking
        let trackerRules = Self.trackerRules
        if let list = await compileRuleList(id: "ghoststream.trackers", rules: trackerRules) {
            compiledRuleLists.append(list)
            totalRules += trackerRules.count
        }

        // 4. Third-party cookie blocking
        let cookieRules = Self.cookieRules
        if let list = await compileRuleList(id: "ghoststream.cookies", rules: cookieRules) {
            compiledRuleLists.append(list)
            totalRules += cookieRules.count
        }

        // 5. Load cached remote rules if available
        if let cachedRules = loadCachedRemoteRules(),
           let list = await compileRuleList(id: "ghoststream.remote", rules: cachedRules) {
            compiledRuleLists.append(list)
            totalRules += cachedRules.count
        }

        ruleCount = totalRules
        isCompiled = !compiledRuleLists.isEmpty
    }

    private func compileRuleList(id: String, rules: [[String: Any]]) async -> WKContentRuleList? {
        guard !rules.isEmpty else { return nil }
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: rules)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
            return try await WKContentRuleListStore.default()
                .compileContentRuleList(forIdentifier: id, encodedContentRuleList: jsonString)
        } catch {
            print("[ContentBlocker] Compilation failed for \(id): \(error)")
            return nil
        }
    }

    /// Apply compiled rules to a WKUserContentController
    func applyRules(to controller: WKUserContentController) async {
        if !isCompiled { await compile() }
        for list in compiledRuleLists {
            controller.add(list)
        }
    }

    /// Synchronously apply cached rules (call after initial compile)
    func applyCachedRules(to controller: WKUserContentController) {
        for list in compiledRuleLists {
            controller.add(list)
        }
    }

    // MARK: - Remote Rule Update

    func downloadLatestRules() async {
        // Download List-KR flat version (compatible with basic adblock syntax)
        let listKRURL = URL(string: "https://raw.githubusercontent.com/AuTumns8585/AuTumns-Filters/main/Filters/AuTumns-iOS-Safari-Filter.txt")!

        do {
            let (data, _) = try await URLSession.shared.data(from: listKRURL)
            if let text = String(data: data, encoding: .utf8) {
                let rules = convertABPToWebKitRules(text: text, maxRules: 3000)
                if !rules.isEmpty {
                    cacheRemoteRules(rules)
                }
            }
        } catch {
            print("[ContentBlocker] Remote update failed: \(error)")
        }

        await compile()
    }

    private func convertABPToWebKitRules(text: String, maxRules: Int) -> [[String: Any]] {
        var rules: [[String: Any]] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            guard rules.count < maxRules else { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("[") { continue }

            // ||domain^ pattern → URL block
            if trimmed.hasPrefix("||") && trimmed.hasSuffix("^") {
                let domain = String(trimmed.dropFirst(2).dropLast(1))
                    .replacingOccurrences(of: ".", with: "\\\\.")
                rules.append([
                    "trigger": ["url-filter": domain],
                    "action": ["type": "block"]
                ])
            }
            // ##.class or ##selector → CSS hiding (global)
            else if let range = trimmed.range(of: "##") {
                let selector = String(trimmed[range.upperBound...])
                if !selector.isEmpty && !selector.contains(":") {
                    let domainPart = String(trimmed[..<range.lowerBound])
                    var trigger: [String: Any] = ["url-filter": ".*"]
                    if !domainPart.isEmpty {
                        let domains = domainPart.components(separatedBy: ",").map { "*\($0)" }
                        trigger["if-domain"] = domains
                    }
                    rules.append([
                        "trigger": trigger,
                        "action": ["type": "css-display-none", "selector": selector]
                    ])
                }
            }
        }
        return rules
    }

    private func cacheRemoteRules(_ rules: [[String: Any]]) {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let dest = cacheDir.appendingPathComponent("remote_rules.json")
        if let data = try? JSONSerialization.data(withJSONObject: rules) {
            try? data.write(to: dest)
            UserDefaults.standard.set(Date(), forKey: "filterLastUpdate")
        }
    }

    private func loadCachedRemoteRules() -> [[String: Any]]? {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let path = cacheDir.appendingPathComponent("remote_rules.json")
        guard let data = try? Data(contentsOf: path),
              let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return rules
    }

    // MARK: - Global Ad Network Rules
    static let globalAdRules: [[String: Any]] = [
        // Google Ads
        ["trigger": ["url-filter": "googlesyndication\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "doubleclick\\.net"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "adservice\\.google"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "pagead2\\.googlesyndication"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "googleadservices\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "google-analytics\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "googletagmanager\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "googletagservices\\.com"], "action": ["type": "block"]],
        // Facebook
        ["trigger": ["url-filter": "connect\\.facebook\\.net"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "facebook\\.com/tr"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "pixel\\.facebook\\.com"], "action": ["type": "block"]],
        // Common ad networks
        ["trigger": ["url-filter": "ads\\.yahoo\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "advertising\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "adsrvr\\.org"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "criteo\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "taboola\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "outbrain\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "moatads\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "amazon-adsystem\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "adnxs\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "rubiconproject\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "pubmatic\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "openx\\.net"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "casalemedia\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "sharethrough\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "bidswitch\\.net"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "smartadserver\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "serving-sys\\.com"], "action": ["type": "block"]],
    ]

    // MARK: - Korean Ad Network & Site-Specific Rules
    static let koreanAdRules: [[String: Any]] = [
        // DCInside ads
        ["trigger": ["url-filter": "ad\\.dcinside\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "nstatic\\.dcinside\\.com.*\\/ad\\/"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "dcad\\.dcinside\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "ad-img\\.dcinside\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "addc\\.dcinside\\.com"], "action": ["type": "block"]],
        // Kakao/Daum ads
        ["trigger": ["url-filter": "t1\\.daumcdn\\.net/kas"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "adfit\\.kakao\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "track\\.kakao\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "kpd\\.kakao\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "display\\.ad\\.daum\\.net"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "ad\\.daum\\.net"], "action": ["type": "block"]],
        // Naver ads
        ["trigger": ["url-filter": "siape\\.veta\\.naver\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "adcreative\\.naver\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "adsearch\\.naver\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "ad\\.naver\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "displayad\\.naver\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "nstat\\.naver\\.com"], "action": ["type": "block"]],
        // Coupang ads
        ["trigger": ["url-filter": "ads\\.coupang\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "coupa\\.ng/ads"], "action": ["type": "block"]],
        // Korean ad networks
        ["trigger": ["url-filter": "ad\\.capri\\.io"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "adbrix\\.io"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "adpopcorn\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "cauly\\.net"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "mobon\\.net"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "daumdn\\.com.*ad"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "realclick\\.co\\.kr"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "admixer\\.co\\.kr"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "mediaad\\.co\\.kr"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "ad-shield\\.io"], "action": ["type": "block"]],
        // Korean trackers
        ["trigger": ["url-filter": "wcs\\.naver\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "lcs\\.naver\\.com"], "action": ["type": "block"]],
    ]

    // MARK: - Korean CSS Element Hiding (css-display-none)
    static let koreanCSSHidingRules: [[String: Any]] = [
        // DCInside — comprehensive ad element hiding
        ["trigger": ["url-filter": ".*", "if-domain": ["*dcinside.com"]],
         "action": ["type": "css-display-none",
                     "selector": ".ad_bottom_list, .ad-banner, #dcAd, .adcenter, .ad-area, .listwrap .ad, .appending_promo, .btn_admovie, .adv-box, .ad_wrapper, .ad-box, .inner_ad, .dcfoot_ad, .dc_ad, .brand-ad, .ad_in_article, .pop_wrap, .ad_center_list, .ad_interscroller, .ad_bnr"]],
        // DCInside iframe ads
        ["trigger": ["url-filter": ".*", "if-domain": ["*dcinside.com"]],
         "action": ["type": "css-display-none",
                     "selector": "iframe[src*='ad.'], iframe[src*='doubleclick'], iframe[src*='googlesyndication'], iframe[src*='adfit'], div[id*='google_ads'], div[class*='ad-'], div[id*='ad-'], ins.adsbygoogle"]],
        // Naver
        ["trigger": ["url-filter": ".*", "if-domain": ["*naver.com"]],
         "action": ["type": "css-display-none",
                     "selector": ".ad_area, .ad_box, .tbl_ad, .ad_spot, #veta_top, #veta_bottom, .sc_ad, ._ad_area, .ad_on_content, .spi_lst, div[class*='sc_ad'], iframe[src*='adcreative']"]],
        // Daum
        ["trigger": ["url-filter": ".*", "if-domain": ["*daum.net"]],
         "action": ["type": "css-display-none",
                     "selector": ".ad_wrap, .ad_item, #mAd, .ad_box, .adfit_container, div[id*='kakaoAdFit'], .article_ad, #dkAdArea"]],
        // Global — common ad containers
        ["trigger": ["url-filter": ".*"],
         "action": ["type": "css-display-none",
                     "selector": "ins.adsbygoogle, div[id^='div-gpt-ad'], div[class*='ad-container'], div[class*='ad-wrapper'], .sponsored-content, div[data-ad], iframe[src*='doubleclick.net']"]],
    ]

    // MARK: - Tracker Rules
    static let trackerRules: [[String: Any]] = [
        ["trigger": ["url-filter": "scorecardresearch\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "quantserve\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "hotjar\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "mixpanel\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "segment\\.io"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "amplitude\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "fingerprintjs\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "cdn\\.jsdelivr\\.net.*fingerprint"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "clarity\\.ms"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "fullstory\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "mouseflow\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "newrelic\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "appsflyer\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "adjust\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "branch\\.io"], "action": ["type": "block"]],
    ]

    // MARK: - Cookie Rules
    static let cookieRules: [[String: Any]] = [
        ["trigger": ["url-filter": ".*", "load-type": ["third-party"], "resource-type": ["raw"]],
         "action": ["type": "block-cookies"]],
    ]
}
