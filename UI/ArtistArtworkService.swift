import Foundation
import SwiftUI
import UIKit

// MARK: - Artist Artwork
// Uses public metadata services instead of Apple Music / MusicKit.
// Source order: Deezer -> iTunes Search -> Wikidata/Wikimedia Commons. Results are cached on disk.

enum ArtistArtworkSource: String {
    case deezer = "Deezer"
    case iTunes = "iTunes"
    case wikidata = "Wikidata / Wikimedia Commons"
    case none = "None"
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

    func imageData(for artistName: String, allowNetwork: Bool) async -> Data? {
        let result = await fetch(artistName: artistName, allowNetwork: allowNetwork)
        return result.data
    }

    func clearCache() -> Int {
        let count = (try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil).count) ?? 0
        memoryCache.removeAll()
        try? fileManager.removeItem(at: cacheDirectory)
        return count
    }

    private struct FetchResult {
        let data: Data?
    }

    private func fetch(artistName: String, allowNetwork: Bool) async -> FetchResult {
        let name = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.lowercased() != "unknown artist" else {
            return FetchResult(data: nil)
        }

        let key = cacheKey(for: name)
        if let cached = memoryCache[key] {
            return FetchResult(data: cached)
        }
        if let cached = readDiskCache(for: key) {
            memoryCache[key] = cached
            return FetchResult(data: cached)
        }

        // Automatic network downloads are opt-in. Existing cached artwork is
        // still returned above even when this is disabled.
        guard allowNetwork else {
            return FetchResult(data: nil)
        }

        if let existing = inFlight[key] {
            return FetchResult(data: await existing.value)
        }

        let task = Task<Data?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.fetchNetwork(artistName: name, cacheKey: key)
        }
        inFlight[key] = task
        let data = await task.value
        inFlight[key] = nil
        return FetchResult(data: data)
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
        var diagnostics: [String] = []

        let deezer = await fetchFromDeezerDetailed(artistName: artistName)
        if let deezer {
            if deezer.data != nil { return deezer }
            diagnostics.append(deezer.message)
        }

        let itunes = await fetchFromITunesDetailed(artistName: artistName)
        if let itunes {
            if itunes.data != nil { return itunes }
            diagnostics.append(itunes.message)
        }

        let wikidata = await fetchFromWikidataDetailed(artistName: artistName)
        if let wikidata {
            if wikidata.data != nil { return wikidata }
            diagnostics.append(wikidata.message)
        }

        return NetworkArtworkResult(
            data: nil,
            source: .none,
            matchedName: nil,
            imageURL: nil,
            message: diagnostics.isEmpty ? "No artwork source returned usable artwork." : diagnostics.joined(separator: " ")
        )
    }

    private func fetchFromDeezerDetailed(artistName: String) async -> NetworkArtworkResult? {
        let queries = searchQueries(for: artistName)
        var lastMessage = "Deezer returned no usable artist artwork."

        for query in queries {
            guard var components = URLComponents(string: "https://api.deezer.com/search/artist") else { continue }
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: "25")
            ]
            guard let url = components.url else { continue }

            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse else { continue }
                guard 200..<300 ~= http.statusCode else {
                    lastMessage = "Deezer HTTP status: \(http.statusCode) for \(query)."
                    continue
                }

                let decoded = try JSONDecoder().decode(DeezerSearchResponse.self, from: data)
                guard !decoded.data.isEmpty else {
                    lastMessage = "Deezer returned no artists for \(query)."
                    continue
                }

                if let artist = bestDeezerMatch(for: artistName, candidates: decoded.data),
                   let imageString = artist.picture_xl ?? artist.picture_big ?? artist.picture_medium,
                   let imageURL = URL(string: imageString) {
                    let imageData = await downloadImage(url: imageURL)
                    if let imageData {
                        return NetworkArtworkResult(
                            data: imageData, source: .deezer, matchedName: artist.name,
                            imageURL: imageURL.absoluteString,
                            message: "Deezer artist image downloaded using query: \(query)."
                        )
                    }
                    lastMessage = "Deezer matched \(artist.name), but its image could not be downloaded."
                } else {
                    lastMessage = "Deezer returned artists for \(query), but no sufficiently close artist match was found."
                }
            } catch {
                lastMessage = "Deezer request failed for \(query): \(error.localizedDescription)"
            }
        }

        return NetworkArtworkResult(data: nil, source: .deezer, matchedName: nil, imageURL: nil, message: lastMessage)
    }

    private func bestDeezerMatch(for artistName: String, candidates: [DeezerArtist]) -> DeezerArtist? {
        let query = normalizeForMatching(artistName)
        guard !query.isEmpty else { return nil }

        var best: (artist: DeezerArtist, score: Double)?
        for candidate in candidates {
            let score = artistMatchScore(query: query, candidate: normalizeForMatching(candidate.name))
            if best == nil || score > best!.score {
                best = (candidate, score)
            }
        }

        guard let best, best.score >= 0.72 else { return nil }
        return best.artist
    }

    private func artistMatchScore(query: String, candidate: String) -> Double {
        if query == candidate { return 1.0 }
        if query.replacingOccurrences(of: " ", with: "") == candidate.replacingOccurrences(of: " ", with: "") { return 0.97 }
        if candidate.contains(query) || query.contains(candidate) { return 0.86 }

        let q = Set(query.split(separator: " "))
        let c = Set(candidate.split(separator: " "))
        guard !q.isEmpty && !c.isEmpty else { return 0 }
        let intersection = q.intersection(c).count
        let union = q.union(c).count
        return Double(intersection) / Double(union)
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

    private func fetchFromWikidataDetailed(artistName: String) async -> NetworkArtworkResult? {
        guard var components = URLComponents(string: "https://www.wikidata.org/w/api.php") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "action", value: "wbsearchentities"),
            URLQueryItem(name: "search", value: artistName),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let searchURL = components.url else { return nil }

        do {
            let (searchData, searchResponse) = try await session.data(from: searchURL)
            guard let http = searchResponse as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                return NetworkArtworkResult(data: nil, source: .wikidata, matchedName: nil, imageURL: nil, message: "Wikidata search request failed.")
            }
            let search = try JSONDecoder().decode(WikidataSearchResponse.self, from: searchData)
            let query = normalizeForMatching(artistName)
            guard let entity = search.search.first(where: { artistMatchScore(query: query, candidate: normalizeForMatching($0.label)) >= 0.72 }) ?? search.search.first else {
                return NetworkArtworkResult(data: nil, source: .wikidata, matchedName: nil, imageURL: nil, message: "Wikidata found no usable artist entity.")
            }

            guard let entityURL = URL(string: "https://www.wikidata.org/wiki/Special:EntityData/\(entity.id).json") else { return nil }
            let (entityData, entityResponse) = try await session.data(from: entityURL)
            guard let entityHTTP = entityResponse as? HTTPURLResponse, 200..<300 ~= entityHTTP.statusCode else {
                return NetworkArtworkResult(data: nil, source: .wikidata, matchedName: entity.label, imageURL: nil, message: "Wikidata entity request failed.")
            }
            let entityJSON = try JSONDecoder().decode(WikidataEntityResponse.self, from: entityData)
            guard let claims = entityJSON.entities[entity.id]?.claims,
                  let p18 = claims["P18"]?.first?.mainsnak.datavalue?.value,
                  !p18.isEmpty else {
                return NetworkArtworkResult(data: nil, source: .wikidata, matchedName: entity.label, imageURL: nil, message: "Wikidata found \(entity.label), but no P18 image is available.")
            }

            let encoded = p18.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? p18
            guard let imageURL = URL(string: "https://commons.wikimedia.org/wiki/Special:Redirect/file/\(encoded)?width=512") else { return nil }
            let imageData = await downloadImage(url: imageURL)
            return NetworkArtworkResult(
                data: imageData, source: .wikidata, matchedName: entity.label, imageURL: imageURL.absoluteString,
                message: imageData == nil ? "Wikimedia Commons image download failed." : "Wikidata/Wikimedia Commons artist image downloaded."
            )
        } catch {
            return NetworkArtworkResult(data: nil, source: .wikidata, matchedName: nil, imageURL: nil, message: "Wikidata request failed: \(error.localizedDescription)")
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

    private func searchQueries(for artistName: String) -> [String] {
        var values: [String] = []
        func add(_ value: String) {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && !values.contains(cleaned) { values.append(cleaned) }
        }

        add(artistName)
        add(artistName.replacingOccurrences(of: "&", with: "and"))
        add(artistName.replacingOccurrences(of: "&", with: " "))
        add(artistName.replacingOccurrences(of: "'", with: ""))
        add(artistName.replacingOccurrences(of: "’", with: ""))
        add(artistName.replacingOccurrences(of: "'", with: " "))

        let punctuationFree = artistName.replacingOccurrences(of: "[^\\p{L}\\p{N} ]", with: " ", options: .regularExpression)
        add(punctuationFree)
        return values
    }

    private func normalizeForMatching(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "[^a-z0-9\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
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

    private struct WikidataSearchResponse: Decodable {
        let search: [WikidataSearchEntity]
    }

    private struct WikidataSearchEntity: Decodable {
        let id: String
        let label: String
    }

    private struct WikidataEntityResponse: Decodable {
        let entities: [String: WikidataEntity]
    }

    private struct WikidataEntity: Decodable {
        let claims: [String: [WikidataClaim]]
    }

    private struct WikidataClaim: Decodable {
        let mainsnak: WikidataMainSnak
    }

    private struct WikidataMainSnak: Decodable {
        let datavalue: WikidataDataValue?
    }

    private struct WikidataDataValue: Decodable {
        let value: String
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

    func load(artistName: String, allowNetwork: Bool) async {
        guard loadedArtist != artistName || image == nil else { return }
        loadedArtist = artistName
        isLoading = true

        // The service always checks its own cache first. `allowNetwork` is
        // represented by the shared preference, so a disabled toggle still
        // allows already-downloaded artwork to be displayed.
        let data = await ArtistArtworkService.shared.imageData(for: artistName, allowNetwork: allowNetwork)
        guard loadedArtist == artistName else { return }
        image = data.flatMap(UIImage.init(data:))
        isLoading = false
    }
}

struct ArtistArtworkView: View {
    let artistName: String
    let size: CGFloat
    @AppStorage(ToyakoPreferences.automaticArtistArtworkKey) private var automaticDownloads = false
    @StateObject private var model = ArtistArtworkViewModel()

    var body: some View {
        ZStack {
            if let image = model.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.22))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.34))
                            .foregroundStyle(.secondary)
                    }
            }

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: "\(artistName)|\(automaticDownloads)") {
            await model.load(artistName: artistName, allowNetwork: automaticDownloads)
        }
    }
}
