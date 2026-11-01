//
//  ConvertToolView.swift
//  MacKey
//
//  Re-encodes whatever is on the clipboard between Vietnamese code tables.
//
//  The four letter-case options are one picker here. They were four checkboxes that each
//  had to remember to switch the other three off - the same rule written four times.
//

import SwiftUI

struct ConvertToolView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var resultMessage: ResultMessage?

    private struct ResultMessage: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                // Labels above their pickers rather than beside them: a grouped Form pushes
                // a row's label and control to opposite edges, which left "Từ" and "Sang"
                // stranded halfway across the window from the menus they name.
                Section("Bảng mã") {
                    HStack(alignment: .bottom, spacing: 12) {
                        codePicker("Từ", selection: Binding(
                            get: { settings.convertFromCode },
                            set: { settings.convertFromCode = $0 }
                        ))
                        Button {
                            settings.swapConvertCodes()
                        } label: {
                            Image(systemName: "arrow.left.arrow.right")
                        }
                        .help("Đảo chiều chuyển mã")
                        .accessibilityLabel("Đảo chiều chuyển mã")
                        .padding(.bottom, 1)
                        codePicker("Sang", selection: Binding(
                            get: { settings.convertToCode },
                            set: { settings.convertToCode = $0 }
                        ))
                    }
                }

                Section("Biến đổi thêm") {
                    Picker("Chữ hoa, chữ thường", selection: Binding(
                        get: { settings.convertCase },
                        set: { settings.convertCase = $0 }
                    )) {
                        Text("Giữ nguyên").tag(MacKeyConvertCase.unchanged)
                        Text("CHỮ HOA TOÀN BỘ").tag(MacKeyConvertCase.allCaps)
                        Text("chữ thường toàn bộ").tag(MacKeyConvertCase.allLower)
                        Text("Hoa chữ đầu câu").tag(MacKeyConvertCase.firstLetter)
                        Text("Hoa Chữ Đầu Mỗi Từ").tag(MacKeyConvertCase.eachWord)
                    }
                    SettingToggle(title: "Loại bỏ dấu tiếng Việt",
                                  isOn: settings.binding(.convertRemoveMark))
                    SettingToggle(title: "Thông báo khi chuyển xong",
                                  isOn: settings.binding(.convertAlertWhenCompleted))
                }

                Section("Phím tắt chuyển mã nhanh") {
                    HotkeyField(hotkey: Binding(
                        get: { settings.convertHotKey },
                        set: { settings.convertHotKey = $0 }
                    ))
                    Text("Sao chép đoạn văn bản rồi nhấn phím tắt để chuyển mã ngay trong clipboard.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)

            Divider()
            ActionBar {
                Spacer()
                Button("Đóng") { NSApp.keyWindow?.performClose(nil) }
                Button {
                    convert()
                } label: {
                    Label("Chuyển mã clipboard", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 420, idealHeight: 480)
        .alert(item: $resultMessage) { message in
            Alert(title: Text(message.title), message: Text(message.detail),
                  dismissButton: .default(Text("OK")))
        }
    }

    private func codePicker(_ title: LocalizedStringKey, selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: selection) {
                ForEach(Array(settings.tableCodeNames.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index)
                }
            }
            .labelsHidden()
        }
    }

    private func convert() {
        if MacKeyBridge.convertClipboard() {
            guard settings.isOn(.convertAlertWhenCompleted) else { return }
            resultMessage = ResultMessage(title: "Đã chuyển mã",
                                          detail: "Kết quả được lưu lại trong clipboard.")
        } else {
            resultMessage = ResultMessage(title: "Clipboard đang trống",
                                          detail: "Hãy sao chép một đoạn văn bản rồi thử lại.")
        }
    }
}
