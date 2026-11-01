#!/usr/bin/env swift

//  render-app-icons.swift
//  macKey
//
//  Regenerates the application icons so they use the same motif as the menu bar
//  status icons: a rounded square with the letter cut into it.
//
//  Run:  swift render-app-icons.swift
//
//  Writes, relative to this script:
//    ../MacKey/Resources/Icon.icns                         macOS app icon
//
//  The old icons were a bare coral "V" floating on transparency, which read as a
//  stray glyph rather than an app next to the solid tiles every other icon is.
//  Giving it a body fixes that and matches the status icon redrawn in
//  render-status-icons.swift.
//
//  The two scripts stay separate rather than sharing a file because each is run as
//  a standalone `swift <file>` script, and they are solving different problems: the
//  status icon has to survive AppKit's template rendering in monochrome, while this
//  one is always drawn in colour. What they do share is the shape language - same
//  corner-radius ratio, same typeface - which is duplicated deliberately below so
//  neither script has a dependency to resolve.

import AppKit
import CoreText

// MARK: - Design constants

// Brand coral, sampled from the icon this replaces so the app stays recognisable.
let coral = NSColor(srgbRed: 0xF6 / 255.0, green: 0x67 / 255.0, blue: 0x67 / 255.0, alpha: 1)

// Fraction of the corner radius to the body's width. 0.225 is Apple's macOS icon
// grid (185.4pt radius on an 824pt body) and is also what the 22pt status icon
// works out to, so both icons round off at the same rate.
let cornerFraction: CGFloat = 0.225

// How much of the body's height the letter's inked height should take up. Large
// enough to carry at 16pt, small enough to leave the corners breathing.
let letterFraction: CGFloat = 0.52

// macOS reserves the outer ~10% of the canvas for the shadow and for icons that
// break their bounds; a body of 824/1024 is the grid's square.
let macBodyFraction: CGFloat = 824.0 / 1024.0

// SF Rounded, as on the status icon: the softer terminals sit better inside a
// rounded square than SF Pro's flat ones.
func maskFont(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    guard let rounded = base.fontDescriptor.withDesign(.rounded),
          let font = NSFont(descriptor: rounded, size: size) else { return base }
    return font
}

// MARK: - Drawing

func inkBounds(_ letter: String, _ font: NSFont, _ ctx: CGContext) -> (CTLine, CGRect) {
    // CTLineDraw takes its colour from the attributed string, not from the context's
    // fill colour, so the attribute has to carry it or the letter comes out black.
    let text = NSAttributedString(string: letter,
                                  attributes: [.font: font, .foregroundColor: NSColor.white])
    let line = CTLineCreateWithAttributedString(text)
    return (line, CTLineGetImageBounds(line, ctx))
}

// Size the font from the letter it has to draw rather than from a fixed point size.
// "V" and "E" have different cap heights and the icon is rendered at ten sizes, so a
// hard-coded size would drift; measuring the ink and scaling makes every icon put the
// same amount of letter in the same amount of square. Font metrics scale linearly,
// so one correction pass lands within a fraction of a pixel.
func fittedFont(_ letter: String, targetHeight: CGFloat, _ ctx: CGContext) -> (CTLine, CGRect) {
    let probe: CGFloat = 200
    let (_, probeInk) = inkBounds(letter, maskFont(probe), ctx)
    let font = maskFont(probe * targetHeight / probeInk.height)
    return inkBounds(letter, font, ctx)
}

func render(size: Int, letter: String, bodyFraction: CGFloat) -> NSBitmapImageRep {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    gc.shouldAntialias = true
    gc.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill(using: .copy)

    let side = (s * bodyFraction).rounded()
    let body = NSRect(x: ((s - side) / 2).rounded(), y: ((s - side) / 2).rounded(),
                      width: side, height: side)
    coral.setFill()
    let radius = side * cornerFraction
    NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius).fill()

    // The status icon knocks the letter through to transparency because AppKit
    // repaints it from the alpha channel. An app icon is composited over whatever
    // wallpaper the user has, so a hole would show through; paint it white instead,
    // which is what the knockout looks like on the menu bar anyway.
    let (line, ink) = fittedFont(letter, targetHeight: side * letterFraction, gc.cgContext)
    gc.cgContext.saveGState()
    gc.cgContext.textPosition = CGPoint(x: body.midX - ink.midX, y: body.midY - ink.midY)
    CTLineDraw(line, gc.cgContext)
    gc.cgContext.restoreGState()

    return rep
}

// MARK: - Output

// Resolved relative to this script so moving or renaming the tree does not break it.
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
func path(_ relative: String) -> URL {
    scriptDir.appendingPathComponent(relative).standardizedFileURL
}

let icnsSizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                 (256, 1), (256, 2), (512, 1), (512, 2)]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
    exit(1)
}

// macOS: build an .iconset and let iconutil pack it, which is the only supported way
// to produce an .icns.
let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("MacKey-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for (points, scale) in icnsSizes {
    autoreleasepool {
        let rep = render(size: points * scale, letter: "V", bodyFraction: macBodyFraction)
        let suffix = scale == 2 ? "@2x" : ""
        let url = iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        guard let data = rep.representation(using: .png, properties: [:]),
              (try? data.write(to: url)) != nil else { fail("Failed to write \(url.path)") }
    }
}

let icns = path("../MacKey/Resources/Icon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fail("iconutil failed") }
print("wrote \(icns.lastPathComponent)")
