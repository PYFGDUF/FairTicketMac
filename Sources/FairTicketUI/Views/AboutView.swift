import AppKit
import SwiftUI

/// What the app says about itself.
///
/// Kept as data rather than baked into the view: the project address is the one string
/// a user opens this window to copy, and an address that is only ever typed inside a
/// view is an address that can silently rot.  `AboutTests` asserts it.
public enum FairTicketProject {
    /// `CFBundleName` in the shipped bundle.
    public static let name = "12306 Fair Ticket"

    /// The project's own one-line description, taken from the repository README so the
    /// About panel and the download page do not drift apart.
    public static let tagline = "多车站、车次、席别放进同一个购物车，按顺序尝试购票"

    /// The GitHub project — the same repository the Windows release is published from.
    public static let repositoryDisplayName = "Tuan-Space/12306FairTicket"
    public static let repositoryAddress = "https://github.com/Tuan-Space/12306FairTicket"

    /// Documentation, issues and the railway itself.
    ///
    /// The two document paths end in Chinese file names, so they are percent-encoded
    /// rather than written out: a hand-typed escape sequence is a link that works in the
    /// author's browser and 404s in everyone else's.
    public static var documentationURL: URL { repositoryFile("docs/四步订票流程操作说明.md") }
    public static var principleURL: URL { repositoryFile("docs/抢票原理说明.md") }
    public static var issuesURL: URL { repositoryURL.appending(path: "issues/new") }
    public static let railwayURL = URL(string: "https://www.12306.cn")!

    /// The engine's own order page — where a grabbed ticket has to be paid for.
    ///
    /// The design's About panel prints this host because it is the one address a user
    /// opens this panel to read: after a run ends, paying happens there and nowhere
    /// else.  The full URL is the engine's to supply (see `AppModel.orderURL`); this is
    /// the display form.
    public static let orderHost = "kyfw.12306.cn"
    public static let orderURL = URL(string: "https://kyfw.12306.cn/otn/view/train_order.html")!

    private static func repositoryFile(_ path: String) -> URL {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let url = URL(string: "\(repositoryAddress)/blob/main/\(encoded)") else {
            preconditionFailure("仓库路径不是合法 URL：\(path)")
        }
        return url
    }

    /// The address as a `URL`.
    ///
    /// The literal above is ours, so a malformed one is a programming error rather than
    /// a condition to handle: it is stated here instead of being pushed out as an
    /// optional that every call site has to unwrap or ignore.
    public static var repositoryURL: URL {
        guard let url = URL(string: repositoryAddress) else {
            preconditionFailure("项目地址不是合法 URL：\(repositoryAddress)")
        }
        return url
    }
}

/// The bundle's own version numbers, resolved into the single line the About panel shows.
public struct FairTicketVersion: Equatable, Sendable {
    public let short: String?
    public let build: String?

    public init(short: String? = nil, build: String? = nil) {
        self.short = short
        self.build = build
    }

    /// Read the running bundle's numbers.
    ///
    /// A bare `swift run` binary has no `Info.plist` at all, and the fallbacks below are
    /// what keep the line honest there: "版本 1.0.0（构建 (null)）" is the alternative.
    public static func current(in bundle: Bundle = .main) -> FairTicketVersion {
        FairTicketVersion(
            short: bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
            build: bundle.infoDictionary?["CFBundleVersion"] as? String
        )
    }

    /// "版本 1.0.0（构建 1）", degrading to whichever half is actually known.
    public var displayText: String {
        let short = short.flatMap { $0.isEmpty ? nil : $0 }
        let build = build.flatMap { $0.isEmpty ? nil : $0 }
        switch (short, build) {
        case let (short?, build?): return "版本 \(short)（构建 \(build)）"
        case let (short?, nil): return "版本 \(short)"
        case let (nil, build?): return "构建 \(build)"
        case (nil, nil): return "开发版本"
        }
    }
}

/// The About window, laid out as the design's identity plate.
///
/// A single panel rather than a page in the main window — it is read once, and the main
/// window is a form that a stray About tab would push around.  The panel is the same
/// surface ladder as the rest of the app, lit from the top by the one gradient the
/// design allows, so it reads as the same product as the countdown rather than as a
/// generic system panel.
public struct AboutView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Flipped for a moment after a copy, because a pasteboard write is invisible and a
    /// button that says nothing happened is indistinguishable from a broken one.
    @State private var copied = false
    /// Held so a second copy restarts the confirmation instead of letting the first
    /// timer switch the label back early, and cancelled when the window closes.
    @State private var copyReset: Task<Void, Never>?

    private let version: FairTicketVersion

    public init(version: FairTicketVersion = .current()) {
        self.version = version
    }

    public var body: some View {
        VStack(spacing: 0) {
            identity
            rule
            links
            rule
            disclaimer
            rule
            footer
        }
        .frame(width: 460)
        .background(Theme.card(scheme))
        .tint(Theme.brand)
        // Set here rather than at the scene: the About window is its own scene and does
        // not inherit the main window's environment, and the copy confirmation is the
        // only motion in it.
        .environment(\.motionEnabled, !reduceMotion)
        .onDisappear { copyReset?.cancel() }
    }

    private var rule: some View {
        Rectangle().fill(Theme.hairline(scheme)).frame(height: 1)
    }

    // MARK: - Identity

    /// Names, centred over the lit top edge.
    ///
    /// The design centres this panel's identity and leaves the icon out: the Dock and
    /// the menu bar already show the mark, and repeating it here would make the panel a
    /// splash screen rather than a statement of what the tool is and is not.
    private var identity: some View {
        VStack(spacing: 0) {
            Text("FAIRTICKET FOR MAC")
                .font(Theme.data(12, .semibold))
                .tracking(1.6)
                .foregroundStyle(Theme.accentText(scheme))

            Text("FairTicket")
                .font(Theme.ui(26, .bold))
                .foregroundStyle(Theme.textStrong(scheme))
                .tracking(-0.3)
                .padding(.top, 8)

            Text("为 macOS 打造的 12306 抢票工具")
                .font(Theme.ui(15))
                .foregroundStyle(Theme.textSecondary(scheme))
                .padding(.top, 7)

            Text(version.displayText)
                .font(Theme.data(13))
                .foregroundStyle(Theme.textTertiary(scheme))
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 34)
        .padding(.bottom, Theme.Space.xl)
        .background(
            // The lit top edge: the panel's own gradient, strongest where the title is
            // and gone by the time the links start.
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(hex: 0x331A06), Color(hex: 0x131313)]
                    : [Color(hex: 0xFFF1E2), Color(hex: 0xFFFFFF)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// The real application icon, from wherever this process can reach it.
    ///
    /// The module's copy is the reliable one: the .app bundle holds the same file, and
    /// the off-screen renderer and Previews hold only the module.  `NSApp`'s own idea of
    /// the icon is tried *last* and only as a fallback — in a process that has no icon of
    /// its own it cheerfully returns a system folder picture, which is how a review
    /// screenshot ends up showing a blue folder next to the product name.
    // MARK: - Links

    private var links: some View {
        VStack(spacing: 0) {
            linkRow(title: "待支付订单页", value: FairTicketProject.orderHost) {
                NSWorkspace.shared.open(FairTicketProject.orderURL)
            }
        }
    }

    private func linkRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.md) {
                Text(title)
                    .font(Theme.ui(15))
                    .foregroundStyle(Theme.textSecondary(scheme))
                Spacer(minLength: Theme.Space.sm)
                Text(value)
                    .font(Theme.data(14, .medium))
                    .foregroundStyle(Theme.accentText(scheme))
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("在浏览器中打开 \(value)")
    }

    // MARK: - Disclaimer

    /// The one paragraph the design puts on this panel, in a recessed well so it reads
    /// as a statement rather than as another link row.
    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("使用声明")
                .font(Theme.ui(14, .medium))
                .foregroundStyle(Theme.textSecondary(scheme))
            Text(
                "本工具仅协助手动操作，不代付、不保存支付信息。"
                    + "请遵守 12306 用户协议，合理使用查询频率。"
            )
            .font(Theme.ui(14))
            .foregroundStyle(Theme.textSecondary(scheme))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.well(scheme),
            in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        )
        .padding(Theme.Space.md)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Theme.Space.sm) {
            Button {
                copyAddress()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(Theme.ui(13, .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(copied ? "已复制" : "2026 FairTicket · GPL-3.0 授权")
                        .font(Theme.ui(14))
                }
                .foregroundStyle(Theme.textTertiary(scheme))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .motion(Theme.Motion.snappy, value: copied)
            .help(
                copied
                    ? "已复制到剪贴板"
                    : "复制项目地址 \(FairTicketProject.repositoryAddress)"
            )

            Spacer(minLength: 0)

            Button("关闭") {
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.inverseAction)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
    }

    private func copyAddress() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(FairTicketProject.repositoryAddress, forType: .string)

        copied = true
        copyReset?.cancel()
        copyReset = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

/// App-menu item that opens the About window.
///
/// Lives in the library with the view it opens, so the app target keeps declaring
/// scenes and commands only — and so the window's identifier is not spelled twice.
public struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        Button("关于 \(FairTicketProject.name)") {
            openWindow(id: FairTicketWindow.aboutID)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

#Preview("关于") {
    AboutView(version: FairTicketVersion(short: "1.0.0", build: "1"))
}

#Preview("关于 · 深色") {
    AboutView(version: FairTicketVersion(short: "1.0.0", build: "1"))
        .preferredColorScheme(.dark)
}

#Preview("关于 · 没有 Info.plist") {
    AboutView(version: FairTicketVersion())
}
