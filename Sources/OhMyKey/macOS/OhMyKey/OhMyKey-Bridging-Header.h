//
//  OhMyKey-Bridging-Header.h
//  OhMyKey
//
//  What Swift is allowed to see of the Objective-C side.
//
//  Deliberately short: the engine headers (Engine.h, Macro.h, ConvertTool.h) are C++
//  and cannot appear here at all. Everything Swift needs from the engine goes through
//  OhMyKeyBridge.h, which is plain Objective-C on the outside and C++ on the inside.
//

#import "OhMyKeyBridge.h"
#import "OhMyKeyManager.h"
#import "AppDelegate.h"
#import "MJAccessibilityUtils.h"
