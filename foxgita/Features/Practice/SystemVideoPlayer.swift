//
//  SystemVideoPlayer.swift
//  foxgita
//

import AVKit
import SwiftUI

struct SystemVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        controller.delegate = context.coordinator
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player?.pause()
        controller.player = nil
        AudioSessionCoordinator.shared.release(.playback)
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            coordinator.animate(alongsideTransition: nil) { _ in
                self.onDismiss()
            }
        }
    }
}
