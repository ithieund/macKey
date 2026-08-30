//
//  AppSettings.swift
//  OhMyKey
//
//  The observable face of OMKBridge.
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
            forName: .OMKSettingsDidChange,
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

    func isOn(_ toggle: OMKToggle) -> Bool {
        OMKBridge.isOn(toggle)
    }

    func binding(_ toggle: OMKToggle) -> Binding<Bool> {
        Binding(
            get: { OMKBridge.isOn(toggle) },
            set: { OMKBridge.setOn($0, toggle: toggle) }
        )
    }

    // MARK: - Input mode

    var vietnameseEnabled: Bool {
        get { OMKBridge.vietnameseEnabled }
        set {
            guard newValue != OMKBridge.vietnameseEnabled else { return }
            OMKBridge.toggleInputMethod()
        }
    }

    var inputType: Int {
        get { OMKBridge.inputType }
        set { OMKBridge.setInputType(newValue) }
    }

    var codeTable: Int {
        get { OMKBridge.codeTable }
        set { OMKBridge.setCodeTable(newValue) }
    }

    var inputTypeNames: [String] { OMKBridge.inputTypeNames }
    var tableCodeNames: [String] { OMKBridge.tableCodeNames }

    // MARK: - Hotkeys

    var switchKey: Hotkey {
        get { Hotkey(packed: OMKBridge.switchKey) }
        set { OMKBridge.setSwitchKey(newValue.packed) }
    }

    var convertHotKey: Hotkey {
        get { Hotkey(packed: OMKBridge.convertHotKey) }
        set { OMKBridge.setConvertHotKey(newValue.packed) }
    }

    // MARK: - Convert tool

    var convertCase: OMKConvertCase {
        get { OMKBridge.convertCase }
        set { OMKBridge.setConvertCase(newValue) }
    }

    var convertFromCode: Int {
        get { OMKBridge.convertFromCode }
        set { OMKBridge.setConvertFromCode(newValue) }
    }

    var convertToCode: Int {
        get { OMKBridge.convertToCode }
        set { OMKBridge.setConvertToCode(newValue) }
    }

    func swapConvertCodes() {
        let from = OMKBridge.convertFromCode
        OMKBridge.setConvertFromCode(OMKBridge.convertToCode)
        OMKBridge.setConvertToCode(from)
    }

    // MARK: - Macros

    var macros: [OMKMacro] { OMKBridge.macros }

    // MARK: - App info

    var versionSummary: String { OMKBridge.versionSummary }
}

extension OMKMacro: Identifiable {
    public var id: String { text }
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
