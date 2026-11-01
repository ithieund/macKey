//
//  MacKeyManager.h
//  macKey
//
//  Created by Tuyen on 1/27/19.
//  Copyright © 2019 Tuyen Mai (OpenKey). Additional changes © 2026 Hung Doan. GPL.
//

#ifndef MacKeyManager_h
#define MacKeyManager_h

#import <Cocoa/Cocoa.h>

typedef void (^CheckNewVersionCallback)(void);

@interface MacKeyManager : NSObject
+(BOOL)isInited;
+(BOOL)initEventTap;
+(BOOL)stopEventTap;
/// macOS disables a tap that takes too long to process an event (and in a few
/// session transitions). Re-enable the existing tap instead of leaving input
/// conversion silently inactive.
+(void)reenableEventTap;
/// Stops the temporary system Vietnamese input source immediately if its opt-in
/// Secure Input fallback has just been turned off.
+(void)secureInputFallbackSettingDidChange;
/// While Secure Input is active, follows Smart Switch by selecting the
/// corresponding built-in macOS Vietnamese or English input source.
+(void)syncSecureInputFallbackWithVietnameseEnabled:(BOOL)enabled;
/// Re-checks Secure Input after a session transition. When macOS has released
/// it, restores the keyboard source that was active before the fallback.
+(void)refreshSecureInputState;
/// Performs the Secure Input check used when OpenKey starts or restarts.
+(void)checkSecureInputStateAtLaunch;

+(NSArray*)getTableCodes;

+(NSString*)getBuildDate;
+(void)showMessage:(NSWindow*)window message:(NSString*)msg subMsg:(NSString*)subMsg;

+(BOOL)quickConvert;

+(void)checkNewVersion:(NSWindow*)parent callbackFunc:(CheckNewVersionCallback) callback;
@end

#endif /* MacKeyManager_h */
