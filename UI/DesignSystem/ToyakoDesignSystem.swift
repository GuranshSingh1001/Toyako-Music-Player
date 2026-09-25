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
        .accessibilityElement(children: .combine)
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

    // One fixed square artwork size is shared by the main library and Home.
    // Keeping this independent from the window width prevents artwork from
    // growing/shrinking during Stage Manager or split-view resizing.
    static let libraryArtwork: CGFloat = 180
    static let libraryCardWidth: CGFloat = 220
    static let homeCard: CGFloat = libraryArtwork
    static let albumCard: CGFloat = libraryArtwork
    static let playlistCard: CGFloat = libraryArtwork
}

// MARK: - Centered adaptive library grid

/// An adaptive library grid whose incomplete final row is centered instead of
/// being pinned to the leading edge. Card widths remain consistent across rows.
struct CenteredLibraryGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let availableWidth: CGFloat
    let minimumItemWidth: CGFloat
    let rowSpacing: CGFloat
    let columnSpacing: CGFloat
    @ViewBuilder let content: (Item) -> Content

    init(
        items: [Item],
        availableWidth: CGFloat,
        minimumItemWidth: CGFloat = 180,
        rowSpacing: CGFloat = 24,
        columnSpacing: CGFloat = 18,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.availableWidth = max(0, availableWidth)
        self.minimumItemWidth = minimumItemWidth
        self.rowSpacing = rowSpacing
        self.columnSpacing = columnSpacing
        self.content = content
    }

    var body: some View {
        let width = max(0, availableWidth)
        let columnCount = max(
            1,
            Int((width + columnSpacing) / (minimumItemWidth + columnSpacing))
        )
        // Deliberately keep each card width fixed. Only the number of columns
        // changes as the window changes; the artwork/card geometry does not.
        let itemWidth = minimumItemWidth

        LazyVStack(alignment: .center, spacing: rowSpacing) {
            ForEach(Array(items.chunked(into: columnCount).enumerated()), id: \.offset) { _, row in
                HStack(spacing: columnSpacing) {
                    ForEach(row) { item in
                        content(item)
                            .frame(width: itemWidth)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)

        var start = 0
        while start < count {
            let end = Swift.min(start + size, count)
            result.append(Array(self[start..<end]))
            start = end
        }
        return result
    }
}
