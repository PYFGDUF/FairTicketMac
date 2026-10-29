import SwiftUI

/// Calendar arithmetic stays independent of the controls so month boundaries,
/// leap years and keyboard navigation share one local Gregorian calendar.
struct TicketCalendarMonth {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "zh_CN")
        value.firstWeekday = 2
        return value
    }

    let start: Date

    init(containing date: Date) {
        start = Self.calendar.dateInterval(of: .month, for: date)?.start
            ?? Self.calendar.startOfDay(for: date)
    }

    var days: [Date] {
        let calendar = Self.calendar
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: start) }
    }

    func contains(_ day: Date) -> Bool {
        Self.calendar.isDate(day, equalTo: start, toGranularity: .month)
    }

    static func move(_ day: Date, by value: Int, component: Calendar.Component) -> Date {
        calendar.date(byAdding: component, value: value, to: day) ?? day
    }
}

/// A roomy popover matching the form's typography, surfaces and brand selection.
struct TicketCalendar: View {
    @Binding private var date: Date
    let onClose: () -> Void

    @Environment(\.colorScheme) private var scheme
    // Seeded on presentation, so reopening starts at the currently selected day.
    @State private var displayedMonth: Date
    @State private var keyboardDay: Date
    @State private var hoveredDay: Date?
    @FocusState private var gridFocused: Bool

    init(date: Binding<Date>, onClose: @escaping () -> Void) {
        self._date = date
        self.onClose = onClose
        self._displayedMonth = State(initialValue: TicketCalendarMonth(containing: date.wrappedValue).start)
        self._keyboardDay = State(initialValue: TicketCalendarMonth.calendar.startOfDay(for: date.wrappedValue))
    }

    private var month: TicketCalendarMonth { TicketCalendarMonth(containing: displayedMonth) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            header
            Rectangle().fill(Theme.divider(scheme)).frame(height: 1)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { title in
                    Text(title)
                        .font(Theme.ui(13, .medium))
                        .foregroundStyle(Theme.textSecondary(scheme))
                        .frame(height: 28)
                }
                ForEach(month.days, id: \.self) { day in dayButton(day) }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($gridFocused)
            Rectangle().fill(Theme.divider(scheme)).frame(height: 1)
            footer
        }
        .padding(Theme.Space.md)
        .frame(width: 336)
        .background(Theme.card(scheme))
        .onAppear { gridFocused = true }
        .onKeyPress(.leftArrow) { moveFocus(-1); return .handled }
        .onKeyPress(.rightArrow) { moveFocus(1); return .handled }
        .onKeyPress(.upArrow) { moveFocus(-7); return .handled }
        .onKeyPress(.downArrow) { moveFocus(7); return .handled }
        .onKeyPress(.return) { select(keyboardDay); return .handled }
        .onKeyPress(.space) { select(keyboardDay); return .handled }
        .onExitCommand(perform: onClose)
        .accessibilityLabel("选择乘车日期")
    }

    private var header: some View {
        HStack {
            monthButton("chevron.left", label: "上个月", delta: -1)
            Spacer(minLength: 0)
            let calendar = TicketCalendarMonth.calendar
            Text("\(String(calendar.component(.year, from: displayedMonth)))年\(calendar.component(.month, from: displayedMonth))月")
                .font(Theme.ui(17, .semibold))
                .foregroundStyle(Theme.textStrong(scheme))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            monthButton("chevron.right", label: "下个月", delta: 1)
        }
    }

    private func monthButton(_ symbol: String, label: String, delta: Int) -> some View {
        Button {
            keyboardDay = TicketCalendarMonth.move(keyboardDay, by: delta, component: .month)
            displayedMonth = TicketCalendarMonth(containing: keyboardDay).start
        } label: {
            Image(systemName: symbol)
                .font(Theme.ui(14, .semibold))
                .frame(width: 32, height: 32)
                .background(Theme.chip(scheme), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.pressable)
        .foregroundStyle(Theme.text(scheme))
        .accessibilityLabel(label)
        .help(label)
    }

    private func dayButton(_ day: Date) -> some View {
        let calendar = TicketCalendarMonth.calendar
        let selected = calendar.isDate(day, inSameDayAs: date)
        let today = calendar.isDateInToday(day)
        let focused = gridFocused && calendar.isDate(day, inSameDayAs: keyboardDay)
        return Button { select(day) } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(Theme.data(15, selected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .foregroundStyle(selected ? Theme.onBrand : (month.contains(day) ? Theme.textStrong(scheme) : Theme.textTertiary(scheme)))
                .background(
                    selected ? Theme.brand : (today ? Theme.brandWash(scheme) : (hoveredDay == day ? Theme.chip(scheme) : Color.clear)),
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(focused || today ? Theme.accentText(scheme) : Color.clear, lineWidth: focused ? 2 : 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .focusable(false)
        .onHover { hoveredDay = $0 ? day : nil }
        .accessibilityLabel(day.formatted(.dateTime.year().month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))))
        .accessibilityValue(today ? "今天" : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.xs) {
            Text("已选 \(ISO8601Day.string(from: date))")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.textSecondary(scheme))
            Spacer(minLength: 0)
            Button("今天") { select(Date()) }
                .buttonStyle(.chipAction(height: 30))
        }
    }

    private func moveFocus(_ days: Int) {
        keyboardDay = TicketCalendarMonth.move(keyboardDay, by: days, component: .day)
        displayedMonth = TicketCalendarMonth(containing: keyboardDay).start
        gridFocused = true
    }

    private func select(_ day: Date) {
        date = TicketCalendarMonth.calendar.startOfDay(for: day)
        onClose()
    }
}
