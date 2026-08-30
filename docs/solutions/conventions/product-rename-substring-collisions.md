---
title: A product-wide rename collides with API names and breaks identifier pairs
date: 2026-08-30
problem_type: convention
module: repo-wide (macOS + win32 + Xcode/MSBuild project files)
severity: high
tags: [rename, branding, sed, win32-api, storyboard, nsuserdefaults, registry]
---

Renaming the product OpenKey -> OhMyKey with one case-preserving substitution pass over
every text file looks safe and mostly is, but it broke the Windows build in a way no
grep for "OpenKey" would flag afterwards: the Win32 API `RegOpenKeyEx` contains the old
product name as a substring, so it became `RegOhMyKeyEx`
(`Sources/OhMyKey/win32/OhMyKey/OhMyKey/OhMyKeyHelper.cpp`). Nothing on macOS catches
this, because the Windows sources are only compiled by the msbuild CI workflow.

The check that finds it is to grep for the _new_ name spliced mid-token rather than for
the old name:

    grep -rnoE '[A-Za-z_]+OhMyKey[A-Za-z_]*' Sources/ --include='*.cpp' --include='*.h'

and then confirm every hit is one of our own identifiers. Everything else in that output
(`vTempOffOhMyKey`, `onOhMyKeyExit`, `_OhMyKeyUpdate`, `TheOhMyKeyProject`) was
intentional; only the `Reg*` one was an API.

The second class of breakage is silent at build time and only shows up at runtime,
because these pairs are matched by string, not by the compiler:

- `Main.storyboard` `storyboardIdentifier` vs `instantiateControllerWithIdentifier:`
  (a mismatch throws when the window is opened, not at launch)
- storyboard `action selector=` / `outlet property=` vs the IBAction and IBOutlet names
  (`onTempOffOhMyKeyByHotKey:`, `TempOffOhMyKey`) - a mismatch is an unrecognized
  selector or an NSUnknownKeyException
- `OHMYKEY_BUNDLE` in `AppDelegate.h` vs `PRODUCT_BUNDLE_IDENTIFIER` in the pbxproj -
  drift here quietly disables the single-instance check and the "ignore our own app"
  filter in `OhMyKey.mm`
- the Windows executable name vs the hardcoded `OhMyKey64.exe` / `OhMyKey32.exe`
  self-detection in `OhMyKeyHelper.cpp`, which decides whether a window belongs to us

Both `LOAD_DATA` on macOS and `APP_GET_DATA`/`APP_SET_DATA` on Windows stringify the
variable name, so renaming the C variable `vTempOffOpenKey` also renames the persisted
key - which is why the migration has to map that one name explicitly.

Two strings must survive a rename untouched: the macro file header in
`Sources/OhMyKey/engine/Macro.cpp` (an on-disk format marker shared with UniKey) and the
legacy identifiers the migration reads (`com.tuyenmai.openkey`,
`HKCU\SOFTWARE\TuyenMai\OpenKey`, `vTempOffOpenKey`). Excluding README/CHANGELOG from the
pass is also worth it: the substitution inverts attribution sentences, turning "credit
the original OpenKey" into "credit OhMyKey".
