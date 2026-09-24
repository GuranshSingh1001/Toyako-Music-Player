import SwiftUI

// MARK: - Detail-page action buttons

struct HeroPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .frame(minHeight: 46)
            .background(
                Capsule(style: .continuous)
                    .fill(.white)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct HeroSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(minHeight: 46)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.16))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 0.7)
                    }
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
