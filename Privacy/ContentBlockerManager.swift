// Privacy/ContentBlockerManager.swift
// GhostStream - WKContentRuleList-based tracker/ad blocking

import Foundation
import WebKit

@Observable
final class ContentBlockerManager: @unchecked Sendable {
    var isCompiled: Bool = false
    var ruleCount: Int = 0
    private var compiledRuleList: WKContentRuleList?

    // Bundled ruleset identifiers
    private let rulesetNames = [
        "easylist",
        "easyprivacy",
        "ghoststream_custom"
    ]

    init() {
        Task { await compile() }
    }

    // MARK: - Compile Rules

    func compile() async {
        var allRules: [[String: Any]] = []

        // Load from bundled JSON files
        for name in rulesetNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                allRules.append(contentsOf: rules)
            }
        }

        // If no bundled rules, use built-in essential rules
        if allRules.isEmpty {
            allRules = Self.essentialBlockRules
        }

        ruleCount = allRules.count

        // Compile into WKContentRuleList
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: allRules)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"

            compiledRuleList = try await WKContentRuleListStore.default()
                .compileContentRuleList(
                    forIdentifier: "ghoststream.blocklist",
                    encodedContentRuleList: jsonString
                )
            isCompiled = true
        } catch {
            print("[ContentBlocker] Compilation failed: \(error)")
        }
    }

    /// Apply compiled rules to a WKUserContentController
    func applyRules(to controller: WKUserContentController) async {
        if !isCompiled { await compile() }
        if let ruleList = compiledRuleList {
            controller.add(ruleList)
        }
    }

    // MARK: - Background Update

    func scheduleBackgroundUpdate() {
        // BGTaskScheduler registration would go here
        // Updates easylist/easyprivacy from remote
    }

    func downloadLatestRules() async {
        let sources: [String: URL] = [
            "easylist": URL(string: "https://easylist.to/easylist/easylist.txt")!,
            "easyprivacy": URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
        ]

        for (name, url) in sources {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { continue }
                let dest = cacheDir.appendingPathComponent("\(name).json")
                // Convert ABP format to WebKit content rule JSON (simplified)
                let rules = convertABPToWebKitRules(data: data)
                try rules.write(to: dest)
            } catch {
                print("[ContentBlocker] Update failed for \(name): \(error)")
            }
        }

        await compile()
    }

    private func convertABPToWebKitRules(data: Data) -> Data {
        // Simplified ABP → WebKit content rule converter
        // In production, use a full parser
        return "[]".data(using: .utf8)!
    }

    // MARK: - Essential Built-in Rules

    static let essentialBlockRules: [[String: Any]] = [
        // Google Analytics
        ["trigger": ["url-filter": "google-analytics\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "googletagmanager\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "googlesyndication\\.com"], "action": ["type": "block"]],
        // Facebook tracking
        ["trigger": ["url-filter": "connect\\.facebook\\.net"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "facebook\\.com/tr"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "pixel\\.facebook\\.com"], "action": ["type": "block"]],
        // Ad networks
        ["trigger": ["url-filter": "doubleclick\\.net"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "adservice\\.google"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "ads\\.yahoo\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "advertising\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "adsrvr\\.org"], "action": ["type": "block"]],
        // Common trackers
        ["trigger": ["url-filter": "scorecardresearch\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "quantserve\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "hotjar\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "mixpanel\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "segment\\.io"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "amplitude\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "criteo\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "taboola\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "outbrain\\.com"], "action": ["type": "block"]],
        // Fingerprinting
        ["trigger": ["url-filter": "fingerprintjs\\.com"], "action": ["type": "block"]],
        ["trigger": ["url-filter": "cdn\\.jsdelivr\\.net.*fingerprint"], "action": ["type": "block"]],
        // Third-party cookies
        ["trigger": ["url-filter": ".*", "load-type": ["third-party"], "resource-type": ["raw"]],
         "action": ["type": "block-cookies"]],
    ]
}
