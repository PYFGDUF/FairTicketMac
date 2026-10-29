import SwiftUI

enum TicketTextSize: String, CaseIterable, Identifiable {
    case small, medium, large

    static let storageKey = "appearance.textSize"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.9
        case .medium: return 1
        case .large: return 1.12
        }
    }

    static func stored(_ value: String) -> Self { Self(rawValue: value) ?? .medium }
}

private struct TicketTextSizeKey: EnvironmentKey {
    static let defaultValue = TicketTextSize.medium
}

extension EnvironmentValues {
    var ticketTextSize: TicketTextSize {
        get { self[TicketTextSizeKey.self] }
        set { self[TicketTextSizeKey.self] = newValue }
    }
}

/// Retains the font's role and base size until the view's local preference is known.
struct TicketFont {
    let family: String
    let pointSize: CGFloat
    let weight: Font.Weight

    func scaledSize(for size: TicketTextSize) -> CGFloat { pointSize * size.scale }

    func resolved(for size: TicketTextSize) -> Font {
        .custom(family, size: scaledSize(for: size)).weight(weight)
    }
}

private struct TicketFontModifier: ViewModifier {
    @Environment(\.ticketTextSize) private var size
    let font: TicketFont

    func body(content: Content) -> some View {
        content.font(font.resolved(for: size))
    }
}

extension View {
    /// Themed fonts resolve here, so changing a preference invalidates each font
    /// directly, including fonts inside an already open calendar or result panel.
    func font(_ font: TicketFont) -> some View {
        modifier(TicketFontModifier(font: font))
    }
}

private struct TextPreferencesModifier: ViewModifier {
    @AppStorage(TicketTextSize.storageKey) private var storedSize = TicketTextSize.medium.rawValue

    func body(content: Content) -> some View {
        content.environment(\.ticketTextSize, TicketTextSize.stored(storedSize))
    }
}

public extension View {
    func ticketTextPreferences() -> some View { modifier(TextPreferencesModifier()) }
}
