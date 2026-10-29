import SwiftUI

/// Lets the menu bar reach the window's presentation state.
///
/// Section switching belongs in the View menu as well as the sidebar: on desktop a
/// navigation action should be reachable from the keyboard, and a menu item is how
/// macOS exposes that.
private struct UIStateFocusedKey: FocusedValueKey {
    typealias Value = UIState
}

extension FocusedValues {
    var uiState: UIState? {
        get { self[UIStateFocusedKey.self] }
        set { self[UIStateFocusedKey.self] = newValue }
    }
}

/// The View menu's section list, with ⌘1…⌘6 in sidebar order.
public struct SectionCommands: View {
    @FocusedValue(\.uiState) private var ui

    public init() {}

    public var body: some View {
        ForEach(Array(ConfigSection.allCases.enumerated()), id: \.element) { index, section in
            Button(section.title) {
                ui?.selectedSection = section
            }
            .keyboardShortcut(
                KeyEquivalent(Character("\(index + 1)")),
                modifiers: .command
            )
            .disabled(ui == nil)
        }

        Divider()

        // The window's only log-strip control hides it, so without this the tail could
        // be dismissed and never brought back.  A checkmark menu item is how macOS
        // spells "show this piece of chrome".
        Toggle("显示日志条", isOn: Binding(
            get: { ui?.showsLogStrip ?? false },
            set: { ui?.showsLogStrip = $0 }
        ))
        .keyboardShortcut("l", modifiers: [.command, .option])
        .disabled(ui == nil)
    }
}