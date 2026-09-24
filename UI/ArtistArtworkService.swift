import Foundation
import SwiftUI
import UIKit

// MARK: - Artist Artwork
// Uses public metadata services instead of Apple Music / MusicKit.
// Source order: Deezer -> iTunes Search. Results are cached on disk.

enum ArtistArtworkSource: String {
    case deezer = "Deezer"
    case iTunes = "iTunes"
    case none = "None"
}

struct ArtistArtworkDebugResult: Sendable {
    let artist: String
    let source: ArtistArtworkSource
    let matchedName: String?
    let imageURL: String?
    let bytes: Int
    let message: String
}

actor ArtistArtworkService {
    static let shared = ArtistArtworkService()

    private let session: URLSession
    private let fileManager = FileManager.default
    private var memoryCache: [String: Data] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
    }

    func imageData(for artistName: String) async -> Data? {
        let result = await fetch(artistName: artistName, debug: false)
        return result.data
    }

    func debugFetch(artistName: String) async -> ArtistArtworkDebugResult {
        let name = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = cacheKey(for: name)
        if let cached = memoryCache[key] ?? readDiskCache(for: key) {
            memoryCache[key] = cached
            return ArtistArtworkDebugResult(
                artist: name, source: .none, matchedName: nil, imageURL: nil,
                bytes: cached.count, message: "Artwork is already cached locally."
            )
        }

        let result = await fetchNetworkDetailed(artistName: name)
        if let data = result.data {
            memoryCache[key] = data
            writeDiskCache(data, for: key)
        }
        return ArtistArtworkDebugResult(
            artist: name,
            source: result.source,
            matchedName: result.matchedName,
            imageURL: result.imageURL,
            bytes: result.data?.count ?? 0,
            message: result.message
        )
    }

    func clearCache() {
        memoryCache.removeAll()
        try? fileManager.removeItem(at: cacheDirectory)
    }

    private struct FetchResult {
        let data: Data?
        let debug: ArtistArtworkDebugResult
    }

    private func fetch(artistName: String, debug: Bool = false) async -> FetchResult {
        let name = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.lowercased() != "unknown artist" else {
            return FetchResult(data: nil, debug: ArtistArtworkDebugResult(
                artist: artistName, source: .none, matchedName: nil, imageURL: nil,
                bytes: 0, message: "Invalid or empty artist name."
            ))
        }

        let key = cacheKey(for: name)
        if let cached = memoryCache[key] {
            return FetchResult(data: cached, debug: ArtistArtworkDebugResult(
                artist: name, source: .none, matchedName: nil, imageURL: nil,
                bytes: cached.count, message: "Loaded from memory cache."
            ))
        }
        if let cached = readDiskCache(for: key) {
            memoryCache[key] = cached
            return FetchResult(data: cached, debug: ArtistArtworkDebugResult(
                artist: name, source: .none, matchedName: nil, imageURL: nil,
                bytes: cached.count, message: "Loaded from disk cache."
            ))
        }

        if let existing = inFlight[key] {
            let data = await existing.value
            return FetchResult(data: data, debug: ArtistArtworkDebugResult(
                artist: name, source: .none, matchedName: nil, imageURL: nil,
                bytes: data?.count ?? 0, message: "Loaded from an existing request."
            ))
        }

        let task = Task<Data?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.fetchNetwork(artistName: name, cacheKey: key)
        }
        inFlight[key] = task
        let data = await task.value
        inFlight[key] = nil

        // A normal UI fetch doesn't need the detailed source information.
        return FetchResult(data: data, debug: ArtistArtworkDebugResult(
            artist: name, source: data == nil ? .none : .deezer,
            matchedName: nil, imageURL: nil, bytes: data?.count ?? 0,
            message: data == nil ? "No artist artwork found." : "Artwork loaded."
        ))
    }

    private struct NetworkArtworkResult {
        let data: Data?
        let source: ArtistArtworkSource
        let matchedName: String?
        let imageURL: String?
        let message: String
    }

    private func fetchNetwork(artistName: String, cacheKey: String) async -> Data? {
        let result = await fetchNetworkDetailed(artistName: artistName)
        if let data = result.data {
            memoryCache[cacheKey] = data
            writeDiskCache(data, for: cacheKey)
        }
        return result.data
    }

    private func fetchNetworkDetailed(artistName: String) async -> NetworkArtworkResult {
        let deezer = await fetchFromDeezerDetailed(artistName: artistName)
        if let deezer, deezer.data != nil {
            return deezer
        }

        let itunes = await fetchFromITunesDetailed(artistName: artistName)
        if let itunes, itunes.data != nil {
            return itunes
        }

        let fallbackMessage = [deezer?.message, itunes?.message]
            .compactMap { $0 }
            .joined(separator: " ")

        return NetworkArtworkResult(
            data: nil,
            source: deezer?.source ?? itunes?.source ?? .none,
            matchedName: deezer?.matchedName ?? itunes?.matchedName,
            imageURL: deezer?.imageURL ?? itunes?.imageURL,
            message: fallbackMessage.isEmpty ? "No artwork source returned usable artwork." : fallbackMessage
        )
    }

    private func fetchFromDeezerDetailed(artistName: String) async -> NetworkArtworkResult? {
        guard var components = URLComponents(string: "https://api.deezer.com/search/artist") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: artistName), URLQueryItem(name: "limit", value: "5")]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard 200..<300 ~= http.statusCode else {
                return NetworkArtworkResult(data: nil, source: .deezer, matchedName: nil, imageURL: nil,
                                            message: "Deezer HTTP status: \(http.statusCode).")
            }
            let decoded = try JSONDecoder().decode(DeezerSearchResponse.self, from: data)
            guard !decoded.data.isEmpty else {
                return NetworkArtworkResult(data: nil, source: .deezer, matchedName: nil, imageURL: nil,
                                            message: "Deezer returned no matching artists.")
            }
            let query = normalize(artistName)
            let artist = decoded.data.first(where: { normalize($0.name) == query }) ?? decoded.data.first!
            guard let imageString = artist.picture_xl ?? artist.picture_big ?? artist.picture_medium,
                  let imageURL = URL(string: imageString) else {
                return NetworkArtworkResult(data: nil, source: .deezer, matchedName: artist.name, imageURL: nil,
                                            message: "Deezer found \(artist.name), but it returned no artist image URL.")
            }
            let imageData = await downloadImage(url: imageURL)
            return NetworkArtworkResult(data: imageData, source: .deezer, matchedName: artist.name,
                                        imageURL: imageURL.absoluteString,
                                        message: imageData == nil ? "Deezer image download failed." : "Deezer artist image downloaded.")
        } catch {
            return NetworkArtworkResult(data: nil, source: .deezer, matchedName: nil, imageURL: nil,
                                        message: "Deezer request failed: \(error.localizedDescription)")
        }
    }

    private func fetchFromITunesDetailed(artistName: String) async -> NetworkArtworkResult? {
        guard var components = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "term", value: artistName),
            URLQueryItem(name: "entity", value: "musicArtist"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard 200..<300 ~= http.statusCode else {
                return NetworkArtworkResult(data: nil, source: .iTunes, matchedName: nil, imageURL: nil,
                                            message: "iTunes HTTP status: \(http.statusCode).")
            }
            let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard !decoded.results.isEmpty else {
                return NetworkArtworkResult(data: nil, source: .iTunes, matchedName: nil, imageURL: nil,
                                            message: "iTunes returned no artist results.")
            }
            let query = normalize(artistName)
            let artist = decoded.results.first(where: { normalize($0.artistName ?? "") == query }) ?? decoded.results.first!
            guard let artwork = artist.artworkUrl100,
                  let imageURL = URL(string: artwork.replacingOccurrences(of: "100x100", with: "600x600")) else {
                return NetworkArtworkResult(data: nil, source: .iTunes, matchedName: artist.artistName, imageURL: nil,
                                            message: "iTunes found the artist, but no artwork URL was available.")
            }
            let imageData = await downloadImage(url: imageURL)
            return NetworkArtworkResult(data: imageData, source: .iTunes, matchedName: artist.artistName,
                                        imageURL: imageURL.absoluteString,
                                        message: imageData == nil ? "iTunes image download failed." : "iTunes image downloaded.")
        } catch {
            return NetworkArtworkResult(data: nil, source: .iTunes, matchedName: nil, imageURL: nil,
                                        message: "iTunes request failed: \(error.localizedDescription)")
        }
    }

    private func downloadImage(url: URL) async -> Data? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode,
                  !data.isEmpty,
                  UIImage(data: data) != nil else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
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
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func diskURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent(key).appendingPathExtension("img")
    }

    private func readDiskCache(for key: String) -> Data? {
        guard let data = try? Data(contentsOf: diskURL(for: key)), !data.isEmpty else { return nil }
        return data
    }

    private func writeDiskCache(_ data: Data, for key: String) {
        try? data.write(to: diskURL(for: key), options: .atomic)
    }

    private struct DeezerSearchResponse: Decodable {
        let data: [DeezerArtist]
    }
    private struct DeezerArtist: Decodable {
        let name: String
        let picture_medium: String?
        let picture_big: String?
        let picture_xl: String?
    }
    private struct ITunesSearchResponse: Decodable {
        let results: [ITunesArtist]
    }
    private struct ITunesArtist: Decodable {
        let artistName: String?
        let artworkUrl100: String?
    }
}

@MainActor
final class ArtistArtworkViewModel: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var isLoading = false
    private var loadedArtist: String?

    func load(artistName: String) async {
        guard loadedArtist != artistName else { return }
        loadedArtist = artistName
        isLoading = true
        let data = await ArtistArtworkService.shared.imageData(for: artistName)
        guard loadedArtist == artistName else { return }
        image = data.flatMap(UIImage.init(data:))
        isLoading = false
    }
}

struct ArtistArtworkView: View {
    let artistName: String
    let size: CGFloat
    @StateObject private var model = ArtistArtworkViewModel()

    var body: some View {
        Group {
            if let image = model.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Circle().fill(Color.gray.opacity(0.3)).overlay {
                    Image(systemName: "person.fill").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: artistName) { await model.load(artistName: artistName) }
    }
}

// MARK: - Debug

struct ArtistArtworkDebugView: View {
    @State private var artistName = "Aimer"
    @State private var isTesting = false
    @State private var result: ArtistArtworkDebugResult?

    var body: some View {
        Form {
            Section("Test Artist") {
                TextField("Artist name", text: $artistName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()

                Button {
                    Task { await runTest() }
                } label: {
                    HStack {
                        Text("Test Artist Artwork")
                        Spacer()
                        if isTesting { ProgressView() }
                    }
                }
                .disabled(isTesting || artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let result {
                Section("Result") {
                    LabeledContent("Artist", value: result.artist)
                    LabeledContent("Source", value: result.source.rawValue)
                    if let matchedName = result.matchedName {
                        LabeledContent("Matched", value: matchedName)
                    }
                    if let imageURL = result.imageURL {
                        Text(imageURL).font(.caption).textSelection(.enabled)
                    }
                    LabeledContent("Image bytes", value: "\(result.bytes)")
                    Text(result.message)
                        .foregroundStyle(result.bytes > 0 ? .green : .red)
                }
            }
        }
        .navigationTitle("Artist Artwork Debug")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runTest() async {
        isTesting = true
        result = await ArtistArtworkService.shared.debugFetch(artistName: artistName)
        isTesting = false
    }
}
