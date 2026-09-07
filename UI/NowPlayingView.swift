import SwiftUI
import UIKit

struct NowPlayingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var audioManager: AudioEngineManager

    var body: some View {
        NowPlayingContainerView(dismissAction: dismiss) {
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height

                ZStack {
                    appleMusicSmartBleedBackground(size: geo.size)

                    if isLandscape {
                        HStack(spacing: geo.size.width * 0.05) {
                            artworkPane(maxHeight: geo.size.height * 0.52)
                                .frame(width: geo.size.width * 0.44)

                            lyricsPane
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .padding(.horizontal, 48)
                        .padding(.vertical, 24)
                    } else {
                        VStack(spacing: 20) {
                            artworkPane(maxHeight: geo.size.height * 0.38)
                            lyricsPane
                        }
                        .padding(24)
                    }
                }
                .overlay(alignment: .topLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(24)
                    }
                }
            }
        }
    }

    // MARK: - Smart Luminance-Adaptive Background Bleed
    private func appleMusicSmartBleedBackground(size: CGSize) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let data = audioManager.currentTrack?.artworkData, let img = UIImage(data: data) {
                let isBright = img.isImageTooBright()

                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(1.35)
                    .clipped()
                    // Reduce brightness and saturation automatically if cover art is white/light
                    .brightness(isBright ? -0.35 : -0.05)
                    .saturation(isBright ? 0.8 : 1.4)
                    .blur(radius: isBright ? 45 : 65)
                    .opacity(isBright ? 0.65 : 0.90)

                // Adaptive contrast scrim
                Color.black.opacity(isBright ? 0.45 : 0.20)
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Left Pane: Artwork, Metadata, Controls
    private func artworkPane(maxHeight: CGFloat) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            if let data = audioManager.currentTrack?.artworkData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maxHeight)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: maxHeight, height: maxHeight)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 54))
                            .foregroundColor(.white.opacity(0.35))
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(audioManager.currentTrack?.title ?? "Unknown Title")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(audioManager.currentTrack?.artist ?? "Unknown Artist")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { audioManager.playbackProgress },
                        set: { newProgress in
                            if let dur = audioManager.currentTrack?.duration {
                                audioManager.seek(to: newProgress * dur)
                            }
                        }
                    ),
                    in: 0.0...1.0
                )
                .tint(.white)

                HStack {
                    Text(formatTime(audioManager.currentTime))
                    Spacer()
                    Text("-" + formatTime(max(0, (audioManager.currentTrack?.duration ?? 0) - audioManager.currentTime)))
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.65))
            }
            .padding(.horizontal, 4)

            HStack(spacing: 40) {
                Button { audioManager.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(audioManager.isShuffle ? .white : .white.opacity(0.35))
                }

                Button { audioManager.backward() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 26))
                }

                Button { audioManager.togglePlayPause() } label: {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 38))
                        .frame(width: 44, height: 44)
                }

                Button { audioManager.forward() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 26))
                }

                Button { audioManager.toggleRepeat() } label: {
                    Image(systemName: repeatIcon())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(audioManager.repeatMode != .off ? .white : .white.opacity(0.35))
                }
            }
            .foregroundColor(.white)
            .padding(.vertical, 4)

            Spacer(minLength: 8)
        }
    }

    // MARK: - Massive Apple Music Lyrics Pane with Inactive Blur
    private var lyricsPane: some View {
        let lyrics = audioManager.currentLyrics
        let activeId = activeLineId()

        return ScrollViewReader { proxy in
            if lyrics.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 42))
                        .foregroundColor(.white.opacity(0.2))
                    Text("Lyrics Unavailable")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 38) {
                        ForEach(lyrics) { line in
                            let isActive = line.id == activeId

                            VStack(alignment: .leading, spacing: 8) {
                                if line.text.trimmingCharacters(in: .whitespaces).isEmpty {
                                    HStack(spacing: 8) {
                                        Circle().frame(width: 10, height: 10)
                                        Circle().frame(width: 10, height: 10)
                                        Circle().frame(width: 10, height: 10)
                                    }
                                    .foregroundColor(.white)
                                    .opacity(isActive ? 0.95 : 0.25)
                                    .padding(.vertical, 10)
                                } else {
                                    // 42pt massive Apple Music lyric sizing
                                    Text(line.text)
                                        .font(.system(size: 42, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .opacity(isActive ? 1.0 : 0.3)
                                        .blur(radius: isActive ? 0.0 : 1.5) // Subtle blur on non-main lines

                                    if let romaji = line.romanized, !romaji.isEmpty {
                                        Text(romaji)
                                            .font(.system(size: 20, weight: .medium, design: .rounded))
                                            .foregroundColor(.white)
                                            .opacity(isActive ? 0.8 : 0.2)
                                            .blur(radius: isActive ? 0.0 : 1.0)
                                    }
                                }
                            }
                            .id(line.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                audioManager.seek(to: line.time)
                            }
                            .animation(.easeInOut(duration: 0.3), value: isActive)
                        }
                    }
                    .padding(.vertical, 240)
                    .padding(.horizontal, 16)
                }
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.15),
                            .init(color: .black, location: 0.85),
                            .init(color: .clear, location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onChange(of: audioManager.currentTime) { _, _ in
                    if let activeId = activeId {
                        withAnimation(.easeInOut(duration: 0.45)) {
                            proxy.scrollTo(activeId, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func repeatIcon() -> String {
        switch audioManager.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func activeLineId() -> UUID? {
        audioManager.currentLyrics.last(where: { $0.time <= audioManager.currentTime })?.id
    }

    private func formatTime(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Native UIKit Interactive Pan Dismissal Container
struct NowPlayingContainerView<Content: View>: UIViewControllerRepresentable {
    let dismissAction: () -> Void
    let content: Content

    init(dismissAction: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.dismissAction = dismissAction
        self.content = content()
    }

    func makeUIViewController(context: Context) -> NowPlayingHostingController<Content> {
        let vc = NowPlayingHostingController(rootView: content)
        vc.dismissAction = dismissAction
        return vc
    }

    func updateUIViewController(_ uiViewController: NowPlayingHostingController<Content>, context: Context) {
        uiViewController.rootView = content
    }
}

class NowPlayingHostingController<Content: View>: UIHostingController<Content> {
    var dismissAction: (() -> Void)?
    private var panGesture: UIPanGestureRecognizer!
    private var initialTouchY: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began:
            initialTouchY = translation.y
        case .changed:
            if translation.y > 0 {
                view.transform = CGAffineTransform(translationX: 0, y: translation.y)
            }
        case .ended, .cancelled:
            if translation.y > 100 || velocity.y > 600 {
                UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                    self.view.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
                } completion: { _ in
                    self.dismissAction?()
                }
            } else {
                UIView.animate(withDuration: 0.3, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
                    self.view.transform = .identity
                }
            }
        default:
            break
        }
    }
}

extension NowPlayingHostingController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as pS? else { return true } // fallback check
        let velocity = pan.velocity(in: view)
        return velocity.y > abs(velocity.x)
    }
}

// MARK: - Artwork Brightness Analyzer Extension
extension UIImage {
    func isImageTooBright() -> Bool {
        guard let cgImage = self.cgImage else { return false }
        let width = 32
        let height = 32
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.prematureLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return false }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var totalLuminance: CGFloat = 0
        let totalPixels = CGFloat(width * height)

        for i in stride(from: 0, to: rawData.count, by: 4) {
            let r = CGFloat(rawData[i]) / 255.0
            let g = CGFloat(rawData[i+1]) / 255.0
            let b = CGFloat(rawData[i+2]) / 255.0
            // Perceived luminance formula
            let luminance = (0.299 * r) + (0.587 * g) + (0.114 * b)
            totalLuminance += luminance
        }

        let averageLuminance = totalLuminance / totalPixels
        return averageLuminance > 0.60 // Returns true if the cover art is predominantly white/light
    }
}
