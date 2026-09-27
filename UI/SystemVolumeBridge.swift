import SwiftUI
import MediaPlayer
import AVFoundation

/// Keeps a hidden MPVolumeView mounted for the lifetime of the app so the web
/// remote can control the iPad's actual output volume even when NowPlayingView
/// is not currently on screen.
struct AppSystemVolumeBridge: UIViewRepresentable {
    @Binding var value: Float

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.showsRouteButton = false
        view.showsVolumeSlider = true

        if let slider = view.subviews.compactMap({ $0 as? UISlider }).first {
            context.coordinator.slider = slider
            slider.value = AVAudioSession.sharedInstance().outputVolume
        }

        context.coordinator.startObservingSystemVolume()
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        context.coordinator.value = $value
    }

    static func dismantleUIView(_ view: MPVolumeView, coordinator: Coordinator) {
        coordinator.stopObservingSystemVolume()
    }

    final class Coordinator: NSObject {
        var value: Binding<Float>
        weak var slider: UISlider?
        private var volumeObservation: NSKeyValueObservation?
        private var remoteVolumeObserver: NSObjectProtocol?

        init(value: Binding<Float>) {
            self.value = value
        }

        func startObservingSystemVolume() {
            guard volumeObservation == nil else { return }

            let session = AVAudioSession.sharedInstance()
            try? session.setActive(true)

            volumeObservation = session.observe(
                \.outputVolume,
                options: [.initial, .new]
            ) { [weak self] _, change in
                guard let self, let newValue = change.newValue else { return }
                DispatchQueue.main.async {
                    self.value.wrappedValue = newValue
                }
            }

            remoteVolumeObserver = NotificationCenter.default.addObserver(
                forName: .toyakoRemoteSystemVolume,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self, let number = notification.userInfo?["value"] as? Float else { return }
                self.setSystemVolume(number)
            }
        }

        func setSystemVolume(_ volume: Float) {
            let clamped = min(1, max(0, volume))
            guard let slider else { return }
            slider.setValue(clamped, animated: false)
            slider.sendActions(for: .valueChanged)
            value.wrappedValue = clamped
        }

        func stopObservingSystemVolume() {
            volumeObservation?.invalidate()
            volumeObservation = nil
            if let remoteVolumeObserver {
                NotificationCenter.default.removeObserver(remoteVolumeObserver)
                self.remoteVolumeObserver = nil
            }
        }
    }
}
