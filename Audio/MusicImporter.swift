import Foundation
import AVFoundation

struct LocalTrack: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let title: String
    let artist: String
    let duration: TimeInterval
}

@MainActor
class LocalLibrary: ObservableObject {
    @Published var tracks: [LocalTrack] = []
    @Published var statusMessage: String = "No songs loaded"

    func reloadFiles() {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            statusMessage = "Cannot locate Documents folder"
            return
        }

        let audioExtensions = Set(["mp3", "m4a", "wav", "flac", "aac", "aiff", "alac"])
        var discoveredTracks: [LocalTrack] = []

        // Recursive enumerator: searches root AND all subfolders/containers
        if let enumerator = fileManager.enumerator(
            at: docs,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                    let asset = AVURLAsset(url: fileURL)
                    let duration = CMTimeGetSeconds(asset.duration)
                    let title = fileURL.deletingPathExtension().lastPathComponent
                    
                    discoveredTracks.append(
                        LocalTrack(
                            url: fileURL,
                            title: title,
                            artist: "Local Track",
                            duration: duration.isNaN ? 0 : duration
                        )
                    )
                }
            }
        }

        if discoveredTracks.isEmpty {
            statusMessage = "Zero audio files found in: \(docs.path)"
            tracks = []
        } else {
            tracks = discoveredTracks
            statusMessage = "Successfully loaded \(discoveredTracks.count) audio file(s)"
        }
    }

    func importExternalURLs(_ urls: [URL]) {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        for url in urls {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }

            let destination = docs.appendingPathComponent(url.lastPathComponent)
            try? fileManager.removeItem(at: destination)
            try? fileManager.copyItem(at: url, to: destination)
        }
        reloadFiles()
    }
}
