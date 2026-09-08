import SwiftUI

struct NowPlayingView: View {
    @Binding var isPresented: Bool

    @EnvironmentObject var audioManager:
        AudioEngineManager

    @State private var
        dragOffset: CGFloat = 0

    @State private var
        isVisible = false

    @State private var
        playPausePressed = false

    @State private var
        previousPressed = false

    @State private var
        nextPressed = false

    var body: some View {
        GeometryReader { geo in

            let landscape =
                geo.size.width >
                geo.size.height

            ZStack {
                Color.black
                    .ignoresSafeArea()

                AppleMusicMovingBleedBackground(
                    artworkData:
                        audioManager
                            .currentTrack?
                            .artworkData
                )
                .ignoresSafeArea()

                if landscape {

                    HStack(
                        spacing:
                            geo.size.width * 0.035
                    ) {
                        artworkPane(
                            maxHeight:
                                geo.size.height
                                * 0.48
                        )
                        .frame(
                            width:
                                geo.size.width
                                * 0.35
                        )

                        lyricsPane
                            .frame(
                                maxWidth:
                                    .infinity,
                                maxHeight:
                                    .infinity
                            )
                    }
                    .padding(
                        .horizontal,
                        48
                    )
                    .padding(
                        .vertical,
                        24
                    )

                } else {

                    VStack(
                        spacing:
                            18
                    ) {
                        artworkPane(
                            maxHeight:
                                geo.size.height
                                * 0.38
                        )

                        lyricsPane
                    }
                    .padding(
                        .horizontal,
                        24
                    )
                }
            }
            .contentShape(
                Rectangle()
            )
            .gesture(
                dismissGesture(
                    height:
                        geo.size.height
                )
            )
            .frame(
                width:
                    geo.size.width,
                height:
                    geo.size.height
            )
            .overlay(
                alignment:
                    .topLeading
            ) {
                Button {
                    close(
                        height:
                            geo.size.height
                    )
                } label: {
                    Image(
                        systemName:
                            "chevron.down"
                    )
                    .font(
                        .system(
                            size: 18,
                            weight: .bold
                        )
                    )
                    .foregroundColor(
                        .white.opacity(
                            0.9
                        )
                    )
                    .frame(
                        width: 52,
                        height: 52
                    )
                    .contentShape(
                        Circle()
                    )
                }
                .padding(
                    .leading,
                    12
                )
                .padding(
                    .top,
                    8
                )
            }
            .offset(
                y:
                    isVisible
                    ? dragOffset
                    : geo.size.height
            )
        }
        .ignoresSafeArea()
        .onAppear {
            if isPresented {
                show()
            }
        }
        .onChange(
            of:
                isPresented
        ) { _, presented in

            if presented {
                show()
            } else {
                isVisible = false
                dragOffset = 0
            }
        }
    }

    // MARK: - Presentation

    private func show() {

        dragOffset = 0

        withAnimation(
            .spring(
                response: 0.38,
                dampingFraction: 0.86
            )
        ) {
            isVisible = true
        }
    }

    private func close(
        height:
            CGFloat
    ) {

        withAnimation(
            .spring(
                response: 0.34,
                dampingFraction: 0.88
            )
        ) {
            dragOffset =
                height
        }

        DispatchQueue.main.asyncAfter(
            deadline:
                .now() + 0.30
        ) {
            isPresented = false
        }
    }

    private func dismissGesture(
        height:
            CGFloat
    ) -> some Gesture {

        DragGesture(
            minimumDistance:
                8,
            coordinateSpace:
                .global
        )
        .onChanged { value in

            guard value.translation.height
                    > 0
            else {
                return
            }

            dragOffset =
                value.translation.height
        }
        .onEnded { value in

            let translation =
                value.translation.height

            let predicted =
                value.predictedEndTranslation
                    .height

            if translation > 100 ||
                predicted > 260 {

                close(
                    height:
                        height
                )

            } else {

                withAnimation(
                    .spring(
                        response: 0.34,
                        dampingFraction: 0.84
                    )
                ) {
                    dragOffset = 0
                }
            }
        }
    }

    // MARK: - Artwork / Controls

    private func artworkPane(
        maxHeight:
            CGFloat
    ) -> some View {

        VStack(
            spacing:
                16
        ) {

            Spacer(
                minLength:
                    4
            )

            if let data =
                audioManager
                    .currentTrack?
                    .artworkData,
               let image =
                    UIImage(
                        data:
                            data
                    ) {

                Image(
                    uiImage:
                        image
                )
                .resizable()
                .scaledToFit()
                .frame(
                    maxHeight:
                        maxHeight
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius:
                            12,
                        style:
                            .continuous
                    )
                )
                .shadow(
                    color:
                        .black.opacity(
                            0.32
                        ),
                    radius:
                        24,
                    y:
                        12
                )
                .id(
                    audioManager
                        .currentTrack?
                        .id
                )

            } else {

                RoundedRectangle(
                    cornerRadius:
                        12,
                    style:
                        .continuous
                )
                .fill(
                    Color.white.opacity(
                        0.08
                    )
                )
                .frame(
                    width:
                        maxHeight,
                    height:
                        maxHeight
                )
                .overlay {
                    Image(
                        systemName:
                            "music.note"
                    )
                    .font(
                        .system(
                            size: 52
                        )
                    )
                    .foregroundColor(
                        .white.opacity(
                            0.35
                        )
                    )
                }
            }

            VStack(
                alignment:
                    .leading,
                spacing:
                    3
            ) {

                Text(
                    audioManager
                        .currentTrack?
                        .title
                    ?? "Unknown Title"
                )
                .font(
                    .system(
                        size: 22,
                        weight: .bold
                    )
                )
                .foregroundColor(
                    .white
                )
                .lineLimit(
                    1
                )

                Text(
                    audioManager
                        .currentTrack?
                        .artist
                    ?? "Unknown Artist"
                )
                .font(
                    .system(
                        size: 17,
                        weight: .medium
                    )
                )
                .foregroundColor(
                    .white.opacity(
                        0.68
                    )
                )
                .lineLimit(
                    1
                )
            }
            .frame(
                maxWidth:
                    .infinity,
                alignment:
                    .leading
            )

            AppleMusicScrubberBar(
                progress:
                    audioManager
                        .playbackProgress,
                duration:
                    audioManager
                        .currentTrack?
                        .duration
                    ?? 0,
                currentTime:
                    audioManager
                        .currentTime,
                onSeek: {
                    progress in

                    guard let duration =
                        audioManager
                            .currentTrack?
                            .duration,
                          duration > 0
                    else {
                        return
                    }

                    audioManager.seek(
                        to:
                            progress
                            * duration
                    )
                }
            )

            HStack(
                spacing:
                    36
            ) {

                Button {
                    audioManager
                        .toggleShuffle()
                } label: {
                    Image(
                        systemName:
                            "shuffle"
                    )
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .foregroundColor(
                        audioManager.isShuffle
                        ? .white
                        : .white.opacity(
                            0.34
                        )
                    )
                }

                Button {
                    previousPressed = true

                    audioManager.backward()

                    DispatchQueue.main.asyncAfter(
                        deadline:
                            .now() + 0.14
                    ) {
                        previousPressed = false
                    }
                } label: {
                    Image(
                        systemName:
                            "backward.fill"
                    )
                    .font(
                        .system(
                            size: 26,
                            weight: .semibold
                        )
                    )
                    .scaleEffect(
                        previousPressed
                        ? 0.76
                        : 1
                    )
                }

                Button {
                    playPausePressed = true

                    audioManager
                        .togglePlayPause()

                    DispatchQueue.main.asyncAfter(
                        deadline:
                            .now() + 0.14
                    ) {
                        playPausePressed = false
                    }
                } label: {
                    Image(
                        systemName:
                            audioManager.isPlaying
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .font(
                        .system(
                            size: 38,
                            weight: .medium
                        )
                    )
                    .frame(
                        width: 48,
                        height: 48
                    )
                    .scaleEffect(
                        playPausePressed
                        ? 0.76
                        : 1
                    )
                    .contentTransition(
                        .symbolEffect(
                            .replace
                        )
                    )
                }

                Button {
                    nextPressed = true

                    audioManager.forward()

                    DispatchQueue.main.asyncAfter(
                        deadline:
                            .now() + 0.14
                    ) {
                        nextPressed = false
                    }
                } label: {
                    Image(
                        systemName:
                            "forward.fill"
                    )
                    .font(
                        .system(
                            size: 26,
                            weight: .semibold
                        )
                    )
                    .scaleEffect(
                        nextPressed
                        ? 0.76
                        : 1
                    )
                }

                Button {
                    audioManager
                        .toggleRepeat()
                } label: {
                    Image(
                        systemName:
                            repeatIcon
                    )
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .foregroundColor(
                        audioManager
                            .repeatMode
                            != .off
                        ? .white
                        : .white.opacity(
                            0.34
                        )
                    )
                }
            }
            .foregroundColor(
                .white
            )

            Spacer(
                minLength:
                    4
            )
        }
    }

    private var repeatIcon:
        String {

        switch audioManager.repeatMode {
        case .off, .all:
            return "repeat"

        case .one:
            return "repeat.1"
        }
    }

    // MARK: - Lyrics

    private var lyricsPane:
        some View {

        let lyrics =
            audioManager.currentLyrics

        let activeID =
            activeLyricID(
                lyrics:
                    lyrics
            )

        return Group {

            if lyrics.isEmpty {

                VStack(
                    spacing:
                        12
                ) {
                    Image(
                        systemName:
                            "quote.bubble"
                    )
                    .font(
                        .system(
                            size: 40
                        )
                    )
                    .foregroundColor(
                        .white.opacity(
                            0.18
                        )
                    )

                    Text(
                        "Lyrics Unavailable"
                    )
                    .font(
                        .headline
                    )
                    .foregroundColor(
                        .white.opacity(
                            0.42
                        )
                    )
                }
                .frame(
                    maxWidth:
                        .infinity,
                    maxHeight:
                        .infinity
                )

            } else {

                SmoothLyricsView(
                    lyrics:
                        lyrics,
                    activeID:
                        activeID
                ) { time in
                    audioManager.seek(
                        to:
                            time
                    )
                }
            }
        }
    }

    private func activeLyricID(
        lyrics:
            [LyricLine]
    ) -> UUID? {

        lyrics.last {
            $0.time <=
                audioManager.currentTime
        }?.id
    }
}

// MARK: - Smooth Lyrics

private struct SmoothLyricsView:
    View {

    let lyrics:
        [LyricLine]

    let activeID:
        UUID?

    let onSeek:
        (TimeInterval) -> Void

    var body: some View {

        ScrollViewReader { proxy in

            ScrollView(
                showsIndicators:
                    false
            ) {

                LazyVStack(
                    alignment:
                        .leading,
                    spacing:
                        28
                ) {

                    ForEach(
                        lyrics
                    ) { line in

                        let active =
                            line.id ==
                            activeID

                        VStack(
                            alignment:
                                .leading,
                            spacing:
                                6
                        ) {

                            if line.text
                                .trimmingCharacters(
                                    in:
                                        .whitespacesAndNewlines
                                )
                                .isEmpty {

                                HStack(
                                    spacing:
                                        7
                                ) {
                                    Circle()
                                        .frame(
                                            width:
                                                8,
                                            height:
                                                8
                                        )

                                    Circle()
                                        .frame(
                                            width:
                                                8,
                                            height:
                                                8
                                        )

                                    Circle()
                                        .frame(
                                            width:
                                                8,
                                            height:
                                                8
                                        )
                                }
                                .foregroundColor(
                                    .white
                                )
                                .opacity(
                                    active
                                    ? 0.9
                                    : 0.22
                                )

                            } else {

                                Text(
                                    line.text
                                )
                                .font(
                                    .system(
                                        size:
                                            active
                                            ? 48
                                            : 43,
                                        weight:
                                            .bold,
                                        design:
                                            .rounded
                                    )
                                )
                                .foregroundColor(
                                    .white
                                )
                                .opacity(
                                    active
                                    ? 1
                                    : 0.30
                                )
                                .scaleEffect(
                                    active
                                    ? 1
                                    : 0.98,
                                    anchor:
                                        .leading
                                )
                                .fixedSize(
                                    horizontal:
                                        false,
                                    vertical:
                                        true
                                )

                                if let romanized =
                                    line.romanized,
                                   !romanized.isEmpty {

                                    Text(
                                        romanized
                                    )
                                    .font(
                                        .system(
                                            size:
                                                active
                                                ? 21
                                                : 19,
                                            weight:
                                                .medium,
                                            design:
                                                .rounded
                                        )
                                    )
                                    .foregroundColor(
                                        .white
                                    )
                                    .opacity(
                                        active
                                        ? 0.70
                                        : 0.20
                                    )
                                }
                            }
                        }
                        .id(
                            line.id
                        )
                        .contentShape(
                            Rectangle()
                        )
                        .onTapGesture {
                            onSeek(
                                line.time
                            )
                        }
                        .animation(
                            .easeInOut(
                                duration:
                                    0.22
                            ),
                            value:
                                active
                        )
                    }
                }
                .padding(
                    .horizontal,
                    12
                )
                .padding(
                    .vertical,
                    220
                )
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(
                            color:
                                .clear,
                            location:
                                0
                        ),
                        .init(
                            color:
                                .black,
                            location:
                                0.14
                        ),
                        .init(
                            color:
                                .black,
                            location:
                                0.86
                        ),
                        .init(
                            color:
                                .clear,
                            location:
                                1
                        )
                    ],
                    startPoint:
                        .top,
                    endPoint:
                        .bottom
                )
            )
            .onChange(
                of:
                    activeID
            ) { _, newID in

                guard let newID
                else {
                    return
                }

                withAnimation(
                    .easeInOut(
                        duration:
                            0.38
                    )
                ) {
                    proxy.scrollTo(
                        newID,
                        anchor:
                            .center
                    )
                }
            }
        }
    }
}

// MARK: - Apple Music Scrubber

struct AppleMusicScrubberBar:
    View {

    let progress:
        Double

    let duration:
        TimeInterval

    let currentTime:
        TimeInterval

    let onSeek:
        (Double) -> Void

    @State private var
        dragging = false

    @State private var
        dragProgress = 0.0

    private var shownProgress:
        Double {

        dragging
        ? dragProgress
        : progress
    }

    var body: some View {

        VStack(
            spacing:
                7
        ) {

            GeometryReader { geometry in

                ZStack(
                    alignment:
                        .leading
                ) {

                    Capsule()
                        .fill(
                            .white.opacity(
                                dragging
                                ? 0.28
                                : 0.20
                            )
                        )
                        .frame(
                            height:
                                dragging
                                ? 8
                                : 5
                        )

                    Capsule()
                        .fill(
                            .white.opacity(
                                dragging
                                ? 1
                                : 0.88
                            )
                        )
                        .frame(
                            width:
                                geometry.size.width
                                * CGFloat(
                                    min(
                                        1,
                                        max(
                                            0,
                                            shownProgress
                                        )
                                    )
                                ),
                            height:
                                dragging
                                ? 8
                                : 5
                        )

                    Circle()
                        .fill(
                            .white
                        )
                        .frame(
                            width:
                                dragging
                                ? 14
                                : 0,
                            height:
                                dragging
                                ? 14
                                : 0
                        )
                        .position(
                            x:
                                min(
                                    geometry.size.width,
                                    max(
                                        0,
                                        geometry.size.width
                                        * CGFloat(
                                            shownProgress
                                        )
                                    )
                                ),
                            y:
                                geometry.size.height
                                / 2
                        )
                        .shadow(
                            radius:
                                3
                        )
                        .opacity(
                            dragging
                            ? 1
                            : 0
                        )
                }
                .frame(
                    maxWidth:
                        .infinity,
                    maxHeight:
                        .infinity
                )
                .contentShape(
                    Rectangle()
                )
                .gesture(
                    DragGesture(
                        minimumDistance:
                            0
                    )
                    .onChanged {
                        value in

                        dragging =
                            true

                        dragProgress =
                            max(
                                0,
                                min(
                                    1,
                                    Double(
                                        value
                                            .location
                                            .x
                                        /
                                        geometry
                                            .size
                                            .width
                                    )
                                )
                            )
                    }
                    .onEnded {
                        value in

                        let finalProgress =
                            max(
                                0,
                                min(
                                    1,
                                    Double(
                                        value
                                            .location
                                            .x
                                        /
                                        geometry
                                            .size
                                            .width
                                    )
                                )
                            )

                        dragProgress =
                            finalProgress

                        onSeek(
                            finalProgress
                        )

                        withAnimation(
                            .spring(
                                response:
                                    0.25,
                                dampingFraction:
                                    0.78
                            )
                        ) {
                            dragging =
                                false
                        }
                    }
                )
                .animation(
                    .spring(
                        response:
                            0.22,
                        dampingFraction:
                            0.8
                    ),
                    value:
                        dragging
                )
            }
            .frame(
                height:
                    18
            )

            HStack {
                Text(
                    formatTime(
                        dragging
                        ? duration
                            * dragProgress
                        : currentTime
                    )
                )

                Spacer()

                let displayed =
                    dragging
                    ? duration
                        * dragProgress
                    : currentTime

                Text(
                    "-" +
                    formatTime(
                        max(
                            0,
                            duration
                            - displayed
                        )
                    )
                )
            }
            .font(
                .system(
                    size:
                        12,
                    weight:
                        .medium,
                    design:
                        .monospaced
                )
            )
            .foregroundColor(
                .white.opacity(
                    0.62
                )
            )
        }
    }

    private func formatTime(
        _ duration:
            TimeInterval
    ) -> String {

        let seconds =
            max(
                0,
                Int(
                    duration
                )
            )

        return String(
            format:
                "%d:%02d",
            seconds / 60,
            seconds % 60
        )
    }
}
