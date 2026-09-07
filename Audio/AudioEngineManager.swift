import AVFoundation
import MediaPlayer
import Combine

class AudioEngineManager: ObservableObject {
    let engine = AVAudioEngine()
    let playerNodeA = AVAudioPlayerNode()
    let playerNodeB = AVAudioPlayerNode()
    let equalizer = AVAudioUnitEQ(numberOfBands: 10)
    
    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false
    @Published var playbackProgress: Double = 0.0
    
    private var activeNode: AVAudioPlayerNode
    private var timer: Timer?

    init() {
        activeNode = playerNodeA
        setupEngine()
        setupRemoteTransportControls()
    }
    
    private func setupEngine() {
        engine.attach(playerNodeA)
        engine.attach(playerNodeB)
        engine.attach(equalizer)
        
        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(playerNodeA, to: equalizer, format: format)
        engine.connect(playerNodeB, to: equalizer, format: format)
        engine.connect(equalizer, to: engine.mainMixerNode, format: format)
        
        try? engine.start()
    }
    
    func play(track: Track) {
        currentTrack = track
        let file = try! AVAudioFile(forReading: track.fileURL)
        
        activeNode.stop()
        activeNode.scheduleFile(file, at: nil)
        activeNode.play()
        isPlaying = true
        
        updateNowPlayingInfo(track: track)
        startProgressTimer(duration: track.duration)
    }
    
    func togglePlayPause() {
        if isPlaying {
            activeNode.pause()
        } else {
            activeNode.play()
        }
        isPlaying.toggle()
    }
    
    private func startProgressTimer(duration: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let nodeTime = self.activeNode.lastRenderTime,
                  let playerTime = self.activeNode.playerTime(forNodeTime: nodeTime) else { return }
            self.playbackProgress = Double(playerTime.sampleTime) / playerTime.sampleRate / duration
        }
    }
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
    }
    
    private func updateNowPlayingInfo(track: Track) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.artistName
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = track.duration
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}
