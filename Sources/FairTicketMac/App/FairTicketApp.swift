import SwiftUI
import FairTicketKit
import FairTicketUI

/// The app is deliberately thin: it owns the two state objects and declares the
/// scenes.  Everything the window and the menu bar draw lives in `FairTicketUI`, so
/// that the interface can be previewed in Xcode — SwiftUI Previews do not run inside
/// an executable target.
@main
struct FairTicketApp: App {
    init() {
        // Before any view is built: `Font.custom` resolves a family against what the
        // process has registered, and an unregistered face silently falls back to the
        // system one — so this cannot be deferred to `.task`.
        AppFonts.register()

        #if DEBUG
        // Development-only: lets `script/preview.sh --dark` capture this instance in
        // dark mode without changing the appearance of the machine it runs on.
        ReviewHooks.applyAppearance()
        #endif
    }

    /// Owned by the App, not by `ContentView`, because the menu bar drives the same
    /// engine: a second model would mean a second child process, a second login and
    /// two countdowns that disagree.
    @StateObject private var model = AppModel()
    @StateObject private var ui = UIState()

    var body: some Scene {
        WindowGroup(id: FairTicketWindow.mainID) {
            ContentView()
                .ticketTextPreferences()
                .environmentObject(model)
                .environmentObject(ui)
                .frame(
                    minWidth: FairTicketWindow.minimumSize.width,
                    minHeight: FairTicketWindow.minimumSize.height
                )
        }
        .defaultSize(width: 1420, height: 880)
        .windowToolbarStyle(.unified)
        .commands {
            // HIG 1.1: File, an app-specific menu, and Help.  The window has no
            // document, so the File menu carries the settings exchange instead of a
            // dead New Item entry — and ⌘O / ⇧⌘S finally mean something.
            CommandGroup(replacing: .newItem) {
                FileCommands()
            }
            // A non-document app leaves SwiftUI's document groups empty, and an empty
            // group still draws its separator.  Replacing `.importExport` removes one of
            // the two rules that followed 打开 12306 订单.  `.saveItem` is deliberately
            // left alone: replacing it also takes 关闭/全部关闭 out of the File menu,
            // which costs ⌘W — a far worse trade than a stray hairline.
            CommandGroup(replacing: .importExport) {}
            CommandMenu("任务") {
                TaskCommands()
            }
            // The stock About panel shows the bundle's name and version and nothing
            // else, and the address of the project is what this app's users look for.
            CommandGroup(replacing: .appInfo) {
                AboutCommand()
            }
            CommandGroup(after: .toolbar) {
                SectionCommands()
            }
            CommandGroup(replacing: .help) {
                HelpCommands()
            }
        }

        // A `Window` rather than a `WindowGroup`: the About panel is one panel, and a
        // second copy would only be a second set of numbers to keep in step.
        Window("关于 \(FairTicketProject.name)", id: FairTicketWindow.aboutID) {
            AboutView()
                .ticketTextPreferences()
        }
        .windowResizability(.contentSize)
        // The view draws its own hero band, so a title bar would be a second header.
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)

        Settings {
            AppSettingsView()
                .ticketTextPreferences()
        }
        .windowResizability(.contentSize)

        // The tray icon on Windows is inert; a resident countdown is the reason
        // this exists here, so it carries the time and the two controls worth
        // reaching when the window is behind something else.
        MenuBarExtra {
            MenuBarMenu()
                .ticketTextPreferences()
                .environmentObject(model)
                .environmentObject(ui)
        } label: {
            MenuBarLabel(model: model)
                .ticketTextPreferences()
        }
    }
}
