import AppKit
import Foundation
import FairTicketKit

#if DEBUG

/// Development-only switches, read from the environment by `script/preview.sh`.
///
/// Reviewing a page used to mean editing the app: selecting a sidebar section, expanding
/// the advanced groups, or faking a finished run each needed a temporary patch that then
/// had to be found and removed again — and forgetting one would have shipped a
/// screenshot-only behaviour.
///
/// Everything here is inside `#if DEBUG`, so it is absent from a release build, and it
/// does nothing at all unless the matching variable is set.  The appearance override is
/// the one that matters most to anyone sharing the machine: it changes *this process's*
/// appearance rather than the system's, so a dark-mode capture never flips the desktop
/// the user is working in.
public enum ReviewHooks {

    // MARK: Appearance

    /// Forces this app's own appearance, never the system's.
    ///
    /// `NSApplication.appearance` is the narrowest scope AppKit offers: it applies to
    /// this process's windows and leaves every other app — and the user's desktop —
    /// untouched.  A launch argument (`--args -AppleInterfaceStyle Dark`) does *not*
    /// work here: AppKit resolves its appearance from the system preference rather than
    /// from the argument domain of `UserDefaults`.
    public static func applyAppearance(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        switch environment["FAIRTICKET_APPEARANCE"]?.lowercased() {
        case "dark":
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case "light":
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        default:
            break
        }
    }

    // MARK: Window state

    /// Applies the state the reviewer asked for.
    ///
    /// Called once the engine handshake has landed, because every one of these depends
    /// on the capabilities payload: the section list, the advanced groups and the field
    /// specs all come from the backend.
    @MainActor
    public static func apply(
        model: AppModel,
        ui: UIState,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        if let raw = environment["FAIRTICKET_SECTION"], let section = ConfigSection(rawValue: raw) {
            ui.selectedSection = section
        }

        // The advanced page is collapsed by default — fifteen fields that all have safe
        // defaults should not read as a page that must be worked through — which also
        // makes it the one page a screenshot cannot reach without help.
        if environment["FAIRTICKET_EXPAND"] != nil,
           let specs = model.capabilities?.fieldSpecs {
            ui.expandedAdvancedGroups = Set(specs.map(\.group))
        }

        if let raw = environment["FAIRTICKET_OUTCOME"] {
            model.apply(outcomeEvent(for: raw))
        }

        markReady()
        dumpMenuIfAsked(environment: environment)
    }

    /// Writes the app's menu bar to a file.
    ///
    /// The menu bar is the one surface a screenshot cannot show without bringing the app
    /// to the front — exactly what this workflow exists to avoid.  Dumping the tree
    /// instead verifies HIG 1.1 (which menus exist), 1.2 (every action has a key
    /// equivalent) and the shape of the app-specific menu, from the running app.
    private static func dumpMenuIfAsked(environment: [String: String]) {
        guard environment["FAIRTICKET_DUMP_MENU"] != nil else { return }
        var lines: [String] = []

        func symbol(_ mask: NSEvent.ModifierFlags) -> String {
            var out = ""
            if mask.contains(.control) { out += "^" }
            if mask.contains(.option) { out += "⌥" }
            if mask.contains(.shift) { out += "⇧" }
            if mask.contains(.command) { out += "⌘" }
            return out
        }

        /// Return, Escape and friends arrive as control characters; the dump is read by a
        /// human, so they are spelled the way the menu bar spells them.
        func keyName(_ raw: String) -> String {
            switch raw {
            case "\r": return "↩"
            case "\u{3}": return "⌤"
            case "\u{1b}": return "⎋"
            case "\t": return "⇥"
            case " ": return "Space"
            case "\u{8}", "\u{7f}": return "⌫"
            default: return raw
            }
        }

        func walk(_ menu: NSMenu, depth: Int) {
            let indent = String(repeating: "  ", count: depth)
            lines.append("\(indent)\(menu.title)")
            for item in menu.items {
                if item.isSeparatorItem {
                    lines.append("\(indent)  ---")
                    continue
                }
                if let submenu = item.submenu {
                    lines.append("\(indent)  \(item.title) ▸")
                    walk(submenu, depth: depth + 2)
                    continue
                }
                let key = item.keyEquivalent.isEmpty
                    ? ""
                    : "  [\(symbol(item.keyEquivalentModifierMask))\(keyName(item.keyEquivalent))]"
                lines.append("\(indent)  \(item.title)\(key)")
            }
        }

        let main = NSApplication.shared.mainMenu
        main?.update()
        if let main { walk(main, depth: 0) }

        let path = "/tmp/fairticket-menu-\(ProcessInfo.processInfo.processIdentifier).txt"
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Touched once the window is not merely up but *ready*.
    ///
    /// A fresh instance draws its first frame before the engine handshake lands, so a
    /// capture taken as soon as a window exists shows an empty form and the default
    /// section — which is exactly what the first version of this workflow produced,
    /// silently.  The script waits for this file instead of guessing a sleep length, so a
    /// capture is never a race between the window appearing and the engine answering.
    ///
    /// The path carries the pid, so two instances cannot answer for each other.
    private static func markReady() {
        let path = "/tmp/fairticket-review-ready-\(ProcessInfo.processInfo.processIdentifier)"
        try? Data().write(to: URL(fileURLWithPath: path))
    }

    /// A finished run, without waiting for one.
    ///
    /// The panel's end state is the app's rarest screen, and the only way to see it for
    /// real is to win a ticket; this replays the engine's own terminal event instead, so
    /// the state under review is the state the reducer produces.
    private static func outcomeEvent(for raw: String) -> RuntimeEvent {
        switch raw {
        case "success":
            return RuntimeEvent.terminated(exitCode: 0)
        case "safestop":
            return RuntimeEvent(
                rawKind: "exit",
                message: "出票状态暂时无法确认，任务已停止以避免重复下单；请到 12306 官方订单页核对",
                data: ["exit_code": .number(1), "safe_stop": .bool(true)]
            )
        case "stopped":
            return RuntimeEvent.terminated(exitCode: 130)
        default:
            return RuntimeEvent.terminated(exitCode: 2)
        }
    }
}

#endif
