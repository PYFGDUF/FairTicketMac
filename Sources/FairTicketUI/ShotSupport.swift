import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import FairTicketKit

/// Off-screen rendering of the window, for reviewing layout without a display.
///
/// The window capture in `script/preview.sh` is the right tool when there is a screen
/// to capture, but it needs a window id and the Screen Recording permission — neither
/// of which exists on a headless or sandboxed machine, and both of which turn "look at
/// the page" into a permission dialog.
///
/// This draws the same `ContentView` through `ImageRenderer` at an exact point size.
/// It is the loop the design document asks for: change a view, render the page,
/// compare it against the plate, repeat.
///
/// The strings the caller passes are parsed against the same enums the app uses, so a
/// typo fails loudly here rather than silently rendering the default state — which is
/// the failure mode that made the old screenshot path show the wrong page.
@MainActor
@discardableResult
public func renderShot(
    out: String,
    section: String? = nil,
    demo: String? = nil,
    outcome: String? = nil,
    appearance: String = "dark",
    textSize: String = "medium",
    width: Double = 1440,
    height: Double = 900,
    scale: Double = 2,
    seedLog: Bool = true,
    showsLogStrip: Bool = false,
    expandAdvanced: Bool = false,
    offline: Bool = false,
    confirm: Bool = false,
    about: Bool = false,
    calendar: Bool = false,
    settings: Bool = false,
    draft: Bool = false,
    manager: Bool = false,
    dismissed: Bool = false
) -> String {
    // The renderer builds views outside the app's own launch path, so the bundled faces
    // have to be registered here too — otherwise every capture would silently come back
    // in the system font and the review would be of a different interface.
    AppFonts.register()

    let scheme: ColorScheme = appearance.lowercased() == "light" ? .light : .dark
    guard let sizePreference = TicketTextSize(rawValue: textSize) else {
        return "error: 未知字号，可选 small、medium、large"
    }

    if settings {
        let panel = TextSizeSettingsContent(selection: .constant(sizePreference))
            .environment(\.ticketTextSize, sizePreference)
            .environment(\.colorScheme, scheme)
        let size = NSHostingView(rootView: panel).fittingSize
        guard let image = rasterize(panel, size: size, dark: scheme == .dark) else {
            return "error: 设置光栅化失败"
        }
        return write(image, to: out)
    }

    if calendar {
        let selected = ISO8601Day.date(from: "2026-11-06") ?? Date()
        let panel = TicketCalendar(date: .constant(selected), onClose: {})
            .environment(\.ticketTextSize, sizePreference)
            .environment(\.colorScheme, scheme)
        let size = NSHostingView(rootView: panel).fittingSize
        guard let image = rasterize(panel, size: size, dark: scheme == .dark) else {
            return "error: 日历光栅化失败"
        }
        return write(image, to: out)
    }

    // The About panel is its own scene with its own fixed width and a height that its
    // copy decides, so it is measured rather than forced into a window-shaped frame —
    // forcing one left a strip of the host window's own background above and below it.
    if about {
        let panel = AboutView(version: FairTicketVersion(short: "2.1.0", build: "1"))
            .environment(\.ticketTextSize, sizePreference)
            .environment(\.colorScheme, scheme)
            .frame(width: width == 1440 ? 460 : width)
        let size = NSHostingView(rootView: panel).fittingSize
        guard let image = rasterize(panel, size: size, dark: scheme == .dark) else {
            return "error: 光栅化失败"
        }
        return write(image, to: out)
    }

    let scenario: DemoScenario?
    if let demo {
        guard let parsed = DemoScenario(rawValue: demo.lowercased()) else {
            return "error: 未知 demo 「\(demo)」，可选：\(DemoScenario.allNames)"
        }
        scenario = parsed
    } else {
        scenario = nil
    }

    let sectionValue: ConfigSection?
    if let section {
        guard let parsed = ConfigSection(rawValue: section) else {
            return "error: 未知 section 「\(section)」，可选：\(ConfigSection.allNames)"
        }
        sectionValue = parsed
    } else {
        sectionValue = nil
    }

    let model = AppModel.preview(scenario: scenario, engineReady: !offline)
    if seedLog { model.seedPreviewLog() }
    if let outcome { model.apply(outcomeEvent(outcome)) }
    if confirm { model.presentStartSummaryForPreview() }

    let ui = UIState.preview(section: sectionValue ?? .cart, inspector: true)
    if expandAdvanced, let specs = model.capabilities?.fieldSpecs {
        ui.expandedAdvancedGroups = Set(specs.map(\.group))
    }
    // The composer only exists once it is opened, so a capture of it needs the flag too.
    // Filled with the design's own example values: an empty composer cannot show the
    // expansion rule, and the expansion rule is the reason the page exists.
    if draft {
        ui.showsCartDraft = true
        model.cartDraft.fromStation = "北京南"
        model.cartDraft.toStation = "上海虹桥"
        model.cartDraft.trainScope = CartItem.scopeSpecific
        model.cartDraft.trainCode = "G101，G105"
        model.cartDraft.seatTypes = ["二等座", "硬卧"]
    }
    if manager {
        ui.showsCartManager = true
    }
    // The window *after* a run has been reported and its panel closed: `runState` still
    // holds the outcome, and that is the state a returning user presses 开始任务 or
    // 管理购物车 in.  Set here because nothing can click the close button in a headless
    // render — and it is exactly the state in which those two panels went unreachable.
    if dismissed {
        model.acknowledgeOutcome()
    }
    ui.showsLogStrip = showsLogStrip
    // Apply the requested viewport before hosting; otherwise the initial three-column
    // intrinsic size can grow an offscreen test window beyond its requested width.
    ui.adaptInspectorToWindowWidth(width)

    let content = ContentView()
        .environment(\.ticketTextSize, sizePreference)
        .environmentObject(model)
        .environmentObject(ui)
        .environment(\.colorScheme, scheme)
        .frame(width: width, height: height)

    guard let image = rasterize(content, size: CGSize(width: width, height: height), dark: scheme == .dark) else {
        return "error: 光栅化失败（视图依赖了窗口？）"
    }
    return write(image, to: out)
}

/// Encodes one bitmap as a PNG and reports what landed on disk.
private func write(_ image: CGImage, to out: String) -> String {
    guard
        let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: out) as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        return "error: 无法在 \(out) 创建 PNG，检查目录是否存在"
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        return "error: 写 PNG 失败：\(out)"
    }
    return "shot: \(out) (\(image.width)x\(image.height))"
}

/// Draws a SwiftUI view through AppKit's own layout, off screen.
///
/// `ImageRenderer` is the obvious tool and was the first one tried, but it lays the
/// view out without a host: a `ScrollView` inside it renders as an empty rectangle,
/// which looked exactly like a broken page.  The window's three panes are all scroll
/// views, so every capture came back blank.
///
/// Hosting the view in a real (borderless, off-screen) window gives it the layout pass
/// a scroll view needs, and `cacheDisplay` reads back the composited result.  The
/// window is placed far off the visible frame and never ordered in front of anything,
/// so nothing appears over the desktop the review is happening on.
@MainActor
private func rasterize<V: View>(_ view: V, size: CGSize, dark: Bool) -> CGImage? {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = CGRect(origin: .zero, size: size)

    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = hosting
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    // Force sRGB.  Left alone, the window inherits the display's profile (Display P3 on
    // any modern Mac), and the brand orange exports as `#EE8238` — the same colour, a
    // different number.  Captures are compared against a design document written in
    // sRGB, so the numbers have to be comparable, not merely equivalent.
    window.colorSpace = .sRGB
    // The window's own background shows through wherever the view does not fill the
    // frame — the corners of a rounded panel, mostly — so it is set to the app's canvas
    // rather than left at AppKit's default white.
    window.backgroundColor = NSColor(dark ? Theme.canvas(.dark) : Theme.canvas(.light))
    window.isReleasedWhenClosed = false
    window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
    window.orderFrontRegardless()

    // Two passes: the first gives the scroll views their content, the second settles
    // the constraint-driven layout that the first one changed.
    hosting.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    hosting.layoutSubtreeIfNeeded()

    defer { window.orderOut(nil) }

    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    return rep.cgImage
}

/// Renders a trivial view, to tell "the renderer is broken here" apart from
/// "this particular view is broken here".
///
/// `ImageRenderer` answers an unsupported view with the system's yellow "no entry"
/// plate rather than an error, so a failed render and an unsupported one look the
/// same.  Proving the pipeline with a view that cannot fail is what separates them.
@MainActor
public func renderProbe(out: String, width: Double = 400, height: Double = 200) -> String {
    let probe = VStack(alignment: .leading, spacing: 8) {
        Text("FairTicket").font(.title.weight(.semibold))
        Text("离屏渲染探针").font(.body)
        RoundedRectangle(cornerRadius: 10).fill(Theme.brand).frame(height: 40)
    }
    .padding(24)
    .frame(width: width, height: height, alignment: .topLeading)
    .background(Theme.panel(.dark))

    let renderer = ImageRenderer(content: probe)
    renderer.scale = 2
    renderer.proposedSize = ProposedViewSize(width: width, height: height)

    guard let image = renderer.cgImage else { return "error: 探针也渲染失败" }
    guard
        let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: out) as CFURL,
            UTType.png.identifier as CFString, 1, nil
        )
    else { return "error: 无法创建 \(out)" }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return "error: 写 PNG 失败" }
    return "probe: \(out) (\(image.width)x\(image.height))"
}

/// A finished run, without winning a ticket.
///
/// The panel's end state is the app's rarest screen — the only way to see it for real
/// is to win a ticket — so the review path replays the engine's own terminal event
/// instead.  Mirrors `ReviewHooks.outcomeEvent`.
private func outcomeEvent(_ raw: String) -> RuntimeEvent {
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

extension ConfigSection {
    /// For the error message, so a mistyped flag names the alternatives.
    static var allNames: String {
        allCases.map(\.rawValue).joined(separator: " | ")
    }
}

extension DemoScenario {
    static var allNames: String {
        ["running", "imminent", "queueing", "safestop", "login"].joined(separator: " | ")
    }
}
