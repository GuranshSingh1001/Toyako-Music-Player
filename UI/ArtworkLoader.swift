import SwiftUI
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

/// Shared, deduplicated artwork loader. Artwork is intentionally kept out of
/// LocalTrack/AlbumGroup so a cover can never invalidate the entire library.
actor ArtworkStore {
    static let shared = ArtworkStore()

    private var memory: [URL: Data] = [:]
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    func data(for url: URL) async -> Data? {
        let key = url.standardizedFileURL
        if let cached = memory[key] { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task.detached(priority: .utility) {
            await Self.loadData(for: key)
        }
        inFlight[key] = task

        let result = await task.value
        inFlight[key] = nil
        if let result { memory[key] = result }
        return result
    }

    nonisolated private static func loadData(for url: URL) async -> Data? {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ToyakoArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let cacheFile = cacheDirectory.appendingPathComponent(filename(for: url))
        if let data = try? Data(contentsOf: cacheFile) {
            return data
        }

        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        for item in metadata {
            let keys = [
                item.commonKey?.rawValue,
                item.identifier?.rawValue,
                item.key.map { String(describing: $0) }
            ]
            .compactMap { $0?.lowercased() }

            guard keys.contains(where: {
                $0 == "artwork" || $0.contains("artwork") ||
                $0.contains("covr") || $0.contains("apic") || $0.contains("picture") || $0.contains("cover")
            }) else { continue }

            var artwork: Data?
            if let data = try? await item.load(.dataValue) {
                artwork = data
            } else if let value = try? await item.load(.value), let data = value as? Data {
                artwork = data
            }

            if let artwork, let downsampled = downsample(artwork) {
                try? downsampled.write(to: cacheFile, options: .atomic)
                return downsampled
            }
        }
        return nil
    }

    nonisolated private static func filename(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    nonisolated private static func downsample(_ data: Data, maxPixel: Int = 512) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return data
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return data
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return data }
        return output as Data
    }
}

struct LazyArtwork: View {
    let url: URL?
    let size: CGFloat
    let cornerRadius: CGFloat

    @State private var data: Data?

    init(url: URL?, size: CGFloat, cornerRadius: CGFloat = 12) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            guard let url else { return }
            let loaded = await ArtworkStore.shared.data(for: url)
            guard !Task.isCancelled else { return }
            data = loaded
        }
    }
}

struct LazyAlbumArtwork: View {
    let url: URL?
    let cornerRadius: CGFloat
    @State private var data: Data?

    init(url: URL?, cornerRadius: CGFloat = 12) {
        self.url = url
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay { Image(systemName: "opticaldisc").font(.title).foregroundStyle(.secondary) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            guard let url else { return }
            let loaded = await ArtworkStore.shared.data(for: url)
            guard !Task.isCancelled else { return }
            data = loaded
        }
    }
}
