import SwiftUI
import FairTicketKit

// MARK: - 本次乘车人

/// The passenger roster: one row per person, with a trailing empty row to add the next.
///
/// The design draws this as a list rather than a text field because the names are a
/// *list* — order matters to the engine, and a comma-separated field hides both the
/// order and how many slots are left.  Rows are minimal on purpose: a number, a name,
/// and the ticket type tucked to the right as an override, since the page's own title
/// promises "只填姓名，票种沿用记录".
///
/// The stored value is still the engine's single delimited string; this is a view over
/// it, not a second source of truth.
struct PassengerRosterEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focusedRow: PassengerRosterRow.ID?

    /// Rows shown, including one trailing empty row.  Held locally because the stored
    /// list cannot represent "a row the user has not typed in yet" — the empty row is
    /// the 新增乘车人 affordance.
    @State private var rows: [PassengerRosterRow] = [PassengerRosterRow()]
    @State private var loaded = false

    private var limit: Int { model.capabilities?.maxPassengers ?? 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                row(index, id: item.id)
            }

            if model.listItems("passenger_names").count >= limit {
                Text("已达 \(limit) 人上限")
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textTertiary(scheme))
                    .padding(.leading, 32)
            }

            // The engine's own count of the contacts the account holds, reported on the
            // `passengers` event once a run has looked.  Shown only when it has actually
            // arrived: before a run nothing knows the number, and a zero would read as
            // "the account is empty" rather than "not asked yet".
            if let available = model.availablePassengerCount {
                Text("当前 12306 账户内有 \(available) 位可用乘车人")
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textTertiary(scheme))
                    .padding(.leading, 32)
            }

            if let message = model.visibleFieldError("passenger_names") {
                FieldErrorNote(title: "乘车人", message: message)
            }
        }
        .onAppear(perform: loadIfNeeded)
        // Reload only when the list was changed by something other than this editor.
        // Comparing filtered rows to the stored names is what makes typing not reload
        // the field the user is in the middle of.
        .onChange(of: model.listItems("passenger_names")) { _, new in
            guard loaded else { return }
            let mine = rows.map { Self.trimmed($0.name) }.filter { !$0.isEmpty }
            if mine != new { load() }
        }
    }

    // MARK: Rows

    private func row(_ index: Int, id: PassengerRosterRow.ID) -> some View {
        let isAddRow = index == rows.count - 1 && rows[index].name.isEmpty
        return HStack(spacing: Theme.Space.sm) {
            // The design marks the first entry in brand orange and the rest in grey: the
            // roster is ordered, and the first name is the one the engine will try first.
            Text(index < rows.count ? "\(index + 1)" : "")
                .font(Theme.data(14, .semibold))
                .foregroundStyle(index == 0 ? Theme.onBrand : Theme.textSecondary(scheme))
                .frame(width: 22, height: 22)
                .background(
                    index == 0 ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Theme.chipHover(scheme)),
                    in: Circle()
                )
                .opacity(isAddRow ? 0 : 1)

            TextField(isAddRow ? "新增乘车人" : "姓名", text: binding(for: id))
                .textFieldStyle(.plain)
                .font(Theme.ui(15))
                .focused($focusedRow, equals: id)
                .onSubmit { appendRow() }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .fieldChrome(isFocused: focusedRow == id, supportsFocus: true)

            // The override lives at the trailing edge, unnamed and unbordered: the page
            // promises the type follows the 12306 record, so this is the exception to
            // that promise rather than the rule.
            if !isAddRow {
                ThemedMenu(
                    selection: ticketBinding(for: name(for: id)),
                    options: (model.capabilities?.ticketTypes ?? []).map {
                        ThemedMenuOption($0.value, $0.label)
                    },
                    font: Theme.ui(14),
                    maxWidth: 130
                )
                .help("学生票需要该联系人在 12306 已完成学生资质核验。")
            }
        }
    }

    // MARK: Binding

    private func name(for id: PassengerRosterRow.ID) -> String {
        guard let row = rows.first(where: { $0.id == id }) else { return "" }
        return Self.trimmed(row.name)
    }

    private func binding(for id: PassengerRosterRow.ID) -> Binding<String> {
        Binding(
            get: { rows.first(where: { $0.id == id })?.name ?? "" },
            set: { newValue in
                guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index].name = newValue
                // The trailing empty row is the add affordance, so typing into it means
                // the user wants another one after it.
                if index == rows.count - 1, !newValue.isEmpty, rows.count < limit + 1 {
                    rows.append(PassengerRosterRow())
                }
                commit()
            }
        )
    }

    private func ticketBinding(for passenger: String) -> Binding<String> {
        Binding(
            get: { model.ticketType(for: passenger) },
            set: { model.setTicketType($0, for: passenger) }
        )
    }

    // MARK: State

    private func loadIfNeeded() {
        guard !loaded else { return }
        load()
    }

    private func load() {
        let saved = model.listItems("passenger_names")
        rows = saved.isEmpty
            ? [PassengerRosterRow()]
            : saved.map { PassengerRosterRow(name: $0) } + [PassengerRosterRow()]
        loaded = true
    }

    private func appendRow() {
        guard rows.count < limit + 1 else { return }
        if rows.last?.name.isEmpty != true { rows.append(PassengerRosterRow()) }
        focusedRow = rows.last?.id
    }

    /// Write the non-empty rows back to the engine's single delimited string.
    private func commit() {
        model.setStringList(
            "passenger_names",
            rows.map { Self.trimmed($0.name) }.filter { !$0.isEmpty }
        )
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A row keeps its identity while names are edited or rows are appended.  The focus
/// state and SwiftUI's diffing both use this id rather than the row's current position.
private struct PassengerRosterRow: Identifiable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String = "") {
        self.id = id
        self.name = name
    }
}
