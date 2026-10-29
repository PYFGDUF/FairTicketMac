import AppKit
import Foundation
import FairTicketUI

/// Command-line shell around `renderShot`.
///
///     swift run UIShot --out /tmp/cart.png --section cart
///     swift run UIShot --out /tmp/run.png --demo running
///     swift run UIShot --out /tmp/light.png --appearance light
///
/// See `renderShot` for the full flag list.  The rendering itself lives in the UI
/// library so it can reuse the app's own enums and view model; this file only parses.

var options: [String: String] = [:]
var flags: Set<String> = []
var index = 1
let arguments = CommandLine.arguments

while index < arguments.count {
    let argument = arguments[index]
    guard argument.hasPrefix("--") else {
        FileHandle.standardError.write(Data("error: 无法识别的参数 \(argument)\n".utf8))
        exit(2)
    }
    let name = String(argument.dropFirst(2))
    // Value-less flags, so `--expand` does not swallow the next flag.
    if ["no-log", "log-strip", "expand", "offline", "probe", "confirm", "about", "calendar", "settings", "draft", "manager", "dismissed"].contains(name) {
        flags.insert(name)
        index += 1
        continue
    }
    guard index + 1 < arguments.count else {
        FileHandle.standardError.write(Data("error: \(argument) 缺少取值\n".utf8))
        exit(2)
    }
    options[name] = arguments[index + 1]
    index += 2
}

guard let out = options["out"] else {
    FileHandle.standardError.write(Data("error: 需要 --out <path>\n".utf8))
    exit(2)
}

// `ImageRenderer` needs an initialised NSApplication even though nothing is shown;
// `.prohibited` keeps a Dock icon from appearing for a process that only draws.
_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.prohibited)

// Hopping onto the main actor explicitly rather than using `assumeIsolated`: in
// language mode 5 the top-level code of `main.swift` is not guaranteed to be
// main-actor isolated, and assuming it were would trap at runtime.
Task { @MainActor in
    // `--probe` draws a view that cannot fail, to tell a broken renderer apart from a
    // view the renderer does not support.
    if flags.contains("probe") {
        let probe = renderProbe(out: out)
        print(probe)
        exit(probe.hasPrefix("error") ? 1 : 0)
    }

    let result = renderShot(
        out: out,
        section: options["section"],
        demo: options["demo"],
        outcome: options["outcome"],
        appearance: options["appearance"] ?? "dark",
        textSize: options["text-size"] ?? "medium",
        width: Double(options["width"] ?? "") ?? 1440,
        height: Double(options["height"] ?? "") ?? 900,
        scale: Double(options["scale"] ?? "") ?? 2,
        seedLog: !flags.contains("no-log"),
        showsLogStrip: flags.contains("log-strip"),
        expandAdvanced: flags.contains("expand"),
        offline: flags.contains("offline"),
        confirm: flags.contains("confirm"),
        about: flags.contains("about"),
        calendar: flags.contains("calendar"),
        settings: flags.contains("settings"),
        draft: flags.contains("draft"),
        manager: flags.contains("manager"),
        dismissed: flags.contains("dismissed")
    )

    if result.hasPrefix("error") {
        FileHandle.standardError.write(Data((result + "\n").utf8))
        exit(1)
    }
    print(result)
    // A missing face changes the typeface and nothing else, so a screenshot cannot
    // show it.  State it instead.
    print(AppFonts.report)
    exit(0)
}

dispatchMain()
