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
            statusMessage = "Cannot access Documents folder"
            return
        }

        do {
            let files = try fileManager.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)
            let audioExtensions = ["mp3", "m4a", "wav", "flac", "aac", "aiff"]
            let matchedFiles = files.filter { audioExtensions.contains($0.pathExtension.lowercased()) }

            if matchedFiles.isEmpty {
                statusMessage = "Folder is empty: \(docs.path)"
                tracks = []
                return
            }

            var loaded: [LocalTrack] = []
            for file in matchedFiles {
                let asset = AVURLAsset(url: file)
                let duration = CMTimeGetSeconds(asset.duration)
                let title = file.deletingPathExtension().lastPathComponent
                loaded.append(LocalTrack(url: file, title: title, artist: "Local File", duration: duration.isNaN ? 0 : duration))
            }

            self.tracks = loaded
            self.statusMessage = "Loaded \(loaded.count) songs"
        } catch {
            statusMessage = "Error reading files: \(error.localizedDescription)"
        }
    }

    func importExternalURLs(_ urls: [URL]) {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        for url in urls {
            let canAccess = url.startAccessingSecurityScopedResource()
            let dest = docs.appendingPathComponent(url.lastPathComponent)

            if !fileManager.fileExists(atPath: dest.path) {
                try? fileManager.copyItem(at: url, to: dest)
            }

            if canAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        reloadFiles()
    }
}
