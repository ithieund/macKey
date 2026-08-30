//
//  Hotkey.swift
//  OhMyKey
//
//  The engine stores a shortcut as one packed Int32 that it compares against live key
//  events, so the layout below is a wire format, not an implementation detail we get to
//  change. This type is the only place that knows it.
//

import Carbon.HIToolbox
import Foundation

struct Hotkey: Equatable {
    /// The engine's "no key assigned" sentinel, used for both the key code and the
    /// display character.
    static let noKey: UInt8 = 0xFE

    var keyCode: UInt8 = Hotkey.noKey
    /// The character to show for `keyCode`. Stored separately because the engine
    /// compares key codes but the UI has to print something.
    var character: UInt8 = Hotkey.noKey

    var control = false
    var option = false
    var command = false
    var shift = false
    /// Only meaningful for the language switch key; the convert hotkey ignores it.
    var beep = false

    init() {}

    init(packed: Int32) {
        let bits = UInt32(bitPattern: packed)
        keyCode = UInt8(bits & 0xFF)
        character = UInt8((bits >> 24) & 0xFF)
        control = bits & 0x100 != 0
        option = bits & 0x200 != 0
        command = bits & 0x400 != 0
        shift = bits & 0x800 != 0
        beep = bits & 0x8000 != 0
    }

    var packed: Int32 {
        var bits = UInt32(keyCode)
        if control { bits |= 0x100 }
        if option { bits |= 0x200 }
        if command { bits |= 0x400 }
        if shift { bits |= 0x800 }
        if beep { bits |= 0x8000 }
        bits |= UInt32(character) << 24
        return Int32(bitPattern: bits)
    }

    var hasKey: Bool { keyCode != Hotkey.noKey }

    var hasModifier: Bool { control || option || command || shift }

    /// What to draw in the key field: a name for keys that have no glyph, otherwise the
    /// character the user typed.
    var keyLabel: String {
        guard hasKey else { return "" }
        if keyCode == UInt8(kVK_Space) { return "Space" }
        guard let scalar = UnicodeScalar(UInt32(character)), character != 0 else { return "" }
        return String(scalar).uppercased()
    }

    /// The whole shortcut as a single string, e.g. "⌥Z". Empty when nothing is bound.
    var displayString: String {
        var result = ""
        if control { result += "⌃" }
        if option { result += "⌥" }
        if command { result += "⌘" }
        if shift { result += "⇧" }
        result += keyLabel
        return result
    }

    mutating func clearKey() {
        keyCode = Hotkey.noKey
        character = Hotkey.noKey
    }

    /// Records a key press. Delete clears the binding, Space is stored by name because
    /// its character is not printable.
    mutating func record(keyCode newKeyCode: UInt16, characters: String?) {
        if newKeyCode == UInt16(kVK_Delete) || newKeyCode == UInt16(kVK_ForwardDelete) {
            clearKey()
            return
        }
        if newKeyCode == UInt16(kVK_Space) {
            keyCode = UInt8(kVK_Space)
            character = UInt8(kVK_Space)
            return
        }
        keyCode = UInt8(truncatingIfNeeded: newKeyCode)
        character = characters?.utf8.first ?? 0
    }
}
