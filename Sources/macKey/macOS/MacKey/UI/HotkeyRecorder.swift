//
//  HotkeyRecorder.swift
//  MacKey
//
//  A field that captures the next key you press instead of typing it.
//
//  SwiftUI has no way to read a raw key code, and the engine matches on key codes, not on
//  characters - so this drops to an NSView that becomes first responder and reads keyDown
//  directly. It replaces MyTextField, which achieved the same thing by installing a global
//  NSEvent monitor and then editing an NSTextField's contents behind its back.
//

import AppKit
import SwiftUI

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKey = { keyCode, characters in
            hotkey.record(keyCode: keyCode, characters: characters)
        }
        return view
    }

    func updateNSView(_ view: KeyCaptureView, context: Context) {
        view.label = hotkey.keyLabel
    }
}

final class KeyCaptureView: NSView {
    var onKey: ((UInt16, String?) -> Void)?

    var label: String = "" {
        didSet {
            guard label != oldValue else { return }
            needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 64, height: 24) }
    override var focusRingMaskBounds: NSRect { bounds }

    override init(frame: NSRect) {
        super.init(frame: frame)
        focusRingType = .exterior
    }

    required init?(coder: NSCoder) {
        fatalError("not loaded from a nib")
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        onKey?(event.keyCode, event.characters)
    }

    /// Swallow the key so AppKit does not also beep at it or move focus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        onKey?(event.keyCode, event.characters)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let focused = window?.firstResponder === self
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        (focused ? NSColor.textBackgroundColor : NSColor.controlBackgroundColor).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()

        let text = label.isEmpty ? (focused ? String(localized: "Nhấn phím") : "–") : label
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: label.isEmpty ? 10 : 13,
                                     weight: label.isEmpty ? .regular : .medium),
            .foregroundColor: label.isEmpty ? NSColor.tertiaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}
