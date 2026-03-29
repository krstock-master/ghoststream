// Extensions/Extensions.swift
import SwiftUI

// MARK: - Color from Hex
extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0; Scanner(string: h).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch h.count {
        case 6: (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8: (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default: (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Glassmorphism
struct GlassModifier: ViewModifier {
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

extension View {
    func glass(_ radius: CGFloat = 16) -> some View { modifier(GlassModifier(radius: radius)) }
}

// MARK: - Accessibility
extension View {
    func a11y(_ label: String) -> some View {
        self.accessibilityLabel(label).accessibilityAddTraits(.isButton)
    }
}

// MARK: - Insecure Connection Banner
struct InsecureConnectionBanner: View {
    let url: URL
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            Text("이 연결은 안전하지 않습니다 (HTTP)").font(.caption2).foregroundStyle(.orange)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - Network Error View
struct NetworkErrorView: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("연결할 수 없음").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("다시 시도", action: onRetry)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(.teal, in: Capsule())
                .foregroundStyle(.white)
        }.padding()
    }
}
