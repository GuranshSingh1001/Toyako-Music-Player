import SwiftUI

struct FolderBrowserView: View {
    let currentURL: URL
    let rootURL: URL
    @ObservedObject var library: LocalLibrary
    @Binding var selectedURLs: Set<URL>
    let onNavigate: (URL) -> Void

    // Pre-computed arrays prevent main-thread lag during scroll
    @State private var subfolders: [(url: URL, count: Int)] = []
    @State private var localTracks: [LocalTrack] = []
    @State private var isLoaded = false

    var body: some View {
        List {
            if isLoaded {
                if !subfolders.isEmpty {
                    Section(header: Text("Folders")) {
                        ForEach(subfolders, id: \.url) { folder in
                            Button {
                                onNavigate(folder.url)
                            } label: {
                                HStack {
                                    Image(systemName: "folder.fill").foregroundColor(.blue)
                                    VStack(alignment: .leading) {
                                        Text(folder.url.lastPathComponent).foregroundColor(.primary)
                                        Text("\(folder.count) songs").font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundColor(.gray).font(.caption)
                                }
                            }
                        }
                    }
                }

                if !localTracks.isEmpty {
                    Section(header: Text("Tracks")) {
                        Button("Select All in Folder") {
                            for track in localTracks { selectedURLs.insert(track.url) }
                        }
                        .foregroundColor(.blue)
                        
                        ForEach(localTracks) { track in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(track.title).lineLimit(1)
                                    Text(track.artist).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedURLs.contains(track.url) {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                                } else {
                                    Image(systemName: "circle").foregroundColor(.gray)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedURLs.contains(track.url) {
                                    selectedURLs.remove(track.url)
                                } else {
                                    selectedURLs.insert(track.url)
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onAppear(perform: loadContents)
    }

    private func loadContents() {
        guard !isLoaded else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let path = currentURL.standardizedFileURL.path
            
            // 1. Find tracks directly in this folder
            let tracksInFolder = library.tracks.filter {
                $0.url.deletingLastPathComponent().standardizedFileURL.path == path
            }
            
            // 2. Find immediate subfolders efficiently
            var folderCounts: [URL: Int] = [:]
            for track in library.tracks {
                let trackDir = track.url.deletingLastPathComponent().standardizedFileURL.path
                if trackDir.hasPrefix(path) && trackDir != path {
                    let relativePath = trackDir.replacingOccurrences(of: path + "/", with: "")
                    let firstComponent = relativePath.components(separatedBy: "/").first ?? ""
                    if !firstComponent.isEmpty {
                        let subfolderURL = currentURL.appendingPathComponent(firstComponent)
                        folderCounts[subfolderURL, default: 0] += 1
                    }
                }
            }
            
            let sortedSubfolders = folderCounts.map { (url: $0.key, count: $0.value) }
                .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
            
            DispatchQueue.main.async {
                self.localTracks = tracksInFolder.sorted { $0.title < $1.title }
                self.subfolders = sortedSubfolders
                self.isLoaded = true
            }
        }
    }
}
