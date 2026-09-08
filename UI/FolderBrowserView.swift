import SwiftUI

struct FolderBrowserView: View {
    let currentURL: URL
    let rootURL: URL
    let library: LocalLibrary
    @Binding var selectedURLs: Set<URL>
    let onNavigate: (URL) -> Void

    enum SelectionState { case none, partial, all }
    struct SubfolderInfo: Identifiable {
        var id: URL { url }
        let name: String
        let url: URL
        let allTracks: [LocalTrack]
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill").foregroundColor(.blue)
                        Text(breadcrumbPath).font(.subheadline.weight(.medium)).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    if !allTracksUnderCurrent.isEmpty {
                        HStack {
                            Text("\(allTracksUnderCurrent.count) total songs").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Button(allCurrentSelected ? "Deselect All" : "Select All in Folder") { toggleCurrentFolder() }
                                .font(.caption.bold()).buttonStyle(.bordered).tint(allCurrentSelected ? .red : .blue)
                        }
                    }
                }.padding(.vertical, 4)
            }

            if !subfolders.isEmpty {
                Section("Folders") {
                    ForEach(subfolders) { folder in
                        HStack(spacing: 12) {
                            Button { onNavigate(folder.url) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder.fill").font(.title3).foregroundColor(.accentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(folder.name).font(.headline).foregroundColor(.primary).lineLimit(1)
                                        Text("\(folder.allTracks.count) songs").font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundColor(Color(UIColor.tertiaryLabel))
                                }
                            }.buttonStyle(.plain)
                            Divider().frame(height: 24)
                            Button { toggleFolder(folder) } label: {
                                Image(systemName: folderStateIcon(for: folder)).font(.title3).foregroundColor(folderStateColor(for: folder)).frame(width: 36, height: 36)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }

            if !directTracks.isEmpty {
                Section("Songs") {
                    ForEach(directTracks) { track in
                        HStack(spacing: 12) {
                            if let data = track.artworkData, let img = UIImage(data: data) {
                                Image(uiImage: img).resizable().scaledToFill().frame(width: 40, height: 40).cornerRadius(6)
                            } else {
                                RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.2)).frame(width: 40, height: 40).overlay(Image(systemName: "music.note").foregroundColor(.gray))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title).font(.subheadline.bold()).lineLimit(1)
                                Text(track.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: selectedURLs.contains(track.url) ? "checkmark.circle.fill" : "circle").font(.title3).foregroundColor(selectedURLs.contains(track.url) ? .blue : .gray)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedURLs.contains(track.url) { selectedURLs.remove(track.url) } else { selectedURLs.insert(track.url) }
                        }
                    }
                }
            }

            if subfolders.isEmpty && directTracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark").font(.system(size: 40)).foregroundColor(.secondary)
                    Text("No audio files in this folder").font(.subheadline).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 40).listRowBackground(Color.clear)
            }
        }.listStyle(.insetGrouped)
    }

    private var breadcrumbPath: String {
        let rootPath = rootURL.standardizedFileURL.path
        let currPath = currentURL.standardizedFileURL.path
        if currPath == rootPath { return "Documents" }
        return "Documents" + currPath.replacingOccurrences(of: rootPath, with: "").replacingOccurrences(of: "/", with: " / ")
    }

    private var allTracksUnderCurrent: [LocalTrack] {
        let currentPath = currentURL.standardizedFileURL.path
        return library.tracks.filter { $0.url.standardizedFileURL.path == currentPath || $0.url.standardizedFileURL.path.hasPrefix(currentPath + "/") }
    }

    private var directTracks: [LocalTrack] {
        let currentPath = currentURL.standardizedFileURL.path
        return library.tracks.filter { $0.url.deletingLastPathComponent().standardizedFileURL.path == currentPath }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var subfolders: [SubfolderInfo] {
        let currentPath = currentURL.standardizedFileURL.path
        var folderMap: [String: (URL, [LocalTrack])] = [:]
        for track in allTracksUnderCurrent {
            let trackPath = track.url.standardizedFileURL.path
            guard trackPath.hasPrefix(currentPath + "/") else { continue }
            let relative = String(trackPath.dropFirst(currentPath.count + 1))
            let components = relative.split(separator: "/")
            if components.count > 1 {
                let folderName = String(components[0])
                let folderURL = currentURL.appendingPathComponent(folderName).standardizedFileURL
                if folderMap[folderName] != nil { folderMap[folderName]?.1.append(track) } else { folderMap[folderName] = (folderURL, [track]) }
            }
        }
        return folderMap.map { SubfolderInfo(name: $0.key, url: $0.value.0, allTracks: $0.value.1) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var allCurrentSelected: Bool {
        guard !allTracksUnderCurrent.isEmpty else { return false }
        return allTracksUnderCurrent.allSatisfy { selectedURLs.contains($0.url) }
    }

    private func toggleCurrentFolder() {
        let urls = allTracksUnderCurrent.map { $0.url }
        if allCurrentSelected { urls.forEach { selectedURLs.remove($0) } } else { urls.forEach { selectedURLs.insert($0) } }
    }

    private func folderSelectionState(for folder: SubfolderInfo) -> SelectionState {
        let folderURLs = Set(folder.allTracks.map { $0.url })
        let intersection = folderURLs.intersection(selectedURLs)
        if intersection.isEmpty { return .none }
        if intersection.count == folderURLs.count { return .all }
        return .partial
    }

    private func folderStateIcon(for folder: SubfolderInfo) -> String {
        switch folderSelectionState(for: folder) {
        case .none: return "circle"
        case .partial: return "minus.circle.fill"
        case .all: return "checkmark.circle.fill"
        }
    }

    private func folderStateColor(for folder: SubfolderInfo) -> Color {
        switch folderSelectionState(for: folder) {
        case .none: return .gray
        case .partial, .all: return .blue
        }
    }

    private func toggleFolder(_ folder: SubfolderInfo) {
        let folderURLs = folder.allTracks.map { $0.url }
        if folderSelectionState(for: folder) == .all {
            folderURLs.forEach { selectedURLs.remove($0) }
        } else {
            folderURLs.forEach { selectedURLs.insert($0) }
        }
    }
}
