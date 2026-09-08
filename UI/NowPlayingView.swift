import SwiftUI

struct NowPlayingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var audioManager: AudioEngineManager

    @State private var dragOffset: CGFloat = 0
    @State private var isVisible: Bool = false

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            
            let dismissGesture = DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { value in
                    let y = value.translation.height
                    if y > 0 {
                        dragOffset = y
                    }
                }
                .onEnded { value in
                    let y = value.translation.height
                    let predicted = value.predictedEndTranslation.height
                    if y > 100 || (predicted - y) > 200 {
                        withAnimation(.interpolatingSpring(stiffness: 250, damping: 25)) {
                            dragOffset = geo.size.height
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isPresented = false
                        }
                    } else {
                        withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
                            dragOffset = 0
                        }
                    }
                }

            ZStack {
                Color.black.ignoresSafeArea()
                
                // 1. Moving Apple Music Ambient Mesh Bleed
                AppleMusicMovingBleedBackground(artworkData: audioManager.currentTrack?.artworkData)
                    .contentShape(Rectangle())
                    .gesture(dismissGesture)
                    .ignoresSafeArea()

                if isLandscape {
                    HStack(spacing: geo.size.width * 0.035) {
                        artworkPane(maxHeight: geo.size.height * 0.48)
                            .frame(width: geo.size.width * 0.35)
                            .contentShape(Rectangle())
                            .gesture(dismissGesture)

                        lyricsPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 20) {
                        artworkPane(maxHeight: geo.size.height * 0.38)
                            .contentShape(Rectangle())
                            .gesture(dismissGesture)
                        
                        lyricsPane
                    }
                    .padding(24)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(alignment: .topLeading) {
                Button {
                    withAnimation(.interpolatingSpring(stiffness: 250, damping: 25)) {
                        dragOffset = geo.size.height
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(24)
                }
            }
            .offset(y: isVisible ? dragOffset : geo.size.height)
            .onAppear {
                withAnimation(.interpolatingSpring(stiffness: 250, damping: 25)) {
                    isVisible = true
                }
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

            // Authentic Apple Music Pill Scrubber
            AppleMusicScrubberBar(
                progress: audioManager.playbackProgress,
                duration: audioManager.currentTrack?.duration ?? 0,
                currentTime: audioManager.currentTime,
                onSeek: { newProgress in
                    if let dur = audioManager.currentTrack?.duration {
                        audioManager.seek(to: newProgress * dur)
                    }
                }
            )
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

    // MARK: - Lyrics Pane
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
                                    Text(line.text)
                                        .font(.system(size: 50, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .opacity(isActive ? 1.0 : 0.3)
                                        .blur(radius: isActive ? 0.0 : 1.5)

                                    if let romaji = line.romanized, !romaji.isEmpty {
                                        Text(romaji)
                                            .font(.system(size: 22, weight: .medium, design: .rounded))
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
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isActive)
                        }
                    }
                    .padding(.vertical, 240)
                    .padding(.horizontal, 16)
                }
                .compositingGroup()
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
                .onChange(of: activeId) { _, newId in
                    if let newId = newId {
                        withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
                            proxy.scrollTo(newId, anchor: .center)
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
}

// MARK: - Authentic Apple Music Interactive Scrubber
struct AppleMusicScrubberBar: View {
    let progress: Double
    let duration: TimeInterval
    let currentTime: TimeInterval
    let onSeek: (Double) -> Void

    @State private var isDragging: Bool = false
    @State private var dragProgress: Double = 0.0

    private var activeProgress: Double {
        isDragging ? dragProgress : progress
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track base (translucent capsule)
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: isDragging ? 8 : 5)

                    // Track elapsed fill
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: max(0, min(geo.size.width * CGFloat(activeProgress), geo.size.width)),
                               height: isDragging ? 8 : 5)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                // 1. Instantly jump to position on tap (without expanding)
                .onTapGesture(coordinateSpace: .local) { location in
                    let computed = Double(location.x / geo.size.width)
                    let finalVal = max(0.0, min(1.0, computed))
                    onSeek(finalVal)
                }
                // 2. Expand and scrub ONLY when actively dragging
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            isDragging = true
                            let computed = Double(value.location.x / geo.size.width)
                            dragProgress = max(0.0, min(1.0, computed))
                        }
                        .onEnded { value in
                            let computed = Double(value.location.x / geo.size.width)
                            let finalVal = max(0.0, min(1.0, computed))
                            onSeek(finalVal)
                            isDragging = false
                        }
                )
                .animation(.easeInOut(duration: 0.15), value: isDragging)
            }
            .frame(height: 14)

            // Timestamps
            HStack {
                Text(formatTime(isDragging ? duration * dragProgress : currentTime))
                Spacer()
                let remaining = max(0, duration - (isDragging ? duration * dragProgress : currentTime))
                Text("-" + formatTime(remaining))
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.6))
        }
    }

    private func formatTime(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}


// MARK: - Animated Apple Music Bleed Engine
struct AppleMusicMovingBleedBackground: View {
    let artworkData: Data?
    @State private var isBright: Bool = false
    @State private var phase: Bool = false

    var body: some View {
        ZStack {
            if let data = artworkData, let img = UIImage(data: data) {
                // Secondary offset layer
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(phase ? 1.45 : 1.30)
                    .rotationEffect(.degrees(phase ? 8 : -8))
                    .offset(x: phase ? 30 : -30, y: phase ? -25 : 25)
                    .clipped()
                    .brightness(isBright ? -0.15 : -0.05)
                    .saturation(isBright ? 0.8 : 1.45)
                    .blur(radius: 60, opaque: true)
                    .opacity(0.75)

                // Primary moving layer
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(phase ? 1.35 : 1.50)
                    .rotationEffect(.degrees(phase ? -12 : 12))
                    .offset(x: phase ? -35 : 35, y: phase ? 30 : -30)
                    .clipped()
                    .brightness(isBright ? -0.15 : -0.05)
                    .saturation(isBright ? 0.85 : 1.5)
                    .blur(radius: isBright ? 45 : 65, opaque: true)
                    .opacity(isBright ? 0.65 : 0.92)
            } else {
                Color.black
            }
        }
        .drawingGroup()
        .onAppear {
            calculateBrightness()
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                phase.toggle()
            }
        }
        .onChange(of: artworkData) { _, _ in calculateBrightness() }
    }

    private func calculateBrightness() {
        guard let data = artworkData, let img = UIImage(data: data) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let bright = img.isImageTooBright()
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.isBright = bright
                }
            }
        }
    }
}

// MARK: - Safe Artwork Brightness Analyzer
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
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return false }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var totalLuminance: CGFloat = 0
        let totalPixels = CGFloat(width * height)

        for i in stride(from: 0, to: rawData.count, by: 4) {
            let r = CGFloat(rawData[i]) / 255.0
            let g = CGFloat(rawData[i+1]) / 255.0
            let b = CGFloat(rawData[i+2]) / 255.0
            let luminance = (0.299 * r) + (0.587 * g) + (0.114 * b)
            totalLuminance += luminance
        }

        let averageLuminance = totalLuminance / totalPixels
        return averageLuminance > 0.60
    }
}
