// UI/Components/BrowserSheets.swift
import SwiftUI

struct PrivacyReportSheet: View {
    let tab: Tab?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    let report = tab?.privacyReport ?? PrivacyReport()
                    ZStack {
                        Circle().stroke(.white.opacity(0.1), lineWidth: 8).frame(width: 100, height: 100)
                        Circle().trim(from: 0, to: Double(report.score) / 100)
                            .stroke(report.score >= 70 ? .green : report.score >= 40 ? .orange : .red,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 100, height: 100).rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text("\(report.score)").font(.title.bold().monospacedDigit()).foregroundStyle(.white)
                            Text("/ 100").font(.caption2).foregroundStyle(Color.gray)
                        }
                    }
                    VStack(spacing: 1) {
                        row("HTTPS", report.isHTTPS ? "ON" : "OFF")
                        row("광고 차단", "\(report.adsBlocked)개")
                        row("트래커 차단", "\(report.trackersBlocked)개")
                        row("핑거프린트 시도", "\(report.fingerprintAttempts)회")
                        row("제3자 도메인", "\(report.thirdPartyDomains.count)개")
                    }.clipShape(RoundedRectangle(cornerRadius: 12))
                    HStack(spacing: 8) {
                        Image(systemName: "lock.circle.fill").foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text("쿠키 격리됨").font(.subheadline.weight(.medium)).foregroundStyle(.white)
                            Text("이 탭의 쿠키는 다른 탭에 영향 없음").font(.caption).foregroundStyle(Color.gray)
                        }
                        Spacer()
                    }.padding().glass()
                }.padding()
            }
            .background(Color(.systemBackground))
            .navigationTitle("프라이버시 리포트").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() }.foregroundStyle(.teal) } }
        }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.subheadline).foregroundStyle(Color.gray)
            Spacer()
            Text(v).font(.subheadline).foregroundStyle(.white)
        }.padding(.horizontal, 16).padding(.vertical, 10).background(.white.opacity(0.03))
    }
}

struct TabGridView: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(\.dismiss) private var dismiss

    // Samsung-style: 2-col cards with large preview area
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Header ───────────────────────────────────────────────
                tabHeader

                // ── Tab Grid ─────────────────────────────────────────────
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(tabManager.tabs) { tab in
                            SamsungTabCard(tab: tab, isActive: tab.id == tabManager.activeTabID) {
                                tabManager.switchTo(tab)
                                dismiss()
                            } onClose: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    tabManager.closeTab(tab)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                }

                // ── Bottom Action Bar ─────────────────────────────────────
                tabBottomBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
    }

    // MARK: - Header
    private var tabHeader: some View {
        HStack(spacing: 0) {
            Button("완료") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.teal)
                .padding(.leading, 18)

            Spacer()

            VStack(spacing: 1) {
                Text("탭")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(tabManager.tabs.count)개 열림")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    tabManager.closeAllTabs()
                }
                dismiss()
            } label: {
                Text("모두 닫기")
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
            }
            .padding(.trailing, 18)
        }
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Bottom Bar
    private var tabBottomBar: some View {
        HStack(spacing: 0) {
            // Private tab
            Button {
                tabManager.newTab(isPrivate: true)
                dismiss()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "lock.square.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.purple)
                    Text("프라이빗")
                        .font(.system(size: 11))
                        .foregroundStyle(.purple)
                }
                .frame(maxWidth: .infinity)
            }

            // New tab (centre, prominent)
            Button {
                tabManager.newTab()
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(.teal)
                        .frame(width: 52, height: 52)
                        .shadow(color: .teal.opacity(0.45), radius: 10, y: 4)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)

            // Placeholder for symmetry (or add bookmark later)
            Button {
                // Reserved: Tab groups / bookmarks Phase 2
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text("그룹")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(true)
        }
        .padding(.vertical, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Samsung-Style Tab Card
struct SamsungTabCard: View {
    let tab: Tab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Card body
            Button(action: onSelect) {
                VStack(spacing: 0) {
                    // ── Preview area ──────────────────────────────────────
                    ZStack {
                        RoundedRectangle(cornerRadius: 0)
                            .fill(tab.isPrivate
                                  ? Color.purple.opacity(0.08)
                                  : Color(.secondarySystemGroupedBackground))
                            .frame(height: 130)

                        // ★ 썸네일 미리보기 (있으면 표시, 없으면 아이콘)
                        if let thumbnail = tab.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 130)
                                .clipped()
                        } else {
                            // Site favicon / icon
                            VStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(tab.isPrivate ? Color.purple.opacity(0.15) : Color(.tertiarySystemFill))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: tab.isPrivate ? "lock.fill" : "globe")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(tab.isPrivate ? Color.purple : Color.teal)
                                }
                                Text(tab.displayTitle)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                            }
                        }
                    }

                    // ── URL bar strip ─────────────────────────────────────
                    HStack(spacing: 6) {
                        Image(systemName: tab.isSecure ? "lock.fill" : "globe")
                            .font(.system(size: 10))
                            .foregroundStyle(tab.isSecure ? Color.green : Color.secondary)
                        Text(tab.url?.host ?? tab.displayTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        if tab.isPrivate {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.purple)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                }
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isActive ? Color.teal : Color(.separator).opacity(0.5),
                        lineWidth: isActive ? 2 : 0.5
                    )
            )
            .shadow(color: Color.black.opacity(isActive ? 0.18 : 0.07), radius: isActive ? 8 : 3, y: 2)

            // ── Close button (★ F5 FIX: 명확한 터치 영역) ──────────────
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .background(Circle().fill(Color(.systemBackground)).padding(3))
            }
            .padding(6)
        }
    }
}
