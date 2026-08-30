---
title: Dock icon lingered after Cmd+W because activation policy was set once at launch
date: 2026-08-30
problem_type: ui_bug
module: macOS/OhMyKey/AppDelegate.m
severity: medium
tags: [macos, dock, activation-policy, lsuielement, menu-bar-app, nswindow]
---

Symptom: with "Hiện biểu tượng trên thanh Dock" on, Cmd+W closed the settings window but the
app icon stayed in the Dock, so the menu-bar app looked half-open.

Root cause: `applicationDidFinishLaunching` set `NSApplicationActivationPolicyRegular` once when
`vShowIconOnDock` was 1 and never revisited it. `LSUIElement=true` in Info.plist only sets the
_initial_ policy (Accessory); after that the policy is whatever code last set.

Resolution: policy is now derived, not stored. `presentWindow:` (used by all four window
openers) switches to Regular before `makeKeyAndOrderFront:`; an `NSWindowWillCloseNotification`
observer re-evaluates via `updateDockIconVisibility` and drops back to Accessory when none of
`_mainWC/_macroWC/_convertWC/_aboutWC` is visible. The `vShowIconOnDock` preference now means
"show the icon while a window is open", not "always".

Gotchas:

- During `NSWindowWillCloseNotification` the window still reports `isVisible == YES`; defer the
  check with `dispatch_async(main)` or the icon never disappears.
- Check `[wc isWindowLoaded]` before touching `wc.window`, otherwise the visibility check itself
  loads the storyboard window.
- Set the policy to Regular _before_ ordering the window front and call
  `activateIgnoringOtherApps:` — switching from Accessory to Regular after the fact leaves the
  window non-key.
- Cmd+Q needs no special handling: main-menu key equivalents (`terminate:`) fire even for an
  Accessory-policy app as long as one of its windows is key.
