// UI/Components/FullscreenDownloadOverlay.swift
// GhostStream — UIWindow-level fullscreen download button
// Uses a dedicated UIWindow above EVERYTHING (including AVPlayerViewController)
// so it's guaranteed visible regardless of which player is used.

import UIKit

final class FullscreenDownloadOverlay {
    static let shared = FullscreenDownloadOverlay()
    private init() {}

    private var overlayWindow: UIWindow?
    private var currentURL: URL?
    private var currentTitle: String = ""
    private var currentQuality: String = "Auto"

    // MARK: - Show

    func show(url: URL, title: String, quality: String, downloadManager: MediaDownloadManager) {
        guard url.absoluteString != "__hide_overlay__" else { hide(); return }

        currentURL     = url
        currentTitle   = title
        currentQuality = quality

        DispatchQueue.main.async {
            // Already showing → just update stored URL (re-use existing button)
            if let win = self.overlayWindow, !win.isHidden {
                self.currentURL = url; return
            }
            self.createOverlay(downloadManager: downloadManager)
        }
    }

    // MARK: - Hide

    func hide() {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.22, delay: 0,
                           options: .curveEaseIn) {
                self.overlayWindow?.alpha = 0
            } completion: { _ in
                self.overlayWindow?.isHidden = true
                self.overlayWindow = nil
            }
        }
    }

    // MARK: - Private

    private func createOverlay(downloadManager: MediaDownloadManager) {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        // Transparent pass-through window sitting above statusBar
        let win = UIWindow(windowScene: scene)
        win.windowLevel = .statusBar + 200          // above AVPlayerViewController
        win.backgroundColor = .clear
        win.isUserInteractionEnabled = true
        win.isHidden = false
        overlayWindow = win

        // Build button
        let btn = makeButton()
        let screenW = scene.screen.bounds.width
        let statusH = scene.statusBarManager?.statusBarFrame.height ?? 47
        let size: CGFloat = 52
        let margin: CGFloat = 14
        btn.frame = CGRect(x: screenW - size - margin, y: statusH + 6, width: size, height: size)
        win.addSubview(btn)

        // Tap → download
        let action = UIAction { [weak self, weak btn] _ in
            guard let self, let url = self.currentURL else { return }
            let type: DetectedMedia.MediaType = url.absoluteString.contains(".m3u8") ? .hls : .mp4
            let media = DetectedMedia(
                url: url, type: type, quality: self.currentQuality,
                title: self.currentTitle.isEmpty ? url.deletingPathExtension().lastPathComponent : self.currentTitle,
                referer: "", thumbnail: nil, estimatedSize: nil
            )
            downloadManager.download(media: media, saveToVault: false)
            self.animateSuccess(btn)
        }
        btn.addAction(action, for: .touchUpInside)

        // Animate in
        btn.alpha = 0
        btn.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        UIView.animate(withDuration: 0.35, delay: 0,
                       usingSpringWithDamping: 0.65, initialSpringVelocity: 0.5) {
            btn.alpha = 1
            btn.transform = .identity
        }
    }

    private func makeButton() -> UIButton {
        let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let btn = UIButton(type: .custom)
        btn.setImage(UIImage(systemName: "arrow.down.circle.fill", withConfiguration: cfg), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor(red: 0.05, green: 0.58, blue: 0.53, alpha: 0.95)
        btn.layer.cornerRadius = 26
        btn.layer.shadowColor  = UIColor.black.cgColor
        btn.layer.shadowOpacity = 0.45
        btn.layer.shadowRadius  = 10
        btn.layer.shadowOffset  = CGSize(width: 0, height: 4)
        btn.clipsToBounds = false
        return btn
    }

    private func animateSuccess(_ btn: UIButton?) {
        guard let btn else { return }
        let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        UIView.transition(with: btn, duration: 0.2, options: .transitionCrossDissolve) {
            btn.setImage(UIImage(systemName: "checkmark.circle.fill", withConfiguration: cfg), for: .normal)
            btn.backgroundColor = UIColor(red: 0.13, green: 0.67, blue: 0.35, alpha: 0.95)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.hide()
        }
    }
}
