---
title: TabView on macOS draws a bordered box, so a grouped Form inside it reads as a nested group
date: 2026-08-30
problem_type: ui_bug
module: Sources/OhMyKey/macOS/OhMyKey/UI (SettingsView)
severity: low
tags: [swiftui, macos, tabview, form, grouped, segmented-picker, applelanguages, relaunch]
---

The settings window showed a rounded box right under the four tabs, with the grouped
form's own rounded sections inside it: a group inside a group.

The outer box is `TabView`'s doing. On macOS the automatic tab style is an `NSTabView`
with a bordered content area, and there is no borderless variant before macOS 15. Any
`Form.formStyle(.grouped)` placed inside it gets that frame for free.

Fix (`UI/SettingsView.swift`): drop `TabView`, use a segmented `Picker` bound to the same
`Tab` enum and `switch` on it to pick the pane. The picker needs `.fixedSize()` or it
stretches across the window. The selection lives in `@AppStorage("SettingsSelectedTab")`,
so `Tab` is `String`-backed; that also lets the preview harness open a pane with
`./scripts/preview-ui.sh -- -SettingsSelectedTab system`.

Related decision in the same change - the UI-language picker (`AppLanguage` in
`UI/AppSettings.swift`):

- It writes `AppleLanguages` rather than a private key, so SwiftUI `Text`,
  `String(localized:)` and the Objective-C `NSLocalizedString` menu all follow it with no
  second mechanism. The cost is that the value is read once at launch, so the picker
  honestly asks for a relaunch instead of half-applying.
- Read the override from `persistentDomain(forName: bundleIdentifier)`, not
  `UserDefaults.standard.array(forKey:)`: the standard lookup also returns the inherited
  global-domain value, which would make "follow system" indistinguishable from an explicit
  choice.
- Relaunching cannot be `open -n` + `terminate`: `AppDelegate` refuses to run while
  another instance is alive and would kill the new copy. Spawn `/bin/sh -c 'while kill -0
$PID; do sleep 0.1; done; open "$APP"'` first, then terminate; the child outlives us.
