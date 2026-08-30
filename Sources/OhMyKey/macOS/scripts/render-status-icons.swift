#!/usr/bin/env swift

//  render-status-icons.swift
//  OhMyKey
//
//  Regenerates the menu bar status icons in ../OhMyKey/Resources.
//
//  Run:  swift render-status-icons.swift
//
//  The old icons were a bare letterform on a transparent background: a thin "V"
//  or "E" that all but disappeared against the light menu bar. These draw a
//  filled rounded square instead and knock the letter out of it, so the letter
//  reads as a hole rather than as strokes.
//
//  That shape is also what makes template rendering work. AppKit throws away the
//  colour of a template image and keeps only the alpha, painting it black on a
//  light menu bar and white on a dark one, and inverting it while the menu is
//  open. A filled square with a transparent letter therefore stays legible in
//  every appearance without the app having to observe the system theme.
//
//  The square is drawn at squareAlpha rather than fully opaque so it renders as
//  a soft dark grey instead of a hard black block. Below about 0.8 the letter
//  stops separating cleanly from the menu bar behind it.

import AppKit

// MARK: - Design constants (points; @2x is the same geometry at twice the scale)

let canvas: CGFloat = 22        // menu bar images are 22pt
let inset: CGFloat = 2          // breathing room so the square is not flush to the edge
let cornerRadius: CGFloat = 4   // "soft rounded edge"
let fontSize: CGFloat = 13      // .heavy at 13pt keeps stems ~1.9px at 1x, above the 1.5px floor,
                                // and leaves margin inside the square; 15pt overflows it
let squareAlpha: CGFloat = 0.85 // the "slightly grey" mask
let squareWhite: CGFloat = 0.56 // #8E8E93, legible on light and dark when not templated

// "V" sits optically low because it tapers to a point; nudge it up slightly.
let opticalNudge: [String: CGFloat] = ["V": 0.5, "E": 0.0]

struct Variant {
    let name: String
    let letter: String
    let fill: NSColor
}

let variants = [
    // Normal state. Drawn grey so that even with template rendering off (the
    // "Biểu tượng hiện đại" setting) the icon still reads on either appearance.
    Variant(name: "Status", letter: "V", fill: NSColor(white: squareWhite, alpha: squareAlpha)),
    Variant(name: "StatusEng", letter: "E", fill: NSColor(white: squareWhite, alpha: squareAlpha)),
    // Shown while the menu is open, when the status item sits on a filled
    // highlight. Only used when template rendering is off; AppKit inverts
    // template images by itself.
    Variant(name: "StatusHighlighted", letter: "V", fill: NSColor(white: 1.0, alpha: 0.9)),
    Variant(name: "StatusHighlightedEng", letter: "E", fill: NSColor(white: 1.0, alpha: 0.9)),
]

// MARK: - Output location

// Resolved relative to this script so the rename of the enclosing directories
// does not break it: scripts/ and OhMyKey/Resources/ stay siblings.
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
let outDir: URL = {
    if CommandLine.arguments.count > 1 {
        return URL(fileURLWithPath: CommandLine.arguments[1])
    }
    return scriptDir.appendingPathComponent("../OhMyKey/Resources").standardizedFileURL
}()

guard FileManager.default.fileExists(atPath: outDir.path) else {
    FileHandle.standardError.write("Output directory not found: \(outDir.path)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - Rendering

func render(_ variant: Variant, scale: Int) -> Data {
    let px = Int(canvas) * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    // Declaring the point size tags the file as 72/144 dpi, which is how AppKit
    // tells the @2x file apart from the @1x one.
    rep.size = NSSize(width: canvas, height: canvas)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.shouldAntialias = true
    ctx.imageInterpolation = .high

    // Transparent background: everything outside the square must let the menu bar through.
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill(using: .copy)

    let box = NSRect(x: inset, y: inset,
                     width: canvas - inset * 2, height: canvas - inset * 2)
    variant.fill.setFill()
    NSBezierPath(roundedRect: box, xRadius: cornerRadius, yRadius: cornerRadius).fill()

    // Knock the letter out of the square: destinationOut erases wherever the
    // glyph paints, leaving a transparent letter rather than a drawn one.
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
        .foregroundColor: NSColor.black,
    ]
    let text = NSAttributedString(string: variant.letter, attributes: attributes)
    // Use the glyph's inked bounds, not the line box, so the letter is centred on
    // what you actually see rather than on the font's ascender/descender metrics.
    let bounds = text.boundingRect(with: NSSize(width: 100, height: 100),
                                   options: [.usesDeviceMetrics])
    let origin = NSPoint(x: box.midX - bounds.midX,
                         y: box.midY - bounds.midY + (opticalNudge[variant.letter] ?? 0))
    ctx.compositingOperation = .destinationOut
    text.draw(at: origin)
    ctx.compositingOperation = .sourceOver

    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Failed to encode \(variant.name)\n".data(using: .utf8)!)
        exit(1)
    }
    return data
}

for variant in variants {
    for scale in [1, 2] {
        autoreleasepool {
            let suffix = scale == 2 ? "@2x" : ""
            let url = outDir.appendingPathComponent("\(variant.name)\(suffix).png")
            do {
                try render(variant, scale: scale).write(to: url)
                print("wrote \(url.lastPathComponent)")
            } catch {
                FileHandle.standardError.write("Failed to write \(url.path): \(error)\n".data(using: .utf8)!)
                exit(1)
            }
        }
    }
}
