//
//  UIPreviewHarness.swift
//  OhMyKey
//
//  Debug-only. Opens every window so the UI can be looked at without the app being
//  able to type anything.
//
//  Why this exists: macOS ties the Accessibility grant to the app's code signature, and
//  an ad-hoc signature changes on every build, so a freshly built OhMyKey always quits at
//  launch asking for permission again. That makes reviewing a UI change far more painful
//  than it should be. Under OMK_UI_ONLY the app skips the permission gate, the
//  single-instance check and the event tap - it loads settings and draws windows, so it
//  can sit alongside the copy you are actually typing with.
//
//  It prints each window's CGWindowID so a caller can screenshot them with screencapture,
//  which composites the real window. Drawing the views into a bitmap ourselves is
//  tempting but lies: SwiftUI material and vibrancy come from the window server, so a
//  cacheDisplay render comes back with blank patches where the interesting parts were.
//

#if DEBUG

import AppKit
import SwiftUI

@objc(OMKUIPreviewHarness)
@MainActor
final class UIPreviewHarness: NSObject {
    /// Set OMK_UI_ONLY to run the UI without the event tap or the permission gate.
    @objc static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["OMK_UI_ONLY"] != nil
    }

    @objc static func run() {
        WindowManager.shared.showAllWindows()

        // Lay the windows out before reporting them, and spread them so screencapture
        // gets each one whole instead of three quarters of one and a corner of another.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            tileWindows()
            reportWindowIDs()
        }

        if let seconds = ProcessInfo.processInfo.environment["OMK_UI_HOLD"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                NSApp.terminate(nil)
            }
        }
    }

    private static func tileWindows() {
        guard let screen = NSScreen.main else { return }
        var origin = NSPoint(x: screen.visibleFrame.minX + 20, y: screen.visibleFrame.maxY - 40)
        for kind in WindowManager.Kind.allCases {
            guard let window = WindowManager.shared.windowForKindName(kind.rawValue) else { continue }
            window.setFrameTopLeftPoint(origin)
            origin.x += window.frame.width + 20
            if origin.x + window.frame.width > screen.visibleFrame.maxX {
                origin.x = screen.visibleFrame.minX + 20
                origin.y -= window.frame.height + 40
            }
        }
    }

    private static func reportWindowIDs() {
        for kind in WindowManager.Kind.allCases {
            guard let window = WindowManager.shared.windowForKindName(kind.rawValue) else { continue }
            let line = "OMK_WINDOW \(kind.rawValue) \(window.windowNumber)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
        FileHandle.standardError.write(Data("OMK_WINDOWS_READY\n".utf8))
    }
}

#endif
