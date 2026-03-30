// UI/Components/FullscreenDownloadOverlay.swift
// GhostStream — Fullscreen video download overlay
// Uses UIWindow at .statusBar+200 level with a STRONG reference to downloadManager
// to prevent weak-capture nil issues.

import UIKit

final class FullscreenDownloadOverlay {
    static let shared = FullscreenDownloadOverlay()
    private init() {}

    private var overlayWindow: UIWindow?
    private var pendingURL: URL?
    private var pendingTitle: String = ""
    private var pendingQuality: String = "Auto"
    // STRONG reference — critical, weak was causing silent failures
    private var strongDownloadManager: MediaDownloadManager?

    // MARK: - Show
    func show(url: URL, title: String, quality: String, downloadManager: MediaDownloadManager) {
        DispatchQueue.main.async { [self] in
            // Update stored values regardless
            pendingURL = url
            pendingTitle = title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
            pendingQuality = quality
            strongDownloadManager = downloadManager  // strong retain

            if overlayWindow != nil { return }  // already showing, just updated URL
            buildWindow()
        }
    }

    func hide() {
        DispatchQueue.main.async { [self] in
            UIView.animate(withDuration: 0.18, animations: {
                self.overlayWindow?.alpha = 0
            }, completion: { _ in
                self.overlayWindow?.isHidden = true
                self.overlayWindow = nil
                self.strongDownloadManager = nil
            })
        }
    }

    // MARK: - Private
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

        // Container view — bottom bar style like Alloha
        let bar = buildBottomBar(screenBounds: scene.screen.bounds)
        win.addSubview(bar)

        bar.alpha = 0
        bar.transform = CGAffineTransform(translationX: 0, y: 60)
        UIView.animate(withDuration: 0.3, delay: 0,
                       usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            bar.alpha = 1
            bar.transform = .identity
        }
    }

    private func buildBottomBar(screenBounds: CGRect) -> UIView {
        let barH: CGFloat = 60
        let barY = screenBounds.height - barH - 34  // above home indicator
        let bar = UIView(frame: CGRect(x: 0, y: barY, width: screenBounds.width, height: barH))
        bar.backgroundColor = UIColor.black.withAlphaComponent(0.72)

        // Download button
        let dlBtn = makeButton(icon: "arrow.down.circle.fill", label: "저장")
        dlBtn.frame = CGRect(x: 16, y: 8, width: 60, height: 44)
        dlBtn.addTarget(self, action: #selector(tappedDownload), for: .touchUpInside)
        bar.addSubview(dlBtn)

        // Title label
        let lbl = UILabel()
        lbl.frame = CGRect(x: 86, y: 0, width: screenBounds.width - 86 - 70, height: barH)
        lbl.text = pendingTitle
        lbl.textColor = UIColor.white.withAlphaComponent(0.85)
        lbl.font = .systemFont(ofSize: 13, weight: .medium)
        lbl.lineBreakMode = .byTruncatingMiddle
        bar.addSubview(lbl)

        // Close button
        let closeBtn = makeButton(icon: "xmark", label: nil)
        closeBtn.frame = CGRect(x: screenBounds.width - 52, y: 8, width: 44, height: 44)
        closeBtn.addTarget(self, action: #selector(tappedClose), for: .touchUpInside)
        bar.addSubview(closeBtn)

        return bar
    }

    private func makeButton(icon: String, label: String?) -> UIButton {
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let btn = UIButton(type: .custom)
        btn.setImage(UIImage(systemName: icon, withConfiguration: cfg), for: .normal)
        btn.tintColor = .white
        if let label {
            btn.setTitle("  \(label)", for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        }
        return btn
    }

    @objc private func tappedDownload() {
        guard let url = pendingURL, let dm = strongDownloadManager else {
            hide(); return
        }
        let isHLS = url.absoluteString.contains(".m3u8")
        let media = DetectedMedia(
            url: url, type: isHLS ? .hls : .mp4,
            quality: pendingQuality, title: pendingTitle,
            referer: "", thumbnail: nil, estimatedSize: nil
        )
        dm.download(media: media, saveToVault: false)

        // Success feedback
        if let bar = overlayWindow?.subviews.first,
           let dlBtn = bar.subviews.first as? UIButton {
            let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            UIView.transition(with: dlBtn, duration: 0.2, options: .transitionCrossDissolve) {
                dlBtn.setImage(UIImage(systemName: "checkmark.circle.fill", withConfiguration: cfg), for: .normal)
                dlBtn.tintColor = UIColor(red: 0.13, green: 0.78, blue: 0.45, alpha: 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.hide() }
    }

    @objc private func tappedClose() { hide() }
}
