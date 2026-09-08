import SwiftUI

struct AbstractPlaylistCover: View {
    let playlistID: UUID
    
    var body: some View {
        if #available(iOS 18.0, *) {
            MeshGradient(
                width: 3, 
                height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.8, 0.2], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: meshColors(for: playlistID)
            )
            .overlay {
                Image(systemName: "music.note.list")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .blendMode(.overlay)
            }
        } else {
            // Fallback for older iOS versions
            LinearGradient(
                colors: [meshColors(for: playlistID).first ?? .purple, meshColors(for: playlistID).last ?? .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "music.note.list")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .blendMode(.overlay)
            }
        }
    }
    
    private func meshColors(for id: UUID) -> [Color] {
        let hash = abs(id.hashValue)
        let palettes: [[Color]] = [
            [.purple, .indigo, .blue, .pink, .orange, .red, .purple, .pink, .orange], 
            [.teal, .cyan, .blue, .mint, .teal, .indigo, .green, .mint, .teal],       
            [.black, .purple, .indigo, .red, .pink, .purple, .black, .red, .orange],  
            [.blue, .purple, .pink, .cyan, .indigo, .purple, .teal, .blue, .pink]     
        ]
        return palettes[hash % palettes.count]
    }
}
