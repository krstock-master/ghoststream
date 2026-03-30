// Privacy/DeviceProfile.swift
// GhostStream — Fake UA + Fingerprint 일관성 프로필 시스템
import Foundation

/// 세션마다 랜덤 선택되는 기기 프로필. UA, Screen, Navigator 속성이 일관되어야 함.
struct DeviceProfile: Codable, Equatable {
    let name: String
    let userAgent: String
    let screenWidth: Int
    let screenHeight: Int
    let pixelRatio: Int
    let hardwareConcurrency: Int
    let maxTouchPoints: Int

    // 가장 대중적인 iPhone 모델 프로필 풀
    static let profiles: [DeviceProfile] = [
        DeviceProfile(
            name: "iPhone 16 Pro",
            userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_3_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1",
            screenWidth: 402, screenHeight: 874, pixelRatio: 3, hardwareConcurrency: 6, maxTouchPoints: 5
        ),
        DeviceProfile(
            name: "iPhone 15",
            userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Mobile/15E148 Safari/604.1",
            screenWidth: 393, screenHeight: 852, pixelRatio: 3, hardwareConcurrency: 6, maxTouchPoints: 5
        ),
        DeviceProfile(
            name: "iPhone 14",
            userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.7 Mobile/15E148 Safari/604.1",
            screenWidth: 390, screenHeight: 844, pixelRatio: 3, hardwareConcurrency: 6, maxTouchPoints: 5
        ),
        DeviceProfile(
            name: "iPhone SE 3",
            userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1",
            screenWidth: 375, screenHeight: 667, pixelRatio: 2, hardwareConcurrency: 6, maxTouchPoints: 5
        ),
        DeviceProfile(
            name: "iPhone 13 mini",
            userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
            screenWidth: 375, screenHeight: 812, pixelRatio: 3, hardwareConcurrency: 6, maxTouchPoints: 5
        ),
    ]

    static let desktop = DeviceProfile(
        name: "macOS Chrome",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        screenWidth: 1920, screenHeight: 1080, pixelRatio: 2, hardwareConcurrency: 8, maxTouchPoints: 0
    )

    /// 앱 시작 시 세션용 랜덤 프로필 선택 (세션 동안 일관 유지)
    static func randomMobile() -> DeviceProfile {
        profiles.randomElement()!
    }
}

/// 세션 동안 유지되는 프로필 관리자
final class DeviceProfileManager {
    static let shared = DeviceProfileManager()

    /// 현재 세션 프로필 (앱 시작 시 랜덤, 세션 동안 고정)
    private(set) var currentProfile: DeviceProfile
    private(set) var isDesktopMode: Bool = false

    private init() {
        self.currentProfile = DeviceProfile.randomMobile()
    }

    var activeProfile: DeviceProfile {
        isDesktopMode ? DeviceProfile.desktop : currentProfile
    }

    func setDesktopMode(_ enabled: Bool) {
        isDesktopMode = enabled
    }

    /// 세션 갱신 (Fire Button 등에서 사용)
    func refreshProfile() {
        currentProfile = DeviceProfile.randomMobile()
    }
}
