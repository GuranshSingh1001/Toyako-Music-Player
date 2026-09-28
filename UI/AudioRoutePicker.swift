import SwiftUI
import AVKit

/// Native iPadOS output-device picker.
///
/// Selecting an AirPlay-compatible receiver changes AVAudioSession's output
/// route, so Toyako continues playback while the iPad's own speakers stop
/// producing the audio. The receiver becomes the active audio output.
struct AudioRoutePicker: UIViewRepresentable {
    var size: CGFloat = 48
    var tintColor: UIColor = .white
    var activeTintColor: UIColor = .white

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.tintColor = tintColor
        view.activeTintColor = activeTintColor
        view.prioritizesVideoDevices = false
        view.accessibilityLabel = "Audio Output"
        view.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        view.layer.cornerRadius = size / 2
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = tintColor
        view.activeTintColor = activeTintColor
        view.prioritizesVideoDevices = false
        view.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        view.layer.cornerRadius = size / 2
        view.clipsToBounds = true
    }
}
