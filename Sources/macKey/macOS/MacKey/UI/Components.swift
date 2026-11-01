//
//  Components.swift
//  MacKey
//
//  The handful of controls every screen shares.
//
//  Nothing here sets an explicit width. The old UI pinned every checkbox to a hand-measured
//  frame, which is why half its longer Vietnamese labels were truncated mid-word; letting
//  the layout system size things is the entire point of the rewrite.
//

import SwiftUI

/// A switch with a title and, when a setting needs one, a quieter line of explanation
/// underneath. The explanation is where the long enumerations live ("cc=ch, gg=gi, ...")
/// that used to be crammed into the label itself.
struct SettingToggle: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    var richDetail: Text?
    @Binding var isOn: Bool

    init(title: LocalizedStringKey, detail: LocalizedStringKey? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self.richDetail = nil
        self._isOn = isOn
    }

    init(title: LocalizedStringKey, detail: Text, isOn: Binding<Bool>) {
        self.title = title
        self.detail = nil
        self.richDetail = detail
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let richDetail {
                    richDetail
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .controlSize(.small)
    }
}

/// The ⌃⌥⌘⇧ row.
///
/// Drawn rather than assembled from Toggle(.button): AppKit greys out control tint in a
/// window that is not key, which made "this modifier is part of the shortcut" invisible
/// exactly when you are looking at a screenshot or a background window. Filling the shape
/// ourselves keeps the state readable whatever the window is doing.
struct ModifierPicker: View {
    @Binding var hotkey: Hotkey

    var body: some View {
        HStack(spacing: 6) {
            chip("⌃", label: "Control", isOn: $hotkey.control)
            chip("⌥", label: "Option", isOn: $hotkey.option)
            chip("⌘", label: "Command", isOn: $hotkey.command)
            chip("⇧", label: "Shift", isOn: $hotkey.shift)
        }
    }

    private func chip(_ glyph: String, label: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(glyph)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 22)
        }
        .buttonStyle(ModifierChipStyle(isOn: isOn.wrappedValue))
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn.wrappedValue ? [.isSelected] : [])
        .help(label)
    }
}

private struct ModifierChipStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isOn ? Color.accentColor : Color(nsColor: .controlColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: isOn ? 0 : 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Modifiers plus the key itself, laid out as one control.
struct HotkeyField: View {
    @Binding var hotkey: Hotkey

    var body: some View {
        HStack(spacing: 8) {
            ModifierPicker(hotkey: $hotkey)
            // Without fixedSize the NSView stretches to fill whatever cell it lands in.
            HotkeyRecorder(hotkey: $hotkey)
                .frame(width: 68, height: 24)
                .fixedSize()
        }
    }
}

/// A link that looks like a link and opens in the browser. `Link` would do, but these
/// URLs are also shown as their own labels elsewhere, so the call sites read better with
/// the title and destination separate.
struct ExternalLink: View {
    let title: String
    let url: String

    var body: some View {
        Button(title) {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        }
        .buttonStyle(.link)
    }
}

/// Row of trailing-aligned buttons across the bottom of a window, above the window edge.
struct ActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
