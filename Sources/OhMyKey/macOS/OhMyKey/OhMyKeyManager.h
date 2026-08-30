//
//  OhMyKeyManager.h
//  OhMyKey
//
//  Created by Tuyen on 1/27/19.
//  Copyright © 2019 Tuyen Mai (OpenKey). Fork: OhMyKey © 2026 Hung Doan. GPL.
//

#ifndef OhMyKeyManager_h
#define OhMyKeyManager_h

#import <Cocoa/Cocoa.h>

typedef void (^CheckNewVersionCallback)(void);

@interface OhMyKeyManager : NSObject
+(BOOL)isInited;
+(BOOL)initEventTap;
+(BOOL)stopEventTap;

+(NSArray*)getTableCodes;

+(NSString*)getBuildDate;
+(void)showMessage:(NSWindow*)window message:(NSString*)msg subMsg:(NSString*)subMsg;

+(BOOL)quickConvert;

+(void)checkNewVersion:(NSWindow*)parent callbackFunc:(CheckNewVersionCallback) callback;
@end

#endif /* OhMyKeyManager_h */
