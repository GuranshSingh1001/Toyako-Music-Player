import SwiftUI

/// Toyako Next is a deliberately expressive visual layer over the existing
/// offline library and playback engine. Classic remains a separate, untouched path.
struct ToyakoNextHomeView: View {
    let tracks: [LocalTrack]
    let recentlyPlayed: [LocalTrack]
    let library: LocalLibrary
    let currentTrack: LocalTrack?
    let isPlaying: Bool
    let onImport: () -> Void
    let onNewPlaylist: () -> Void
    let onPlayTrack: (Int) -> Void
    let onShuffleAll: () -> Void
    let onOpenPlayer: () -> Void

    @AppStorage("Toyako.Interface.Mode") private var interfaceMode = "next"

    private let ink = Color(red: 0.16, green: 0.17, blue: 0.22)
    private let paper = Color(red: 0.98, green: 0.96, blue: 0.90)
    private let lime = Color(red: 0.77, green: 0.96, blue: 0.36)
    private let coral = Color(red: 1.00, green: 0.43, blue: 0.34)
    private let lilac = Color(red: 0.73, green: 0.66, blue: 0.98)

    private var featuredTrack: LocalTrack? {
        currentTrack ?? recentlyPlayed.first ?? tracks.first
    }

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    welcomeCard

                    if let featuredTrack {
                        nowPlayingCard(featuredTrack)
                    }

                    quickActions

                    if !recentlyPlayed.isEmpty {
                        recentSection
                    }

                    libraryCount
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 124)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TOYAKO")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(ink.opacity(0.55))
                Text("Good sound.\nGood mood.")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .tracking(-1.5)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                interfaceMode = "classic"
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.left.arrow.right")
                    Text("Classic")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(.white.opacity(0.78), in: Capsule())
                .overlay(Capsule().stroke(ink.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Switch to Classic mode")
        }
    }

    private var welcomeCard: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(lime)

            Circle()
                .fill(coral)
                .frame(width: 126, height: 126)
                .offset(x: 25, y: -34)

            Circle()
                .stroke(ink.opacity(0.18), lineWidth: 2)
                .frame(width: 164, height: 164)
                .offset(x: 35, y: 48)

            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                    Text("YOUR OFFLINE UNIVERSE")
                        .tracking(1.4)
                }
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(ink.opacity(0.65))

                Text(tracks.isEmpty ? "A little space\nfor your music." : "Your music.\nYour rules.")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .tracking(-1.5)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(tracks.isEmpty ? "Bring your favourite tracks in and make yourself at home." : "\(tracks.count) tracks, ready when you are.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(ink.opacity(0.72))

                Button(action: tracks.isEmpty ? onImport : onShuffleAll) {
                    HStack(spacing: 9) {
                        Image(systemName: tracks.isEmpty ? "plus" : "shuffle")
                        Text(tracks.isEmpty ? "Add your music" : "Surprise me")
                    }
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(minHeight: 244)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private func nowPlayingCard(_ track: LocalTrack) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("ON THE TURNTABLE")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(ink.opacity(0.48))
                Spacer()
                Circle().fill(isPlaying ? Color.green : coral).frame(width: 8, height: 8)
                Text(isPlaying ? "PLAYING" : "PAUSED")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(ink.opacity(0.6))
            }

            Button(action: onOpenPlayer) {
                HStack(spacing: 15) {
                    LazyArtwork(url: library.artworkURL(for: track) ?? track.url, size: 86, cornerRadius: 18)
                        .frame(width: 86, height: 86)
                        .rotationEffect(.degrees(-3))
                        .shadow(color: ink.opacity(0.16), radius: 10, y: 6)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title)
                            .font(.system(size: 19, weight: .black, design: .rounded))
                            .foregroundStyle(ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(track.artist)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(ink.opacity(0.58))
                            .lineLimit(1)
                        Text("OPEN THE PLAYER  ↗")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(coral)
                            .padding(.top, 4)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(ink)
                }
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(ink.opacity(0.07), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            actionTile("Import", symbol: "plus", color: coral, action: onImport)
            actionTile("Playlist", symbol: "rectangle.stack.badge.plus", color: lilac, action: onNewPlaylist)
            actionTile("Shuffle", symbol: "shuffle", color: lime, action: onShuffleAll)
        }
    }

    private func actionTile(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(ink)
                Text(title)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(ink)
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .padding(14)
            .background(color, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Back for another spin")
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(ink)
                Spacer()
                Text("RECENT")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(ink.opacity(0.42))
            }

            VStack(spacing: 8) {
                ForEach(Array(recentlyPlayed.prefix(6))) { track in
                    Button {
                        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                            onPlayTrack(index)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            LazyArtwork(url: library.artworkURL(for: track) ?? track.url, size: 48, cornerRadius: 12)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(ink)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(ink.opacity(0.52))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 25))
                                .foregroundStyle(ink.opacity(0.72))
                        }
                        .padding(9)
                        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var libraryCount: some View {
        HStack(spacing: 0) {
            countPill(value: tracks.count, label: "TRACKS")
            countPill(value: Set(tracks.map(\.album)).count, label: "ALBUMS")
            countPill(value: Set(tracks.map(\.artist)).count, label: "ARTISTS")
        }
        .padding(.vertical, 15)
        .background(lilac.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func countPill(value: Int, label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(ink)
            Text(label)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }
}


/// Compact Next-mode controls keep the playful visual language visible on every tab.
struct ToyakoNextMiniPlayer: View {
    @EnvironmentObject private var audioManager: AudioEngineManager
    @EnvironmentObject private var clock: PlaybackClock
    let isNowPlayingPresented: Bool
    let onOpenNowPlaying: () -> Void

    private let ink = Color(red: 0.16, green: 0.17, blue: 0.22)
    private let lime = Color(red: 0.77, green: 0.96, blue: 0.36)

    var body: some View {
        HStack(spacing: 11) {
            Button(action: onOpenNowPlaying) {
                HStack(spacing: 10) {
                    if let track = audioManager.currentTrack {
                        LazyArtwork(url: track.url, size: 42, cornerRadius: 11)
                    } else {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(lime)
                            .frame(width: 42, height: 42)
                            .overlay(Image(systemName: "waveform").foregroundStyle(ink))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(audioManager.currentTrack?.title ?? "Pick your soundtrack")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                        Text(audioManager.currentTrack?.artist ?? "Your library is waiting")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(ink.opacity(0.58))
                            .lineLimit(1)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ink.opacity(0.12))
                                Capsule().fill(ink).frame(width: proxy.size.width * min(max(clock.playbackProgress, 0), 1))
                            }
                        }
                        .frame(height: 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button { audioManager.togglePlayPause() } label: {
                Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(ink)
                    .frame(width: 42, height: 42)
                    .background(lime, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(audioManager.currentTrack == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.98, green: 0.96, blue: 0.90), in: Capsule())
        .overlay(Capsule().stroke(ink.opacity(0.16), lineWidth: 1.5))
        .allowsHitTesting(!isNowPlayingPresented)
    }
}

/// A separate, playful Now Playing surface. It talks to the same audio engine
/// as Classic, so changing presentation never changes the active song or queue.
struct ToyakoNextNowPlayingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var audioManager: AudioEngineManager
    @EnvironmentObject private var clock: PlaybackClock

    private let ink = Color(red: 0.16, green: 0.17, blue: 0.22)
    private let paper = Color(red: 0.98, green: 0.96, blue: 0.90)
    private let lime = Color(red: 0.77, green: 0.96, blue: 0.36)
    private let coral = Color(red: 1.00, green: 0.43, blue: 0.34)

    private func timeLabel(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                paper.ignoresSafeArea()

                Circle()
                    .fill(lime)
                    .frame(width: proxy.size.width * 0.9)
                    .blur(radius: 2)
                    .offset(x: proxy.size.width * 0.42, y: -proxy.size.height * 0.38)

                Circle()
                    .fill(coral.opacity(0.75))
                    .frame(width: proxy.size.width * 0.55)
                    .blur(radius: 2)
                    .offset(x: -proxy.size.width * 0.52, y: proxy.size.height * 0.38)

                VStack(spacing: 0) {
                    HStack {
                        Button { isPresented = false } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 17, weight: .black))
                                .foregroundStyle(ink)
                                .frame(width: 46, height: 46)
                                .background(.white.opacity(0.8), in: Circle())
                        }
                        .buttonStyle(.plain)

                        Spacer()
                        Text("TOYAKO / NOW")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(ink.opacity(0.55))
                        Spacer()

                        Button {} label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 17, weight: .black))
                                .foregroundStyle(ink)
                                .frame(width: 46, height: 46)
                                .background(.white.opacity(0.8), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(true)
                        .opacity(0.25)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)

                    Spacer(minLength: 18)

                    if let track = audioManager.currentTrack {
                        LazyArtwork(url: track.url, size: min(proxy.size.width - 76, proxy.size.height * 0.43), cornerRadius: 28)
                            .frame(width: min(proxy.size.width - 76, proxy.size.height * 0.43), height: min(proxy.size.width - 76, proxy.size.height * 0.43))
                            .rotationEffect(.degrees(audioManager.isPlaying ? -2 : 0))
                            .shadow(color: ink.opacity(0.22), radius: 28, y: 18)
                            .padding(.bottom, 30)

                        VStack(spacing: 7) {
                            Text(track.title)
                                .font(.system(size: 27, weight: .black, design: .rounded))
                                .tracking(-0.8)
                                .foregroundStyle(ink)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            Text(track.artist)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(ink.opacity(0.58))
                        }
                        .padding(.horizontal, 28)

                        Spacer(minLength: 22)

                        GeometryReader { bar in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ink.opacity(0.12))
                                Capsule()
                                    .fill(ink)
                                    .frame(width: bar.size.width * min(max(clock.playbackProgress, 0), 1))
                            }
                        }
                        .frame(height: 7)
                        .padding(.horizontal, 30)

                        HStack(spacing: 0) {
                            Text(timeLabel(clock.currentTime))
                            Spacer()
                            Text(timeLabel(track.duration))
                        }
                        .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(ink.opacity(0.48))
                        .padding(.horizontal, 31)
                        .padding(.top, 7)

                        HStack(spacing: 34) {
                            Button { audioManager.backward() } label: {
                                Image(systemName: "backward.end.fill")
                                    .font(.system(size: 24, weight: .bold))
                            }
                            Button { audioManager.togglePlayPause() } label: {
                                Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 25, weight: .black))
                                    .contentTransition(.symbolEffect(.replace))
                                    .frame(width: 76, height: 76)
                                    .background(lime, in: Circle())
                                    .overlay(Circle().stroke(ink, lineWidth: 2))
                            }
                            Button { audioManager.forward() } label: {
                                Image(systemName: "forward.end.fill")
                                    .font(.system(size: 24, weight: .bold))
                            }
                        }
                        .foregroundStyle(ink)
                        .buttonStyle(.plain)
                        .padding(.top, 24)
                        .padding(.bottom, 28)
                    } else {
                        ContentUnavailableView("Nothing playing", systemImage: "waveform", description: Text("Choose a track from your library to get started."))
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
    }
}
