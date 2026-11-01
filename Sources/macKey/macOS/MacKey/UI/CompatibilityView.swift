//
//  CompatibilityView.swift
//  MacKey
//
//  Compatibility controls and per-application replacement delivery settings.
//

import SwiftUI

struct CompatibilityView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var applications: [MacKeyApplicationKeyMode] = []
    @State private var keyDeliveryModes: [String: MacKeyApplicationKeyDeliveryMode] = [:]
    @State private var searchText = ""

    private var filteredApplications: [MacKeyApplicationKeyMode] {
        guard !searchText.isEmpty else { return applications }
        return applications.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Tương thích") {
                    SettingToggle(title: "Sửa lỗi gợi ý",
                                  detail: "Dành cho trình duyệt, Excel và các ứng dụng tự động hoàn thành.",
                                  isOn: settings.binding(.fixRecommendBrowser))
                    SettingToggle(title: "Tương thích với layout bàn phím khác",
                                  detail: "Hỗ trợ Dvorak, Colemak và các bố cục không phải QWERTY.",
                                  isOn: settings.binding(.performLayoutCompat))
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                CompatibilitySectionHeader("Applications")

                if applications.isEmpty {
                    Text("Apps appear here after they are activated while Smart Switch is enabled.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                } else {
                    TextField("Search applications", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 20)

                    // Keep this snapshot in SwiftUI state. Repeatedly crossing the
                    // Objective-C++ bridge while a Table is scrolling caused visible lag.
                    Table(filteredApplications) {
                        TableColumn("Name") { application in
                            HStack(spacing: 8) {
                                Image(nsImage: application.icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(application.name)
                                    Text(application.bundleIdentifier)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .width(min: 260, ideal: 340)

                        TableColumn("Key Mode") { application in
                            Picker("Key Mode", selection: keyModeBinding(for: application)) {
                                Text("Default").tag(MacKeyApplicationKeyDeliveryMode.default)
                                Text("Send key-by-key").tag(MacKeyApplicationKeyDeliveryMode.keyByKey)
                                Text("Clipboard paste").tag(MacKeyApplicationKeyDeliveryMode.clipboardPaste)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 154)
                        }
                        .width(min: 150, ideal: 160, max: 170)
                    }
                    .tableStyle(.bordered)
                    .frame(minHeight: 230, idealHeight: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
                    )
                    // Full-width rows should fill the shared content area, not
                    // bleed to the window edge beyond the section margins.
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .padding(.top, 16)
        }
        .onAppear(perform: reloadApplications)
        // A newly activated Smart Switch app is recorded outside SwiftUI.
        // Refresh this snapshot immediately when the bridge publishes it, so
        // an already-open control panel gains the row without being reopened.
        .onReceive(settings.objectWillChange) { _ in
            reloadApplications()
        }
    }

    private func reloadApplications() {
        let snapshot = settings.applicationKeyModes
        applications = snapshot
        keyDeliveryModes = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.bundleIdentifier, $0.keyDeliveryMode) })
    }

    private func keyModeBinding(for application: MacKeyApplicationKeyMode) -> Binding<MacKeyApplicationKeyDeliveryMode> {
        Binding(
            get: { keyDeliveryModes[application.bundleIdentifier] ?? application.keyDeliveryMode },
            set: { mode in
                keyDeliveryModes[application.bundleIdentifier] = mode
                MacKeyBridge.setKeyDeliveryMode(mode, forApplication: application.bundleIdentifier)
            }
        )
    }
}

private struct CompatibilitySectionHeader: View {
    private let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 28)
    }
}
