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
                let isSecurityScoped = url.startAccessingSecurityScopedResource()
                let destinationURL = documentDirectory.appendingPathComponent(url.lastPathComponent)
                
                if !fileManager.fileExists(atPath: destinationURL.path) {
                    try? fileManager.copyItem(at: url, to: destinationURL)
                }
                if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
                
                await processAndInsert(url: destinationURL, context: context)
            }
            try? context.save() // Forces UI to update
        }
    }
    
    static func scanDocumentsDirectory(into context: ModelContext, existingTracks: [Track]) {
        Task {
            let fileManager = FileManager.default
            let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            
            guard let urls = try? fileManager.contentsOfDirectory(at: documentDirectory, includingPropertiesForKeys: nil) else { return }
            
            let audioExtensions = ["mp3", "m4a", "wav", "aiff", "alac", "flac"]
            let existingURLs = Set(existingTracks.map { $0.fileURL.lastPathComponent })
            
            for url in urls where audioExtensions.contains(url.pathExtension.lowercased()) {
                if !existingURLs.contains(url.lastPathComponent) {
                    await processAndInsert(url: url, context: context)
                }
            }
            try? context.save()
        }
    }
    
    private static func processAndInsert(url: URL, context: ModelContext) async {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration).seconds
            let metadata = try await asset.load(.commonMetadata)
            
            var title = url.deletingPathExtension().lastPathComponent
            var artist = "Unknown Artist"
            
            for item in metadata {
                if item.commonKey?.rawValue == "title", let value = try await item.load(.stringValue) { title = value }
                if item.commonKey?.rawValue == "artist", let value = try await item.load(.stringValue) { artist = value }
            }
            
            let track = Track(fileURL: url, title: title, artistName: artist, albumTitle: "Unknown Album", duration: duration)
            context.insert(track)
        } catch {
            print("Failed to load metadata for \(url)")
        }
    }
}