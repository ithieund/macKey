//
//  Windows.swift
//  MacKey
//
//  Creates and remembers the app's windows.
//
//  This replaces the storyboard, which existed mainly to hold four window controllers and
//  a main menu. Windows are built in code so their sizes come from their content instead
//  of from a canvas somebody measured in 2019.
//

import AppKit
import SwiftUI

@objc(MacKeyWindowManager)
@MainActor
final class WindowManager: NSObject {
    @objc static let shared = WindowManager()

    enum Kind: String, CaseIterable {
        case settings, macros, convert, about

        var title: String {
            switch self {
            case .settings: return "macKey"
            case .macros: return String(localized: "Gõ tắt")
            case .convert: return String(localized: "Công cụ chuyển mã")
            case .about: return String(localized: "Giới thiệu macKey")
            }
        }

        var isResizable: Bool { self != .about }
    }

    private var controllers: [Kind: NSWindowController] = [:]

    private override init() {
        super.init()
    }

    // MARK: - Entry points used from AppDelegate

    @objc func showSettings() { show(.settings) }
    @objc func showMacros() { show(.macros) }
    @objc func showConvertTool() { show(.convert) }
    @objc func showAbout() { show(.about) }

    @objc func closeSettings() {
        controllers[.settings]?.close()
    }

    /// Whether any of our windows is on screen. The Dock icon follows this.
    @objc var hasVisibleWindow: Bool {
        controllers.values.contains { $0.isWindowLoaded && $0.window?.isVisible == true }
    }

    /// Opens every window at once. Only the UI preview harness uses this.
    @objc func showAllWindows() {
        Kind.allCases.forEach { show($0) }
    }

    @objc func windowForKindName(_ name: String) -> NSWindow? {
        guard let kind = Kind(rawValue: name) else { return nil }
        return controllers[kind]?.window
    }

    // MARK: -

    private func show(_ kind: Kind) {
        let controller = controllers[kind] ?? make(kind)
        // LSUIElement apps are not activated for free, so without this the window opens
        // behind whatever the user was typing in.
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        // Above ordinary windows, matching how the app has always presented its panels.
        controller.window?.level = .floating
    }

    private func make(_ kind: Kind) -> NSWindowController {
        let hosting = NSHostingController(rootView: rootView(for: kind))
        hosting.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: hosting)
        window.title = kind.title
        window.styleMask = kind.isResizable
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.titled, .closable]
        // Closing must not deallocate the window: the menu reopens the same one, and
        // setFrameAutosaveName only pays off if the instance survives.
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("macKey.\(kind.rawValue)")
        if window.frame.origin == .zero {
            window.center()
        }

        let controller = NSWindowController(window: window)
        controllers[kind] = controller
        return controller
    }

    @ViewBuilder
    private func rootView(for kind: Kind) -> some View {
        Group {
            switch kind {
            case .settings: SettingsView()
            case .macros: MacroView()
            case .convert: ConvertToolView()
            case .about: AboutView()
            }
        }
        .environmentObject(AppSettings.shared)
    }
}
