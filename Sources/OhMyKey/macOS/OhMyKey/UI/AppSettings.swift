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
