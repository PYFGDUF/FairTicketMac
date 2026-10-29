import SwiftUI

// MARK: - Page heading

/// A page's heading: the section's name in brand orange, the page's own title, and one
/// sentence of guidance.
///
/// This replaces the old icon-tile header.  The design states where you are in words
/// rather than with a glyph, and puts the weight on the second line — which is also
/// what makes the page scannable from across the room while the form below it is being
/// filled in.
///
/// The heading crossfades when its words change, and only the heading does.  Wrapping the
/// whole page in a transition instead would hold both pages in the scroll view at once
/// for the length of the animation, so the form below would jump down and back up.
struct PageHeader: View {
    let title: String
    let subtitle: String
    /// The section's name, shown above the title in brand orange.
    var eyebrow: String
    var accessory: AnyView?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 6) {
                if !eyebrow.isEmpty {
                    Text(eyebrow)
                        .font(Theme.eyebrow)
                        .foregroundStyle(Theme.accentText(scheme))
                        .contentTransition(.opacity)
                }
                Text(title)
                    .font(Theme.pageTitle)
                    .foregroundStyle(Theme.textStrong(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.pageLead)
                        .foregroundStyle(Theme.textSecondary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
            }
            .motion(Theme.Motion.snappy, value: title)
            Spacer(minLength: 0)
            if let accessory { accessory }
        }
        .padding(.bottom, Theme.Space.xs)
    }
}

// MARK: - Card

/// A grouped surface: one step up the elevation ladder, one hairline, no shadow.
///
/// The header is a title, an optional right-hand marker (必填 / 可选 / 不保证) and an
/// optional accessory, separated from the body by a rule.  A card with no title draws
/// only its body, which is what the inspector's small readouts use.
struct Card<Content: View>: View {
    var title: String?
    /// A heading in brand orange instead of the default text colour.
    ///
    /// Reserved for a card whose subject is the thing the page is *about* right now —
    /// the live query interval on 高级参数 — so the eye lands on it among collapsed
    /// groups that all look alike.
    var titleTint: Color?
    /// The marker the design puts at the header's trailing edge.  Orange for a
    /// required field group, grey for anything the engine treats as a preference.
    var marker: String?
    var markerTint: Color?
    var accessory: AnyView?
    /// False when the content is deliberately hidden — a collapsed disclosure.  The
    /// card then draws only its header: leaving the rule and the content padding in
    /// place would put an empty strip under every collapsed group.
    var showsContent: Bool = true
    /// The body's own inset, for the few cards that want a tighter or looser one.
    var bodyInset: CGFloat = Theme.Layout.cardInset
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme

    init(
        title: String? = nil,
        titleTint: Color? = nil,
        marker: String? = nil,
        markerTint: Color? = nil,
        accessory: AnyView? = nil,
        showsContent: Bool = true,
        bodyInset: CGFloat = Theme.Layout.cardInset,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.titleTint = titleTint
        self.marker = marker
        self.markerTint = markerTint
        self.accessory = accessory
        self.showsContent = showsContent
        self.bodyInset = bodyInset
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                header(title: title)
                if showsContent {
                    Rectangle()
                        .fill(Theme.divider(scheme))
                        .frame(height: 1)
                }
            }
            if showsContent {
                content
                    .padding(bodyInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(Theme.Motion.reveal)
            }
        }
        .cardSurface()
        .clipped()
        .motion(Theme.Motion.snappy, value: showsContent)
    }

    private func header(title: String) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Text(title)
                .font(Theme.cardTitle)
                .foregroundStyle(titleTint ?? Theme.textStrong(scheme))
            Spacer(minLength: Theme.Space.xs)
            if let marker {
                Text(marker)
                    .font(Theme.ui(12, .medium))
                    .foregroundStyle(markerTint ?? Theme.accentText(scheme))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (markerTint ?? Theme.brand).opacity(0.14),
                        in: Capsule()
                    )
            }
            if let accessory { accessory }
        }
        .padding(.horizontal, Theme.Layout.cardInset)
        .padding(.vertical, 12)
    }
}

// MARK: - Small parts

/// Rounded glyph tile.  Still used for the seat map and the candidate readout, where a
/// single object benefits from a mark.
struct IconTile: View {
    let systemImage: String
    var tint: Color = .secondary
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.opacity(0.15))
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(tint)
            )
            .frame(width: size, height: size)
    }
}

/// The orange sequence number the design puts at the head of a cart entry.
struct SequenceBadge: View {
    let value: Int
    /// `false` for the alternatives after the first: the design dims everything that is
    /// not the engine's first choice, so the orange stays meaningful.
    var emphasised: Bool = true
    var size: CGFloat = 22

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text("\(value)")
            .font(Theme.ui(size * 0.55, .semibold))
            .monospacedDigit()
            .foregroundStyle(
                emphasised
                    ? Theme.onBrand
                    : Theme.text(scheme)
            )
            .frame(width: size, height: size)
            .background(
                emphasised ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Theme.chip(scheme)),
                in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            )
    }
}

/// Compact status label: a word in a tinted capsule.
struct StatusPill: View {
    let text: String
    var tint: Color?
    var systemImage: String?
    var showsDot: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2.weight(.semibold))
            } else if showsDot {
                Circle().fill(tint ?? Theme.textTertiary(scheme)).frame(width: 6, height: 6)
            }
            Text(text)
                .font(Theme.ui(13, .medium))
                .contentTransition(.opacity)
        }
        .foregroundStyle(tint ?? Theme.textSecondary(scheme))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            tint == nil ? Theme.chip(scheme) : (tint ?? .clear).opacity(0.16),
            in: Capsule()
        )
        // A badge is a state indicator, and during a run this one turns over eight times
        // as the engine works through its phases.  Words that change in place, with the
        // capsule's tint easing across, read as one badge changing its mind — where a
        // simultaneous text-and-colour swap reads as the badge being replaced.
        .motion(Theme.Motion.snappy, value: text)
    }
}

/// One field the 「添加备选」 row is still waiting for.
///
/// Nouns, not sentences.  A disabled primary button has to say what it is waiting for,
/// and the fewest words that can do that are the labels of the controls themselves.
struct RequirementChip: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(Theme.ui(12, .medium))
            .foregroundStyle(Theme.accentText(scheme))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.brandWash(scheme), in: Capsule())
    }
}

/// "还需" plus one chip per outstanding field.
struct RequirementStrip: View {
    let fields: [CartDraftField]

    var body: some View {
        HStack(spacing: 5) {
            Text("还需")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            ForEach(fields) { field in
                RequirementChip(text: field.label)
            }
        }
    }
}

/// Neutral count chip, e.g. "12 项" on a disclosure header.
struct CountChip: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(Theme.ui(14, .medium))
            .monospacedDigit()
            .foregroundStyle(Theme.textTertiary(scheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.chip(scheme), in: Capsule())
    }
}

/// Inline explanatory strip.
///
/// The brand is reserved for things that will surprise the user — a soft preference
/// that will not be honoured, a draft that will not be submitted — so it keeps its
/// meaning instead of decorating every field.  The mark is a filled rounded square,
/// the design's own note glyph, rather than an outlined system symbol.
struct InlineNote: View {
    enum Tone {
        case neutral
        case warning
        case success
        case brand

        func tint(_ scheme: ColorScheme) -> Color {
            switch self {
            case .neutral: return Theme.brand
            case .warning: return Theme.brand
            case .success: return Theme.success(scheme)
            case .brand: return Theme.brand
            }
        }

        /// The strip's own fill.  A warning sits on the brand's wash; a confirmed state
        /// on the success wash; a plain note stays on the card.
        func background(_ scheme: ColorScheme) -> Color {
            switch self {
            case .neutral: return Theme.card(scheme)
            case .warning, .brand: return Theme.brandWash(scheme)
            case .success: return Theme.successWash(scheme)
            }
        }

        /// The strip's prose colour.
        func text(_ scheme: ColorScheme) -> Color {
            switch self {
            case .neutral: return Theme.textSecondary(scheme)
            case .warning, .brand: return Theme.brandText(scheme)
            case .success: return Theme.successText(scheme)
            }
        }

        var icon: String {
            switch self {
            case .neutral: return "exclamationmark"
            case .warning: return "exclamationmark"
            case .success: return "checkmark"
            case .brand: return "checkmark"
            }
        }
    }

    let text: String
    var tone: Tone = .neutral

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.sm) {
            if tone == .neutral {
                // A plain note carries a dot, not a glyph plate: it informs rather than
                // warns, and the plate is what makes a warning read as one.
                Circle()
                    .fill(tone.tint(scheme))
                    .frame(width: 6, height: 6)
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tone.tint(scheme))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Image(systemName: tone.icon)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tone == .success && scheme == .light ? Color.white : Theme.onBrand)
                    )
            }
            Text(text)
                .font(Theme.ui(14))
                .foregroundStyle(tone.text(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            tone.background(scheme),
            in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        )
    }
}

/// One readout in a metric strip: a small label over a large figure.
struct MetricTile: View {
    let name: String
    let value: String
    var unit: String = ""
    var tint: Color?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(Theme.fieldLabel)
                .foregroundStyle(Theme.textTertiary(scheme))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.metricFont)
                    .foregroundStyle(tint ?? Theme.textStrong(scheme))
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(Theme.ui(14))
                        .foregroundStyle(Theme.textTertiary(scheme))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Monospaced block for engine-authored text (attempt order, similar payloads).
///
/// Unchanged text is shown, never reflowed: these strings encode the engine's real
/// decision rules.
struct EngineTextBlock: View {
    let text: String
    var maxLines: Int?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(Theme.monoCaption)
            .foregroundStyle(Theme.textSecondary(scheme))
            .textSelection(.enabled)
            .lineLimit(maxLines)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Theme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.well(scheme),
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            )
    }
}
