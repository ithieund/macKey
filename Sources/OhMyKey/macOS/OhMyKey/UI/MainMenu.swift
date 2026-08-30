//
//  MainMenu.swift
//  OhMyKey
//
//  The app's menu bar menu - not the status item, the one along the top of the screen
//  while one of our windows is focused.
//
//  The storyboard used to supply this for free. Without it NSApp.mainMenu is nil, and a
//  nil main menu costs you ⌘C, ⌘V, ⌘Z and ⌘W inside every text field, because AppKit
//  routes those through menu key equivalents rather than handling them in NSTextView.
//  Only the items that carry a working shortcut are here; a menu full of greyed-out
//  entries an input method will never implement helps nobody.
//

import AppKit

@objc(OMKMainMenu)
final class MainMenu: NSObject {
    @objc static func install() {
        let appName = "OhMyKey"
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "Giới thiệu \(appName)"),
                        action: #selector(AppDelegate.onAboutSelected), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Cài đặt…"),
                        action: #selector(AppDelegate.onControlPanelSelected), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Ẩn \(appName)"),
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: String(localized: "Thoát \(appName)"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Edit menu - the reason this file exists.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: String(localized: "Sửa"))
        editMenu.addItem(withTitle: String(localized: "Hoàn tác"),
                         action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: String(localized: "Làm lại"),
                         action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "Cắt"),
                         action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Sao chép"),
                         action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Dán"),
                         action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "Chọn tất cả"),
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // Window menu
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: String(localized: "Cửa sổ"))
        windowMenu.addItem(withTitle: String(localized: "Thu nhỏ"),
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: String(localized: "Đóng"),
                           action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}
