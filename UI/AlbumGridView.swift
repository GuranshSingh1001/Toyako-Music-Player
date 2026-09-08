import SwiftUI

struct AlbumGridView: View {
    let albums: [AlbumGroup]
    let library: LocalLibrary
    @EnvironmentObject var audioManager: AudioEngineManager

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(albums) { album in
                    VStack(alignment: .leading, spacing: 8) {
                        if let data = album.artworkData, let img = UIImage(data: data) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 160, height: 160)
                                .cornerRadius(12)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 160, height: 160)
                                .overlay(Image(systemName: "square.stack").font(.largeTitle).foregroundColor(.gray))
                        }
                        Text(album.name).font(.headline).lineLimit(1)
                        Text(album.artist).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    }
                    .frame(width: 160)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        audioManager.startQueue(tracks: album.tracks, startIndex: 0)
                    }
                }
            }
            .padding()
            .padding(.bottom, audioManager.currentTrack != nil ? 70 : 0)
        }
    }
}
