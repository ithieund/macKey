//
//  SettingsView.swift
//  OhMyKey
//
//  The control panel. Four panes of grouped settings behind a segmented control, laid out
//  the way System Settings lays out its own panes, over a fixed header that carries the three things people
//  actually come here to change: the mode, the input method and the code table.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    // Remembered across launches, like System Settings. Also lets the preview harness
    // open a given pane: `-SettingsSelectedTab system`.
    @AppStorage("SettingsSelectedTab") private var selectedTab = Tab.typing
    @State private var showResetConfirmation = false

    private enum Tab: String {
        case typing, macro, system, about
    }

    var body: some View {
        VStack(spacing: 0) {
            InputModeHeader()
            Divider()
            // A segmented control rather than TabView: TabView on macOS draws its own
            // bordered box around the content, and a grouped Form inside that box reads as
            // a group inside a group. The picker gives the same four tabs without the frame.
            Picker("", selection: $selectedTab) {
                Text("Bộ gõ").tag(Tab.typing)
                Text("Gõ tắt").tag(Tab.macro)
                Text("Hệ thống").tag(Tab.system)
                Text("Giới thiệu").tag(Tab.about)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 10)
            Group {
                switch selectedTab {
                case .typing: TypingSettings()
                case .macro: MacroSettings()
                case .system: SystemSettings()
                case .about: AboutPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            ActionBar {
                Button("Khôi phục mặc định") { showResetConfirmation = true }
                Spacer()
                Button("Thoát OhMyKey") { NSApp.terminate(nil) }
                Button("Xong") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 460, idealHeight: 560)
        .alert("Khôi phục cấu hình mặc định?", isPresented: $showResetConfirmation) {
            Button("Huỷ", role: .cancel) {}
            Button("Khôi phục", role: .destructive) { OMKBridge.restoreDefaultSettings() }
        } message: {
            Text("Mọi tuỳ chọn sẽ trở về giá trị ban đầu. Danh sách gõ tắt được giữ nguyên.")
        }
    }
}

// MARK: - Header

private struct InputModeHeader: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: Binding(
                get: { settings.vietnameseEnabled },
                set: { settings.vietnameseEnabled = $0 }
            )) {
                Text("Tiếng Việt").tag(true)
                Text("English").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Kiểu gõ")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { settings.inputType },
                        set: { settings.inputType = $0 }
                    )) {
                        ForEach(Array(settings.inputTypeNames.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index)
                        }
                    }
                    .labelsHidden()

                    Text("Bảng mã")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { settings.codeTable },
                        set: { settings.codeTable = $0 }
                    )) {
                        ForEach(Array(settings.tableCodeNames.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Phím chuyển")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        HotkeyField(hotkey: Binding(
                            get: { settings.switchKey },
                            set: { settings.switchKey = $0 }
                        ))
                        Toggle("Kêu bíp", isOn: Binding(
                            get: { settings.switchKey.beep },
                            set: { var key = settings.switchKey; key.beep = $0; settings.switchKey = key }
                        ))
                        .toggleStyle(.checkbox)
                    }
                    .gridCellColumns(3)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Tabs

private struct TypingSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Chính tả") {
                SettingToggle(title: "Kiểm tra chính tả",
                              detail: "Chỉ cho phép các tổ hợp hợp lệ trong tiếng Việt.",
                              isOn: settings.binding(.checkSpelling))
                Group {
                    SettingToggle(title: "Tự khôi phục phím với từ sai",
                                  isOn: settings.binding(.restoreIfInvalidWord))
                    SettingToggle(title: "Cho phép z, w, j, f làm phụ âm",
                                  isOn: settings.binding(.allowConsonantZFWJ))
                    SettingToggle(title: "Tạm tắt kiểm tra chính tả bằng phím ⌃",
                                  isOn: settings.binding(.tempOffSpelling))
                }
                .disabled(!settings.isOn(.checkSpelling))
            }

            Section("Cách gõ") {
                SettingToggle(title: "Đặt dấu kiểu mới",
                              detail: "oà, uý thay cho òa, úy.",
                              isOn: settings.binding(.modernOrthography))
                SettingToggle(title: "Bỏ dấu tự do",
                              detail: "Cho phép đặt dấu ở bất kỳ vị trí nào trong từ.",
                              isOn: settings.binding(.freeMark))
                SettingToggle(title: "Viết hoa chữ cái đầu câu",
                              isOn: settings.binding(.upperCaseFirstChar))
                SettingToggle(title: "Gõ nhanh phụ âm",
                              detail: "cc→ch, gg→gi, kk→kh, nn→ng, qq→qu, pp→ph, tt→th.",
                              isOn: settings.binding(.quickTelex))
            }

            Section("Chuyển chế độ") {
                SettingToggle(title: "Chuyển chế độ thông minh",
                              detail: "Ghi nhớ chế độ gõ riêng cho từng ứng dụng.",
                              isOn: settings.binding(.useSmartSwitchKey))
                SettingToggle(title: "Ghi nhớ bảng mã theo ứng dụng",
                              isOn: settings.binding(.rememberCode))
                SettingToggle(title: "Tạm tắt OhMyKey bằng phím ⌘",
                              isOn: settings.binding(.tempOffOhMyKey))
                SettingToggle(title: "Tắt tiếng Việt khi bàn phím hệ thống không phải tiếng Anh",
                              isOn: settings.binding(.otherLanguage))
            }

            Section("Tương thích") {
                SettingToggle(title: "Sửa lỗi gợi ý",
                              detail: "Dành cho trình duyệt, Excel và các ứng dụng tự động hoàn thành.",
                              isOn: settings.binding(.fixRecommendBrowser))
                SettingToggle(title: "Sửa lỗi trên trình duyệt nhân Chromium",
                              detail: "Thử nghiệm.",
                              isOn: settings.binding(.fixChromiumBrowser))
                    .disabled(!settings.isOn(.fixRecommendBrowser))
                SettingToggle(title: "Tương thích với layout bàn phím khác",
                              detail: "Dvorak, Colemak và các bố cục không phải QWERTY.",
                              isOn: settings.binding(.performLayoutCompat))
            }
        }
        .formStyle(.grouped)
    }
}

private struct MacroSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                SettingToggle(title: "Bật gõ tắt", isOn: settings.binding(.useMacro))
                SettingToggle(title: "Gõ tắt cả khi đang ở chế độ English",
                              isOn: settings.binding(.useMacroInEnglishMode))
                SettingToggle(title: "Tự động viết hoa theo phím tắt",
                              detail: "Gõ VN thay cho vn sẽ cho kết quả viết hoa.",
                              isOn: settings.binding(.autoCapsMacro))
            }

            Section("Gõ tắt phụ âm") {
                SettingToggle(title: "Phụ âm đầu",
                              detail: "f→ph, j→gi, w→qu.",
                              isOn: settings.binding(.quickStartConsonant))
                SettingToggle(title: "Phụ âm cuối",
                              detail: "g→ng, h→nh, k→ch.",
                              isOn: settings.binding(.quickEndConsonant))
            }

            Section {
                Button {
                    WindowManager.shared.showMacros()
                } label: {
                    Label("Mở bảng gõ tắt…", systemImage: "list.bullet.rectangle")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SystemSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var checkingForUpdate = false
    @State private var showRelaunchPrompt = false

    var body: some View {
        Form {
            Section("Khởi động") {
                SettingToggle(title: "Khởi động cùng macOS", isOn: settings.binding(.runOnStartup))
                SettingToggle(title: "Mở bảng điều khiển khi khởi động",
                              isOn: settings.binding(.showUIOnStartup))
            }

            Section("Giao diện") {
                Picker(selection: Binding(
                    get: { AppLanguage.current },
                    set: { language in
                        guard language != AppLanguage.current else { return }
                        AppLanguage.current = language
                        showRelaunchPrompt = true
                    }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: "\(language.flag)  \(language.name)").tag(language)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ngôn ngữ giao diện")
                        Text("Có hiệu lực sau khi khởi động lại OhMyKey.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                SettingToggle(title: "Biểu tượng đơn sắc trên thanh menu",
                              detail: "Tự đổi màu theo giao diện sáng hoặc tối.",
                              isOn: settings.binding(.grayIcon))
                SettingToggle(title: "Hiện biểu tượng trên Dock",
                              detail: "Chỉ hiện khi có cửa sổ đang mở.",
                              isOn: settings.binding(.showIconOnDock))
            }

            Section("Nâng cao") {
                SettingToggle(title: "Gửi từng phím một",
                              detail: "Bật khi có ứng dụng nhận thiếu ký tự.",
                              isOn: settings.binding(.sendKeyStepByStep))
            }

            Section("Cập nhật") {
                SettingToggle(title: "Kiểm tra bản mới khi khởi động",
                              isOn: settings.binding(.checkUpdateOnStartup))
                Button {
                    checkingForUpdate = true
                    OhMyKeyManager.checkNewVersion(NSApp.keyWindow) {
                        checkingForUpdate = false
                    }
                } label: {
                    Label(checkingForUpdate ? "Đang kiểm tra…" : "Kiểm tra bản mới",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(checkingForUpdate)
            }
        }
        .formStyle(.grouped)
        .alert("Khởi động lại OhMyKey để đổi ngôn ngữ?", isPresented: $showRelaunchPrompt) {
            Button("Để sau", role: .cancel) {}
            Button("Khởi động lại") { AppLanguage.relaunch() }
        } message: {
            Text("Ngôn ngữ mới sẽ được dùng ở lần mở tiếp theo.")
        }
    }
}

private struct AboutPane: View {
    var body: some View {
        AboutContent(showsUpdateControls: false)
    }
}
