//
//  MacKey-Bridging-Header.h
//  macKey
//
//  What Swift is allowed to see of the Objective-C side.
//
//  Deliberately short: the engine headers (Engine.h, Macro.h, ConvertTool.h) are C++
//  and cannot appear here at all. Everything Swift needs from the engine goes through
//  MacKeyBridge.h, which is plain Objective-C on the outside and C++ on the inside.
//

#import "MacKeyBridge.h"
#import "MacKeyManager.h"
#import "AppDelegate.h"
#import "MJAccessibilityUtils.h"
