import AppKit
import SwiftUI
import Testing
@testable import FairTicketUI

@MainActor
@Suite("主题可读性")
struct ThemeContrastTests {
    @Test("正文与辅助标签在各级表面达到 4.5:1", arguments: [ColorScheme.light, .dark])
    func textContrast(scheme: ColorScheme) throws {
        let surfaces = [Theme.card(scheme), Theme.canvas(scheme), Theme.rail(scheme),
                        Theme.chip(scheme), Theme.well(scheme)]
        let inks = [Theme.text(scheme), Theme.textSecondary(scheme), Theme.textTertiary(scheme)]
        for surface in surfaces {
            for ink in inks {
                #expect(try contrast(ink, on: surface) >= 4.5)
            }
        }
    }

    @Test("提示、成功状态与品牌按钮具有足够对比度", arguments: [ColorScheme.light, .dark])
    func semanticContrast(scheme: ColorScheme) throws {
        for tone in [InlineNote.Tone.warning, .brand, .success] {
            #expect(try contrast(tone.text(scheme), on: tone.background(scheme)) >= 4.5)
        }
        #expect(try contrast(Theme.accentText(scheme), on: Theme.card(scheme)) >= 4.5)
        #expect(try contrast(Theme.successText(scheme), on: Theme.card(scheme)) >= 4.5)
        #expect(try contrast(Theme.onBrand, on: Theme.brand) >= 4.5)
    }

    // Resolve sRGB values and composite translucent washes over the card before
    // applying WCAG relative luminance; comparing hex values alone misses opacity.
    private func contrast(_ foreground: Color, on background: Color) throws -> Double {
        func rgba(_ color: Color) throws -> [Double] {
            let value = try #require(NSColor(color).usingColorSpace(.sRGB))
            return [value.redComponent, value.greenComponent, value.blueComponent, value.alphaComponent]
        }
        func over(_ top: [Double], _ bottom: [Double]) -> [Double] {
            (0..<3).map { top[$0] * top[3] + bottom[$0] * (1 - top[3]) } + [1]
        }
        func luminance(_ color: [Double]) -> Double {
            let linear = color.prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let base = try rgba(Theme.card(.light))
        let back = over(try rgba(background), base)
        let front = over(try rgba(foreground), back)
        let light = max(luminance(front), luminance(back))
        let dark = min(luminance(front), luminance(back))
        return (light + 0.05) / (dark + 0.05)
    }
}
