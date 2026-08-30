---
title: Adding Swift to the Objective-C++ macOS target fails four different ways
date: 2026-08-30
problem_type: build_error
module: Sources/OhMyKey/macOS (Xcode target OhMyKey)
severity: medium
tags: [swift, objective-cpp, bridging-header, xcodebuild, linker, extern-c, pbxproj]
---

Turning on Swift in this target - a 2019 Objective-C/Objective-C++ app that links a C++
engine - produced four failures in a row, each with an error message that pointed
somewhere other than the cause.

**`'ViewController.h' file not found` while compiling the bridging header.** The bridging
header is compiled as part of every Swift file's import, so anything it reaches
transitively must exist and must be C or Objective-C. Two consequences: the engine headers
(`Engine.h`, `Macro.h`, `ConvertTool.h`) can never appear in it - they are C++, they use
`std::string`/`std::vector` and `using namespace std` - and `AppDelegate.h` had to stop
importing view-controller headers. That constraint is the whole reason `OhMyKeyBridge.h/.mm`
exists: plain Objective-C on the outside, C++ on the inside.

**The bridging header is silently ignored unless modules are on.** The target carried
`CLANG_ENABLE_MODULES = NO` (the project level said `YES`; the target overrode it). Swift's
clang importer needs modules, and the generated `OhMyKey-Swift.h` emits `@import`. Removing
the target-level override was the fix.

**`Undefined symbols: MJAccessibilityIsEnabled()` - with the parentheses.** The trailing
`()` in a linker error is the tell that C++ name mangling is involved. `MJAccessibilityUtils.h`
declared plain C functions with no `extern "C"` guard; it had only ever been included from
`.m` files, so nothing noticed until an `.mm` file included it. Same for the engine entry
points `OhMyKeyInit` and `OnSpellCheckingChanged`, which `OhMyKey.mm` defines inside an
`extern "C"` block - a bare `extern void OhMyKeyInit(void);` in another `.mm` looks for the
mangled name.

**`ld: warning: ignoring duplicate libraries: '-lc++'`.** `OTHER_LDFLAGS` was
`("-lc++\n-lc++")` - a literal newline inside a single string, so the linker had been
receiving one malformed flag for years. It can simply be deleted: the driver for a target
containing `.cpp`/`.mm` is `clang++`, which links libc++ on its own.

The gotcha worth remembering is the ordering: these surface one at a time, and the first
three all present as "Swift is not seeing the Objective-C side" when only the second one
actually is. Also note the project file was edited as text (`/tmp/pbx.py` in that session's
transcript, since no `xcodeproj` gem is installed here) - after any such edit,
`plutil -lint OhMyKey.xcodeproj/project.pbxproj` catches a mangled file far faster than
xcodebuild does, and a multi-line build-setting value will not be matched by a
single-line regex, which is how `OTHER_LDFLAGS` briefly ended up defined twice.
