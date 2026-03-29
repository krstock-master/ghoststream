// UI/Components/OnboardingView.swift
// GhostStream - First launch security notice + feature tour

import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var page: Int = 0
    @State private var agreedToTerms = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "060612"), Color(hex: "0A0A1A"), Color(hex: "060612")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            TabView(selection: $page) {
                welcomePage.tag(0)
                privacyPage.tag(1)
                downloadPage.tag(2)
                securityPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
    }

    // MARK: - Welcome
    private var welcomePage: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "ghost")
                .font(.system(size: 72))
                .foregroundStyle(GhostTheme.accent)
                .shadow(color: GhostTheme.accent.opacity(0.4), radius: 20)

            VStack(spacing: 8) {
                Text("GhostStream")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                Text("프라이버시 미디어 브라우저")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("보고 싶은 건 저장하고,\n내가 뭘 봤는지는 아무도 모른다.")
                .font(.body)
                .italic()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            nextButton { page = 1 }
        }
    }

    // MARK: - Privacy
    private var privacyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            featureIcon("shield.checkered", color: GhostTheme.accent)

            Text("Brave급 프라이버시")
                .font(.title2.bold())
                .foregroundStyle(.white)

            VStack(spacing: 16) {
                featureRow("hand.raised.fill", "7-벡터 핑거프린팅 방어")
                featureRow("eye.slash.fill", "트래커 + 광고 차단 (30,000+ 룰)")
                featureRow("lock.fill", "탭별 쿠키 완전 격리")
                featureRow("network.badge.shield.half.filled", "DNS over HTTPS (DoH)")
                featureRow("shield.fill", "내장 WireGuard VPN")
            }
            .padding(.horizontal, 32)

            Spacer()

            nextButton { page = 2 }
        }
    }

    // MARK: - Download
    private var downloadPage: some View {
        VStack(spacing: 24) {
            Spacer()

            featureIcon("arrow.down.circle.fill", color: GhostTheme.accentAlt)

            Text("모든 미디어 다운로드")
                .font(.title2.bold())
                .foregroundStyle(.white)

            VStack(spacing: 16) {
                featureRow("play.circle.fill", "JW Player / HLS (m3u8) 자동 감지")
                featureRow("film.fill", "MP4 / WebM 직접 다운로드")
                featureRow("photo.fill", "GIF · 짤 저장")
                featureRow("rectangle.stack.fill", "Blob URL 캡처")
                featureRow("lock.shield.fill", "AES-256-GCM 암호화 보관함")
            }
            .padding(.horizontal, 32)

            Spacer()

            nextButton { page = 3 }
        }
    }

    // MARK: - Security Notice
    private var securityPage: some View {
        VStack(spacing: 24) {
            Spacer()

            featureIcon("exclamationmark.shield.fill", color: GhostTheme.warning)

            Text("사용 전 주의사항")
                .font(.title2.bold())
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 16) {
                noticeRow("⚠️", "저작권이 있는 콘텐츠를 무단 다운로드하지 마세요.")
                noticeRow("🔒", "DRM 보호 콘텐츠(Netflix 등)는 지원하지 않습니다.")
                noticeRow("📱", "SideStore 배포 시 7일마다 재서명이 필요합니다.")
                noticeRow("🛡️", "VPN은 완전한 익명성을 보장하지 않습니다.")
                noticeRow("✅", "이 앱은 교육 및 합법적 용도 전용입니다.")
            }
            .padding(.horizontal, 24)

            Toggle(isOn: $agreedToTerms) {
                Text("위 사항을 이해하고 동의합니다")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .tint(GhostTheme.accent)
            .padding(.horizontal, 24)
            .padding(16)
            .glass()
            .padding(.horizontal)

            Spacer()

            Button(action: onComplete) {
                Text("시작하기")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(agreedToTerms ? GhostTheme.accent : .gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!agreedToTerms)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Components

    private func featureIcon(_ name: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.1))
                .frame(width: 90, height: 90)
            Image(systemName: name)
                .font(.system(size: 40))
                .foregroundStyle(color)
        }
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(GhostTheme.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func noticeRow(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(emoji)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func nextButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("다음")
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(GhostTheme.accent, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }
}
