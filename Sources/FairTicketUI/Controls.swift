import AppKit
import SwiftUI

// The app's own control layer.
//
// `Theme` gave the surfaces a vocabulary — cards, chips, status pills, the mesh hero —
// but nothing below that: every input still came from AppKit, at AppKit's radius, with
// AppKit's focus ring and AppKit's system-blue selection.  The result was a form whose
// boxes came from a different design language from the surfaces holding them.
//
// Everything here exists so a control has one resting state, one focused state and one
// invalid state, in the app's own colours, and so press feedback is a property of the
// button rather than something each call site remembers or forgets.

// MARK: - Field chrome

/// The one shape every editable control wears.
///
/// A filled surface with a hairline that recedes while the control is in use: at rest
/// the border carries the separation, while focused or invalid the *state* carries it
/// and the hairline drops away.  Invalid is a state of the same control rather than a
/// different one, so a field the engine rejected never changes size or jumps.
struct FieldChrome: ViewModifier {
    var isFocused = false
    var isInvalid = false
    /// Pop-ups have no focus ring of their own — they open a menu instead of holding a
    /// caret, so a ring would claim an editing state the control is never in.
    var supportsFocus = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Space.xs)
            .frame(height: Theme.Control.height)
            .background(
                RoundedRectangle(cornerRadius: Theme.Control.radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Control.radius, style: .continuous)
                    .strokeBorder(edge, lineWidth: isEmphasised ? 1.5 : 1)
            )
            .motion(Theme.Motion.snappy, value: isFocused)
            .motion(Theme.Motion.snappy, value: isInvalid)
    }

    private var isEmphasised: Bool {
        isInvalid || (isFocused && supportsFocus)
    }

    private var fill: AnyShapeStyle {
        if isInvalid { return AnyShapeStyle(Theme.danger(scheme).opacity(scheme == .dark ? 0.14 : 0.07)) }
        if isFocused && supportsFocus { return AnyShapeStyle(Theme.brandWash(scheme)) }
        // 高层: a control sits *above* the card it is on, so it is brighter than the card
        // rather than sunk into it.  Recessing the fields made every one of them read as
        // a hole punched through the surface.
        return AnyShapeStyle(Theme.chip(scheme))
    }

    private var edge: AnyShapeStyle {
        if isInvalid { return AnyShapeStyle(Theme.danger(scheme).opacity(contrast == .increased ? 0.85 : 0.55)) }
        if isFocused && supportsFocus { return AnyShapeStyle(Theme.brandEdge(scheme)) }
        return AnyShapeStyle(Theme.hairline(scheme))
    }
}

extension View {
    /// See `FieldChrome`.  A modifier rather than a wrapper so a control that needs its
    /// own keyboard handling — the station field's ↑↓ list, the numeric field's format —
    /// keeps it while still wearing the shared chrome.
    func fieldChrome(
        isFocused: Bool = false,
        isInvalid: Bool = false,
        supportsFocus: Bool = true
    ) -> some View {
        modifier(FieldChrome(isFocused: isFocused, isInvalid: isInvalid, supportsFocus: supportsFocus))
    }
}

// MARK: - Text field

/// A text field wearing the app's chrome.
///
/// Owns its focus state instead of taking one from the caller: the ring has to appear
/// on the field being typed in, and a `FocusState` threaded through every call site is
/// exactly how one field ends up without a ring.
struct ThemedField: View {
    let placeholder: String
    @Binding var text: String
    var isInvalid = false
    var font: TicketFont = Theme.value
    var alignment: TextAlignment = .leading
    var maxWidth: CGFloat?

    @FocusState private var isFocused: Bool

    init(
        _ placeholder: String,
        text: Binding<String>,
        isInvalid: Bool = false,
        font: TicketFont = Theme.value,
        alignment: TextAlignment = .leading,
        maxWidth: CGFloat? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.isInvalid = isInvalid
        self.font = font
        self.alignment = alignment
        self.maxWidth = maxWidth
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .multilineTextAlignment(alignment)
            .focused($isFocused)
            .fieldChrome(isFocused: isFocused, isInvalid: isInvalid)
            .frame(maxWidth: maxWidth)
    }
}

// MARK: - Pop-up

/// A pop-up in the app's chrome instead of AppKit's bezel.
///
/// `Picker(.menu)` draws a stock `NSPopUpButton`: the small twin-chevron bezel from
/// the system-settings look, which is the single control that most made the form read
/// as dated next to its own cards.  A `Menu` with our own label is the same control
/// with our own resting state — and the menu that opens is still the system menu, so
/// the part that is genuinely better as a system control stays one.
struct ThemedMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [ThemedMenuOption<Value>]
    var icon: String?
    var font: TicketFont = Theme.value
    var maxWidth: CGFloat?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    // The system menu cannot show our tick tile, so the selected row is
                    // marked the way every macOS menu marks it.
                    if option.value == selection {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(Theme.accentText(scheme))
                }
                Text(currentLabel)
                    .font(font)
                    .lineLimit(1)
                Spacer(minLength: Theme.Space.xs)
                Image(systemName: "chevron.up.chevron.down")
                    .font(Theme.ui(10, .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .fieldChrome(supportsFocus: false)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: maxWidth)
        .accessibilityLabel(currentLabel)
    }

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }
}

/// One row of a `ThemedMenu`.
struct ThemedMenuOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }

    init(_ value: Value, _ label: String) {
        self.value = value
        self.label = label
    }
}

// MARK: - Date

/// The date, as the app's own field, with the system calendar behind a click.
///
/// `.datePickerStyle(.field)` is an `NSDatePicker`: it renders `2026/10 / 1` with its
/// own stepper and its own type, and no modifier reaches inside it.  Showing the ISO
/// value in the shared chrome and putting the graphical calendar in a popover keeps
/// the calendar itself — nothing about picking a date is reimplemented — while the
/// resting state matches the field beside it.
struct ThemedDateField: View {
    @Binding var date: Date
    var isInvalid = false
    /// A date needs no more room than its own text: left to fill the card it became a
    /// 900pt-wide input for ten characters.
    var maxWidth: CGFloat? = 220

    @State private var showingCalendar = false

    var body: some View {
        Button {
            showingCalendar = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ISO8601Day.string(from: date))
                    .font(Theme.mono(.callout))
                Spacer(minLength: Theme.Space.xs)
                Image(systemName: "chevron.down")
                    .font(Theme.ui(10, .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .fieldChrome(isInvalid: isInvalid, supportsFocus: false)
            .frame(maxWidth: maxWidth)
        }
        .buttonStyle(.pressable)
        .popover(isPresented: $showingCalendar, arrowEdge: .bottom) {
            TicketCalendar(date: $date, onClose: { showingCalendar = false })
        }
        .accessibilityLabel("乘车日期")
        .accessibilityValue(ISO8601Day.string(from: date))
    }
}

// MARK: - Tick

/// The app's tick, replacing the stock checkbox glyph.
///
/// `square` / `checkmark.square.fill` is the AppKit checkbox drawn with SF Symbols: it
/// carries the system's weight and the system's blue, and it was the only place the
/// form still showed one.  A tile that fills with the brand and holds a white tick
/// belongs to the same family as the seat map and the chips around it.
///
/// The tick settles rather than bouncing: this control is toggled dozens of times while
/// a cart is filled, and a bounce repeated that often turns a confirmation into a tic.
struct CheckTile: View {
    let isOn: Bool
    var size: CGFloat = Theme.Control.tileSize

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(isOn ? AnyShapeStyle(Theme.accent(for: scheme)) : AnyShapeStyle(Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(
                        isOn ? Color.clear : Theme.separatorColor.opacity(0.9),
                        lineWidth: 1
                    )
            )
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.58, weight: .bold))
                    .foregroundStyle(Theme.onBrand)
                    .opacity(isOn ? 1 : 0)
                    // Never from scale(0): a mark that appears from nothing reads as a
                    // glitch, one that grows from most of its size reads as a press.
                    .scaleEffect(isOn ? 1 : 0.6)
            )
            .frame(width: size, height: size)
            .motion(Theme.Motion.snappy, value: isOn)
    }
}

// MARK: - Stepper

/// The app's stepper: two small buttons sharing one chrome.
///
/// The stock `Stepper` draws the system's bezel with its own divider, which beside a
/// field in the app's chrome read as a control from another app.  Same affordance, same
/// height and radius as everything else; at the ends of its range it dims rather than
/// disappearing, so the control does not change shape while it is being held.
struct NumberStepper: View {
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    var decrementEnabled = true
    var incrementEnabled = true

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: decrementEnabled, action: onDecrement)
            Rectangle()
                .fill(Theme.separatorColor.opacity(0.5))
                .frame(width: 1, height: 14)
            button("plus", enabled: incrementEnabled, action: onIncrement)
        }
        .frame(height: Theme.Control.height)
        .background(
            RoundedRectangle(cornerRadius: Theme.Control.radius, style: .continuous)
                .fill(.quaternary.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Control.radius, style: .continuous)
                .strokeBorder(Theme.separatorColor.opacity(0.7), lineWidth: 1)
        )
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.ui(11, .semibold))
                .frame(width: 24, height: Theme.Control.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .foregroundStyle(
            enabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.secondary.opacity(0.35))
        )
        .disabled(!enabled)
        .accessibilityLabel(symbol == "minus" ? "减少" : "增加")
    }
}

// MARK: - Buttons

/// Press feedback for the buttons the app draws itself.
///
/// AppKit's bezels already answer a press.  The app's own buttons did not, so a click
/// gave no acknowledgement until whatever it triggered had finished — which is the
/// difference between an interface that feels alive and one that feels busy.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = Theme.Control.pressScale

    @Environment(\.motionEnabled) private var motionEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && motionEnabled ? scale : 1)
            .animation(motionEnabled ? Theme.Motion.press : nil, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// The press response on its own, for a control that draws its own chrome.
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// The app's primary action.
///
/// Replaces `.borderedProminent`, whose bezel is a gradient, a border and a shadow
/// borrowed from the system's own controls — three effects the app's surfaces do not
/// use anywhere else.  This is one flat brand fill at the app's radius, with the same
/// press response as everything else.
///
/// It is the *only* filled button in the window.  The design gives the brand to
/// precisely one control per screen, which is what keeps it meaning "this is the
/// thing to press" instead of becoming decoration.
struct BrandActionButtonStyle: ButtonStyle {
    var size: CGFloat = 32

    @Environment(\.colorScheme) private var scheme
    @Environment(\.motionEnabled) private var motionEnabled
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(15, .semibold))
            .foregroundStyle(
                isEnabled
                    ? Theme.onBrand
                    : Color.white.opacity(0.7)
            )
            .padding(.horizontal, Theme.Space.lg)
            .frame(height: size)
            .background(
                Theme.brand.opacity(isEnabled ? 1 : 0.35),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed && motionEnabled ? Theme.Control.pressScale : 1)
            .animation(motionEnabled ? Theme.Motion.press : nil, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BrandActionButtonStyle {
    /// A primary action at the standard control height.
    static var brandAction: BrandActionButtonStyle { BrandActionButtonStyle() }
    /// A primary action with room for a two-line label.
    static func brandAction(height: CGFloat) -> BrandActionButtonStyle {
        BrandActionButtonStyle(size: height)
    }
}

/// A secondary action that reads as a control rather than as a link.
///
/// 更新站点, 去选择卧铺席别 and 恢复高级参数默认值 were plain brand-coloured text: no
/// resting shape, no hover, nothing to press.  A quiet fill on hover is what separates
/// "this does something" from "this is a label", without giving three inline actions
/// the weight of a filled button.
struct QuietButton: View {
    let title: String
    var systemImage: String?
    var tint: Color?
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    init(
        _ title: String,
        systemImage: String? = nil,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption)
                }
                Text(title).font(Theme.ui(13, .medium)).lineLimit(1)
            }
            .foregroundStyle(tint ?? Theme.accentText(scheme))
            .padding(.horizontal, Theme.Space.xs)
            .frame(height: 30)
            .background(
                hovering ? Theme.accentFill(for: scheme) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .opacity(isEnabled ? 1 : 0.45)
    }
}
