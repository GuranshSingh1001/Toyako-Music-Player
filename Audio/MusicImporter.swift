import SwiftData
import AVFoundation
import Foundation

@MainActor
struct MusicImporter {
    static func importAudioFiles(from urls: [URL], into context: ModelContext) {
        Task {
            let fileManager = FileManager.default
            let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            
            for url in urls {
                // Request security-scoped access to read files from outside the app sandbox
                guard url.startAccessingSecurityScopedResource() else { continue }
                
                let destinationURL = documentDirectory.appendingPathComponent(url.lastPathComponent)
                
                // Copy file locally for guaranteed offline persistence
                if !fileManager.fileExists(atPath: destinationURL.path) {
                    try? fileManager.copyItem(at: url, to: destinationURL)
                }
                url.stopAccessingSecurityScopedResource()
                
                let asset = AVURLAsset(url: destinationURL)
                do {
                    let duration = try await asset.load(.duration).seconds
                    let metadata = try await asset.load(.commonMetadata)
                    
                    var title = url.deletingPathExtension().lastPathComponent
                    var artist = "Unknown Artist"
                    
                    for item in metadata {
                        if item.commonKey?.rawValue == "title", let value = try await item.load(.stringValue) { title = value }
                        if item.commonKey?.rawValue == "artist", let value = try await item.load(.stringValue) { artist = value }
                    }
                    
                    let track = Track(fileURL: destinationURL, title: title, artistName: artist, albumTitle: "Unknown Album", duration: duration)
                    context.insert(track)
                } catch {
                    print("Failed to load metadata for \(destinationURL)")
                }
            }
        }
    }
}
