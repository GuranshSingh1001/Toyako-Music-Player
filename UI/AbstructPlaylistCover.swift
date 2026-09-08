import SwiftUI

struct AbstractPlaylistCover: View {
    let playlistID: UUID
    
    var body: some View {
        let palette = colors(for: playlistID)
        
        ZStack {
            // Base linear gradient
            LinearGradient(
                colors: [palette.0, palette.1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Secondary radial glow for that rich "mesh" feel
            RadialGradient(
                colors: [palette.2.opacity(0.8), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 180
            )
            .blendMode(.screen)
            
            Image(systemName: "music.note.list")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
        }
    }
    
    // Consistently assigns a vibrant palette based on the playlist's unique ID
    private func colors(for id: UUID) -> (Color, Color, Color) {
        let hash = abs(id.hashValue)
        let palettes: [(Color, Color, Color)] = [
            (.purple, .indigo, .cyan),     // Deep Space
            (.pink, .orange, .yellow),     // Sunset
            (.indigo, .purple, .pink),     // Berry
            (.teal, .mint, .green),        // Aqua
            (.red, .pink, .orange),        // Crimson
            (.blue, .teal, .indigo)        // Ocean
        ]
        return palettes[hash % palettes.count]
    }
}
