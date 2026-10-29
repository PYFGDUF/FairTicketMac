import AppKit
import SwiftUI

extension Color {
    /// Build a colour from a 24-bit hex literal, so the palette stays readable in
    /// source instead of being scattered as `red:green:blue:` triples.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Design tokens, taken from the FairTicket for Mac design document.
///
/// The document fixes three things and everything else follows from them:
///
///   * one brand orange (`#FF7A17`, deepening to `#FF4A00`) — the ticket glyph, the
///     primary action, the sequence numbers, the release countdown.  Nothing else in
///     the window carries a hue, which is what makes the orange read as "this is the
///     thing to press" rather than as decoration;
///   * an ink canvas (`#0A0A0A`) with a three-step elevation ladder —
///     canvas → panel → card — each step about seven levels of luminance apart.
///     Depth is carried by that ladder plus a hairline, never by a shadow;
///   * a flat, quiet surface language: no glass, no gradients except the one behind
///     the countdown, no bezels borrowed from AppKit.
///
/// Structure is *not* semantic-coloured.  The ladder and the text greys are literal
/// values because the design specifies them; light mode gets its own measured ladder
/// rather than a system inversion, so the two appearances have the same relationships.
enum Theme {

    // MARK: - Brand

    /// `#FF7A17` — the design's 强调色.  Fills, the primary action, the countdown.
    static let brand = Color(hex: 0xFF7A17)
    /// `#F44A0D` — the design's 深压色, the deeper end of the app icon's gradient.
    static let brandDeep = Color(hex: 0xF44A0D)
    /// `#0A0A0A` — the design's 画布, the darkest step of the canvas.
    static let ink = Color(hex: 0x0A0A0A)
    /// Prose on a warning surface needs a distinct ink for each appearance.
    static func brandText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xFEC184) : Color(hex: 0x963C06)
    }
    /// Orange ink for links and selected labels, separate from the bright brand fill.
    static func accentText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? brand : Color(hex: 0xA34408)
    }
    static let onBrand = Color(hex: 0x1A0E02)
    /// `#1F1309` — the solid brand wash: warning banners, a selected scope panel.
    static let brandWashSolid = Color(hex: 0x1F1309)
    static func successWash(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x101B13) : Color(hex: 0xEAF6ED)
    }
    static func successText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x8FCB9A) : Color(hex: 0x166534)
    }

    /// Brand at low opacity, for a selected row's fill.
    static func brandWash(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? brandWashSolid : brand.opacity(0.10)
    }

    /// Brand as a border, one step stronger than the wash.
    static func brandEdge(_ scheme: ColorScheme) -> Color {
        brand.opacity(scheme == .dark ? 0.55 : 0.40)
    }

    /// An opaque selection surface that stays distinct from the sidebar rail.
    static func navigationSelection(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x38210F) : Color(hex: 0xFFE6CC)
    }

    // MARK: - Elevation ladder
    //
    // The four values are the specification's, in order: 画布 → 卡片 → 高层.  A fourth
    // step sits between the canvas and the card because the two work areas — the form
    // and the task-status column — have to be separable from the sidebar without being
    // as bright as a card.
    //
    // The model is *raising*, not recessing: a control inside a card is brighter than
    // the card, so everything the user can touch reads as coming forward while prose
    // and rules stay flat.  An earlier build recessed its inputs instead, which made
    // every field look like a hole in the card.

    /// `#090909` — the specification's 画布.  The window floor: the detail pane and the
    /// top bar, the two surfaces everything else is measured against.
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x090909) : Color(hex: 0xF2F2F2)
    }

    /// `#0C0C0C` — the rail: sidebar, inspector and bottom bar.  One step above the
    /// canvas so the three fixed columns read as furniture around the work area.
    static func rail(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x0C0C0C) : Color(hex: 0xECECEC)
    }

    /// A step between the canvas and a card, for the two work areas.
    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x0C0C0C) : Color(hex: 0xFAFAFA)
    }

    /// `#131313` — the specification's 卡片.
    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x131313) : Color(hex: 0xFFFFFF)
    }

    /// `#1F1F1F` — the specification's 高层: inputs, chips, selected rows, the surfaces
    /// that sit *on* a card.
    static func chip(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x1F1F1F) : Color(hex: 0xEDEDED)
    }

    /// `chip`, one step further forward, for a pointer resting on a control.
    ///
    /// Needed because `chip` is now a control's *resting* state: with the surfaces no
    /// longer recessed, hover has nowhere to go but up.
    static func chipHover(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x2A2A2A) : Color(hex: 0xE2E2E2)
    }

    /// A recessed strip *inside* a card — engine text, the log table, a field.  Not
    /// interactive, so it goes the other way from `chip` and settles back towards the
    /// canvas.
    static func well(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x0B0B0B) : Color(hex: 0xF5F5F5)
    }

    /// `#252525` — the unfilled part of a progress bar or slider.
    static func track(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x252525) : Color(hex: 0xDBDBDB)
    }

    /// The 1pt rule that separates two surfaces.
    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.09)
    }

    /// A stronger rule, for the inside of a card.
    static func divider(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.05)
            : Color.black.opacity(0.06)
    }

    // MARK: - Text
    //
    // The specification's three greys.  They are cool by design — a neutral or warm
    // grey next to `#0A0A0A` reads as dirty, which is what the previous warm-ish greys
    // did on this canvas.

    /// `#FFFFFF` — 强调.  Page titles, sidebar row titles, readouts: the few places the
    /// design lets type reach full white, so hierarchy comes from colour as well as
    /// size.
    static func textStrong(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xFFFFFF) : Color(hex: 0x000000)
    }

    /// `#D4D4D9` — 正文.  Values and running text.
    static func text(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xD4D4D9) : Color(hex: 0x1A1A1A)
    }

    /// Secondary prose remains readable on cards, rails and control surfaces.
    static func textSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xA8ADB5) : Color(hex: 0x4B5563)
    }

    /// Supporting labels and units retain at least 4.5:1 contrast on the surface ladder.
    static func textTertiary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x9097A1) : Color(hex: 0x626B78)
    }

    // MARK: - Signals

    /// The design uses exactly one hue.  Everything that would otherwise be "red" or
    /// "yellow" is either the brand (act soon) or a desaturated role colour, so the
    /// orange never has to compete with a second accent.
    static func success(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x5FB85F) : Color(hex: 0x177D3A)
    }

    static func warning(_ scheme: ColorScheme) -> Color { brand }

    static func danger(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xFF5D5D) : Color(hex: 0xD22F2F)
    }

    // MARK: - Compatibility aliases
    //
    // The surfaces that have not been moved onto the ladder yet keep reading these.
    // They resolve to the same values, so nothing renders in a second accent while
    // the rewrite is in flight.

    static let accent = brand
    static let accentDarkMode = brand

    static func accent(for scheme: ColorScheme) -> Color { brand }
    static func accentFill(for scheme: ColorScheme) -> Color {
        brand.opacity(scheme == .dark ? 0.18 : 0.10)
    }
    static func accentEdge(for scheme: ColorScheme) -> Color {
        brand.opacity(scheme == .dark ? 0.50 : 0.34)
    }

    /// The brand doubles as the "release is imminent" signal: the countdown turns
    /// from white to orange inside the last minute.
    static let amber = brand
    static let amberDarkMode = brand
    static func amber(for scheme: ColorScheme) -> Color { brand }
    static func amberEdge(for scheme: ColorScheme) -> Color {
        brand.opacity(scheme == .dark ? 0.45 : 0.30)
    }

    static var separatorColor: Color { Color(nsColor: .separatorColor) }

    // MARK: - Spacing

    /// 4pt half-step over an 8pt grid.  The design's own paddings land on it: a page
    /// is inset 28, a card 18, a field row 16.
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 22
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 36
    }

    // MARK: - Radius

    enum Radius {
        /// Inputs, chips, small buttons.
        static let control: CGFloat = 8
        /// A sidebar row, a banner.
        static let row: CGFloat = 10
        /// A grouped card.
        static let card: CGFloat = 12
        /// The countdown panel, which is the largest object on screen.
        static let hero: CGFloat = 14
        static let window: CGFloat = 12
        static let pill: CGFloat = 999
    }

    // MARK: - Controls

    enum Control {
        /// One height for fields, pop-ups and the small action buttons.
        static let height: CGFloat = 34
        static let smallHeight: CGFloat = 30
        static let radius: CGFloat = Radius.control
        static let pressScale: CGFloat = 0.97
        /// The tick on a selected seat, sized to the label beside it.
        static let tileSize: CGFloat = 16
    }

    // MARK: - Motion

    /// Short, interruptible springs for controls and panels; bounce is reserved for
    /// a rare successful outcome rather than repeated form interactions.
    enum Motion {
        static let snappy = Animation.snappy(duration: 0.22, extraBounce: 0)
        static let bouncy = Animation.bouncy(duration: 0.28, extraBounce: 0.06)
        static let smooth = Animation.smooth(duration: 0.26)
        static let press = Animation.snappy(duration: 0.14, extraBounce: 0)

        static let panel = AnyTransition.scale(scale: 0.96).combined(with: .opacity)
        static let reveal = AnyTransition.offset(y: -8).combined(with: .opacity)
        static let item = AnyTransition.scale(scale: 0.97, anchor: .top).combined(with: .opacity)

        static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }
    }

    // MARK: - Typography
    //
    // Two families, both bundled in `Resources/Fonts` and registered at launch by
    // `AppFonts.register`:
    //
    //   界面文字  Sarasa Gothic SC   — the specification's 中文字体
    //   数据文字  JetBrains Mono     — the specification's 数据字体
    //
    // Body and values use 14–16pt; supporting labels use 12–13pt. Keep the same
    // hierarchy in both appearances, with scrollable content when more room is needed.

    /// The bundled UI family.  Falls back to the system face if it is not registered.
    static let uiFamily = "Sarasa Gothic SC"
    /// The bundled data family.
    static let dataFamily = "JetBrains Mono"

    /// Interface text: labels, prose, headings.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> TicketFont {
        TicketFont(family: uiFamily, pointSize: size, weight: weight)
    }

    /// Data text: clock readings, train codes, counters, engine output.
    ///
    /// JetBrains Mono is not a fallback for the UI face — it is the second half of the
    /// specification, and the reason figures line up in the log table and the countdown
    /// does not shuffle sideways as the seconds tick.
    static func data(_ size: CGFloat, _ weight: Font.Weight = .regular) -> TicketFont {
        TicketFont(family: dataFamily, pointSize: size, weight: weight)
    }

    /// A text style resolved to the point size this layout uses for it.
    ///
    /// Mapping the styles by hand rather than using `.custom(_:size:relativeTo:)` keeps
    /// `Theme.mono` working for the call sites that still pass a style, without letting
    /// Dynamic Type resize a layout that is measured in points.
    private static func size(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 26
        case .title: return 22
        case .title2: return 17
        case .title3: return 15
        case .headline: return 15
        case .subheadline: return 14
        case .callout: return 14
        case .body: return 15
        case .footnote: return 13
        case .caption: return 13
        case .caption2: return 12
        @unknown default: return 14
        }
    }

    /// Engine output at a text style, in the data family.
    static func mono(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> TicketFont {
        data(size(for: style), weight)
    }

    static let metricFont = data(20, .semibold)
    static let monoCaption = data(13)

    /// The page's eyebrow: the section's own name, above the title.
    static let eyebrow = ui(13, .semibold)

    /// The page title.  The largest type in the window apart from the countdown.
    static let pageTitle = ui(26, .semibold)

    /// The sentence under a page title.
    static let pageLead = ui(14)

    /// A card's header.
    static let cardTitle = ui(18, .semibold)

    /// Sections within a card carry more weight than their explanatory text.
    static let sectionTitle = ui(16, .semibold)

    /// A field's label, and the small caps above a readout.
    static let fieldLabel = ui(13, .medium)

    /// Values: route names, train codes, dates.
    static let value = ui(15)
    static let valueStrong = ui(16, .semibold)

    /// The release countdown: the one reading allowed to dominate the window.
    static let countdown = data(40)

    // MARK: - Layout

    /// The window's fixed furniture, measured off the design document.
    enum Layout {
        /// The top bar: brand, engine state, window actions.
        static let topBarHeight: CGFloat = 52
        /// The bottom bar: what will happen, and the one button that makes it happen.
        static let bottomBarHeight: CGFloat = 60
        static let sidebarWidth: CGFloat = 240
        static let sidebarMinWidth: CGFloat = 216
        static let inspectorWidth: CGFloat = 360
        static let inspectorMinWidth: CGFloat = 300
        /// A form reads badly past this width: the design's own column is narrower
        /// than the pane, and letting cards run the full width of a 27" display is
        /// what made the old form look like a spreadsheet.
        static let contentMaxWidth: CGFloat = 776
        static let pageInset: CGFloat = 32
        static let cardInset: CGFloat = 16
    }

    static let configMinimumWidth: CGFloat = 520
    static let sidebarWidth: CGFloat = Layout.sidebarWidth
    static let inspectorWidth: CGFloat = Layout.inspectorWidth
    /// Below this the window can no longer hold three columns at their minimums.
    static let inspectorCollapseWidth: CGFloat = 1180
    static let qrDisplaySize: CGFloat = 160

    // MARK: - Card metrics (legacy names kept: call sites read better with them)

    static let cardRadius: CGFloat = Radius.card
    static let controlRadius: CGFloat = Radius.control
    static let windowRadius: CGFloat = Radius.window
    static let cardPadding: CGFloat = Layout.cardInset
    static let sectionGap: CGFloat = Space.md

    // MARK: - Atmosphere

    /// The one gradient in the window: the wash behind the release countdown.
    ///
    /// A warm pool in the top-left corner fading into the panel it sits on.  The
    /// design's hero is lit rather than filled — the digits stay white, and the colour
    /// only tells you the countdown is live.  Inside the last minute the pool deepens
    /// and shifts to the brand's own hue, which is how the design says "act now"
    /// without a second colour or a warning triangle.
    static func heroAtmosphere(for scheme: ColorScheme, imminent: Bool) -> LinearGradient {
        if scheme == .dark {
            // The pool falls away vertically into the rail it sits on, so the lit top
            // reads as light falling on the surface rather than as a panel of its own.
            return LinearGradient(
                colors: imminent
                    ? [Color(hex: 0x3A1C06), Color(hex: 0x221408), Color(hex: 0x0B0A09)]
                    : [Color(hex: 0x2A1506), Color(hex: 0x1A1006), Color(hex: 0x0B0A09)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: imminent
                ? [Color(hex: 0xFFE9D2), Color(hex: 0xFFF4E8), Color(hex: 0xFFFFFF)]
                : [Color(hex: 0xFFF1E2), Color(hex: 0xFFF8F1), Color(hex: 0xFFFFFF)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The wash behind a captured-ticket card while the run is submitting: warmer and
    /// flatter than the countdown's, because by then the light is the news.
    static func hitAtmosphere(for scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
            ? LinearGradient(
                colors: [Color(hex: 0x33200F), Color(hex: 0x241608)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [Color(hex: 0xFFF1E2), Color(hex: 0xFFF8F1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
    }

    /// The header wash of a finished-run panel: green for a submitted order, olive for
    /// a run that ended without one.
    static func outcomeAtmosphere(for scheme: ColorScheme, succeeded: Bool) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: succeeded
                    ? [Color(hex: 0x16281B), Color(hex: 0x0E1710)]
                    : [Color(hex: 0x2A2410), Color(hex: 0x171409)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: succeeded
                ? [Color(hex: 0xE4F4E7), Color(hex: 0xF4FBF5)]
                : [Color(hex: 0xF7EEDC), Color(hex: 0xFCF8F0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The app mark's fill: the icon's own 135° gradient, from the design's icon page.
    static func brandMark(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [brand, brandDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Surfaces

extension View {
    /// A grouped card: the ladder's third step, one hairline, no shadow.
    func cardSurface(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }
}

/// Reads the scheme from the environment so call sites stay a single word.
///
/// A `ViewModifier` rather than a plain modifier chain because `@Environment` is only
/// readable from inside a view or modifier — and the whole point is that the surface
/// colour follows the appearance without every call site passing it in.
private struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                Theme.card(scheme),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            // The design's cards carry no resting border — the ladder alone separates
            // them from the canvas.  Increase Contrast is the one setting that needs
            // the edge back.
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        contrast == .increased ? Theme.hairline(scheme) : .clear,
                        lineWidth: 1
                    )
            )
    }
}

extension Theme {
    /// A hairline that answers Increase Contrast.
    ///
    /// HIG 11.7: with Increase Contrast on, a border drawn at a fixed low alpha is
    /// exactly the low-contrast edge the setting exists to remove, so under that
    /// setting every hairline becomes a real line.
    static func hairline(contrast: ColorSchemeContrast, alpha: Double) -> Color {
        contrast == .increased
            ? Color.primary.opacity(0.5)
            : separatorColor.opacity(alpha)
    }
}

// MARK: - Motion plumbing

private struct MotionEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False when the system asks for reduced motion.
    ///
    /// Set once at the window root instead of being read at each call site: with twenty
    /// animations across the form, an accessibility setting that every one of them has
    /// to remember to honour is one that will end up honoured unevenly.  `motion(_:value:)`
    /// is what reads it.
    var motionEnabled: Bool {
        get { self[MotionEnabledKey.self] }
        set { self[MotionEnabledKey.self] = newValue }
    }
}

extension View {
    /// Animate a change with one of the app's springs — or land it instantly when the
    /// system's Reduce Motion setting is on.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.motionEnabled) private var enabled
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(enabled ? animation : nil, value: value)
    }
}
