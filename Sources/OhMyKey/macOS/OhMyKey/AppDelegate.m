//
//  AppDelegate.m
//  OhMyKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai (OpenKey). Fork: OhMyKey © 2026 Hung Doan. GPL.
//

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#include <libproc.h>
#include <sys/proc_info.h>
#import "AppDelegate.h"
#import "OhMyKeyManager.h"
#import "MJAccessibilityUtils.h"
#import "OhMyKeyBridge.h"
#import "OhMyKey-Swift.h"

AppDelegate* appDelegate;
extern void OnTableCodeChange(void);
extern void OnInputMethodChanged(void);
extern void RequestNewSession(void);
extern void OnActiveAppChanged(void);

//see document in Engine.h
int vLanguage = 1;
int vInputType = 0;
int vFreeMark = 0;
int vCodeTable = 0;
int vCheckSpelling = 1;
int vUseModernOrthography = 1;
int vQuickTelex = 0;
#define DEFAULT_SWITCH_STATUS 0x7A000206 //default option + z
int vSwitchKeyStatus = DEFAULT_SWITCH_STATUS;
int vRestoreIfWrongSpelling = 0;
int vFixRecommendBrowser = 1;
int vUseMacro = 1;
int vUseMacroInEnglishMode = 1;
int vAutoCapsMacro = 0;
int vSendKeyStepByStep = 0;
int vUseSmartSwitchKey = 1;
int vUpperCaseFirstChar = 0;
int vTempOffSpelling = 0;
int vAllowConsonantZFWJ = 0;
int vQuickStartConsonant = 0;
int vQuickEndConsonant = 0;
int vRememberCode = 1; //new on version 2.0
int vOtherLanguage = 1; //new on version 2.0
int vTempOffOhMyKey = 0; //new on version 2.0

int vShowIconOnDock = 0; //new on version 2.0

int vPerformLayoutCompat = 0;

//beta feature
int vFixChromiumBrowser = 0; //new on version 2.0

extern int convertToolHotKey;
extern bool convertToolDontAlertWhenCompleted;

@interface AppDelegate ()

@end


@implementation AppDelegate {
    NSStatusItem *statusItem;
    NSMenu *theMenu;
    
    NSMenuItem* menuInputMethod;
    
    NSMenuItem* mnuTelex;
    NSMenuItem* mnuVNI;
    NSMenuItem* mnuSimpleTelex1;
    NSMenuItem* mnuSimpleTelex2;
    
    NSMenuItem* mnuUnicode;
    NSMenuItem* mnuTCVN;
    NSMenuItem* mnuVNIWindows;
    
    NSMenuItem* mnuUnicodeComposite;
    NSMenuItem* mnuVietnameseLocaleCP1258;
    
    NSMenuItem* mnuQuickConvert;
}

-(void)askPermission {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText: [NSString stringWithFormat:NSLocalizedString(@"OhMyKey cần bạn cấp quyền để có thể hoạt động!", nil)]];
    [alert setInformativeText:NSLocalizedString(@"Vui lòng chạy lại ứng dụng sau khi cấp quyền.", nil)];

    [alert addButtonWithTitle:NSLocalizedString(@"Không", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Cấp quyền", nil)];

    [alert.window makeKeyAndOrderFront:nil];
    [alert.window setLevel:NSStatusWindowLevel];

    NSModalResponse res = [alert runModal];

    if (res == 1001) {
        MJAccessibilityOpenPanel();
    }

    [NSApp terminate:0];
}


//Copy settings over from the OpenKey preferences domain the first time OhMyKey runs.
//NSUserDefaults keys the standard domain on the bundle id, so the rename to
//com.hungdoansy.ohmykey would otherwise silently reset every option, all macros and
//the smart-switch table. Values come back as the plist types they were written as
//(NSNumber for the integer options, NSData for macroData/smartSwitchKey), so copying
//them straight into the new domain round-trips exactly.
//The legacy domain is deliberately left in place: the user may still run OpenKey.
static void migrateLegacyDefaultsIfNeeded(void) {
    NSUserDefaults* ud = [NSUserDefaults standardUserDefaults];
    if ([ud boolForKey:OHMYKEY_MIGRATED_KEY])
        return;
    //Never clobber settings the user already made in this domain.
    if ([ud objectForKey:@"NonFirstTime"] != nil) {
        [ud setBool:YES forKey:OHMYKEY_MIGRATED_KEY];
        return;
    }

    CFStringRef legacyAppId = (__bridge CFStringRef)OHMYKEY_LEGACY_BUNDLE;
    CFArrayRef keys = CFPreferencesCopyKeyList(legacyAppId, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keys == NULL)
        return; //no OpenKey install to migrate from; retry next launch in case one appears
    CFDictionaryRef values = CFPreferencesCopyMultiple(keys, legacyAppId, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (values != NULL) {
        [(__bridge NSDictionary*)values enumerateKeysAndObjectsUsingBlock:^(NSString* key, id value, BOOL* stop) {
            if ([key hasPrefix:@"NS"])
                return; //AppKit's own state (window frames, tooltip delay), not our settings
            //The one setting whose key carries the old product name.
            if ([key isEqualToString:@"vTempOffOpenKey"])
                key = @"vTempOffOhMyKey";
            [ud setObject:value forKey:key];
        }];
        CFRelease(values);
    }
    CFRelease(keys);

    [ud setBool:YES forKey:OHMYKEY_MIGRATED_KEY];
    [ud synchronize];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    appDelegate = self;

    //must run before anything reads NSUserDefaults
    migrateLegacyDefaultsIfNeeded();
    
    [self registerSupportedNotification];
    
    //set quick tooltip
    [[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: 50]
                                              forKey: @"NSInitialToolTipDelay"];
    
#ifdef DEBUG
    // Debug-only escape hatch for looking at the UI; see UIPreviewHarness.swift.
    BOOL uiOnly = [OMKUIPreviewHarness isEnabled];
#else
    BOOL uiOnly = NO;
#endif

    //check whether this app has been launched before that or not
    //Only check instances owned by current user (for multi-user/Fast User Switching support)
    uid_t currentUID = getuid();
    NSArray<NSRunningApplication *>* runningApps = [[NSWorkspace sharedWorkspace] runningApplications];
    pid_t myPID = [[NSProcessInfo processInfo] processIdentifier];
    BOOL alreadyRunning = NO;

    for (NSRunningApplication *app in runningApps) {
        if ([app.bundleIdentifier isEqualToString:OHMYKEY_BUNDLE] &&
            app.processIdentifier != myPID) {
            pid_t pid = app.processIdentifier;
            struct proc_bsdinfo proc;
            int size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &proc, sizeof(proc));
            if (size == sizeof(proc) && proc.pbi_uid == currentUID) {
                alreadyRunning = YES;
                break;
            }
        }
    }

    if (alreadyRunning && !uiOnly) {
        [NSApp terminate:nil];
        return;
    }
    
    // check if user granted Accessabilty permission
    if (!uiOnly && !MJAccessibilityIsEnabled()) {
        [self askPermission];
        return;
    }
    
    vShowIconOnDock = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@"vShowIconOnDock"];
    // Dock icon follows window visibility: shown while a window is open, hidden when the last one closes.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onAnyWindowWillClose:)
                                                 name:NSWindowWillCloseNotification
                                               object:nil];
    
    if (vSwitchKeyStatus & 0x8000)
        NSBeep();

    [OMKMainMenu install];
    [self createStatusBarMenu];
    
    if (uiOnly) {
#ifdef DEBUG
        // Everything except the one thing that needs permission: settings are loaded and
        // the status menu is built, so the preview exercises the same wiring as a real
        // launch, it just cannot see or send a keystroke.
        [OMKBridge loadSettingsOnly];
        dispatch_async(dispatch_get_main_queue(), ^{
            [OMKUIPreviewHarness run];
        });
#endif
        return;
    }

    //init
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![OhMyKeyManager initEventTap]) {
            [self onControlPanelSelected];
        } else {
            NSInteger showui = [[NSUserDefaults standardUserDefaults] integerForKey:@"ShowUIOnStartup"];
            if (showui == 1) {
                [self onControlPanelSelected];
            }
        }
        [self setQuickConvertString];
    });
    
    //load default config if is first launch
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"NonFirstTime"] == 0) {
        [self loadDefaultConfig];
    }
    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"NonFirstTime"];
    
    //check update if enable
    NSInteger dontCheckUpdate = [[NSUserDefaults standardUserDefaults] integerForKey:@"DontCheckUpdate"];
    if (!dontCheckUpdate)
        [OhMyKeyManager checkNewVersion:nil callbackFunc:nil];
    
    //correct run on startup
    NSInteger val = [[NSUserDefaults standardUserDefaults] integerForKey:@"RunOnStartup"];
    [appDelegate setRunOnStartup:val];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self onControlPanelSelected];
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

-(void) createStatusBarMenu {
    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
    statusItem = [statusBar statusItemWithLength:NSVariableStatusItemLength];
    statusItem.button.image = [NSImage imageNamed:@"Status"];
    statusItem.button.alternateImage = [NSImage imageNamed:@"StatusHighlighted"];
    
    theMenu = [[NSMenu alloc] initWithTitle:@""];
    [theMenu setAutoenablesItems:NO];
    
    menuInputMethod = [theMenu addItemWithTitle:NSLocalizedString(@"Bật Tiếng Việt", nil)
                                                     action:@selector(onInputMethodSelected)
                                              keyEquivalent:@""];
    [theMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* menuInputType = [theMenu addItemWithTitle:NSLocalizedString(@"Kiểu gõ", nil) action:nil keyEquivalent:@""];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    mnuUnicode = [theMenu addItemWithTitle:NSLocalizedString(@"Unicode dựng sẵn", nil) action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuUnicode.tag = 0;
    mnuTCVN = [theMenu addItemWithTitle:@"TCVN3 (ABC)" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuTCVN.tag = 1;
    mnuVNIWindows = [theMenu addItemWithTitle:@"VNI Windows" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuVNIWindows.tag = 2;
    NSMenuItem* menuCode = [theMenu addItemWithTitle:NSLocalizedString(@"Bảng mã khác", nil) action:nil keyEquivalent:@""];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    [theMenu addItemWithTitle:NSLocalizedString(@"Công cụ chuyển mã...", nil) action:@selector(onConvertTool) keyEquivalent:@""];
    mnuQuickConvert = [theMenu addItemWithTitle:NSLocalizedString(@"Chuyển mã nhanh", nil) action:@selector(onQuickConvert) keyEquivalent:@""];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    [theMenu addItemWithTitle:NSLocalizedString(@"Bảng điều khiển...", nil) action:@selector(onControlPanelSelected) keyEquivalent:@""];
    [theMenu addItemWithTitle:NSLocalizedString(@"Gõ tắt...", nil) action:@selector(onMacroSelected) keyEquivalent:@""];
    [theMenu addItemWithTitle:NSLocalizedString(@"Giới thiệu", nil) action:@selector(onAboutSelected) keyEquivalent:@""];
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    [theMenu addItemWithTitle:NSLocalizedString(@"Thoát", nil) action:@selector(terminate:) keyEquivalent:@"q"];
    
    
    [self setInputTypeMenu:menuInputType];
    [self setCodeMenu:menuCode];
    
    //set menu
    [statusItem setMenu:theMenu];
    
    [self fillData];
}

-(void)setQuickConvertString {
    NSMutableString* hotKey = [NSMutableString stringWithString:@""];
    bool hasAdd = false;
    if (convertToolHotKey & 0x100) {
        [hotKey appendString:@"⌃"];
        hasAdd = true;
    }
    if (convertToolHotKey & 0x200) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        [hotKey appendString:@"⌥"];
        hasAdd = true;
    }
    if (convertToolHotKey & 0x400) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        [hotKey appendString:@"⌘"];
        hasAdd = true;
    }
    if (convertToolHotKey & 0x800) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        [hotKey appendString:@"⇧"];
        hasAdd = true;
    }
    
    unsigned short k = ((convertToolHotKey>>24) & 0xFF);
    if (k != 0xFE) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        if (k == kVK_Space)
            [hotKey appendFormat:@"%@", @"␣ "];
        else
            [hotKey appendFormat:@"%c", k];
    }
    [mnuQuickConvert setTitle: hasAdd ? [NSString stringWithFormat:NSLocalizedString(@"Chuyển mã nhanh - [%@]", nil), [hotKey uppercaseString]] : NSLocalizedString(@"Chuyển mã nhanh", nil)];
}

-(void)loadDefaultConfig {
    vLanguage = 1; [[NSUserDefaults standardUserDefaults] setInteger:vLanguage forKey:@"InputMethod"];
    vInputType = 0; [[NSUserDefaults standardUserDefaults] setInteger:vInputType forKey:@"InputType"];
    vFreeMark = 0; [[NSUserDefaults standardUserDefaults] setInteger:vFreeMark forKey:@"FreeMark"];
    vCheckSpelling = 1; [[NSUserDefaults standardUserDefaults] setInteger:vCheckSpelling forKey:@"Spelling"];
    vCodeTable = 0; [[NSUserDefaults standardUserDefaults] setInteger:vCodeTable forKey:@"CodeTable"];
    vSwitchKeyStatus = DEFAULT_SWITCH_STATUS; [[NSUserDefaults standardUserDefaults] setInteger:vCodeTable forKey:@"SwitchKeyStatus"];
    vQuickTelex = 0; [[NSUserDefaults standardUserDefaults] setInteger:vQuickTelex forKey:@"QuickTelex"];
    vUseModernOrthography = 0; [[NSUserDefaults standardUserDefaults] setInteger:vUseModernOrthography forKey:@"ModernOrthography"];
    vRestoreIfWrongSpelling = 0; [[NSUserDefaults standardUserDefaults] setInteger:vRestoreIfWrongSpelling forKey:@"RestoreIfInvalidWord"];
    vFixRecommendBrowser = 1; [[NSUserDefaults standardUserDefaults] setInteger:vFixRecommendBrowser forKey:@"FixRecommendBrowser"];
    vUseMacro = 1; [[NSUserDefaults standardUserDefaults] setInteger:vUseMacro forKey:@"UseMacro"];
    vUseMacroInEnglishMode = 0; [[NSUserDefaults standardUserDefaults] setInteger:vUseMacroInEnglishMode forKey:@"UseMacroInEnglishMode"];
    vSendKeyStepByStep = 0;[[NSUserDefaults standardUserDefaults] setInteger:vUseMacroInEnglishMode forKey:@"SendKeyStepByStep"];
    vUseSmartSwitchKey = 1;[[NSUserDefaults standardUserDefaults] setInteger:vUseSmartSwitchKey forKey:@"UseSmartSwitchKey"];
    vUpperCaseFirstChar = 0;[[NSUserDefaults standardUserDefaults] setInteger:vUpperCaseFirstChar forKey:@"UpperCaseFirstChar"];
    vTempOffSpelling = 0;[[NSUserDefaults standardUserDefaults] setInteger:vTempOffSpelling forKey:@"vTempOffSpelling"];
    vAllowConsonantZFWJ = 0;[[NSUserDefaults standardUserDefaults] setInteger:vAllowConsonantZFWJ forKey:@"vAllowConsonantZFWJ"];
    vQuickStartConsonant = 0;[[NSUserDefaults standardUserDefaults] setInteger:vQuickStartConsonant forKey:@"vQuickStartConsonant"];
    vQuickEndConsonant = 0;[[NSUserDefaults standardUserDefaults] setInteger:vQuickEndConsonant forKey:@"vQuickEndConsonant"];
    vRememberCode = 1;[[NSUserDefaults standardUserDefaults] setInteger:vRememberCode forKey:@"vRememberCode"];
    vOtherLanguage = 1;[[NSUserDefaults standardUserDefaults] setInteger:vOtherLanguage forKey:@"vOtherLanguage"];
    vTempOffOhMyKey = 0;[[NSUserDefaults standardUserDefaults] setInteger:vTempOffOhMyKey forKey:@"vTempOffOhMyKey"];
    vShowIconOnDock = 0;[[NSUserDefaults standardUserDefaults] setInteger:vShowIconOnDock forKey:@"vShowIconOnDock"];
    vFixChromiumBrowser = 0;[[NSUserDefaults standardUserDefaults] setInteger:vFixChromiumBrowser forKey:@"vFixChromiumBrowser"];
    vPerformLayoutCompat = 0;[[NSUserDefaults standardUserDefaults] setInteger:vPerformLayoutCompat forKey:@"vPerformLayoutCompat"];

    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"GrayIcon"];
    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"RunOnStartup"];

    [self fillData];
    [OMKBridge notifySettingsChanged];
}

-(void)setRunOnStartup:(BOOL)val {
    CFStringRef appId = (__bridge CFStringRef)@"com.hungdoansy.OhMyKeyHelper";
    SMLoginItemSetEnabled(appId, val);
}

-(void)setGrayIcon:(BOOL)val {
    [self fillData];
}

-(void)showIconOnDock:(BOOL)val {
    [self updateDockIconVisibility];
}

#pragma mark -Dock icon

-(BOOL)hasVisibleAppWindow {
    return [OMKWindowManager shared].hasVisibleWindow;
}

// Regular (Dock icon) only while one of our windows is open and the user allows it;
// Accessory (menu bar only) otherwise, so Cmd+W looks like the app went away while it keeps running.
-(void)updateDockIconVisibility {
    BOOL wantIcon = vShowIconOnDock && [self hasVisibleAppWindow];
    NSApplicationActivationPolicy policy = wantIcon ? NSApplicationActivationPolicyRegular
                                                    : NSApplicationActivationPolicyAccessory;
    if ([NSApp activationPolicy] != policy)
        [NSApp setActivationPolicy:policy];
}

-(void)onAnyWindowWillClose:(NSNotification *)note {
    // the window is still visible during willClose; re-evaluate once it is actually gone
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateDockIconVisibility];
    });
}

#pragma mark -StatusBar menu data

- (void)setInputTypeMenu:(NSMenuItem*) parent {
    //sub for Kieu Go
    NSMenu *sub = [[NSMenu alloc] initWithTitle:@""];
    [sub setAutoenablesItems:NO];
    mnuTelex = [sub addItemWithTitle:@"Telex" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuTelex.tag = 0;
    mnuVNI = [sub addItemWithTitle:@"VNI" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuVNI.tag = 1;
    mnuSimpleTelex1 = [sub addItemWithTitle:@"Simple Telex 1" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuSimpleTelex1.tag = 2;
    mnuSimpleTelex2 = [sub addItemWithTitle:@"Simple Telex 2" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuSimpleTelex2.tag = 3;
    [theMenu setSubmenu:sub forItem:parent];
}

- (void)setCodeMenu:(NSMenuItem*) parent {
    //sub for Code
    NSMenu *sub = [[NSMenu alloc] initWithTitle:@""];
    [sub setAutoenablesItems:NO];
    mnuUnicodeComposite = [sub addItemWithTitle:@"Unicode tổ hợp" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuUnicodeComposite.tag = 3;
    mnuVietnameseLocaleCP1258 = [sub addItemWithTitle:@"Vietnamese Locale CP 1258" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuVietnameseLocaleCP1258.tag = 4;
    
    [theMenu setSubmenu:sub forItem:parent];
}

- (void) fillData {
    //fill data
    NSInteger intInputMethod = [[NSUserDefaults standardUserDefaults] integerForKey:@"InputMethod"];
    NSInteger grayIcon = [[NSUserDefaults standardUserDefaults] integerForKey:@"GrayIcon"];
    BOOL isVietnamese = (intInputMethod == 1);
    [menuInputMethod setState:(isVietnamese ? NSControlStateValueOn : NSControlStateValueOff)];

    //Copy before marking as template: +imageNamed: hands out a shared cached image,
    //so setting the flag on it would change that image everywhere in the app.
    NSImage* icon = [[NSImage imageNamed:(isVietnamese ? @"Status" : @"StatusEng")] copy];
    [icon setTemplate:(grayIcon ? YES : NO)];
    statusItem.button.image = icon;

    //A template image is inverted by AppKit while the menu is open, so an explicit
    //highlight image is only needed when template rendering is off.
    statusItem.button.alternateImage = grayIcon ? nil
        : [NSImage imageNamed:(isVietnamese ? @"StatusHighlighted" : @"StatusHighlightedEng")];
    vLanguage = (int)intInputMethod;
    
    NSInteger intInputType = [[NSUserDefaults standardUserDefaults] integerForKey:@"InputType"];
    [mnuTelex setState:NSControlStateValueOff];
    [mnuVNI setState:NSControlStateValueOff];
    [mnuSimpleTelex1 setState:NSControlStateValueOff];
    [mnuSimpleTelex2 setState:NSControlStateValueOff];
    if (intInputType == 0) {
        [mnuTelex setState:NSControlStateValueOn];
    } else if (intInputType == 1) {
        [mnuVNI setState:NSControlStateValueOn];
    } else if (intInputType == 2) {
        [mnuSimpleTelex1 setState:NSControlStateValueOn];
    } else if (intInputType == 3) {
        [mnuSimpleTelex2 setState:NSControlStateValueOn];
    }
    vInputType = (int)intInputType;
    
    NSInteger intSwitchKeyStatus = [[NSUserDefaults standardUserDefaults] integerForKey:@"SwitchKeyStatus"];
    vSwitchKeyStatus = (int)intSwitchKeyStatus;
    if (vSwitchKeyStatus == 0)
        vSwitchKeyStatus = DEFAULT_SWITCH_STATUS;
    
    NSInteger intCode = [[NSUserDefaults standardUserDefaults] integerForKey:@"CodeTable"];
    [mnuUnicode setState:NSControlStateValueOff];
    [mnuTCVN setState:NSControlStateValueOff];
    [mnuVNIWindows setState:NSControlStateValueOff];
    [mnuUnicodeComposite setState:NSControlStateValueOff];
    [mnuVietnameseLocaleCP1258 setState:NSControlStateValueOff];
    if (intCode == 0) {
        [mnuUnicode setState:NSControlStateValueOn];
    } else if (intCode == 1) {
        [mnuTCVN setState:NSControlStateValueOn];
    } else if (intCode == 2) {
        [mnuVNIWindows setState:NSControlStateValueOn];
    } else if (intCode == 3) {
        [mnuUnicodeComposite setState:NSControlStateValueOn];
    } else if (intCode == 4) {
        [mnuVietnameseLocaleCP1258 setState:NSControlStateValueOn];
    }
    vCodeTable = (int)intCode;
    
    //
    NSInteger intRunOnStartup = [[NSUserDefaults standardUserDefaults] integerForKey:@"RunOnStartup"];
    [self setRunOnStartup:intRunOnStartup ? YES : NO];

}

-(void)onImputMethodChanged:(BOOL)willNotify {
    NSInteger intInputMethod = [[NSUserDefaults standardUserDefaults] integerForKey:@"InputMethod"];
    if (intInputMethod == 0)
        intInputMethod = 1;
    else
        intInputMethod = 0;
    vLanguage = (int)intInputMethod;
    [[NSUserDefaults standardUserDefaults] setInteger:intInputMethod forKey:@"InputMethod"];

    [self fillData];
    [OMKBridge notifySettingsChanged];
    
    if (willNotify)
        OnInputMethodChanged();
}

#pragma mark -StatusBar menu action
- (void)onInputMethodSelected {
    [self onImputMethodChanged:YES];
}

- (void)onInputTypeSelected:(id)sender {
    NSMenuItem *menuItem = (NSMenuItem*) sender;
    [self onInputTypeSelectedIndex:(int)menuItem.tag];
}

- (void)onInputTypeSelectedIndex:(int)index {
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"InputType"];
    vInputType = index;
    [self fillData];
    [OMKBridge notifySettingsChanged];
}

- (void)onCodeTableChanged:(int)index {
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"CodeTable"];
    vCodeTable = index;
    [self fillData];
    [OMKBridge notifySettingsChanged];
    OnTableCodeChange();
}

- (void)onCodeSelected:(id)sender {
    NSMenuItem *menuItem = (NSMenuItem*) sender;
    [self onCodeTableChanged:(int)menuItem.tag];
}

-(void)onConvertTool {
    if (vShowIconOnDock)
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [[OMKWindowManager shared] showConvertTool];
}

-(void)onQuickConvert {
    if ([OhMyKeyManager quickConvert]) {
        if (!convertToolDontAlertWhenCompleted) {
            [OhMyKeyManager showMessage: nil message:NSLocalizedString(@"Chuyển mã thành công!", nil) subMsg:NSLocalizedString(@"Kết quả đã được lưu trong clipboard.", nil)];
        }
    } else {
        [OhMyKeyManager showMessage: nil message:NSLocalizedString(@"Không có dữ liệu trong clipboard!", nil) subMsg:NSLocalizedString(@"Hãy sao chép một đoạn text để chuyển đổi!", nil)];
    }
}

-(void)onControlPanelSelected {
    if (vShowIconOnDock)
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [[OMKWindowManager shared] showSettings];
}

-(void)onMacroSelected {
    if (vShowIconOnDock)
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [[OMKWindowManager shared] showMacros];
}

-(void)onAboutSelected {
    if (vShowIconOnDock)
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [[OMKWindowManager shared] showAbout];
}

#pragma mark -Short key event
-(void)onSwitchLanguage {
    [self onInputMethodSelected];
    [OMKBridge notifySettingsChanged];
}

#pragma mark Reset OhMyKey after mac computer awake
-(void)receiveWakeNote: (NSNotification*)note {
    [OhMyKeyManager initEventTap];
}

-(void)receiveSleepNote: (NSNotification*)note {
    [OhMyKeyManager stopEventTap];
}

-(void)receiveActiveSpaceChanged: (NSNotification*)note {
    RequestNewSession();
}

-(void)activeAppChanged: (NSNotification*)note {
    if (vUseSmartSwitchKey && [OhMyKeyManager isInited]) {
        OnActiveAppChanged();
    }
}

-(void)registerSupportedNotification {
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveWakeNote:)
                                                               name: NSWorkspaceDidWakeNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveSleepNote:)
                                                               name: NSWorkspaceWillSleepNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveActiveSpaceChanged:)
                                                               name: NSWorkspaceActiveSpaceDidChangeNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(activeAppChanged:)
                                                               name: NSWorkspaceDidActivateApplicationNotification object: NULL];
}
@end
