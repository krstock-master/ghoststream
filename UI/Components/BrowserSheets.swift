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
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(tabManager.tabs) { tab in
                        VStack(spacing: 0) {
                            ZStack(alignment: .topTrailing) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(tab.isPrivate ? .purple.opacity(0.1) : .white.opacity(0.05))
                                    .frame(height: 120)
                                    .overlay {
                                        VStack {
                                            Image(systemName: tab.isPrivate ? "lock.fill" : "globe").font(.title2)
                                                .foregroundStyle(tab.isPrivate ? .purple : Color.gray)
                                            Text(tab.displayTitle).font(.caption2).foregroundStyle(Color.gray).lineLimit(1).padding(.horizontal, 4)
                                        }
                                    }
                                Button { tabManager.closeTab(tab) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.body).foregroundStyle(Color.gray)
                                }.padding(6)
                            }
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(tab.id == tabManager.activeTabID ? .teal : .clear, lineWidth: 2))
                        }
                        .onTapGesture { tabManager.switchTo(tab); dismiss() }
                    }
                }.padding()
            }
            .background(Color(.systemBackground))
            .navigationTitle("탭 (\(tabManager.tabs.count))").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("모두 닫기") { tabManager.closeAllTabs(); dismiss() }.font(.caption).foregroundStyle(.red)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("완료") { dismiss() }.foregroundStyle(.teal) }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button { tabManager.newTab(); dismiss() } label: { Label("새 탭", systemImage: "plus") }
                        Spacer()
                        Button { tabManager.newTab(isPrivate: true); dismiss() } label: { Label("프라이빗", systemImage: "lock") }
                    }.foregroundStyle(.teal)
                }
            }
        }
    }
}
