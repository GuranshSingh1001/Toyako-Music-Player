import SwiftUI
import Foundation
import MusicKit
import UIKit

struct AppleMusicArtworkDebugResult: Sendable {
    let success: Bool
    let message: String
    let details: String
}

/// Fetches artist artwork from Apple's Apple Music catalog and caches it locally.
///
/// Artist names come from the user's local music metadata. The returned artwork
/// comes from Apple's catalog through MusicKit.
actor AppleMusicArtistArtworkService {
    static let shared = AppleMusicArtistArtworkService()

    private let fileManager = FileManager.default
    private let session: URLSession
    private var memoryCache: [String: Data] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private var authorizationTask: Task<Bool, Never>?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration)
    }

    func imageData(for artistName: String) async -> Data? {
        let name = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.lowercased() != "unknown artist" else {
            return nil
        }

        let key = cacheKey(for: name)

        if let data = memoryCache[key] {
            return data
        }

        if let diskData = readDiskCache(for: key) {
            memoryCache[key] = diskData
            return diskData
        }

        if let existingTask = inFlight[key] {
            return await existingTask.value
        }

        let task = Task<Data?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.fetchArtwork(for: name, cacheKey: key)
        }

        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    func debugTest(artistName: String) async -> AppleMusicArtworkDebugResult {
        let name = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return AppleMusicArtworkDebugResult(
                success: false,
                message: "Enter an artist name.",
                details: "The MusicKit catalog test was not started."
            )
        }

        do {
            let statusBefore = MusicAuthorization.currentStatus
            if statusBefore != .authorized {
                let status = await MusicAuthorization.request()
                guard status == .authorized else {
                    return AppleMusicArtworkDebugResult(
                        success: false,
                        message: "MusicKit authorization was not granted.",
                        details: "Current status: \(String(describing: status)). This test cannot continue without MusicKit authorization in the current implementation."
                    )
                }
            }

            var request = MusicCatalogSearchRequest(term: name, types: [Artist.self])
            request.limit = 5
            let response = try await request.response()
            let artists = Array(response.artists)

            guard !artists.isEmpty else {
                return AppleMusicArtworkDebugResult(
                    success: false,
                    message: "Apple Music returned no artists.",
                    details: "Search term: \(name)"
                )
            }

            let normalizedQuery = normalize(name)
            let artist = artists.first(where: { normalize($0.name) == normalizedQuery }) ?? artists.first!

            guard let artwork = artist.artwork else {
                return AppleMusicArtworkDebugResult(
                    success: false,
                    message: "Artist found, but no artwork was returned.",
                    details: "Matched artist: \(artist.name)"
                )
            }

            guard let url = artwork.url(width: 512, height: 512) else {
                return AppleMusicArtworkDebugResult(
                    success: false,
                    message: "Artist artwork exists, but no image URL was returned.",
                    details: "Matched artist: \(artist.name)"
                )
            }

            var urlRequest = URLRequest(url: url)
            urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, urlResponse) = try await session.data(for: urlRequest)

            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                return AppleMusicArtworkDebugResult(
                    success: false,
                    message: "Artwork request returned an invalid response.",
                    details: url.absoluteString
                )
            }

            guard 200..<300 ~= httpResponse.statusCode, !data.isEmpty else {
                return AppleMusicArtworkDebugResult(
                    success: false,
                    message: "Artwork image download failed.",
                    details: "HTTP \(httpResponse.statusCode)\n\(url.absoluteString)"
                )
            }

            guard UIImage(data: data) != nil else {
                return AppleMusicArtworkDebugResult(
                    success: false,
                    message: "Apple returned data, but it is not a valid image.",
                    details: "Downloaded \(data.count) bytes."
                )
            }

            return AppleMusicArtworkDebugResult(
                success: true,
                message: "Apple Music artist artwork works.",
                details: "Matched: \(artist.name)\nDownloaded: \(data.count) bytes\nHTTP: \(httpResponse.statusCode)"
            )
        } catch {
            return AppleMusicArtworkDebugResult(
                success: false,
                message: "MusicKit request failed.",
                details: "\(String(reflecting: error))"
            )
        }
    }

    private func fetchArtwork(for artistName: String, cacheKey: String) async -> Data? {
        do {
            guard await ensureMusicKitAuthorization() else {
                return nil
            }

            var request = MusicCatalogSearchRequest(
                term: artistName,
                types: [Artist.self]
            )
            request.limit = 5

            let searchResponse = try await request.response()
            let artists = Array(searchResponse.artists)

            let normalizedQuery = normalize(artistName)
            let artist = artists.first(where: {
                normalize($0.name) == normalizedQuery
            }) ?? artists.first

            guard let artist,
                  let artwork = artist.artwork,
                  let url = artwork.url(width: 512, height: 512) else {
                return nil
            }

            var urlRequest = URLRequest(url: url)
            urlRequest.cachePolicy = .returnCacheDataElseLoad

            let (data, urlResponse) = try await session.data(for: urlRequest)

            guard let httpResponse = urlResponse as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode,
                  !data.isEmpty,
                  UIImage(data: data) != nil else {
                return nil
            }

            memoryCache[cacheKey] = data
            writeDiskCache(data, for: cacheKey)
            return data
        } catch {
            // Artist artwork is optional. A network/API failure must never
            // interfere with the local music library or playback.
            return nil
        }
    }

    private func ensureMusicKitAuthorization() async -> Bool {
        if MusicAuthorization.currentStatus == .authorized {
            return true
        }

        if let authorizationTask {
            return await authorizationTask.value
        }

        let task = Task<Bool, Never> {
            let status = await MusicAuthorization.request()
            return status == .authorized
        }

        authorizationTask = task
        let result = await task.value
        authorizationTask = nil
        return result
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func cacheKey(for artistName: String) -> String {
        let normalized = normalize(artistName)
        return normalized.data(using: .utf8)?.base64EncodedString() ?? artistName
    }

    private var cacheDirectory: URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("ArtistArtwork", isDirectory: true)

        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        return directory
    }

    private func diskURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent(key).appendingPathExtension("jpg")
    }

    private func readDiskCache(for key: String) -> Data? {
        let url = diskURL(for: key)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }
        return data
    }

    private func writeDiskCache(_ data: Data, for key: String) {
        try? data.write(to: diskURL(for: key), options: .atomic)
    }
}

struct AppleMusicArtistArtworkView: View {
    let artistName: String
    let size: CGFloat

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .contentShape(Circle())
        .task(id: artistName) {
            let data = await AppleMusicArtistArtworkService.shared.imageData(for: artistName)
            guard !Task.isCancelled else { return }
            image = data.flatMap(UIImage.init(data:))
        }
    }
}
