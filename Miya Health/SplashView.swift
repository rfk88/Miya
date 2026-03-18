//
//  SplashView.swift
//  Miya Health
//
//  Full-screen splash video shown on cold start. Plays once, then calls onFinish.
//  Add splash.mp4 to the Miya Health target in Xcode (Add Files to "Miya Health"…).
//

import SwiftUI
import AVFoundation
import UIKit

private let splashVideoName = "splash"
private let splashVideoExtension = "mp4"

// MARK: - Custom UIView so the player layer gets correct frame in layoutSubviews

private final class SplashVideoPlayerUIView: UIView {
    let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        clipsToBounds = true
          layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

// MARK: - Video player representable

private struct SplashVideoPlayerView: UIViewRepresentable {
    let url: URL
    let onDidPlayToEnd: () -> Void

    func makeUIView(context: Context) -> SplashVideoPlayerUIView {
        let view = SplashVideoPlayerUIView()
        let player = AVPlayer(url: url)
        view.playerLayer.player = player
        context.coordinator.player = player
        context.coordinator.observeEndOfVideo(player: player)
        player.play()
        return view
    }

    func updateUIView(_ uiView: SplashVideoPlayerUIView, context: Context) {
        // Frame is set in layoutSubviews; no update needed here.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDidPlayToEnd: onDidPlayToEnd)
    }

    class Coordinator: NSObject {
        var player: AVPlayer?
        var endObserver: NSObjectProtocol?
        let onDidPlayToEnd: () -> Void

        init(onDidPlayToEnd: @escaping () -> Void) {
            self.onDidPlayToEnd = onDidPlayToEnd
        }

        func observeEndOfVideo(player: AVPlayer) {
            guard let item = player.currentItem else { return }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.onDidPlayToEnd()
            }
        }

        deinit {
            if let o = endObserver {
                NotificationCenter.default.removeObserver(o)
            }
        }
    }
}

// MARK: - Splash view

struct SplashView: View {
    var onFinish: () -> Void

    @State private var appeared = false

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: splashVideoName, withExtension: splashVideoExtension) {
                SplashVideoPlayerView(url: url, onDidPlayToEnd: onFinish)
            } else {
                Color.white
            }
        }
        .ignoresSafeArea()
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if Bundle.main.url(forResource: splashVideoName, withExtension: splashVideoExtension) == nil {
                onFinish()
                return
            }
            withAnimation(.easeOut(duration: 0.35)) {
                appeared = true
            }
        }
    }
}

#Preview {
    SplashView(onFinish: {})
}
