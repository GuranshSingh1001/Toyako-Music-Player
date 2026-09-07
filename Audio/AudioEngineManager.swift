import AVFoundation
import Foundation

class AudioEngineManager: ObservableObject {
    private var player: AVPlayer?

    @Published var currentTrack: LocalTrack?
    @Published var isPlaying: Bool = false
    @Published var playbackProgress: Double = 0.0

    private var timeObserverToken: Any?

    func play(track: LocalTrack) {
        currentTrack = track
        player?.pause()
        
        let playerItem = AVPlayerItem(url: track.url)
        player = AVPlayer(playerItem: playerItem)
        player?.play()
        isPlaying = true

        addPeriodicTimeObserver(duration: track.duration)
    }

    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func addPeriodicTimeObserver(duration: TimeInterval) {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }

        guard duration > 0 else { return }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let current = CMTimeGetSeconds(time)
            self.playbackProgress = current / duration
        }
    }
}
