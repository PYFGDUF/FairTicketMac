// Renders the app icon from the same brand tokens the interface uses, so the Dock,
// the Finder and the window agree on what the app looks like.
//
//   swift script/make_icon.swift Resources/AppIcon-1024.png
//
// Drawn rather than generated: an icon needs to be crisp at 16pt as well as 1024pt,
// and the mark is a teal squircle plus the train glyph the sidebar already uses.
// `script/make_icon.sh` turns the master PNG into AppIcon.icns.

import AppKit
import CoreGraphics
import Foundation

let canvasSize = 1024

// macOS icons keep a margin: the artwork is a rounded square, not a full-bleed tile.
let margin: CGFloat = 74
let side = CGFloat(canvasSize) - margin * 2
let rect = CGRect(x: margin, y: margin, width: side, height: side)
let corner = side * 0.2237  // the system's squircle ratio

// teal-500 → teal-700, matching Theme.brandMark.
let topColor = NSColor(srgbRed: 0x20 / 255.0, green: 0xC0 / 255.0, blue: 0xB0 / 255.0, alpha: 1)
let bottomColor = NSColor(srgbRed: 0x0B / 255.0, green: 0x6E / 255.0, blue: 0x66 / 255.0, alpha: 1)

guard
    let context = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    FileHandle.standardError.write(Data("cannot create a bitmap context\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

// --- squircle with a light source at the top ------------------------------------

let squircle = CGPath(
    roundedRect: rect,
    cornerWidth: corner,
    cornerHeight: corner,
    transform: nil
)

context.saveGState()
context.addPath(squircle)
context.clip()
if let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [topColor.cgColor, bottomColor.cgColor] as CFArray,
    locations: [0, 1]
) {
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
}
// A soft highlight across the top third: without it the fill reads as flat print.
if let sheen = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [
        NSColor.white.withAlphaComponent(0.34).cgColor,
        NSColor.white.withAlphaComponent(0).cgColor,
    ] as CFArray,
    locations: [0, 1]
) {
    context.drawLinearGradient(
        sheen,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.1),
        options: []
    )
}
context.restoreGState()

// --- the mark -------------------------------------------------------------------

// Hierarchical rather than palette: the symbol has several layers (body, window,
// rails), and a palette with fewer colours than layers leaves the rest to the
// current drawing colour, which darkened the plate behind the train.
let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.5, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))
guard
    let symbol = NSImage(systemSymbolName: "tram.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
else {
    FileHandle.standardError.write(Data("SF Symbol tram.fill is unavailable\n".utf8))
    exit(1)
}

let glyphSize = symbol.size
let glyphRect = CGRect(
    x: rect.midX - glyphSize.width / 2,
    y: rect.midY - glyphSize.height / 2 + side * 0.015,
    width: glyphSize.width,
    height: glyphSize.height
)
symbol.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1)

NSGraphicsContext.restoreGraphicsState()

// --- write ----------------------------------------------------------------------

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("cannot render the icon\n".utf8))
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon-1024.png"
let url = URL(fileURLWithPath: outputPath)
let bitmap = NSBitmapImageRep(cgImage: image)
bitmap.size = NSSize(width: canvasSize, height: canvasSize)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("cannot encode the PNG\n".utf8))
    exit(1)
}
try png.write(to: url)
print("wrote \(outputPath) (\(png.count) bytes)")