import SwiftUI

extension View {
    /// Applies a modern iOS Liquid Glass material effect.
    func glassEffect(cornerRadius: CGFloat = 16) -> some View {
        self
            // 1. The core refractive material
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            // 2. Subtle bright edge mimicking glass reflection
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                    .blendMode(.overlay)
            )
            // 3. Soft ambient shadow for depth
            .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
    }
}
