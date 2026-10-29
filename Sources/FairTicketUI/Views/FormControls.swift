import SwiftUI
import FairTicketKit

/// Renders one field from its engine-provided spec.
///
/// Nothing here decides bounds or wording: the label, help text, control kind,
/// range, step and options all arrive in the spec, so a field added on the Python
/// side appears without a Swift change and an input can never offer a value the
/// backend validator rejects.
struct FieldRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let spec: FieldSpec

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            // The cart is the page's own subject and the card around it already names it,
            // so a third heading here ("备选购物车" under a 备选购物车 page and a 备选列表
            // card) said the same thing three times.  Its error note comes from the editor
            // too, so both halves of the chrome are skipped together.
            if spec.kind != .cart {
                header
            }
            control
            // Gated: the engine checks on every edit, but only a check the user asked
            // for turns the form red (see AppModel.visibleFieldError).
            if spec.kind != .cart, let message = model.visibleFieldError(spec.key) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(message)
                        .font(Theme.ui(13))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.danger(scheme))
                .padding(.horizontal, 6)
                .padding(.vertical, Theme.Space.xxs)
                .background(
                    Theme.danger(scheme).opacity(scheme == .dark ? 0.16 : 0.08),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .motion(Theme.Motion.snappy, value: model.visibleFieldError(spec.key))
    }

    private var header: some View {
        HStack(spacing: Theme.Space.xxs) {
            Text(spec.label)
                .font(Theme.fieldLabel)
                .foregroundStyle(Theme.textTertiary(scheme))
            if !spec.help.isEmpty {
                Image(systemName: "questionmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help(spec.help)
            }
            Spacer(minLength: Theme.Space.xs)
            headerAccessory
        }
    }

    /// A control that switches the field off belongs on the label line, not under it: it
    /// states something about the field rather than about its value.  Moving it up takes a
    /// mostly-empty row out of every time field and puts the switches on one shared
    /// alignment line instead of leaving each one floating after its own text.
    @ViewBuilder
    private var headerAccessory: some View {
        if spec.kind == .time, !spec.optionalToggle.isEmpty {
            TimeFieldToggle(spec: spec)
        }
    }

    @ViewBuilder
    private var control: some View {
        switch spec.kind {
        case .text:
            ThemedField(spec.placeholder, text: stringBinding, isInvalid: isInvalid)

        case .list:
            // The raw text is kept as typed: the backend splits on every separator
            // it accepts, so re-implementing that here would risk divergence.
            ThemedField(spec.placeholder, text: listBinding, isInvalid: isInvalid)

        case .date:
            ThemedDateField(date: dateBinding, isInvalid: isInvalid)

        case .time:
            TimeFieldRow(spec: spec)

        case .number, .integer:
            NumericField(spec: spec)

        case .toggle:
            Toggle(spec.inlineLabel.isEmpty ? spec.label : spec.inlineLabel, isOn: boolBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(Theme.value)

        case .choice:
            ThemedMenu(
                selection: choiceBinding,
                options: spec.options.map { ThemedMenuOption($0.value, $0.label) },
                maxWidth: 260
            )

        case .cart:
            CartEditor(spec: spec)

        case .ticketTypes:
            // The roster owns both the names and the per-passenger override, because the
            // design puts them on one row.  This case still exists so the engine's field
            // stays reachable if some other page renders it.
            PassengerRosterEditor()

        case .seatMap:
            SeatMapEditor(spec: spec)

        case .berths:
            BerthCountEditor(spec: spec)
        }
    }

    /// Whether the engine flagged this field *and* the user asked for a check — the
    /// same gate the message under the control uses, so the red border and the red
    /// note can never disagree about whether there is a problem.
    private var isInvalid: Bool {
        model.visibleFieldError(spec.key) != nil
    }

    // MARK: Bindings

    private var stringBinding: Binding<String> {
        Binding(get: { model.string(spec.key) }, set: { model.setString(spec.key, $0) })
    }

    /// A list field shows one line of text.  The backend hands back an array after
    /// import, so both shapes have to render.
    private var listBinding: Binding<String> {
        Binding(get: { model.listText(spec.key) }, set: { model.setListText(spec.key, $0) })
    }

    private var boolBinding: Binding<Bool> {
        Binding(get: { model.bool(spec.key) }, set: { model.setBool(spec.key, $0) })
    }

    private var choiceBinding: Binding<String> {
        Binding(get: { model.string(spec.key) }, set: { model.setString(spec.key, $0) })
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { ISO8601Day.date(from: model.string(spec.key)) ?? Date() },
            set: { model.setString(spec.key, ISO8601Day.string(from: $0)) }
        )
    }
}

// MARK: - Stations

/// Station input with the desktop form's completion rule.
///
/// The names come from the engine's own snapshot and the match rule mirrors the
/// Windows completer exactly (case-insensitive substring, twelve visible, sorted),
/// so both frontends offer the same names for the same keystrokes instead of one
/// being quietly more helpful than the other.
///
/// Completion is only an affordance: the typed text is submitted verbatim and the
/// backend still resolves it, so nothing here can make an invalid station look
/// acceptable.  Takes a binding rather than a `FieldSpec` because version 5 has no
/// station *fields* — the two station editors now live inside one cart entry, and
/// there can be an arbitrary number of them in flight.
struct StationField: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.motionEnabled) private var motionEnabled
    let label: String
    let placeholder: String
    @Binding var text: String

    @FocusState private var isFocused: Bool
    @State private var highlighted = 0
    @State private var hovered: String?
    /// Set when Escape hid the list, so it stays hidden until the text changes
    /// again rather than reappearing on the next keystroke-free redraw.
    @State private var suppressedFor: String?

    private static let visibleLimit = 12

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .fieldChrome(isFocused: isFocused)
                .accessibilityLabel(label)
                .onSubmit(accept)
                .onKeyPress(.downArrow) { moveHighlight(1) }
                .onKeyPress(.upArrow) { moveHighlight(-1) }
                .onKeyPress(.escape) {
                    suppressedFor = text
                    return .handled
                }
                .onChange(of: text) { _, _ in
                    highlighted = 0
                    suppressedFor = nil
                }

            if !suggestions.isEmpty {
                suggestionList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .motion(Theme.Motion.snappy, value: suggestions.isEmpty)
    }

    private var suggestions: [String] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard isFocused, !query.isEmpty, suppressedFor != text else { return [] }
        return Array(
            model.stationNames
                .filter { $0 != query && $0.localizedCaseInsensitiveContains(query) }
                .sorted()
                .prefix(Self.visibleLimit)
        )
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        // Identity is the station name, not the row's position: the list
                        // is refiltered on every keystroke, so index identity made SwiftUI
                        // reuse a row for a different station while scrolling to it.
                        ForEach(Array(suggestions.enumerated()), id: \.element) { index, name in
                            suggestionRow(name: name, index: index)
                                .id(name)
                        }
                    }
                    .padding(3)
                }
                .frame(maxHeight: 200)
                // ↑↓ can walk past the visible rows; keep the selection in view.
                .onChange(of: highlighted) { _, index in
                    guard suggestions.indices.contains(index) else { return }
                    withAnimation(motionEnabled ? Theme.Motion.snappy : nil) {
                        proxy.scrollTo(suggestions[index], anchor: .center)
                    }
                }
            }
            Divider().opacity(0.5)
            // A footer, not an overlay: as an overlay it covered the last row.
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.xs)
                .padding(.vertical, 4)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(.separator.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
    }

    private func suggestionRow(name: String, index: Int) -> some View {
        let active = index == highlighted || hovered == name
        return Button {
            accept(name)
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(active ? Theme.accentText(scheme) : Color.secondary.opacity(0.6))
                    .accessibilityHidden(true)
                Text(name).font(.callout)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, 5)
            .background(
                active ? Theme.accentFill(for: scheme) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择\(name)")
        .onHover { hovered = $0 ? name : (hovered == name ? nil : hovered) }
    }

    private var hint: String {
        let query = text.trimmingCharacters(in: .whitespaces)
        let total = model.stationNames
            .filter { $0.localizedCaseInsensitiveContains(query) }
            .count
        if total > suggestions.count {
            return "共 \(total) 个匹配 · ↑↓ 选择，回车确认"
        }
        return "↑↓ 选择，回车确认"
    }

    private func moveHighlight(_ delta: Int) -> KeyPress.Result {
        let count = suggestions.count
        guard count > 0 else { return .ignored }
        highlighted = (highlighted + delta + count) % count
        return .handled
    }

    private func accept() {
        if suggestions.indices.contains(highlighted) {
            accept(suggestions[highlighted])
        } else {
            isFocused = false
        }
    }

    private func accept(_ name: String) {
        text = name
        highlighted = 0
        suppressedFor = nil
        isFocused = false
    }
}

/// `yyyy-MM-dd` in a fixed locale, so the stored string never depends on the
/// user's regional settings.
let ISO8601Day: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

// MARK: - Time

/// Hour / minute / second plus the "off" switch.
///
/// The desktop form serialises a disabled time to an empty string, which the
/// engine reads as "start now" or "no stop time"; the switch label comes from the
/// spec so the wording stays identical.
private struct TimeFieldRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let spec: FieldSpec

    var body: some View {
        HStack(spacing: 0) {
            component("时", value: parts.hour, range: 0...23)
            divider
            component("分", value: parts.minute, range: 0...59)
            divider
            component("秒", value: parts.second, range: 0...59)
        }
        .background(
            .quaternary.opacity(0.35),
            in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(.separator.opacity(0.8), lineWidth: 1)
        )
        .fixedSize()
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    /// A hairline rather than a colon glyph: at this height a floating ":" between two
    /// numbers reads as three separate boxes, which is what made the old control look like a
    /// box inside a box inside the card.
    private var divider: some View {
        Rectangle()
            .fill(.separator.opacity(0.6))
            .frame(width: 1, height: 16)
    }

    private var isDisabled: Bool { model.string(spec.key).isEmpty }

    private var parts: (hour: Int, minute: Int, second: Int) {
        let raw = model.string(spec.key)
        let fields = raw.split(separator: ":").compactMap { Int($0) }
        guard fields.count == 3 else { return (10, 0, 0) }
        return (fields[0], fields[1], fields[2])
    }

    private func component(_ unit: String, value: Int, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 3) {
            TextField("", value: Binding(
                get: { value },
                set: { newValue in
                    let clamped = min(max(newValue, range.lowerBound), range.upperBound)
                    let current = parts
                    let updated: (Int, Int, Int)
                    switch unit {
                    case "时": updated = (clamped, current.minute, current.second)
                    case "分": updated = (current.hour, clamped, current.second)
                    default: updated = (current.hour, current.minute, clamped)
                    }
                    model.setString(
                        spec.key,
                        String(format: "%02d:%02d:%02d", updated.0, updated.1, updated.2)
                    )
                }
            ), format: .number)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(Theme.mono(.body, .medium))
            .frame(width: 28)

            // Number first, unit after it: the unit rides beside its number instead of
            // sitting under it, so the whole control is one row tall and lines up with the
            // text fields around it.
            Text(unit)
                .font(Theme.ui(12))
                .foregroundStyle(Theme.textTertiary(scheme))
        }
        .padding(.horizontal, Theme.Space.xs)
        .padding(.vertical, 7)
    }
}

/// The switch that takes a time field out of play, drawn on the field's label line by
/// `FieldRow`.
///
/// "Off" is stored as an empty string, and turning it back on restores the packaged default
/// rather than inventing a time — the two halves of that rule live together here.
private struct TimeFieldToggle: View {
    @EnvironmentObject private var model: AppModel
    let spec: FieldSpec

    var body: some View {
        Toggle(spec.optionalToggle, isOn: isDisabledBinding)
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(Theme.ui(13))
    }

    private var isDisabled: Bool { model.string(spec.key).isEmpty }

    private var isDisabledBinding: Binding<Bool> {
        Binding(
            get: { isDisabled },
            set: { disabled in
                if disabled {
                    model.setString(spec.key, "")
                } else {
                    // Restore the packaged default rather than inventing a time.
                    let fallback = model.capabilities?.defaults[spec.key]?.stringValue ?? "10:00:00"
                    model.setString(spec.key, fallback.isEmpty ? "10:00:00" : fallback)
                }
            }
        )
    }
}

// MARK: - Task mode

/// The design's mode switch: two panels, one of them lit.
///
/// The engine stores this as one boolean, and the two states are not a setting so much
/// as a promise about what the app will do to the user's account — so each panel says
/// what it *does*, not what it is called.  A plain switch said neither.
struct ModeSelector: View {
    @Binding var autoSubmit: Bool
    var enabled = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            option(
                title: "自动提交",
                detail: "抢到余票即提交订单",
                on: autoSubmit
            ) { autoSubmit = true }

            option(
                title: "仅监控",
                detail: "只查询不提交，可先观察",
                on: !autoSubmit
            ) { autoSubmit = false }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }

    private func option(
        title: String,
        detail: String,
        on: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.ui(16, .semibold))
                    .foregroundStyle(on ? Theme.accentText(scheme) : Theme.text(scheme))
                Text(detail)
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textSecondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.sm)
            .background(
                on ? Theme.brand.opacity(scheme == .dark ? 0.14 : 0.08) : Theme.chip(scheme),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        on ? Theme.brandEdge(scheme) : Theme.hairline(scheme),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

// MARK: - Numbers

/// Honours the spec's range and step, and refuses to write a value outside it, so
/// the form can never hand the validator something it will reject.
private struct NumericField: View {
    @EnvironmentObject private var model: AppModel
    let spec: FieldSpec

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            TextField("", value: valueBinding, format: format)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .fieldChrome(isFocused: isFocused, isInvalid: isInvalid)
                .frame(width: 110)
                .font(Theme.mono(.body))
            if !spec.suffix.isEmpty {
                Text(spec.suffix.trimmingCharacters(in: .whitespaces))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5), in: Capsule())
            }
            if spec.kind == .integer {
                NumberStepper(
                    onDecrement: { model.setInt(spec.key, max(intBinding.wrappedValue - step, intRange.lowerBound)) },
                    onIncrement: { model.setInt(spec.key, min(intBinding.wrappedValue + step, intRange.upperBound)) },
                    decrementEnabled: intBinding.wrappedValue > intRange.lowerBound,
                    incrementEnabled: intBinding.wrappedValue < intRange.upperBound
                )
            }
        }
    }

    private var isInvalid: Bool {
        model.visibleFieldError(spec.key) != nil
    }

    private var step: Int {
        max(1, Int(spec.step ?? 1))
    }

    private var format: FloatingPointFormatStyle<Double> {
        .number.precision(.fractionLength(spec.decimals))
    }

    private var doubleRange: ClosedRange<Double> {
        (spec.minimum ?? 0)...(spec.maximum ?? .greatestFiniteMagnitude)
    }

    private var intRange: ClosedRange<Int> {
        Int(spec.minimum ?? 0)...Int(spec.maximum ?? 1_000_000)
    }

    private var valueBinding: Binding<Double> {
        Binding(
            get: { model.double(spec.key) },
            set: { model.setDouble(spec.key, clamp($0)) }
        )
    }

    private var intBinding: Binding<Int> {
        Binding(
            get: { model.int(spec.key) },
            set: { model.setInt(spec.key, min(max($0, intRange.lowerBound), intRange.upperBound)) }
        )
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, doubleRange.lowerBound), doubleRange.upperBound)
    }
}
