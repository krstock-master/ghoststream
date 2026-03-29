// Extensions/Extensions.swift
// GhostStream - Color, Glassmorphism, Theme, Accessibility, Reduced Motion

import SwiftUI

// MARK: - Color from Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default: (r, g, b) = (128, 128, 128)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
    }
}

// MARK: - Glassmorphism
struct GlassModifier: ViewModifier {
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(0.08), lineWidth: 0.5))
    }
}

extension View {
    func glass(_ radius: CGFloat = 16) -> some View { modifier(GlassModifier(radius: radius)) }
}

// MARK: - Theme
enum GhostTheme {
    static let bg = Color(hex: "0A0A14")
    static let surface = Color(hex: "12121E")
    static let accent = Color(hex: "00D4AA")
    static let accentAlt = Color(hex: "7B61FF")
    static let danger = Color(hex: "FF4757")
    static let warning = Color(hex: "FECA57")
    static let success = Color(hex: "1DD1A1")
    static let gradient = LinearGradient(colors: [accent, accentAlt], startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Accessibility Helpers
extension View {
    func a11y(label: String, hint: String = "", traits: AccessibilityTraits = []) -> some View {
        self.accessibilityLabel(label).accessibilityHint(hint).accessibilityAddTraits(traits)
    }
    func a11yButton(_ label: String, hint: String = "") -> some View {
        self.a11y(label: label, hint: hint, traits: .isButton)
    }
    func a11yImage(_ label: String) -> some View {
        self.a11y(label: label, traits: .isImage)
    }
    func a11yHeader(_ label: String) -> some View {
        self.a11y(label: label, traits: .isHeader)
    }
}

// MARK: - Reduced Motion
struct SafeAnimationModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: UUID())
    }
}

extension View {
    func motionSafe(_ animation: Animation = .default) -> some View {
        modifier(SafeAnimationModifier(animation: animation))
    }
}

// MARK: - Network Error View
struct NetworkErrorView: View {
    let message: String
    let retryAction: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("연결할 수 없음").font(.headline).foregroundStyle(.secondary)
            Text(message).font(.subheadline).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            Button(action: retryAction) {
                Label("다시 시도", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.black)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(GhostTheme.accent, in: Capsule())
            }.a11yButton("다시 시도", hint: "네트워크 연결을 재시도합니다")
        }.padding(32)
    }
}

// MARK: - HTTP Warning Banner
struct InsecureConnectionBanner: View {
    let url: URL
    var body: some View {
        if url.scheme == "http" {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(GhostTheme.warning)
                Text("이 연결은 안전하지 않습니다 (HTTP)").font(.caption2).foregroundStyle(GhostTheme.warning)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(GhostTheme.warning.opacity(0.1))
            .a11y(label: "보안 경고: 암호화되지 않은 HTTP 연결")
        }
    }
}

// MARK: - Jailbreak Warning
struct JailbreakWarningView: View {
    @Binding var isPresented: Bool
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.shield.fill").font(.system(size: 52)).foregroundStyle(GhostTheme.danger)
            Text("보안 경고").font(.title2.bold()).foregroundStyle(.white)
            Text("이 기기는 탈옥된 상태로 감지되었습니다. 보관함의 암호화 키가 노출될 위험이 있습니다.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
            Button { isPresented = false } label: {
                Text("위험을 감수하고 계속").font(.headline).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(GhostTheme.danger, in: RoundedRectangle(cornerRadius: 12))
            }.padding(.horizontal, 24)
        }.padding(.vertical, 40)
    }
}
