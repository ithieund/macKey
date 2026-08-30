//
//  HotkeyTests.swift
//  OhMyKey
//
//  Hotkey is the one piece of the new UI that has to agree, bit for bit, with something
//  outside it: the engine compares this packed integer against live key events, and the
//  same layout is already sitting in people's preferences. Getting a bit wrong would not
//  crash anything - it would quietly bind the wrong key - so it is worth pinning down.
//
//  Run with scripts/run-tests.sh. There is no XCTest target; this is a plain executable
//  so it can be compiled straight from source without an Xcode scheme.
//

import Carbon.HIToolbox
import Foundation

@main
enum HotkeyTests {
    static var failures = 0

    // Compared as strings so one helper covers UInt8, Bool and String without a pile of
    // overloads; these are test assertions, not a general-purpose matcher.
    static func expect(_ actual: some Equatable, _ expected: some Equatable, _ what: String) {
        if "\(actual)" == "\(expected)" {
            print("  ok   \(what)")
        } else {
            print("  FAIL \(what): expected \(expected), got \(actual)")
            failures += 1
        }
    }

    static func main() {
        // The shipped default: option + z, no beep. Written as a literal because this is the
        // value in AppDelegate.m's DEFAULT_SWITCH_STATUS and the two must not drift.
        print("default switch key (0x7A000206)")
        do {
            let key = Hotkey(packed: Int32(bitPattern: 0x7A00_0206))
            expect(key.option, true, "option is set")
            expect(key.control, false, "control is clear")
            expect(key.command, false, "command is clear")
            expect(key.shift, false, "shift is clear")
            expect(key.beep, false, "beep is clear")
            expect(key.keyCode, 6, "key code is z")
            expect(key.keyLabel, "Z", "label is Z")
            expect(key.displayString, "⌥Z", "display string")
            expect(key.packed, Int32(bitPattern: 0x7A00_0206), "round trips")
    }

    // A modifiers-only shortcut. The engine allows it and real preferences contain it, which
    // is why the UI cannot be a conventional macOS shortcut recorder.
    print("modifiers only, no key (0xFE0089FE)")
    do {
        let key = Hotkey(packed: Int32(bitPattern: 0xFE00_89FE))
        expect(key.control, true, "control is set")
        expect(key.shift, true, "shift is set")
        expect(key.beep, true, "beep is set")
        expect(key.hasKey, false, "no key bound")
        expect(key.keyLabel, "", "label is empty")
        expect(key.displayString, "⌃⇧", "display string is modifiers only")
        expect(key.packed, Int32(bitPattern: 0xFE00_89FE), "round trips")
    }

    print("empty hotkey (0xFE0000FE, the engine's EMPTY_HOTKEY)")
    do {
        let key = Hotkey(packed: Int32(bitPattern: 0xFE00_00FE))
        expect(key.hasKey, false, "no key bound")
        expect(key.hasModifier, false, "no modifiers")
        expect(key.displayString, "", "displays as nothing")
    }

    print("every bit survives a round trip")
    do {
        for packed in [0x0000_0000, 0x7A00_0206, 0xFE00_89FE, 0xFF00_8F41, 0x4100_0F00] as [UInt32] {
            let value = Int32(bitPattern: packed)
            expect(Hotkey(packed: value).packed, value, String(format: "0x%08X", packed))
        }
    }

    print("recording keys")
    do {
        var key = Hotkey(packed: Int32(bitPattern: 0x7A00_0206))

        key.record(keyCode: UInt16(kVK_Space), characters: " ")
        expect(key.keyCode, UInt8(kVK_Space), "space stores its key code")
        expect(key.character, UInt8(kVK_Space), "space stores the key code as its character too")
        expect(key.keyLabel, "Space", "space is spelled out")
        expect(key.option, true, "recording a key leaves modifiers alone")

        key.record(keyCode: UInt16(kVK_Delete), characters: nil)
        expect(key.hasKey, false, "delete clears the binding")
        expect(key.character, Hotkey.noKey, "delete clears the character too")

        key.record(keyCode: UInt16(kVK_ForwardDelete), characters: nil)
        expect(key.hasKey, false, "forward delete also clears")

        key.record(keyCode: 6, characters: "z")
        expect(key.keyCode, 6, "ordinary key stores its code")
        expect(key.character, 0x7A, "ordinary key stores its character")
        expect(key.keyLabel, "Z", "ordinary key is shown uppercased")
    }

    print("")
    if failures == 0 {
        print("Hotkey: all assertions passed")
        exit(0)
    } else {
        print("Hotkey: \(failures) failure(s)")
        exit(1)
    }
    }
}
