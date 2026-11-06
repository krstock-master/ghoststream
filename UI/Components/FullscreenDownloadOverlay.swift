// UI/Components/FullscreenDownloadOverlay.swift
import GhostStreamCore
// GhostStream — Aloha-style fullscreen download bar
// UIWindow at .statusBar+200 — the ONLY way to show UI over iOS native video fullscreen

import UIKit

final class FullscreenDownloadOverlay {
    static let shared = FullscreenDownloadOverlay()
    private init() {}

    private var overlayWindow: UIWindow?
    private var pendingURL: URL?
    private var pendingTitle: String = ""
    private var pendingQuality: String = "Auto"
    private var strongDownloadManager: MediaDownloadManager?
    private var hideWorkItem: DispatchWorkItem?

    func show(url: URL, title: String, quality: String, downloadManager: MediaDownloadManager) {
        DispatchQueue.main.async { [self] in
            // Cancel any pending hide
            hideWorkItem?.cancel()
            hideWorkItem = nil

            pendingURL = url
            pendingTitle = title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
            pendingQuality = quality
            strongDownloadManager = downloadManager
            if overlayWindow != nil { return }
            buildWindow()
        }
    }

    func hide() {
        DispatchQueue.main.async { [self] in
            UIView.animate(withDuration: 0.25, animations: {
                self.overlayWindow?.alpha = 0
            }, completion: { _ in
                self.overlayWindow?.isHidden = true
                self.overlayWindow = nil
                self.strongDownloadManager = nil
            })
        }
    }

    /// Debounced hide — waits before actually hiding (prevents premature dismiss)
    func hideDebounced(delay: TimeInterval = 1.5) {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func buildWindow() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        let win = UIWindow(windowScene: scene)
        win.windowLevel = .statusBar + 200
        win.backgroundColor = .clear
        win.isUserInteractionEnabled = true
        win.isHidden = false
        overlayWindow = win

        // ★ v2.0.5: 홈 인디케이터 높이를 하드코딩(34) 대신 실제 safe area에서 읽음 (SE 등 대응)
        let safeBottom = scene.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 34
        let bar = buildBar(screenBounds: scene.screen.bounds, safeBottom: safeBottom)
        win.addSubview(bar)

        bar.alpha = 0
        // ★ v2.0.5: 동작 줄이기 설정 시 슬라이드 없이 페이드만
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        bar.transform = reduceMotion ? .identity : CGAffineTransform(translationX: 0, y: 80)
        UIView.animate(withDuration: reduceMotion ? 0.2 : 0.35, delay: 0,
                       usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            bar.alpha = 1
            bar.transform = .identity
        }
    }

    private func buildBar(screenBounds: CGRect, safeBottom: CGFloat) -> UIView {
        let barH: CGFloat = 72
        let barY = screenBounds.height - barH - safeBottom
        let bar = UIView(frame: CGRect(x: 0, y: barY, width: screenBounds.width, height: barH + safeBottom))

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        blur.frame = bar.bounds
        bar.addSubview(blur)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.frame = CGRect(x: 20, y: 8, width: screenBounds.width - 40, height: 56)
        bar.addSubview(stack)

        stack.addArrangedSubview(makeBtn(icon: "arrow.down.circle.fill", label: "저장", color: .systemTeal, action: #selector(tappedDownload)))
        // ★ v2.0.5: "PiP"/"반복" 버튼 제거 — 둘 다 닫기(tappedClose)에 연결되어 있어 오해를 유발
        stack.addArrangedSubview(makeBtn(icon: "xmark.circle.fill", label: "닫기", color: .systemRed.withAlphaComponent(0.8), action: #selector(tappedClose)))

        return bar
    }

    private func makeBtn(icon: String, label: String, color: UIColor, action: Selector) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium))
        config.title = label
        config.baseForegroundColor = color
        config.imagePlacement = .top
        config.imagePadding = 4
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var a = $0; a.font = UIFont.systemFont(ofSize: 10, weight: .medium); return a }
        let btn = UIButton(configuration: config)
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    @objc private func tappedDownload() {
        guard let url = pendingURL else { hide(); return }

        // ★ WKWebView.startDownload 경로로 — 브라우저 세션 사용 (삼성/알로하 동일)
        NotificationCenter.default.post(name: .wkDownloadRequested, object:
            DetectedMedia(url: url, type: url.absoluteString.contains(".m3u8") ? .hls : .mp4,
                quality: pendingQuality, title: pendingTitle,
                referer: "", thumbnail: nil, estimatedSize: nil))

        // Visual feedback
        if let bar = overlayWindow?.subviews.first,
           let stack = bar.subviews.compactMap({ $0 as? UIStackView }).first,
           let dlBtn = stack.arrangedSubviews.first as? UIButton {
            var cfg = dlBtn.configuration
            cfg?.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium))
            cfg?.baseForegroundColor = .systemGreen
            cfg?.title = "완료"
            dlBtn.configuration = cfg
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.hide() }
    }

    @objc private func tappedClose() { hide() }
}
