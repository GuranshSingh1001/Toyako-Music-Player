import SwiftUI

// MARK: - Toyako Design System

/// Shared visual language for every Toyako screen.
/// Keep visual constants here instead of defining ad-hoc values in individual views.
enum ToyakoDesign {
    enum Color {
        /// Toyako's primary accent. Keep this consistent across navigation, actions,
        /// selected states, sliders and playback affordances.
        static let accent = SwiftUI.Color.white
        static let canvas = SwiftUI.Color(uiColor: .systemBackground)
        static let surface = SwiftUI.Color(uiColor: .secondarySystemBackground)
        static let subtleSurface = SwiftUI.Color(uiColor: .tertiarySystemBackground)
        static let divider = SwiftUI.Color.primary.opacity(0.085)
        static let selectedFill = accent.opacity(0.15)
        static let accentFill = accent.opacity(0.11)
    }

    enum Metrics {
        static let screenHorizontal: CGFloat = 20
        static let screenTop: CGFloat = 14
        static let screenBottom: CGFloat = 100
        static let sectionSpacing: CGFloat = 26
        static let itemSpacing: CGFloat = 12
        static let cardRadius: CGFloat = 18
        static let controlRadius: CGFloat = 14
        static let compactControlHeight: CGFloat = 44
        static let standardControlHeight: CGFloat = 50
        static let largeControlHeight: CGFloat = 54
        static let rowHeight: CGFloat = 64
        static let artworkSmallRadius: CGFloat = 8
        static let artworkRadius: CGFloat = 12
    }

    enum Typography {
        static let screenTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let section = Font.system(.title3, design: .rounded).weight(.bold)
        static let item = Font.system(.body, design: .rounded).weight(.semibold)
        static let metadata = Font.system(.caption, design: .rounded)
        static let button = Font.system(.headline, design: .rounded).weight(.semibold)
        static let smallButton = Font.system(.subheadline, design: .rounded).weight(.semibold)
    }
}

// MARK: - Reusable button language

struct ToyakoPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ToyakoDesign.Typography.button)
            .foregroundStyle(.black)
            .frame(minHeight: ToyakoDesign.Metrics.largeControlHeight)
            .padding(.horizontal, 20)
            .background(ToyakoDesign.Color.accent, in: Capsule())
            .shadow(
                color: ToyakoDesign.Color.accent.opacity(configuration.isPressed ? 0.10 : 0.24),
                radius: configuration.isPressed ? 4 : 12,
                y: configuration.isPressed ? 2 : 6
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct ToyakoSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ToyakoDesign.Typography.button)
            .foregroundStyle(.primary)
            .frame(minHeight: ToyakoDesign.Metrics.largeControlHeight)
            .padding(.horizontal, 20)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(ToyakoDesign.Color.divider, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct ToyakoIconButtonStyle: ButtonStyle {
    let size: CGFloat

    init(size: CGFloat = 44) {
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(.thinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(ToyakoDesign.Color.divider, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct ToyakoSmallActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ToyakoDesign.Typography.smallButton)
            .foregroundStyle(ToyakoDesign.Color.accent)
            .frame(minHeight: ToyakoDesign.Metrics.compactControlHeight)
            .padding(.horizontal, 14)
            .background(ToyakoDesign.Color.accentFill, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(ToyakoDesign.Color.accent.opacity(0.22), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}


struct ToyakoToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 12)

                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn
                              ? ToyakoDesign.Color.accent.opacity(0.28)
                              : SwiftUI.Color.primary.opacity(0.12))
                        .frame(width: 50, height: 30)
                        .overlay {
                            Capsule()
                                .stroke(SwiftUI.Color.primary.opacity(0.10), lineWidth: 1)
                        }

                    Circle()
                        .fill(configuration.isOn ? ToyakoDesign.Color.accent : SwiftUI.Color.secondary.opacity(0.72))
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        .padding(3)
                }
                .frame(width: 50, height: 30)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(configuration.label)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

// MARK: - Reusable surfaces

struct ToyakoCard<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat = ToyakoDesign.Metrics.cardRadius,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ToyakoDesign.Color.divider, lineWidth: 1)
            }
    }
}

struct ToyakoSectionHeader: View {
    let title: String
    let trailingTitle: String?
    let trailingAction: (() -> Void)?

    init(
        _ title: String,
        trailingTitle: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.trailingTitle = trailingTitle
        self.trailingAction = trailingAction
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(ToyakoDesign.Typography.section)

            Spacer(minLength: 0)

            if let trailingTitle, let trailingAction {
                Button(trailingTitle, action: trailingAction)
                    .buttonStyle(ToyakoSmallActionButtonStyle())
            }
        }
    }
}

extension View {
    func toyakoScreenPadding(bottom: CGFloat = ToyakoDesign.Metrics.screenBottom) -> some View {
        padding(.horizontal, ToyakoDesign.Metrics.screenHorizontal)
            .padding(.top, ToyakoDesign.Metrics.screenTop)
            .padding(.bottom, bottom)
    }

    func toyakoCard(cornerRadius: CGFloat = ToyakoDesign.Metrics.cardRadius) -> some View {
        background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ToyakoDesign.Color.divider, lineWidth: 1)
            }
    }

    func toyakoArtwork(cornerRadius: CGFloat = ToyakoDesign.Metrics.artworkRadius) -> some View {
        clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Consistent image sizes

enum ToyakoArtworkSize {
    static let row: CGFloat = 44
    static let compactRow: CGFloat = 48
    static let homeCard: CGFloat = 145
    static let albumCard: CGFloat = 160
    static let playlistCard: CGFloat = 160
}
