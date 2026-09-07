import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audioManager: AudioEngineManager
    @StateObject private var library = LocalLibrary()

    @State private var showFilePicker = false
    @State private var showNowPlaying = false

    var body: some View {
        NavigationSplitView {
            List {
                Section("Library") {
                    Text("Songs (\(library.tracks.count))")
                }
                Section("Debug Info") {
                    Text(library.statusMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Library")
        } detail: {
            ZStack(alignment: .bottom) {
                VStack {
                    if library.tracks.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "music.note")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No Tracks Detected")
                                .font(.title3.bold())
                            Text(library.statusMessage)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .foregroundColor(.secondary)
                            
                            Button("Choose Audio Files") {
                                showFilePicker = true
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Scan Folder Again") {
                                library.reloadFiles()
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(library.tracks) { track in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(track.title)
                                        .font(.headline)
                                    Text(track.artist)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(String(format: "%.0fs", track.duration))
                                    .font(.caption.monospacedDigit())
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                audioManager.play(track: track)
                            }
                        }
                    }
                }

                if audioManager.currentTrack != nil {
                    MiniPlayerView()
                        .onTapGesture {
                            showNowPlaying = true
                        }
                        .padding(.bottom, 12)
                }
            }
            .navigationTitle("Songs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        library.reloadFiles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker { urls in
                library.importExternalURLs(urls)
            }
        }
        .onAppear {
            library.reloadFiles()
        }
    }
}
