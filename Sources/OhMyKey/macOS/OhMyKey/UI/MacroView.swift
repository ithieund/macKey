//
//  MacroView.swift
//  OhMyKey
//
//  The gõ tắt (text expansion) list.
//
//  Selecting a row loads it into the editor and the add button becomes a save button,
//  which is how the old window worked - it is a good fit for a list where the shortcut
//  itself is the identity, so "edit" and "add the same shortcut again" are one action.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MacroView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var shortcut = ""
    @State private var expansion = ""
    @State private var selection: OMKMacro.ID?
    @State private var pendingImportURL: URL?

    private var macros: [OMKMacro] { settings.macros }

    private var isEditingExisting: Bool {
        !shortcut.isEmpty && OMKBridge.hasMacro(shortcut)
    }

    private var canSave: Bool {
        !shortcut.trimmingCharacters(in: .whitespaces).isEmpty && !expansion.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            table
            Divider()
            editor
            Divider()
            ActionBar {
                Button {
                    chooseFileToImport()
                } label: {
                    Label("Nhập từ tệp…", systemImage: "square.and.arrow.down")
                }
                Button {
                    chooseFileToExport()
                } label: {
                    Label("Xuất ra tệp…", systemImage: "square.and.arrow.up")
                }
                Spacer()
                Toggle("Tự động viết hoa", isOn: settings.binding(.autoCapsMacro))
                    .toggleStyle(.checkbox)
            }
        }
        .frame(minWidth: 520, idealWidth: 620, minHeight: 400, idealHeight: 480)
        .onChange(of: selection) { newValue in
            guard let macro = macros.first(where: { $0.id == newValue }) else { return }
            shortcut = macro.text
            expansion = macro.content
        }
        .alert("Nhập dữ liệu gõ tắt",
               isPresented: Binding(get: { pendingImportURL != nil },
                                    set: { if !$0 { pendingImportURL = nil } })) {
            Button("Giữ lại danh sách hiện tại") { performImport(keepingExisting: true) }
            Button("Thay thế toàn bộ", role: .destructive) { performImport(keepingExisting: false) }
            Button("Huỷ", role: .cancel) { pendingImportURL = nil }
        } message: {
            Text("Bạn muốn giữ các mục đang có hay thay thế bằng nội dung trong tệp?")
        }
    }

    // Empty state instead of the table, not on top of it: an inset Table still paints its
    // alternating rows when it has no content, which showed through the placeholder.
    @ViewBuilder
    private var table: some View {
        if macros.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("Chưa có mục gõ tắt nào")
                    .foregroundStyle(.secondary)
                Text("Nhập từ viết tắt và nội dung đầy đủ bên dưới để thêm mục đầu tiên.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(macros, selection: $selection) {
                TableColumn("Từ gõ tắt", value: \.text)
                TableColumn("Nội dung đầy đủ", value: \.content)
            }
            .tableStyle(.inset)
        }
    }

    private var editor: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Từ gõ tắt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("vd: vn", text: $shortcut)
                    .frame(minWidth: 100, idealWidth: 130)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Nội dung đầy đủ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("vd: Việt Nam", text: $expansion)
            }
            Button {
                save()
            } label: {
                Label(isEditingExisting ? "Lưu" : "Thêm", systemImage: isEditingExisting ? "checkmark" : "plus")
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!canSave)

            Button {
                delete()
            } label: {
                Label("Xoá", systemImage: "minus")
            }
            .disabled(!isEditingExisting)
        }
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func save() {
        let key = shortcut.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !expansion.isEmpty else { return }
        OMKBridge.setMacro(key, content: expansion)
        clearEditor()
    }

    private func delete() {
        OMKBridge.deleteMacro(shortcut)
        clearEditor()
    }

    private func clearEditor() {
        shortcut = ""
        expansion = ""
        selection = nil
    }

    private func performImport(keepingExisting: Bool) {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        OMKBridge.importMacros(fromPath: url.path, keepingExisting: keepingExisting)
    }

    // AppKit panels rather than fileImporter/fileExporter: the engine reads and writes
    // these files itself with C++ streams, so there is no document for SwiftUI to carry,
    // and the panels need raising above the floating window level the app uses.
    private func chooseFileToImport() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Chọn tệp dữ liệu gõ tắt")
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.level = .statusBar
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingImportURL = url
    }

    private func chooseFileToExport() {
        let panel = NSSavePanel()
        panel.message = String(localized: "Chọn nơi lưu dữ liệu gõ tắt")
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "OhMyKeyMacro"
        panel.canCreateDirectories = true
        panel.level = .statusBar
        guard panel.runModal() == .OK, let url = panel.url else { return }
        OMKBridge.exportMacros(toPath: url.path)
    }
}
