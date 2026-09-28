import SwiftUI
import AVKit

/// A single, full-width output button. Tapping anywhere opens the native
/// iPadOS AirPlay/output picker; the label shows the current active route.
struct AudioRoutePicker: UIViewRepresentable {
    let routeName: String

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.prioritizesVideoDevices = false
        // The native glyph is replaced by our own so the whole control can
        // read as one button: "Playing on <device>" + AirPlay glyph.
        view.tintColor = .clear
        view.activeTintColor = .clear
        view.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        view.layer.cornerRadius = 14
        view.clipsToBounds = true
        view.accessibilityLabel = "Audio Output: Playing on \(routeName)"

        let icon = UIImageView(image: UIImage(systemName: "airplayaudio"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false
        icon.tag = 1001

        let label = UILabel()
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.text = "Playing on \(routeName)"
        label.lineBreakMode = .byTruncatingTail
        label.isUserInteractionEnabled = false
        label.tag = 1002

        view.addSubview(icon)
        view.addSubview(label)
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.accessibilityLabel = "Audio Output: Playing on \(routeName)"
        (view.viewWithTag(1002) as? UILabel)?.text = "Playing on \(routeName)"
    }
}
