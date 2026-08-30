//
//  AboutView.swift
//  OhMyKey
//
//  Shared by the standalone About window and the "Giới thiệu" tab of the control panel,
//  so the two cannot drift apart the way the old storyboard's two copies did.
//

import SwiftUI

struct AboutContent: View {
    var showsUpdateControls = true

    @EnvironmentObject private var settings: AppSettings
    @State private var checkingForUpdate = false

    private var appIcon: NSImage {
        NSApp.applicationIconImage ?? NSImage(named: "Icon") ?? NSImage()
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("OhMyKey")
                    .font(.title.weight(.semibold))
                Text("Bộ gõ tiếng Việt cho macOS")
                    .foregroundStyle(.secondary)
                Text(settings.versionSummary)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 16) {
                ExternalLink(title: String(localized: "Mã nguồn"),
                             url: "https://github.com/hungdoansy/OhMyKey")
                ExternalLink(title: String(localized: "Bản phát hành"),
                             url: "https://github.com/hungdoansy/OhMyKey/releases")
            }

            if showsUpdateControls {
                VStack(spacing: 10) {
                    Toggle("Kiểm tra bản mới khi khởi động",
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

            Text("Phát triển từ OpenKey của Mai Vũ Tuyên. Phát hành theo giấy phép GPL.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(minWidth: 360, maxWidth: 460)
    }
}

struct AboutView: View {
    var body: some View {
        AboutContent()
    }
}
