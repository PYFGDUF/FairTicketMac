// swift-tools-version: 6.2
import PackageDescription

// Three targets, so the transport layer can be exercised without a window and the
// interface can be previewed without an engine:
//
//   FairTicketKit   models + sidecar client, no SwiftUI
//   FairTicketUI    theme, view model and views (a library, so Xcode can run
//                   SwiftUI Previews on it — previews do not work inside an
//                   executable target)
//   FairTicketMac   the app: scenes, window, menu bar item — nothing else
//   SidecarProbe    a CLI that runs the handshake, mirroring the Python
//                   project's existing --smoke-test convention
//
// The app has no third-party dependencies: it drives the existing Python engine
// as a child process over a JSON-Lines pipe, so everything here is system
// frameworks only.
//
// Language mode stays on v5 while the app is brought up.  The code is written
// with explicit isolation anyway, so moving to v6 later is a small change rather
// than a rewrite.
let package = Package(
    name: "FairTicketMac",
    // macOS 26 for Liquid Glass: the toolbar, the hero countdown and the floating
    // log strip use `glassEffect`, which is the current Apple surface language and
    // is what keeps the app looking native next to Finder rather than dated.
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "FairTicketKit",
            path: "Sources/FairTicketKit"
        ),
        .target(
            name: "FairTicketUI",
            dependencies: ["FairTicketKit"],
            path: "Sources/FairTicketUI",
            resources: [
                .copy("Resources/capabilities.json"),
                .copy("Resources/login-qr.json"),
                // The app icon again, inside the module: the About panel has to show it in
                // the off-screen renderer and in Previews too, and neither of those has
                // the .app bundle to read it from.
                .copy("Resources/AppIcon.icns"),
                // The two families the design document names.  Copied as a directory so
                // the faces keep their names, which is what `AppFonts.register` looks
                // them up by.
                .copy("Resources/Fonts"),
            ]
        ),
        .executableTarget(
            name: "FairTicketMac",
            dependencies: ["FairTicketKit", "FairTicketUI"],
            path: "Sources/FairTicketMac"
        ),
        .executableTarget(
            name: "SidecarProbe",
            dependencies: ["FairTicketKit"],
            path: "Sources/SidecarProbe"
        ),
        // Renders the window off-screen, straight to PNG.
        //
        // The screenshot workflow in `script/preview.sh` needs a window, a window id
        // and the Screen Recording permission; none of those exist on a headless or
        // sandboxed machine, which is where the layout is most often reviewed.  This
        // target draws the same views through `ImageRenderer` at a fixed size, so a
        // page can be compared against the design document without a display.
        .executableTarget(
            name: "UIShot",
            dependencies: ["FairTicketKit", "FairTicketUI"],
            path: "Sources/UIShot"
        ),
        // Assertions on the view model instead of screenshots: `swift test` renders
        // nothing, needs no engine and no window, and catches exactly the class of
        // bug that a screenshot only catches by luck (a code that flashes and
        // vanishes, a countdown that drifts, a state that clears itself).
        .testTarget(
            name: "FairTicketUITests",
            dependencies: ["FairTicketUI"],
            path: "Tests/FairTicketUITests"
        ),
    ],
    swiftLanguageModes: [.v5]
)