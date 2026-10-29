import AppKit
import CoreText
import Foundation

/// Registers the two bundled font families with this process.
///
/// The app is assembled by hand from a SwiftPM build (`script/build_and_run.sh`), so
/// there is no `Info.plist` font declaration to lean on — `ATSApplicationFontsPath`
/// would have to be written into a plist this project generates itself, and it only
/// ever applies to a bundle.  Registering from the resource bundle at launch works in
/// all three places this code runs: the app, `UIShot`, and SwiftUI Previews.
///
/// Failure is deliberately not fatal.  `Font.custom` falls back to the system face when
/// a family is unknown, so a missing file costs the intended typeface and nothing else —
/// which is the right trade for a cosmetic asset that is also 40 MB of CJK glyphs.
public enum AppFonts {

    /// The faces actually shipped.
    ///
    /// Not the whole family: Sarasa Gothic SC carries the full CJK glyphset, so each
    /// weight is about 13 MB and shipping all ten would add more to the bundle than
    /// everything else in it combined.  These three are what the interface asks for.
    ///
    /// The family has no Medium — it steps ExtraLight, Light, Regular, SemiBold, Bold —
    /// so a `.medium` weight resolves to the nearest face CoreText has rather than to a
    /// synthesised one, which is why `.medium` is deliberately absent here.
    private static let uiFaces = [
        "SarasaGothicSC-Regular",
        "SarasaGothicSC-SemiBold",
        "SarasaGothicSC-Bold",
    ]

    /// Latin-only and small, so the full set is affordable.
    private static let dataFaces = [
        "JetBrainsMono-Regular",
        "JetBrainsMono-Medium",
        "JetBrainsMono-SemiBold",
        "JetBrainsMono-Bold",
    ]

    private static let directory = "Fonts"

    /// Registration is process-wide and idempotent, so the second call is a no-op rather
    /// than a second round of CoreText work.
    private static var didRegister = false

    /// Call once, before any view is built.
    public static func register() {
        guard !didRegister else { return }
        didRegister = true

        for face in uiFaces + dataFaces {
            guard
                let url = Bundle.module.url(
                    forResource: face,
                    withExtension: "ttf",
                    subdirectory: directory
                )
            else { continue }

            var error: Unmanaged<CFError>?
            // `.process` scope: the fonts belong to this app, not to the user's session.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    /// Whether the UI family is actually available, so a caller can tell "bundled and
    /// registered" apart from "falling back to the system face".
    public static var isUIFamilyAvailable: Bool {
        NSFontManager.shared.availableFontFamilies.contains(Theme.uiFamily)
    }

    public static var isDataFamilyAvailable: Bool {
        NSFontManager.shared.availableFontFamilies.contains(Theme.dataFamily)
    }

    /// One line naming both families' state, for the off-screen renderer's output.
    ///
    /// A missing face is invisible in a screenshot — the layout is identical and only
    /// the typeface is wrong — so the renderer states it rather than leaving the reader
    /// to notice.
    public static var report: String {
        "字体 界面=\(isUIFamilyAvailable ? "✓" : "✗ 回退系统") "
            + "数据=\(isDataFamilyAvailable ? "✓" : "✗ 回退系统")"
    }
}
