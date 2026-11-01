//
//  AppSettings.swift
//  MacKey
//
//  The observable face of MacKeyBridge.
//
//  Settings can change from three places: this UI, the status-bar menu, and the hotkeys
//  the engine watches for. Rather than mirror every value and try to keep the copies
//  honest, this object holds almost no state - reads go straight through to the bridge,
//  and a single revision counter republishes when anything changes anywhere.
//

import Combine
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Bumped whenever the bridge reports a change. Views observe this object, so a bump
    /// re-runs their bodies, and their bodies read current values from the bridge.
    @Published private var revision = 0

    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .MacKeySettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.revision &+= 1 }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Toggles

    func isOn(_ toggle: MacKeyToggle) -> Bool {
        MacKeyBridge.isOn(toggle)
    }

    func binding(_ toggle: MacKeyToggle) -> Binding<Bool> {
        Binding(
            get: { MacKeyBridge.isOn(toggle) },
            set: { MacKeyBridge.setOn($0, toggle: toggle) }
        )
    }

    // MARK: - Input mode

    var vietnameseEnabled: Bool {
        get { MacKeyBridge.vietnameseEnabled }
        set {
            guard newValue != MacKeyBridge.vietnameseEnabled else { return }
            MacKeyBridge.toggleInputMethod()
        }
    }

    var inputType: Int {
        get { MacKeyBridge.inputType }
        set { MacKeyBridge.setInputType(newValue) }
    }

    var codeTable: Int {
        get { MacKeyBridge.codeTable }
        set { MacKeyBridge.setCodeTable(newValue) }
    }

    var inputTypeNames: [String] { MacKeyBridge.inputTypeNames }
    var tableCodeNames: [String] { MacKeyBridge.tableCodeNames }

    // MARK: - Hotkeys

    var switchKey: Hotkey {
        get { Hotkey(packed: MacKeyBridge.switchKey) }
        set { MacKeyBridge.setSwitchKey(newValue.packed) }
    }

    var convertHotKey: Hotkey {
        get { Hotkey(packed: MacKeyBridge.convertHotKey) }
        set { MacKeyBridge.setConvertHotKey(newValue.packed) }
    }

    // MARK: - Convert tool

    var convertCase: MacKeyConvertCase {
        get { MacKeyBridge.convertCase }
        set { MacKeyBridge.setConvertCase(newValue) }
    }

    var convertFromCode: Int {
        get { MacKeyBridge.convertFromCode }
        set { MacKeyBridge.setConvertFromCode(newValue) }
    }

    var convertToCode: Int {
        get { MacKeyBridge.convertToCode }
        set { MacKeyBridge.setConvertToCode(newValue) }
    }

    func swapConvertCodes() {
        let from = MacKeyBridge.convertFromCode
        MacKeyBridge.setConvertFromCode(MacKeyBridge.convertToCode)
        MacKeyBridge.setConvertToCode(from)
    }

    // MARK: - Macros

    var macros: [MacKeyMacro] { MacKeyBridge.macros }

    // MARK: - Compatibility

    var applicationKeyModes: [MacKeyApplicationKeyMode] { MacKeyBridge.applicationKeyModes() }

    func keyModeBinding(for application: MacKeyApplicationKeyMode) -> Binding<MacKeyApplicationKeyDeliveryMode> {
        Binding(
            get: { MacKeyBridge.applicationKeyModes().first(where: { $0.bundleIdentifier == application.bundleIdentifier })?.keyDeliveryMode ?? .default },
            set: { MacKeyBridge.setKeyDeliveryMode($0, forApplication: application.bundleIdentifier) }
        )
    }

    // MARK: - App info

    var versionSummary: String { MacKeyBridge.versionSummary }
}

extension MacKeyMacro: Identifiable {
    public var id: String { text }
}

extension MacKeyApplicationKeyMode: Identifiable {
    public var id: String { bundleIdentifier }
}

// MARK: - UI language

/// Which language the UI itself is drawn in - not the input mode, which is what the
/// Vietnamese/English switch in the header controls.
///
/// Stored as `AppleLanguages`, the key the system itself reads to pick a bundle
/// localisation, so every path (SwiftUI Text, String(localized:), NSLocalizedString in
/// the Objective-C menu) follows it without a second mechanism. It is read once at
/// launch, which is why a change asks for a relaunch instead of pretending to apply.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, vietnamese = "vi", english = "en"

    private static let key = "AppleLanguages"

    var id: String { rawValue }

    var flag: String {
        switch self {
        case .system: return "🌐"
        case .vietnamese: return "🇻🇳"
        case .english: return "🇺🇸"
        }
    }

    /// Each language names itself, so you can find your own even when the UI is
    /// currently in the other one.
    var name: String {
        switch self {
        case .system: return String(localized: "Theo hệ thống")
        case .vietnamese: return "Tiếng Việt"
        case .english: return "English"
        }
    }

    static var current: AppLanguage {
        get {
            // Only an override we wrote ourselves counts. The key is also present when it
            // was inherited from the global domain (that is what "system" means here).
            guard let languages = UserDefaults.standard.persistentDomain(
                forName: Bundle.main.bundleIdentifier ?? "")?[key] as? [String],
                  let first = languages.first,
                  let code = first.split(separator: "-").first
            else { return .system }
            return AppLanguage(rawValue: String(code)) ?? .system
        }
        set {
            switch newValue {
            case .system:
                UserDefaults.standard.removeObject(forKey: key)
            case .vietnamese, .english:
                UserDefaults.standard.set([newValue.rawValue], forKey: key)
            }
        }
    }

    /// Quits and reopens the app. The launch waits for this process to exit, because the
    /// app refuses to run a second copy of itself while the first is still alive.
    static func relaunch() {
        let script = "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; open \"$0\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
