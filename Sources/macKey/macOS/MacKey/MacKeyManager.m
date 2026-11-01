//
//  MacKeyManager.m
//  macKey
//
//  Created by Tuyen on 1/27/19.
//  Copyright © 2019 Tuyen Mai (OpenKey). Additional changes © 2026 Hung Doan. GPL.
//

#import "MacKeyManager.h"
#import "AppDelegate.h"
#import <IOKit/IOKitLib.h>
#import <Carbon/Carbon.h>

extern void MacKeyInit(void);

extern CGEventRef MacKeyCallback(CGEventTapProxy proxy,
                                  CGEventType type,
                                  CGEventRef event,
                                  void *refcon);

extern NSString* ConvertUtil(NSString* str);

@interface MacKeyManager ()

+(void)logSecureInputStateIfChanged;

@end

@implementation MacKeyManager {

}
static BOOL _isInited = NO;

static CFMachPortRef      eventTap;
static CGEventMask        eventMask;
static CFRunLoopSourceRef runLoopSource;
static dispatch_source_t  eventTapWatchdog;
static dispatch_source_t  clipboardMonitor;
static NSInteger          observedClipboardChangeCount;
static pid_t              reportedSecureInputPID;
static NSString           *secureInputPreviousSourceID;
static NSString           *secureInputVietnameseSourceID;

// Secure Input intentionally hides keyboard events from session event taps.
// The window server publishes the current console session in IOResources. This
// is read only and diagnostic-only: OpenKey never changes Secure Input state.
static pid_t secureInputPID(void) {
    io_service_t resources = IOServiceGetMatchingService(kIOMainPortDefault,
                                                         IOServiceMatching("IOResources"));
    if (resources == IO_OBJECT_NULL) return 0;

    CFTypeRef consoleUsers = IORegistryEntryCreateCFProperty(resources,
                                                               CFSTR("IOConsoleUsers"),
                                                               kCFAllocatorDefault,
                                                               0);
    IOObjectRelease(resources);
    if (consoleUsers == NULL || CFGetTypeID(consoleUsers) != CFArrayGetTypeID()) {
        if (consoleUsers != NULL) CFRelease(consoleUsers);
        return 0;
    }

    pid_t pid = 0;
    for (NSDictionary *session in (__bridge NSArray *)consoleUsers) {
        if (![session[@"kCGSSessionOnConsoleKey"] boolValue]) continue;
        NSNumber *securePID = session[@"kCGSSessionSecureInputPID"];
        if ([securePID isKindOfClass:[NSNumber class]]) {
            pid = securePID.intValue;
            break;
        }
    }
    CFRelease(consoleUsers);
    return pid;
}

static NSString *secureInputProcessName(pid_t pid) {
    NSRunningApplication *application = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    NSString *name = application.localizedName;
    if (name.length > 0) return name;
    NSString *path = application.executableURL.path;
    return path.lastPathComponent.length > 0 ? path.lastPathComponent : nil;
}

static NSString *inputSourceID(TISInputSourceRef source) {
    CFStringRef identifier = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
    return identifier != NULL ? CFBridgingRelease(CFRetain(identifier)) : nil;
}

static TISInputSourceRef inputSourceWithID(NSString *identifier) {
    if (identifier.length == 0) return NULL;
    CFDictionaryRef query = (__bridge CFDictionaryRef)@{(__bridge NSString *)kTISPropertyInputSourceID: identifier};
    CFArrayRef sources = TISCreateInputSourceList(query, false);
    if (sources == NULL || CFArrayGetCount(sources) == 0) {
        if (sources != NULL) CFRelease(sources);
        return NULL;
    }
    TISInputSourceRef source = (TISInputSourceRef)CFRetain(CFArrayGetValueAtIndex(sources, 0));
    CFRelease(sources);
    return source;
}

static TISInputSourceRef enabledVietnameseInputSource(void) {
    CFArrayRef sources = TISCreateInputSourceList(NULL, false);
    if (sources == NULL) return NULL;
    TISInputSourceRef result = NULL;
    for (id candidate in (__bridge NSArray *)sources) {
        TISInputSourceRef source = (__bridge TISInputSourceRef)candidate;
        NSString *bundleID = (__bridge NSString *)TISGetInputSourceProperty(source, kTISPropertyBundleID);
        if ([bundleID isEqualToString:@"com.apple.inputmethod.VietnameseIM"]) {
            result = (TISInputSourceRef)CFRetain(source);
            break;
        }
    }
    CFRelease(sources);
    return result;
}

static void enableAppleVietnameseInputModes(void) {
    NSArray<NSString *> *sourceIDs = @[
        @"com.apple.inputmethod.VietnameseIM.VietnameseVNI",
        @"com.apple.inputmethod.VietnameseIM.VietnameseTelex"
    ];
    for (NSString *sourceID in sourceIDs) {
        CFDictionaryRef query = (__bridge CFDictionaryRef)@{(__bridge NSString *)kTISPropertyInputSourceID: sourceID};
        CFArrayRef sources = TISCreateInputSourceList(query, true);
        if (sources == NULL || CFArrayGetCount(sources) == 0) {
            if (sources != NULL) CFRelease(sources);
            MacKeyDebugLog([NSString stringWithFormat:@"macOS Vietnamese input source is not installed: %@.", sourceID.lastPathComponent]);
            continue;
        }
        TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(sources, 0);
        if (TISEnableInputSource(source) == noErr) {
            MacKeyDebugLog([NSString stringWithFormat:@"Enabled macOS Vietnamese input source: %@.", sourceID.lastPathComponent]);
        } else {
            MacKeyDebugLog([NSString stringWithFormat:@"Could not enable macOS Vietnamese input source: %@.", sourceID.lastPathComponent]);
        }
        CFRelease(sources);
    }
}

static void restoreSecureInputPreviousSource(void) {
    if (secureInputPreviousSourceID.length == 0) return;
    TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
    NSString *currentID = current ? inputSourceID(current) : nil;
    if (current != NULL) CFRelease(current);
    // A manual source change always wins over our automatic restoration.
    if ([currentID isEqualToString:secureInputVietnameseSourceID]) {
        TISInputSourceRef previous = inputSourceWithID(secureInputPreviousSourceID);
        if (previous != NULL) {
            TISSelectInputSource(previous);
            CFRelease(previous);
            MacKeyDebugLog(@"Secure Input fallback restored the previous keyboard input source.");
        }
    }
    secureInputPreviousSourceID = nil;
    secureInputVietnameseSourceID = nil;
}

static TISInputSourceRef fallbackEnglishInputSource(void) {
    // Prefer the source selected before Secure Input began. It preserves the
    // user's chosen English layout (for example ABC, U.S., Dvorak, or Colemak).
    TISInputSourceRef source = inputSourceWithID(secureInputPreviousSourceID);
    if (source != NULL) return source;

    // Secure Input can start while macOS Vietnamese is already selected, so
    // there may be no previous English source to restore. ABC is the built-in
    // English layout present on current macOS releases; U.S. supports older
    // systems where ABC is unavailable.
    source = inputSourceWithID(@"com.apple.keylayout.ABC");
    if (source != NULL) return source;
    return inputSourceWithID(@"com.apple.keylayout.US");
}

static void restoreNormalInputSourceAfterSecureInput(void) {
    TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
    NSString *currentBundleID = current ? (__bridge NSString *)TISGetInputSourceProperty(current, kTISPropertyBundleID) : nil;
    if (current != NULL) CFRelease(current);
    if (![currentBundleID isEqualToString:@"com.apple.inputmethod.VietnameseIM"]) return;

    // A restarted process cannot retain the source selected before it quit.
    // In that case, choose the normal English layout so Apple Vietnamese does
    // not continue processing keystrokes alongside OpenKey.
    TISInputSourceRef normalSource = fallbackEnglishInputSource();
    if (normalSource != NULL) {
        if (TISSelectInputSource(normalSource) == noErr) {
            MacKeyDebugLog(@"Secure Input was already clear at launch; restored the normal keyboard input source.");
        }
        CFRelease(normalSource);
    }
}

static void syncSecureInputFallback(BOOL vietnameseEnabled) {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"UseVietnameseInputSourceDuringSecureInput"] || secureInputPID() <= 0) return;

    TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
    NSString *currentID = current ? inputSourceID(current) : nil;
    TISInputSourceRef target = vietnameseEnabled ? enabledVietnameseInputSource() : fallbackEnglishInputSource();
    NSString *targetID = target ? inputSourceID(target) : nil;

    if (target == NULL) {
        MacKeyDebugLog(vietnameseEnabled
                    ? @"Secure Input fallback needs the macOS Vietnamese input source enabled in Keyboard settings."
                    : @"Secure Input fallback could not find an English macOS input source.");
    } else if (![currentID isEqualToString:targetID]) {
        // Preserve the source from before the fallback takes control. Do not
        // overwrite it on each Smart Switch transition; it is our English
        // destination and the source to restore once Secure Input ends.
        if (secureInputPreviousSourceID.length == 0 && currentID.length > 0 && ![currentID isEqualToString:secureInputVietnameseSourceID]) {
            secureInputPreviousSourceID = currentID;
        }
        if (vietnameseEnabled) secureInputVietnameseSourceID = targetID;

        if (TISSelectInputSource(target) == noErr) {
            MacKeyDebugLog(vietnameseEnabled
                        ? @"Secure Input fallback selected the macOS Vietnamese input source."
                        : @"Secure Input fallback selected the macOS English input source.");
        } else {
            MacKeyDebugLog(@"Secure Input fallback could not select the requested macOS input source.");
        }
    }

    if (current != NULL) CFRelease(current);
    if (target != NULL) CFRelease(target);
}

static NSString *stringByRemovingTrailingNewlines(NSString *string) {
    NSUInteger end = string.length;
    while (end > 0) {
        unichar character = [string characterAtIndex:end - 1];
        if (character != '\n' && character != '\r') break;
        end--;
    }
    return end == string.length ? string : [string substringToIndex:end];
}

+(BOOL)isInited {
    return _isInited;
}

+(void)startEventTapWatchdog {
    if (eventTapWatchdog != nil) return;

    eventTapWatchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(eventTapWatchdog,
                              dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                              2 * NSEC_PER_SEC,
                              200 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(eventTapWatchdog, ^{
        if (!_isInited || eventTap == nil || !CFMachPortIsValid(eventTap)) return;

        [self logSecureInputStateIfChanged];

        if (!CGEventTapIsEnabled(eventTap)) {
            MacKeyDebugLog(@"Watchdog detected a disabled keyboard event tap; re-enabling.");
            [self reenableEventTap];
            return;
        }

    });
    dispatch_resume(eventTapWatchdog);
}

+(void)logSecureInputStateIfChanged {
    pid_t currentPID = secureInputPID();
    if (currentPID == reportedSecureInputPID) return;

    if (currentPID > 0) {
        NSString *name = secureInputProcessName(currentPID);
        NSString *owner = name.length > 0
            ? [NSString stringWithFormat:@"reported owner: %@ (PID %d)", name, currentPID]
            : [NSString stringWithFormat:@"reported PID %d", currentPID];
        MacKeyDebugLog([NSString stringWithFormat:@"Secure Input is active (%@). Vietnamese conversion is temporarily unavailable until macOS releases Secure Input.", owner]);
        syncSecureInputFallback([[NSUserDefaults standardUserDefaults] integerForKey:@"InputMethod"] == 1);
    } else if (reportedSecureInputPID > 0) {
        restoreSecureInputPreviousSource();
        MacKeyDebugLog(@"Secure Input cleared; resuming normal keyboard event-tap monitoring.");
        [self reenableEventTap];
    }

    reportedSecureInputPID = currentPID;
}

+(void)refreshSecureInputState {
    [self logSecureInputStateIfChanged];
}

+(void)checkSecureInputStateAtLaunch {
    [self refreshSecureInputState];
    if (secureInputPID() <= 0) {
        restoreNormalInputSourceAfterSecureInput();
    }
}

+(void)secureInputFallbackSettingDidChange {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"UseVietnameseInputSourceDuringSecureInput"]) {
        enableAppleVietnameseInputModes();
        syncSecureInputFallback([[NSUserDefaults standardUserDefaults] integerForKey:@"InputMethod"] == 1);
    } else {
        restoreSecureInputPreviousSource();
    }
}

+(void)syncSecureInputFallbackWithVietnameseEnabled:(BOOL)enabled {
    syncSecureInputFallback(enabled);
}

+(void)stopEventTapWatchdog {
    if (eventTapWatchdog != nil) {
        dispatch_source_cancel(eventTapWatchdog);
        eventTapWatchdog = nil;
    }
}

+(void)startClipboardMonitor {
    if (clipboardMonitor != nil) return;

    observedClipboardChangeCount = NSPasteboard.generalPasteboard.changeCount;
    clipboardMonitor = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(clipboardMonitor,
                              dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                              100 * NSEC_PER_MSEC,
                              20 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(clipboardMonitor, ^{
        NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
        if (pasteboard.changeCount == observedClipboardChangeCount) return;
        observedClipboardChangeCount = pasteboard.changeCount;
        if (![[NSUserDefaults standardUserDefaults] boolForKey:@"AutoTrimClipboardTrailingNewlines"]) return;

        NSMutableArray<NSPasteboardItem *> *updatedItems = [NSMutableArray array];
        BOOL changed = NO;
        for (NSPasteboardItem *item in pasteboard.pasteboardItems ?: @[]) {
            NSPasteboardItem *updatedItem = [[NSPasteboardItem alloc] init];
            for (NSPasteboardType type in item.types) {
                NSString *string = [item stringForType:type];
                if ([type isEqualToString:NSPasteboardTypeString] && string != nil) {
                    NSString *trimmed = stringByRemovingTrailingNewlines(string);
                    [updatedItem setString:trimmed forType:type];
                    changed |= ![trimmed isEqualToString:string];
                } else {
                    NSData *data = [item dataForType:type];
                    if (data != nil) [updatedItem setData:data forType:type];
                }
            }
            [updatedItems addObject:updatedItem];
        }

        if (!changed) return;
        [pasteboard clearContents];
        [pasteboard writeObjects:updatedItems];
        observedClipboardChangeCount = pasteboard.changeCount;
    });
    dispatch_resume(clipboardMonitor);
}

+(void)stopClipboardMonitor {
    if (clipboardMonitor != nil) {
        dispatch_source_cancel(clipboardMonitor);
        clipboardMonitor = nil;
    }
}

+(BOOL)initEventTap {
    if (_isInited)
        return true;
    
    //init MacKey
    MacKeyInit();
    
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
                                MacKeyCallback,
                                NULL);
    
    if (!eventTap) {
        MacKeyDebugLog(@"Failed to create the keyboard event tap.");
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
    [self startEventTapWatchdog];
    [self startClipboardMonitor];
    [self checkSecureInputStateAtLaunch];
    MacKeyDebugLog(@"Keyboard event tap started.");
    
    return YES;
}

+(BOOL)stopEventTap {
    if (_isInited) { //release all object
        [self stopEventTapWatchdog];
        [self stopClipboardMonitor];
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
        runLoopSource = nil;
        
        CFMachPortInvalidate(eventTap);
        CFRelease(eventTap);
        eventTap = nil;
        
        _isInited = false;
        MacKeyDebugLog(@"Keyboard event tap stopped.");
    }
    return YES;
}

+(void)reenableEventTap {
    // The disable notification is delivered through the tap itself, so do not
    // tear it down and recreate it from the callback. The port remains valid;
    // Core Graphics expects clients to explicitly enable it again.
    if (_isInited && eventTap != nil && CFMachPortIsValid(eventTap)) {
        CGEventTapEnable(eventTap, true);
        MacKeyDebugLog(@"Keyboard event tap re-enabled.");
    } else {
        MacKeyDebugLog(@"Could not re-enable keyboard event tap: port is unavailable.");
    }
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
    [[aSession dataTaskWithURL:[NSURL URLWithString:@"https://raw.githubusercontent.com/ithieund/macKey/master/version.json"] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
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
    [alert setMessageText:(needUpdating ? [NSString stringWithFormat:NSLocalizedString(@"macKey Có phiên bản mới (%@), bạn có muốn cập nhật không?", nil), versionString] : NSLocalizedString(@"Bạn đang dùng phiên bản mới nhất!", nil))];
    [alert setInformativeText:(needUpdating ? NSLocalizedString(@"Bấm 'Có' để cập nhật macKey.", nil) : @"")];
    
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
    NSString* target = [NSString stringWithFormat:@"%@/MacKeyUpdate.app", [self getApplicationSupportFolder]];
    [[NSFileManager defaultManager] removeItemAtPath:target error:&copyError];
    if (![[NSFileManager defaultManager] fileExistsAtPath:target]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:[self getApplicationSupportFolder] withIntermediateDirectories:YES attributes:nil error:nil];
        
        if (![[NSFileManager defaultManager] copyItemAtPath:[self getUpdateBundlePath] toPath:target error:&copyError]) {
            NSLog(@"Error on copy");
        }
    }
    
    NSURL *url = [NSURL fileURLWithPath:target isDirectory:YES];
    NSWorkspaceOpenConfiguration *configuration = [[NSWorkspaceOpenConfiguration alloc] init];
    configuration.arguments = @[@"yeah"];
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:url
                                           configuration:configuration
                                       completionHandler:^(NSRunningApplication *application, NSError *error) {
        if (error != nil) {
            MacKeyDebugLog([NSString stringWithFormat:@"Could not launch the update helper: %@", error.localizedDescription]);
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp terminate:nil];
        });
    }];
}

+(NSString*)getApplicationSupportFolder {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *applicationSupportDirectory = [paths firstObject];
    return [NSString stringWithFormat:@"%@/MacKey", applicationSupportDirectory];
}

+(NSString*)getUpdateBundlePath {
    NSString *currentpath = [[NSBundle mainBundle] bundlePath];
    return [NSString stringWithFormat:@"%@/Contents/Library/LoginItems/MacKeyUpdate.app", currentpath];
}
@end
