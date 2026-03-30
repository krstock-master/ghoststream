// UI/Components/ReaderModeView.swift
// GhostStream v1.0 — Reader Mode (Firefox/Safari 스타일)
import SwiftUI
import WebKit

struct ReaderModeView: View {
    let title: String
    let content: String
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("readerFontSize") private var fontSize: Double = 18
    @AppStorage("readerTheme") private var theme: String = "auto"
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    Text(title)
                        .font(.system(size: fontSize + 8, weight: .bold, design: .serif))
                        .foregroundStyle(.primary)

                    if let host = url?.host {
                        Text(host)
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }

                    Divider()

                    // Article body
                    Text(content)
                        .font(.system(size: fontSize, design: .serif))
                        .lineSpacing(fontSize * 0.5)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .background(readerBackground)
            .navigationTitle("리더 모드")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22)).foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Font size
                        Button { fontSize = max(14, fontSize - 2) } label: {
                            Label("글씨 줄이기", systemImage: "textformat.size.smaller")
                        }
                        Button { fontSize = min(28, fontSize + 2) } label: {
                            Label("글씨 키우기", systemImage: "textformat.size.larger")
                        }
                        Divider()
                        // Theme
                        Button { theme = "auto" } label: {
                            Label("시스템", systemImage: theme == "auto" ? "checkmark" : "")
                        }
                        Button { theme = "sepia" } label: {
                            Label("세피아", systemImage: theme == "sepia" ? "checkmark" : "")
                        }
                        Button { theme = "dark" } label: {
                            Label("다크", systemImage: theme == "dark" ? "checkmark" : "")
                        }
                    } label: {
                        Image(systemName: "textformat")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
            }
        }
    }

    private var readerBackground: Color {
        switch theme {
        case "sepia": return Color(red: 0.98, green: 0.95, blue: 0.88)
        case "dark": return Color(red: 0.1, green: 0.1, blue: 0.1)
        default: return Color(.systemBackground)
        }
    }
}

// MARK: - Reader Mode JS Extraction
enum ReaderModeExtractor {
    /// Readability-lite: 페이지에서 본문 텍스트 추출하는 JS
    static let extractionJS = """
    (function() {
        // 1. 메타 태그에서 제목 가져오기
        var title = document.title || '';
        var ogTitle = document.querySelector('meta[property="og:title"]');
        if (ogTitle) title = ogTitle.content || title;

        // 2. article/main 요소 찾기
        var candidates = [
            document.querySelector('article'),
            document.querySelector('[role="main"]'),
            document.querySelector('main'),
            document.querySelector('.article-body'),
            document.querySelector('.article-content'),
            document.querySelector('.post-content'),
            document.querySelector('.entry-content'),
            document.querySelector('.story-body'),
            document.querySelector('#article-body'),
            document.querySelector('#content'),
        ].filter(Boolean);

        var content = '';
        if (candidates.length > 0) {
            // 가장 긴 텍스트를 가진 후보 선택
            var best = candidates[0];
            candidates.forEach(function(c) {
                if (c.textContent.length > best.textContent.length) best = c;
            });
            // 텍스트 추출 (태그 제거, 단락 유지)
            var paragraphs = best.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li, blockquote');
            var texts = [];
            paragraphs.forEach(function(p) {
                var t = p.textContent.trim();
                if (t.length > 20) texts.push(t);
            });
            content = texts.join('\\n\\n');
        }

        // Fallback: 모든 <p> 태그
        if (content.length < 200) {
            var allP = document.querySelectorAll('p');
            var texts2 = [];
            allP.forEach(function(p) {
                var t = p.textContent.trim();
                if (t.length > 30) texts2.push(t);
            });
            content = texts2.join('\\n\\n');
        }

        return JSON.stringify({ title: title, content: content });
    })()
    """;
}
