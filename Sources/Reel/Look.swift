import SwiftUI

/// Reel's look: one matte canvas, glass sheets floating on it, quiet tiles inside them.
/// ponytail: values copied by hand from a private design package; update both together.
enum Look {
    enum Colors {
        /// Cream in light mode, charcoal in dark mode.
        static func canvas(dark: Bool) -> Color {
            dark ? Color(.sRGB, red: 0.11, green: 0.10, blue: 0.09) : Color(.sRGB, red: 0.96, green: 0.94, blue: 0.90)
        }
        static func glassTint(dark: Bool) -> Color { canvas(dark: dark).opacity(0.5) }
        static func glassBase(dark: Bool) -> Color { canvas(dark: dark).opacity(0.6) }

        /// Tile edge only; never a divider inside a sheet.
        static let hairline = Color.primary.opacity(0.07)
        static let cardFill = Color.primary.opacity(0.04)
        static let chipFill = Color.primary.opacity(0.05)
        static let chipHoverFill = Color.primary.opacity(0.10)
    }

    enum Spacing {
        static let hair: CGFloat = 3
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        /// Between the window edge and the glass sheets.
        static let canvas: CGFloat = 28
    }

    enum Radius {
        static let chip: CGFloat = 8
        static let card: CGFloat = 14
        static let sheet: CGFloat = 22
    }

    enum Typography {
        static let title = Font.title2.bold()
        static let titleSmall = Font.title3.bold()
        static let headline = Font.headline
        static let label = Font.body.weight(.medium)
        static let callout = Font.callout
        static let caption = Font.caption
    }
}

extension View {
    /// The matte canvas under the whole window, toolbar included.
    func deskBackground() -> some View {
        background(CanvasFill().ignoresSafeArea())
    }

    /// A glass sheet on the canvas, tinted with the canvas colour.
    func glassSheet(cornerRadius: CGFloat = Look.Radius.sheet) -> some View {
        glass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// A glass pill on the canvas, for floating controls such as the link field.
    func glassPill() -> some View {
        glass(in: Capsule(style: .continuous))
    }

    private func glass<S: InsettableShape>(in shape: S) -> some View {
        clipShape(shape)
            .background { GlassFill(shape: shape) }
            .shadow(color: .black.opacity(0.06), radius: 14, y: 4)
    }

    /// A quiet tile inside a sheet: a faint lift and a hairline edge, never a white card.
    func quietCard(cornerRadius: CGFloat = Look.Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(Look.Colors.cardFill, in: shape)
            .overlay(shape.strokeBorder(Look.Colors.hairline, lineWidth: 0.5))
    }

    /// No toolbar backdrop: toolbar controls sit straight on the canvas.
    func clearToolbar() -> some View {
        toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

private struct CanvasFill: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Look.Colors.canvas(dark: scheme == .dark) }
}

private struct GlassFill<S: InsettableShape>: View {
    let shape: S
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        shape.fill(Look.Colors.glassBase(dark: dark))
            .glassEffect(.regular.tint(Look.Colors.glassTint(dark: dark)), in: shape)
    }
}

/// A quiet chip button inside a sheet: a faint face that lifts on hover, the accent only when selected.
struct QuietChipStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration, isSelected: isSelected)
    }

    private struct Chip: View {
        let configuration: Configuration
        let isSelected: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Look.Radius.chip, style: .continuous)
            let lifted = hovering || configuration.isPressed
            configuration.label
                .font(Look.Typography.label)
                .lineLimit(1)
                .padding(.horizontal, Look.Spacing.sm)
                .frame(minHeight: 30)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(lifted ? Look.Colors.chipHoverFill : Look.Colors.chipFill), in: shape)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(shape)
                .onHover { hovering = $0 }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

extension ButtonStyle where Self == QuietChipStyle {
    static var quietChip: QuietChipStyle { QuietChipStyle() }
    static func quietChip(selected: Bool) -> QuietChipStyle { QuietChipStyle(isSelected: selected) }
}
