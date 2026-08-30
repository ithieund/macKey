//
//  OhMyKeyManager.m
//  OhMyKey
//
//  Created by Tuyen on 1/27/19.
//  Copyright © 2019 Tuyen Mai (OpenKey). Fork: OhMyKey © 2026 Hung Doan. GPL.
//

#import "OhMyKeyManager.h"

extern void OhMyKeyInit(void);

extern CGEventRef OhMyKeyCallback(CGEventTapProxy proxy,
                                  CGEventType type,
                                  CGEventRef event,
                                  void *refcon);

extern NSString* ConvertUtil(NSString* str);

@interface OhMyKeyManager ()

@end

@implementation OhMyKeyManager {

}
static BOOL _isInited = NO;

static CFMachPortRef      eventTap;
static CGEventMask        eventMask;
static CFRunLoopSourceRef runLoopSource;

+(BOOL)isInited {
    return _isInited;
}

+(BOOL)initEventTap {
    if (_isInited)
        return true;
    
    //init OhMyKey
    OhMyKeyInit();
    
    // Create an event tap. We are interested in key presses.
    eventMask = ((1 << kCGEventKeyDown) |
                 (1 << kCGEventKeyUp) |
                 (1 << kCGEventFlagsChanged) |
                 (1 << kCGEventLeftMouseDown) |
                 (1 << kCGEventRightMouseDown) |
                 (1 << kCGEventLeftMouseDragged) |
                 (1 << kCGEventRightMouseDragged));
    
    eventTap = CGEventTapCreate(kCGSessionEventTap,
                                kCGHeadInsertEventTap,
                                0,
                                eventMask,
                                OhMyKeyCallback,
                                NULL);
    
    if (!eventTap) {
        
        fprintf(stderr, "failed to create event tap\n");
        return NO;
    }
    
    _isInited = YES;
    
    // Create a run loop source.
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    
    // Add to the current run loop.
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    
    // Enable the event tap.
    CGEventTapEnable(eventTap, true);
    
    return YES;
}

+(BOOL)stopEventTap {
    if (_isInited) { //release all object
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
        runLoopSource = nil;
        
        CFMachPortInvalidate(eventTap);
        CFRelease(eventTap);
        eventTap = nil;
        
        _isInited = false;
    }
    return YES;
}

+(NSArray*)getTableCodes {
    return [[NSArray alloc] initWithObjects:
            @"Unicode",
            @"TCVN3 (ABC)",
            @"VNI Windows",
            NSLocalizedString(@"Unicode tổ hợp", nil),
            @"Vietnamese Locale CP 1258", nil];
}

+(NSString*)getBuildDate {
    return [NSString stringWithUTF8String:__DATE__];
}

#pragma mark -Convert feature
+(BOOL)quickConvert {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSString *htmlString = [pasteboard stringForType:NSPasteboardTypeHTML];
    NSString *rawString = [pasteboard stringForType:NSPasteboardTypeString];
    bool converted = false;
    if (htmlString != nil) {
        htmlString = ConvertUtil(htmlString);
        converted = true;
    }
    if (rawString != nil) {
        rawString = ConvertUtil(rawString);
        converted = true;
    }
    if (converted) {
        [pasteboard clearContents];
        if (htmlString != nil)
            [pasteboard setString:htmlString forType:NSPasteboardTypeHTML];
        if (rawString != nil)
            [pasteboard setString:rawString forType:NSPasteboardTypeString];
        
        return YES;
    }
    return NO;
}

+(void)showMessage:(NSWindow*)window message:(NSString*)msg subMsg:(NSString*)subMsg {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:msg];
    [alert setInformativeText:subMsg];
    [alert addButtonWithTitle:@"OK"];
    if (window) {
        [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        }];
    } else {
        [alert runModal];
    }
}

#pragma mark -AutoUpdate feature

+(void)checkNewVersion:(NSWindow*)parent callbackFunc:(CheckNewVersionCallback) callback {
    //load new version config
    NSURLSession *aSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    [[aSession dataTaskWithURL:[NSURL URLWithString:@"https://raw.githubusercontent.com/hungdoansy/OhMyKey/master/version.json"] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (((NSHTTPURLResponse *)response).statusCode == 200) {
            if (data) {
                if(NSClassFromString(@"NSJSONSerialization")) {
                    NSError *error = nil;
                    id object = [NSJSONSerialization
                                 JSONObjectWithData:data
                                 options:0
                                 error:&error];
                    
                    if(error) {  }
                    if([object isKindOfClass:[NSDictionary class]]) {
                        NSDictionary *results = object;
                        NSDictionary *ver = [results valueForKey:@"latestVersion"];
                        NSString* versionCodeString = [ver valueForKey:@"versionCode"];
                        int versionCode = (int)[versionCodeString integerValue];
                        int currentVersionCode = (int)[((NSString*)[[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleVersion"]) integerValue];
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (callback != nil) {
                                callback();
                            }
                            if (versionCode > currentVersionCode || callback != nil) {
                                [self showUpdateMessage:parent needUpdating:versionCode > currentVersionCode newVersion:[ver valueForKey:@"versionName"]];
                            }
                        });
                    }
                    else {
                        //oh my god
                    }
                }
                else {
                    //can not parse json
                }
            }
        }
    }] resume];
}

+(void)showUpdateMessage:(NSWindow*)parent needUpdating:(BOOL)needUpdating newVersion:(NSString*)versionString {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:(needUpdating ? [NSString stringWithFormat:NSLocalizedString(@"OhMyKey Có phiên bản mới (%@), bạn có muốn cập nhật không?", nil), versionString] : NSLocalizedString(@"Bạn đang dùng phiên bản mới nhất!", nil))];
    [alert setInformativeText:(needUpdating ? NSLocalizedString(@"Bấm 'Có' để cập nhật OhMyKey.", nil) : @"")];
    
    if (!needUpdating) {
        [alert addButtonWithTitle:@"OK"];
    } else {
        [alert addButtonWithTitle:NSLocalizedString(@"Có", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"Không", nil)];
    }
    if (parent == nil) {
        [alert.window makeKeyAndOrderFront:nil];
        [alert.window setLevel:NSStatusWindowLevel];
        NSModalResponse res = [alert runModal];
        if (res == 1000 && needUpdating) {
            [self launchUpdateHelper];
        }
    } else {
        [alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse returnCode) {
            if (returnCode == 1000 && needUpdating) {
                [self launchUpdateHelper];
            }
        }];
    }
}

+(void)launchUpdateHelper {
    //check update app has exist or not
    NSError *copyError = nil;
    NSString* target = [NSString stringWithFormat:@"%@/OhMyKeyUpdate.app", [self getApplicationSupportFolder]];
    [[NSFileManager defaultManager] removeItemAtPath:target error:&copyError];
    if (![[NSFileManager defaultManager] fileExistsAtPath:target]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:[self getApplicationSupportFolder] withIntermediateDirectories:YES attributes:nil error:nil];
        
        if (![[NSFileManager defaultManager] copyItemAtPath:[self getUpdateBundlePath] toPath:target error:&copyError]) {
            NSLog(@"Error on copy");
        }
    }
    
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSURL *url = [NSURL fileURLWithPath:[workspace fullPathForApplication:target]];
    NSError *error = nil;
    NSArray *arguments = [NSArray arrayWithObjects: @"yeah", nil];
    [workspace launchApplicationAtURL:url options:0 configuration:[NSDictionary dictionaryWithObject:arguments forKey:NSWorkspaceLaunchConfigurationArguments] error:&error];
    
    [NSApp terminate:0]; //exit main app
}

+(NSString*)getApplicationSupportFolder {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *applicationSupportDirectory = [paths firstObject];
    return [NSString stringWithFormat:@"%@/OhMyKey", applicationSupportDirectory];
}

+(NSString*)getUpdateBundlePath {
    NSString *currentpath = [[NSBundle mainBundle] bundlePath];
    return [NSString stringWithFormat:@"%@/Contents/Library/LoginItems/OhMyKeyUpdate.app", currentpath];
}
@end
