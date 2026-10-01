import SwiftUI

/// Applies Liquid Glass on iPadOS 26+ and an opaque fallback on older OS versions.
///
/// The availability check is evaluated at runtime, so the same app build can run on
/// iPadOS 18 through newer releases without requiring Liquid Glass APIs on older systems.
struct ToyakoAdaptiveGlass<S: Shape>: ViewModifier {
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background(Color(uiColor: .systemBackground), in: shape)
        }
    }
}

extension View {
    func toyakoAdaptiveGlass<S: Shape>(in shape: S) -> some View {
        modifier(ToyakoAdaptiveGlass(shape: shape))
    }
}
