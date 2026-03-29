// UI/Components/FullscreenDownloadOverlay.swift
// GhostStream – native UIKit button injected into AVPlayerViewController

import UIKit
import SwiftUI

final class FullscreenDownloadOverlay {
    static let shared = FullscreenDownloadOverlay()
    private init() {}

    private weak var overlayButton: UIButton?

    // Call when webkitbeginfullscreen fires (after 0.4s delay for VC to appear)
    func show(url: URL, title: String, quality: String, downloadManager: MediaDownloadManager) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            guard let playerView = self.findFullscreenView() else { return }

            // Remove any stale button
            self.overlayButton?.removeFromSuperview()

            let btn = self.makeButton()
            btn.frame = CGRect(
                x: playerView.bounds.width - 64,
                y: 44,
                width: 44, height: 44
            )
            btn.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
            playerView.addSubview(btn)
            self.overlayButton = btn

            // Animate in
            btn.alpha = 0
            btn.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
                btn.alpha = 1
                btn.transform = .identity
            }

            // Tap handler
            let action = UIAction { [weak btn] _ in
                let isHLS = url.absoluteString.contains(".m3u8")
                let media = DetectedMedia(
                    url: url, type: isHLS ? .hls : .mp4,
                    quality: quality, title: title,
                    referer: url.absoluteString, thumbnail: nil, estimatedSize: nil
                )
                downloadManager.download(media: media, saveToVault: false)

                // Checkmark feedback
                let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
                btn?.setImage(UIImage(systemName: "checkmark.circle.fill", withConfiguration: cfg), for: .normal)
                UIView.animate(withDuration: 0.15) { btn?.backgroundColor = UIColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 0.92) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak btn] in
                    let cfg2 = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
                    btn?.setImage(UIImage(systemName: "arrow.down.circle.fill", withConfiguration: cfg2), for: .normal)
                    UIView.animate(withDuration: 0.15) { btn?.backgroundColor = UIColor(red: 0.05, green: 0.58, blue: 0.53, alpha: 0.92) }
                }
            }
            btn.addAction(action, for: .touchUpInside)
        }
    }

    func hide() {
        UIView.animate(withDuration: 0.2) { self.overlayButton?.alpha = 0 } completion: { _ in
            self.overlayButton?.removeFromSuperview()
            self.overlayButton = nil
        }
    }

    // MARK: - Private

    private func makeButton() -> UIButton {
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let btn = UIButton(type: .custom)
        btn.setImage(UIImage(systemName: "arrow.down.circle.fill", withConfiguration: cfg), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor(red: 0.05, green: 0.58, blue: 0.53, alpha: 0.92)
        btn.layer.cornerRadius = 22
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOpacity = 0.4
        btn.layer.shadowRadius = 8
        btn.layer.shadowOffset = CGSize(width: 0, height: 3)
        btn.clipsToBounds = false
        return btn
    }

    private func findFullscreenView() -> UIView? {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return nil }
        return findPlayerView(in: root)
    }

    private func findPlayerView(in vc: UIViewController) -> UIView? {
        let name = String(describing: type(of: vc))
        // AVPlayerViewController or its internal fullscreen wrapper
        if name.contains("AVPlayerViewController") || name.contains("AVFullScreen") || name.contains("AVPlayerView") {
            return vc.view
        }
        // Fullscreen is typically presented
        if let presented = vc.presentedViewController {
            if let found = findPlayerView(in: presented) { return found }
        }
        for child in vc.children {
            if let found = findPlayerView(in: child) { return found }
        }
        return nil
    }
}
