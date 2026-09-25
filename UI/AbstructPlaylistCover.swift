import SwiftUI

struct AbstractPlaylistCover: View {
    let playlistID: UUID
    
    var body: some View {
        let colors = palette(for: playlistID)
        
        ZStack {
            // Clean, rich Apple Music style background
            LinearGradient(
                colors: [colors.0, colors.1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Soft overlay glow
            RadialGradient(
                colors: [.white.opacity(0.3), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 150
            )
            .blendMode(.overlay)
            
            Image(systemName: "music.note.list")
                .font(.system(size: 50, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
    }
    
    private func palette(for id: UUID) -> (Color, Color) {
        let hash = abs(id.hashValue)
        let palettes: [(Color, Color)] = [
            (.pink, .red),         // Classic Apple Music Pink
            (.cyan, .blue),        // Deep Ocean
            (.purple, .pink),      // Berry
            (.mint, .teal),        // Fresh
            (.orange, .red),       // Sunset
            (.indigo, .purple)     // Midnight
        ]
        return palettes[hash % palettes.count]
    }
}
