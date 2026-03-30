// UI/Components/FullscreenDownloadOverlay.swift
// GhostStream — Aloha-style fullscreen download bar
// UIWindow at .statusBar+200 — ONLY way to show UI during iOS native video fullscreen
// (JS elements are hidden because system AVPlayerViewController takes over)

import UIKit

final class FullscreenDownloadOverlay {
    static let shared = FullscreenDownloadOverlay()
    private init() {}

    private var overlayWindow: UIWindow?
    private var pendingURL: URL?
    private var pendingTitle: String = ""
    private var pendingQuality: String = "Auto"
    private var strongDownloadManager: MediaDownloadManager?

    func show(url: URL, title: String, quality: String, downloadManager: MediaDownloadManager) {
        DispatchQueue.main.async { [self] in
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
            UIView.animate(withDuration: 0.2, animations: {
                self.overlayWindow?.alpha = 0
            }, completion: { _ in
                self.overlayWindow?.isHidden = true
                self.overlayWindow = nil
                self.strongDownloadManager = nil
            })
        }
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

        let bar = buildBar(screenBounds: scene.screen.bounds)
        win.addSubview(bar)

        bar.alpha = 0
        bar.transform = CGAffineTransform(translationX: 0, y: 80)
        UIView.animate(withDuration: 0.35, delay: 0,
                       usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            bar.alpha = 1
            bar.transform = .identity
        }
    }

    private func buildBar(screenBounds: CGRect) -> UIView {
        let barH: CGFloat = 72
        let safeBottom: CGFloat = 34
        let barY = screenBounds.height - barH - safeBottom
        let bar = UIView(frame: CGRect(x: 0, y: barY, width: screenBounds.width, height: barH + safeBottom))

        // Blur background (Aloha style)
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        blur.frame = bar.bounds
        bar.addSubview(blur)

        // Buttons row
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.frame = CGRect(x: 20, y: 8, width: screenBounds.width - 40, height: 56)
        bar.addSubview(stack)

        // ⬇️ Download
        stack.addArrangedSubview(makeBarButton(icon: "arrow.down.circle.fill", label: "저장", color: .systemTeal, action: #selector(tappedDownload)))
        // 📱 PiP — placeholder
        stack.addArrangedSubview(makeBarButton(icon: "pip.fill", label: "PiP", color: .white, action: #selector(tappedClose)))
        // 🔁 Repeat — placeholder
        stack.addArrangedSubview(makeBarButton(icon: "repeat", label: "반복", color: .white, action: #selector(tappedClose)))
        // ✖ Close
        stack.addArrangedSubview(makeBarButton(icon: "xmark.circle.fill", label: "닫기", color: .systemRed.withAlphaComponent(0.8), action: #selector(tappedClose)))

        return bar
    }

    private func makeBarButton(icon: String, label: String, color: UIColor, action: Selector) -> UIButton {
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
        guard let url = pendingURL, let dm = strongDownloadManager else { hide(); return }
        let isHLS = url.absoluteString.contains(".m3u8")
        let media = DetectedMedia(
            url: url, type: isHLS ? .hls : .mp4,
            quality: pendingQuality, title: pendingTitle,
            referer: "", thumbnail: nil, estimatedSize: nil
        )
        dm.download(media: media, saveToVault: false)

        // Feedback
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
