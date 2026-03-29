// UI/Components/BrowserSheets.swift
// GhostStream - Browser menu, privacy report, tab grid

import SwiftUI

// MARK: - Browser Menu
struct BrowserMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TabManager.self) private var tabManager
    @Environment(VPNManager.self) private var vpnManager

    var body: some View {
        NavigationStack {
            List {
                Section("탭") {
                    menuRow("새 탭", icon: "plus.square") {
                        tabManager.newTab()
                        dismiss()
                    }
                    menuRow("새 프라이빗 탭", icon: "lock.square") {
                        tabManager.newTab(isPrivate: true)
                        dismiss()
                    }
                    menuRow("모든 탭 닫기", icon: "xmark.square", color: .red) {
                        tabManager.closeAllTabs()
                        dismiss()
                    }
                }

                Section("도구") {
                    menuRow("보관함", icon: "lock.shield.fill") { dismiss() }
                    menuRow("다운로드", icon: "arrow.down.circle") { dismiss() }
                    menuRow("방문 기록", icon: "clock.arrow.circlepath") { dismiss() }
                    menuRow("북마크", icon: "star.fill") { dismiss() }
                }

                Section("보안") {
                    HStack {
                        Image(systemName: vpnManager.status.icon)
                            .foregroundStyle(Color(hex: vpnManager.status.color))
                        Text("VPN: \(vpnManager.status.rawValue)")
                        Spacer()
                    }
                    menuRow("프라이버시 설정", icon: "shield.fill") { dismiss() }
                }

                Section {
                    menuRow("설정", icon: "gearshape.fill") { dismiss() }
                }
            }
            .navigationTitle("메뉴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(GhostTheme.accent)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func menuRow(_ title: String, icon: String, color: Color = GhostTheme.accent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .foregroundStyle(color == .red ? color : Color.primary)
        }
    }
}

// MARK: - Privacy Report Sheet
struct PrivacyReportSheet: View {
    let tab: Tab?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    let report = tab?.privacyReport ?? PrivacyReport()

                    // Score circle
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.1), lineWidth: 8)
                            .frame(width: 100, height: 100)
                        Circle()
                            .trim(from: 0, to: Double(report.score) / 100)
                            .stroke(scoreColor(report.score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text("\(report.score)")
                                .font(.title.bold().monospacedDigit())
                                .foregroundStyle(.white)
                            Text("/ 100")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    // Connection info
                    VStack(spacing: 1) {
                        infoRow("HTTPS", value: report.isHTTPS ? "✅" : "❌")
                        infoRow("TLS", value: report.isHTTPS ? "1.3" : "—")
                        infoRow("DoH", value: "✅")
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Blocked stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text("이 페이지에서 차단됨")
                            .font(.headline)
                            .foregroundStyle(.white)

                        statBar("광고", count: report.adsBlocked, color: GhostTheme.warning)
                        statBar("트래커", count: report.trackersBlocked, color: GhostTheme.danger)
                        statBar("핑거프린트 시도", count: report.fingerprintAttempts, color: GhostTheme.accentAlt)
                    }
                    .padding()
                    .glass()

                    // Cookie isolation
                    HStack {
                        Image(systemName: "lock.circle.fill")
                            .foregroundStyle(GhostTheme.success)
                        VStack(alignment: .leading) {
                            Text("쿠키 격리됨")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                            Text("이 탭의 쿠키는 다른 탭에 영향 없음")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .glass()
                }
                .padding()
            }
            .background(GhostTheme.bg)
            .navigationTitle("프라이버시 리포트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(GhostTheme.accent)
                }
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        score >= 70 ? GhostTheme.success : score >= 40 ? GhostTheme.warning : GhostTheme.danger
    }

    private func infoRow(_ key: String, value: String) -> some View {
        HStack {
            Text(key).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).foregroundStyle(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.white.opacity(0.03))
    }

    private func statBar(_ label: String, count: Int, color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text("\(count)").font(.headline.monospacedDigit()).foregroundStyle(color)
        }
    }
}

// MARK: - Tab Grid View
struct TabGridView: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(tabManager.tabs) { tab in
                        tabCell(tab)
                    }
                }
                .padding()
            }
            .background(GhostTheme.bg)
            .navigationTitle("탭 (\(tabManager.tabs.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { tabManager.closeAllTabs(); dismiss() } label: {
                        Text("모두 닫기").font(.caption).foregroundStyle(.red)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                        .foregroundStyle(GhostTheme.accent)
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button { tabManager.newTab(); dismiss() } label: {
                            Label("새 탭", systemImage: "plus")
                        }
                        Spacer()
                        Button { tabManager.newTab(isPrivate: true); dismiss() } label: {
                            Label("프라이빗 탭", systemImage: "lock")
                        }
                    }
                    .foregroundStyle(GhostTheme.accent)
                }
            }
        }
    }

    private func tabCell(_ tab: Tab) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tab.isPrivate ? GhostTheme.accentAlt.opacity(0.1) : .white.opacity(0.05))
                    .frame(height: 120)
                    .overlay {
                        VStack {
                            if tab.isPrivate {
                                Image(systemName: "lock.fill")
                                    .font(.title2)
                                    .foregroundStyle(GhostTheme.accentAlt)
                            } else {
                                Image(systemName: "globe")
                                    .font(.title2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                Button { tabManager.closeTab(tab) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }

            Text(tab.displayTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tab.id == tabManager.activeTabID ? GhostTheme.accent : .clear, lineWidth: 2)
        )
        .onTapGesture {
            tabManager.switchTo(tab)
            dismiss()
        }
    }
}
