import SwiftUI
import AppKit
import FairTicketKit

/// Full log page: the only place the complete history is shown.
///
/// Laid out as the design's table — time, level, message — rather than as a list of
/// pill-plus-text rows.  Lines arrive already redacted from the engine's log pipeline,
/// so nothing here has to know about tokens, ID numbers or passenger names.
struct LogPageView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ui: UIState
    @Environment(\.colorScheme) private var scheme

    /// Held by the page rather than by `ThemedField` because the field here sits inside
    /// a row that also holds the magnifier and the clear button — the ring has to wrap
    /// all three, which is what makes the whole row read as one field.
    @FocusState private var searchFocused: Bool

    var body: some View {
        PageHeader(
            title: "运行日志",
            subtitle: ConfigSection.log.lead,
            eyebrow: "RUNTIME"
        )
        .padding(.bottom, Theme.Space.xs)

        filterBar
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.xs)
            .cardSurface(cornerRadius: Theme.Radius.row)

        table

        footer
    }

    // MARK: Filter

    private var filterBar: some View {
        HStack(spacing: Theme.Space.xs) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.textTertiary(scheme))
                TextField("筛选关键字，例如 排队 / 余票 / 校时", text: $ui.logFilter)
                    .textFieldStyle(.plain)
                    .font(Theme.ui(14))
                    .focused($searchFocused)
                if !ui.logFilter.isEmpty {
                    Button {
                        ui.logFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(Theme.ui(13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textTertiary(scheme))
                    .accessibilityLabel("清除筛选")
                }
            }
            .fieldChrome(isFocused: searchFocused, supportsFocus: true)
            .frame(maxWidth: 260)

            thresholdMenu

            Spacer(minLength: Theme.Space.xs)

            Button("复制") { copy(visible) }
                .buttonStyle(.chipAction(height: 28))
                .disabled(visible.isEmpty)
                .help("把当前筛选结果复制到剪贴板")

            Button("导出") { exportToFile() }
                .buttonStyle(.chipAction(height: 28))
                .disabled(visible.isEmpty)
                .help("把当前筛选结果保存为文本文件")

            Button("清空") { model.clearLog() }
                .buttonStyle(.chipAction(height: 28))
                .disabled(model.logEntries.isEmpty)
                .help("清空本次运行的全部日志")
        }
    }

    /// Which levels are on screen.
    ///
    /// A menu of thresholds rather than four checkboxes: the log is read by narrowing
    /// it — "just the warnings" — and never by selecting two non-adjacent levels.
    private var thresholdMenu: some View {
        Menu {
            Button("全部级别") { ui.logThreshold = nil }
            Divider()
            ForEach(thresholds, id: \.self) { level in
                Button(level.menuTitle) { ui.logThreshold = level }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(thresholdTint)
                    .frame(width: 6, height: 6)
                Text(ui.logThreshold.map(\.menuTitle) ?? "级别筛选")
                    .font(Theme.ui(14))
                Image(systemName: "chevron.down")
                    .font(Theme.ui(10, .semibold))
                    .foregroundStyle(Theme.textTertiary(scheme))
            }
            .foregroundStyle(Theme.textSecondary(scheme))
            .padding(.horizontal, Theme.Space.sm)
            .frame(height: 28)
            .background(Theme.chip(scheme), in: Capsule())
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// The levels the filter offers, taken from the engine's own declared set.
    ///
    /// `capabilities.log_levels` is the engine's statement of what it can emit.  A menu
    /// built from a hard-coded list silently drops whatever the engine adds later — an
    /// earlier version of this control offered four levels and left CRITICAL out, so a
    /// critical line could not be isolated at all.
    private var thresholds: [LogEntry.Level] {
        let declared = (model.capabilities?.logLevels ?? [])
            .compactMap { LogEntry.Level(rawValue: $0) }
        let levels = declared.isEmpty ? LogEntry.Level.fallbackThresholds : declared
        return levels.sorted { $0.rank < $1.rank }
    }

    private var thresholdTint: Color {
        guard let level = ui.logThreshold else { return Theme.textTertiary(scheme) }
        return color(for: level)
    }

    // MARK: Table

    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow

            if visible.isEmpty {
                ContentUnavailableView(
                    model.logEntries.isEmpty ? "尚无日志" : "没有匹配的日志",
                    systemImage: model.logEntries.isEmpty ? "text.alignleft" : "line.3.horizontal.decrease",
                    description: Text(
                        model.logEntries.isEmpty
                            ? "开始任务后会显示已脱敏的运行日志。"
                            : "换一个关键字，或放宽级别筛选。"
                    )
                )
                .frame(height: 220)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.divider(scheme))
                                .frame(height: 1)
                        }
                        row(entry)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardSurface()
        .overlay(alignment: .bottom) {
            if !visible.isEmpty { EmptyView() }
        }
    }

    /// Time and level share one column heading, as the design draws it.
    ///
    /// They are two fields but one idea — *when, and how loudly* — and the rows keep
    /// them in fixed columns so the values still line up.  Two headings over two very
    /// narrow columns spent more width on words than on the data beneath them.
    private var headerRow: some View {
        HStack(spacing: Theme.Space.sm) {
            Text("时间 · 级别")
                .frame(width: Self.timeWidth + Self.levelWidth + Theme.Space.sm, alignment: .leading)
            Text("内容")
            Spacer(minLength: 0)
        }
        .font(Theme.ui(14, .medium))
        .foregroundStyle(Theme.textTertiary(scheme))
        .padding(.horizontal, Theme.Layout.cardInset)
        .padding(.vertical, 11)
        .background(alignment: .bottom) {
            Rectangle().fill(Theme.divider(scheme)).frame(height: 1)
        }
    }

    private static let timeWidth: CGFloat = 78
    private static let levelWidth: CGFloat = 66

    private func row(_ entry: LogEntry) -> some View {
        let split = Self.split(entry)
        return HStack(alignment: .top, spacing: Theme.Space.sm) {
            Text(split.time ?? "--:--:--")
                .font(Theme.data(14))
                .foregroundStyle(Theme.textTertiary(scheme))
                .frame(width: Self.timeWidth, alignment: .leading)

            Text(String(entry.level.rawValue.prefix(4)).uppercased())
                .font(Theme.data(14, .medium))
                .foregroundStyle(color(for: entry.level))
                .frame(width: Self.levelWidth, alignment: .leading)

            Text(split.message)
                .font(Theme.ui(14))
                .foregroundStyle(entry.level == .debug ? Theme.textTertiary(scheme) : Theme.text(scheme))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Layout.cardInset)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            Button("复制这一行") { copy([entry]) }
            Button("复制全部（当前筛选）") { copy(visible) }
                .disabled(visible.isEmpty)
        }
    }

    /// The footer's own count, so the page never has to be scrolled to the bottom to
    /// know how much of it is on screen.
    private var footer: some View {
        Text(
            "共 \(model.logEntries.count) 行 · 引擎输出已脱敏 · "
                + (ui.logThreshold.map { "当前级别 \($0.menuTitle)" } ?? "显示全部级别")
                + " · 显示 \(visible.count) 行"
        )
        .font(Theme.ui(14))
        .foregroundStyle(Theme.textTertiary(scheme))
    }

    // MARK: Parsing

    /// The engine writes `HH:mm:ss  LEVEL  message` into one string.  The design shows
    /// three columns, so the time and the level are lifted out of the text here rather
    /// than by changing the engine's format — the log is also written to disk in that
    /// shape, and one reader does not get to redefine it.
    static func split(_ entry: LogEntry) -> (time: String?, message: String) {
        let characters = Array(entry.text)
        guard characters.count >= 8 else { return (nil, entry.text) }

        for start in 0...(characters.count - 8) {
            let window = characters[start..<(start + 8)]
            guard Self.looksLikeTime(window) else { continue }
            let time = String(window)
            var rest = String(characters[(start + 8)...]).trimmingCharacters(in: .whitespaces)
            // Drop the level word the engine repeats, since the table has a column for it.
            for token in [entry.level.rawValue, String(entry.level.rawValue.prefix(4))] {
                if rest.uppercased().hasPrefix(token) {
                    rest = String(rest.dropFirst(token.count)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            return (time, rest)
        }
        return (nil, entry.text)
    }

    private static func looksLikeTime(_ window: ArraySlice<Character>) -> Bool {
        let digits = window.enumerated().filter { $0.offset == 0 || $0.offset == 1 || $0.offset == 3
            || $0.offset == 4 || $0.offset == 6 || $0.offset == 7 }
        guard digits.allSatisfy({ $0.element.isNumber }) else { return false }
        let array = Array(window)
        return array[2] == ":" && array[5] == ":"
    }

    // MARK: Filtering

    private var visible: [LogEntry] {
        model.logEntries.filter { entry in
            if let threshold = ui.logThreshold, entry.level.rank < threshold.rank {
                return false
            }
            guard !ui.logFilter.isEmpty else { return true }
            return entry.text.localizedCaseInsensitiveContains(ui.logFilter)
        }
    }

    private func color(for level: LogEntry.Level) -> Color {
        switch level {
        case .error, .critical: return Theme.danger(scheme)
        case .warning: return Theme.accentText(scheme)
        case .debug: return Theme.textTertiary(scheme)
        case .info: return Theme.text(scheme)
        }
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "fairticket-log.txt"
        panel.message = "导出已脱敏日志"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = visible.map { "\($0.level.rawValue)  \($0.text)" }.joined(separator: "\n")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// One place builds the line format, so "copy this line" and "copy all" cannot
    /// disagree about what a line looks like on the pasteboard.
    private func copy(_ entries: [LogEntry]) {
        let text = entries.map { "\($0.level.rawValue)  \($0.text)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension LogEntry.Level {
    /// Used only before the engine's own list has arrived.
    ///
    /// The live menu reads `capabilities.log_levels`; this is what the page shows in the
    /// frame between the window opening and the handshake landing, so the control is
    /// never empty.
    static var fallbackThresholds: [LogEntry.Level] {
        [.debug, .info, .warning, .error, .critical]
    }

    /// How loud this level is, for range comparisons.
    var rank: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        case .critical: return 4
        }
    }

    var menuTitle: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }
}
