#!/usr/bin/env swift

//  render-app-icons.swift
//  OhMyKey
//
//  Regenerates the application icons so they use the same motif as the menu bar
//  status icons: a rounded square with the letter cut into it.
//
//  Run:  swift render-app-icons.swift
//
//  Writes, relative to this script:
//    ../OhMyKey/Resources/Icon.icns                       macOS app icon
//    ../../win32/OhMyKey/OhMyKey/icon.ico                 Windows app icon
//    ../../win32/OhMyKey/OhMyKeyUpdate/OhMyKeyUpdate.ico  Windows updater icon
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
// Blue from the old updater icon, kept for its refresh badge.
let badgeBlue = NSColor(srgbRed: 0x28 / 255.0, green: 0xA3 / 255.0, blue: 0xD6 / 255.0, alpha: 1)

// Fraction of the corner radius to the body's width. 0.225 is Apple's macOS icon
// grid (185.4pt radius on an 824pt body) and is also what the 22pt status icon
// works out to, so both icons round off at the same rate.
let cornerFraction: CGFloat = 0.225

// How much of the body's height the letter's inked height should take up. Large
// enough to carry at 16pt, small enough to leave the corners breathing.
let letterFraction: CGFloat = 0.52

// macOS reserves the outer ~10% of the canvas for the shadow and for icons that
// break their bounds; a body of 824/1024 is the grid's square. Windows has no such
// convention and an inset that big just makes the icon look small in the taskbar.
let macBodyFraction: CGFloat = 824.0 / 1024.0
let winBodyFraction: CGFloat = 0.94

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

func drawRefreshBadge(in rect: NSRect) {
    // The updater is the same app doing a different job, so it gets the app icon
    // with a badge rather than a design of its own.
    NSColor.white.setFill()
    NSBezierPath(ovalIn: rect).fill()

    let inset = rect.insetBy(dx: rect.width * 0.16, dy: rect.height * 0.16)
    let config = NSImage.SymbolConfiguration(pointSize: inset.height, weight: .bold)
    guard let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath",
                               accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return }

    // Tint in a scratch image first. Filling the destination with .sourceAtop would
    // otherwise catch the opaque square underneath and repaint the whole icon blue.
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    badgeBlue.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    tinted.unlockFocus()

    // Symbol images carry padding around the glyph, so centre on the image, not the ink.
    let s = symbol.size
    let fit = min(inset.width / s.width, inset.height / s.height)
    let drawn = NSSize(width: s.width * fit, height: s.height * fit)
    tinted.draw(in: NSRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                           width: drawn.width, height: drawn.height))
}

func render(size: Int, letter: String, bodyFraction: CGFloat, badge: Bool) -> NSBitmapImageRep {
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

    if badge {
        // Sits inside the body rather than overhanging it: the Windows canvas only
        // leaves a few percent of margin, so an overhang would clip.
        let d = side * 0.44
        let pad = side * 0.02
        drawRefreshBadge(in: NSRect(x: body.maxX - d - pad, y: body.minY + pad,
                                    width: d, height: d))
    }

    return rep
}

// MARK: - ICO container
//
// Written by hand because nothing in AppKit emits .ico. The format is a directory of
// images; entries up to 128px are raw DIBs, 256px is stored as PNG (the size field is
// a byte, so 256 is encoded as 0 and only the PNG form is universally understood).

func dib(_ rep: NSBitmapImageRep) -> Data {
    let w = rep.pixelsWide, h = rep.pixelsHigh
    var out = Data()
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
    func i32(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }

    u32(40)                     // BITMAPINFOHEADER
    i32(Int32(w))
    i32(Int32(h * 2))           // doubled: the header covers the colour and mask planes
    u16(1)                      // planes
    u16(32)                     // bpp
    u32(0)                      // BI_RGB
    u32(UInt32(w * h * 4))
    i32(0); i32(0); u32(0); u32(0)

    // Bottom-up BGRA. CoreGraphics hands back premultiplied alpha; Windows wants it
    // straight, so undo the multiply or every soft edge comes out too dark.
    let src = rep.bitmapData!
    let stride = rep.bytesPerRow
    for row in (0..<h).reversed() {
        let line = src + row * stride
        for x in 0..<w {
            let p = line + x * 4
            let a = p[3]
            func un(_ c: UInt8) -> UInt8 {
                guard a > 0 else { return 0 }
                return UInt8(min(255, Int(c) * 255 / Int(a)))
            }
            out.append(un(p[2])); out.append(un(p[1])); out.append(un(p[0])); out.append(a)
        }
    }
    // AND mask: superseded by the alpha channel, but the format still requires the
    // bytes. All zero = "opaque everywhere", the conventional filler.
    out.append(Data(count: ((w + 31) / 32) * 4 * h))
    return out
}

func writeICO(_ reps: [NSBitmapImageRep], to url: URL) throws {
    let images: [Data] = reps.map {
        $0.pixelsWide >= 256 ? $0.representation(using: .png, properties: [:])! : dib($0)
    }
    var out = Data()
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }

    u16(0); u16(1); u16(UInt16(reps.count))
    var offset = 6 + 16 * reps.count
    for (rep, data) in zip(reps, images) {
        let px = rep.pixelsWide
        out.append(px >= 256 ? 0 : UInt8(px))
        out.append(px >= 256 ? 0 : UInt8(px))
        out.append(0); out.append(0)
        u16(1); u16(32)
        u32(UInt32(data.count)); u32(UInt32(offset))
        offset += data.count
    }
    for data in images { out.append(data) }
    try out.write(to: url)
}

// MARK: - Output

// Resolved relative to this script so moving or renaming the tree does not break it.
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
func path(_ relative: String) -> URL {
    scriptDir.appendingPathComponent(relative).standardizedFileURL
}

let icnsSizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                 (256, 1), (256, 2), (512, 1), (512, 2)]
let icoSizes = [16, 32, 40, 48, 64, 128, 256]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
    exit(1)
}

// macOS: build an .iconset and let iconutil pack it, which is the only supported way
// to produce an .icns.
let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("OhMyKey-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for (points, scale) in icnsSizes {
    autoreleasepool {
        let rep = render(size: points * scale, letter: "V",
                         bodyFraction: macBodyFraction, badge: false)
        let suffix = scale == 2 ? "@2x" : ""
        let url = iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        guard let data = rep.representation(using: .png, properties: [:]),
              (try? data.write(to: url)) != nil else { fail("Failed to write \(url.path)") }
    }
}

let icns = path("../OhMyKey/Resources/Icon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fail("iconutil failed") }
print("wrote \(icns.lastPathComponent)")

// Windows.
for (relative, badge) in [("../../win32/OhMyKey/OhMyKey/icon.ico", false),
                          ("../../win32/OhMyKey/OhMyKeyUpdate/OhMyKeyUpdate.ico", true)] {
    let url = path(relative)
    let reps = icoSizes.map {
        render(size: $0, letter: "V", bodyFraction: winBodyFraction, badge: badge)
    }
    do {
        try writeICO(reps, to: url)
        print("wrote \(url.lastPathComponent)")
    } catch {
        fail("Failed to write \(url.path): \(error)")
    }
}
