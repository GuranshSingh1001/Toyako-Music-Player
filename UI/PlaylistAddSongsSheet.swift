import SwiftUI

struct PlaylistAddSongsSheet: View {
    let playlist: Playlist
    let library: LocalLibrary
    @Environment(\.dismiss) var dismiss
    @State private var selectedURLs: Set<URL> = []
    @State private var navigationPath: [URL] = []

    private var rootDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            FolderBrowserView(
                currentURL: rootDirectory,
                rootURL: rootDirectory,
                library: library,
                selectedURLs: $selectedURLs,
                onNavigate: { folderURL in
                    navigationPath.append(folderURL)
                }
            )
            .navigationDestination(for: URL.self) { folderURL in
                FolderBrowserView(
                    currentURL: folderURL,
                    rootURL: rootDirectory,
                    library: library,
                    selectedURLs: $selectedURLs,
                    onNavigate: { nextURL in
                        navigationPath.append(nextURL)
                    }
                )
            }
            .navigationTitle("Add Songs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done (\(selectedURLs.count))") {
                        library.addTracksToPlaylist(playlistID: playlist.id, trackURLs: Array(selectedURLs))
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            selectedURLs = Set(playlist.trackURLs)
        }
    }
}
