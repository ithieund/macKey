//
//  AppDelegate.m
//  MacKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai (OpenKey). Additional changes © 2026 Hung Doan. GPL.
//

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#include <libproc.h>
#include <sys/proc_info.h>
#import "AppDelegate.h"
#import "MacKeyManager.h"
#import "MJAccessibilityUtils.h"
#import "MacKeyBridge.h"
#import "macKey-Swift.h"

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
int vUseSmartSwitchKey = 1;
int vUpperCaseFirstChar = 0;
int vTempOffSpelling = 0;
int vAllowConsonantZFWJ = 0;
int vQuickStartConsonant = 0;
int vQuickEndConsonant = 0;
int vRememberCode = 1; //new on version 2.0
int vOtherLanguage = 1; //new on version 2.0
int vTempOffMacKey = 0; //new on version 2.0

int vShowIconOnDock = 0; //new on version 2.0

int vPerformLayoutCompat = 0;

//beta feature
int vFixChromiumBrowser = 0; //new on version 2.0

extern int convertToolHotKey;
extern bool convertToolDontAlertWhenCompleted;

static NSString * const MacKeyDebugLoggingEnabledKey = @"DebugLoggingEnabled";

static BOOL MacKeyDebugLoggingEnabled(void) {
    id storedValue = [[NSUserDefaults standardUserDefaults] objectForKey:MacKeyDebugLoggingEnabledKey];
    // Preserve the historical default of recording diagnostics for existing users.
    return storedValue == nil || [storedValue boolValue];
}

void MacKeyDebugLog(NSString *message) {
    if (MacKeyDebugLoggingEnabled() && appDelegate != nil && message.length > 0) {
        [appDelegate appendDebugLog:message];
    }
}

static NSURL *MacKeyDebugLogURL(void) {
    NSURL *logsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory
                                                                    inDomains:NSUserDomainMask] firstObject];
    logsDirectory = [logsDirectory URLByAppendingPathComponent:@"Logs/macKey" isDirectory:YES];
    return [logsDirectory URLByAppendingPathComponent:@"Debug.log" isDirectory:NO];
}

@interface AppDelegate ()

@end


@implementation AppDelegate {
    NSStatusItem *statusItem;
    NSMenu *theMenu;
    
    NSMenuItem* menuInputMethod;
    NSMenuItem* menuInputType;
    NSMenuItem* menuCodeTable;
    
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
    NSPanel *smartSwitchErrorToast;
    NSPanel *debugLogPanel;
    NSTextView *debugLogTextView;
    NSMutableArray<NSString *> *debugLogs;
    NSButton *debugClearButton;
    NSSwitch *debugLoggingSwitch;
    NSTextField *debugLoggingLabel;
}

-(void)askPermission {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText: [NSString stringWithFormat:NSLocalizedString(@"macKey cần bạn cấp quyền để có thể hoạt động!", nil)]];
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


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    appDelegate = self;
    debugLogs = [NSMutableArray array];
    [self loadPersistedDebugLogs];
    [self appendDebugLog:@"Application launched."];

    
    [self registerSupportedNotification];
    
    //set quick tooltip
    [[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: 50]
                                              forKey: @"NSInitialToolTipDelay"];
    
#ifdef DEBUG
    // Debug-only escape hatch for looking at the UI; see UIPreviewHarness.swift.
    BOOL uiOnly = [MacKeyUIPreviewHarness isEnabled];
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
        if ([app.bundleIdentifier isEqualToString:MACKEY_BUNDLE] &&
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

    [MacKeyMainMenu install];
    [self createStatusBarMenu];
    
    if (uiOnly) {
#ifdef DEBUG
        // Everything except the one thing that needs permission: settings are loaded and
        // the status menu is built, so the preview exercises the same wiring as a real
        // launch, it just cannot see or send a keystroke.
        [MacKeyBridge loadSettingsOnly];
        dispatch_async(dispatch_get_main_queue(), ^{
            [MacKeyUIPreviewHarness run];
        });
#endif
        return;
    }

    //init
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![MacKeyManager initEventTap]) {
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
        [MacKeyManager checkNewVersion:nil callbackFunc:nil];
    
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
    menuCodeTable = [theMenu addItemWithTitle:NSLocalizedString(@"Bảng mã", nil) action:nil keyEquivalent:@""];
    menuCodeTable.image = [NSImage imageWithSystemSymbolName:@"textformat" accessibilityDescription:nil];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    menuInputType = [theMenu addItemWithTitle:NSLocalizedString(@"Kiểu gõ", nil) action:nil keyEquivalent:@""];
    menuInputType.image = [NSImage imageWithSystemSymbolName:@"keyboard" accessibilityDescription:nil];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    [theMenu addItemWithTitle:NSLocalizedString(@"Bảng điều khiển", nil) action:@selector(onControlPanelSelected) keyEquivalent:@""];
    [theMenu addItemWithTitle:NSLocalizedString(@"Gõ tắt", nil) action:@selector(onMacroSelected) keyEquivalent:@""];
    [theMenu addItemWithTitle:NSLocalizedString(@"Công cụ chuyển mã", nil) action:@selector(onConvertTool) keyEquivalent:@""];
    mnuQuickConvert = [theMenu addItemWithTitle:NSLocalizedString(@"Chuyển mã nhanh", nil) action:@selector(onQuickConvert) keyEquivalent:@""];
    [theMenu addItem:[NSMenuItem separatorItem]];

    [theMenu addItemWithTitle:@"Restart" action:@selector(onRestart:) keyEquivalent:@""];
    [theMenu addItemWithTitle:@"Debug" action:@selector(onShowDebugLog:) keyEquivalent:@""];
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem *aboutItem = [theMenu addItemWithTitle:NSLocalizedString(@"Giới thiệu", nil) action:@selector(onAboutSelected) keyEquivalent:@""];
    aboutItem.image = [NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:nil];
    [theMenu addItemWithTitle:NSLocalizedString(@"Thoát", nil) action:@selector(terminate:) keyEquivalent:@"q"];
    
    
    [self setCodeTableMenu:menuCodeTable];
    [self setInputTypeMenu:menuInputType];
    
    //set menu
    [statusItem setMenu:theMenu];
    
    [self fillData];
}

- (void)appendDebugLog:(NSString *)message {
    if (message.length == 0) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        NSString *line = [NSString stringWithFormat:@"%@  %@", [formatter stringFromDate:NSDate.date], message];
        [self->debugLogs addObject:line];
        if (self->debugLogs.count > 250) {
            [self->debugLogs removeObjectAtIndex:0];
        }
        [self updateDebugLogControls];
        if (self->debugLogTextView != nil) {
            self->debugLogTextView.string = [self->debugLogs componentsJoinedByString:@"\n"];
            [self->debugLogTextView scrollRangeToVisible:NSMakeRange(self->debugLogTextView.string.length, 0)];
            // Keep the diagnostic panel alive and showing the newest event even
            // while focus is in the app where the typing failure occurred.
            if (self->debugLogPanel.isVisible) {
                [self->debugLogPanel orderFrontRegardless];
            }
        }
        [self appendLineToPersistentDebugLog:line];
    });
}

- (void)updateDebugLogControls {
    debugClearButton.enabled = debugLogs.count > 0;
    debugLoggingSwitch.state = MacKeyDebugLoggingEnabled() ? NSControlStateValueOn : NSControlStateValueOff;
    debugLoggingLabel.stringValue = MacKeyDebugLoggingEnabled()
        ? NSLocalizedString(@"Tắt Debug", nil)
        : NSLocalizedString(@"Bật Debug", nil);
}

- (void)loadPersistedDebugLogs {
    NSString *contents = [NSString stringWithContentsOfURL:MacKeyDebugLogURL()
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    if (contents.length == 0) {
        return;
    }
    NSArray<NSString *> *lines = [contents componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSUInteger firstLine = lines.count > 250 ? lines.count - 250 : 0;
    for (NSUInteger index = firstLine; index < lines.count; index++) {
        if (lines[index].length > 0) {
            [debugLogs addObject:lines[index]];
        }
    }
}

- (void)appendLineToPersistentDebugLog:(NSString *)line {
    NSURL *logURL = MacKeyDebugLogURL();
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *directoryError = nil;
    [fileManager createDirectoryAtURL:[logURL URLByDeletingLastPathComponent]
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&directoryError];
    if (directoryError != nil) {
        return;
    }

    NSDictionary<NSFileAttributeKey, id> *attributes = [fileManager attributesOfItemAtPath:logURL.path error:nil];
    if ([[attributes objectForKey:NSFileSize] unsignedLongLongValue] > 2 * 1024 * 1024) {
        // Keep the latest diagnostic session without allowing a key-event issue to
        // grow an unbounded log file.
        [fileManager removeItemAtURL:logURL error:nil];
    }
    if (![fileManager fileExistsAtPath:logURL.path]) {
        [fileManager createFileAtPath:logURL.path contents:nil attributes:nil];
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logURL.path];
    [handle seekToEndOfFile];
    [handle writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

- (void)onShowDebugLog:(id)sender {
    if (debugLogPanel == nil) {
        NSRect panelFrame = NSMakeRect(0, 0, 680, 420);
        debugLogPanel = [[NSPanel alloc] initWithContentRect:panelFrame
                                                    styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
        debugLogPanel.title = @"Debug";
        debugLogPanel.level = NSStatusWindowLevel;
        debugLogPanel.minSize = NSMakeSize(460, 260);
        debugLogPanel.hidesOnDeactivate = NO;
        debugLogPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;

        NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 52, 648, 352)];
        scrollView.hasVerticalScroller = YES;
        scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        debugLogTextView = [[NSTextView alloc] initWithFrame:scrollView.bounds];
        debugLogTextView.editable = NO;
        debugLogTextView.selectable = YES;
        debugLogTextView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
        debugLogTextView.textContainerInset = NSMakeSize(8, 8);
        scrollView.documentView = debugLogTextView;
        [debugLogPanel.contentView addSubview:scrollView];

        NSBox *footerSeparator = [[NSBox alloc] initWithFrame:NSMakeRect(0, 51, panelFrame.size.width, 1)];
        footerSeparator.boxType = NSBoxSeparator;
        footerSeparator.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
        [debugLogPanel.contentView addSubview:footerSeparator];

        NSButton *clearButton = [[NSButton alloc] initWithFrame:NSMakeRect(16, 14, 92, 26)];
        clearButton.title = NSLocalizedString(@"Xóa log", nil);
        clearButton.bezelStyle = NSBezelStyleRounded;
        clearButton.target = self;
        clearButton.action = @selector(onClearDebugLog:);
        clearButton.autoresizingMask = NSViewMaxYMargin;
        [debugLogPanel.contentView addSubview:clearButton];
        debugClearButton = clearButton;

        debugLoggingLabel = [NSTextField labelWithString:@""];
        debugLoggingLabel.alignment = NSTextAlignmentRight;
        // Let the full localized state label fit, then leave a deliberate
        // 10-point gap before the native switch.
        debugLoggingLabel.frame = NSMakeRect(502, 16, 112, 20);
        debugLoggingLabel.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
        [debugLogPanel.contentView addSubview:debugLoggingLabel];

        debugLoggingSwitch = [[NSSwitch alloc] initWithFrame:NSMakeRect(624, 16, 40, 20)];
        debugLoggingSwitch.controlSize = NSControlSizeSmall;
        debugLoggingSwitch.target = self;
        debugLoggingSwitch.action = @selector(onDebugLoggingToggled:);
        debugLoggingSwitch.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
        [debugLogPanel.contentView addSubview:debugLoggingSwitch];
    }
    debugLogTextView.string = [debugLogs componentsJoinedByString:@"\n"];
    [self updateDebugLogControls];
    [debugLogTextView scrollRangeToVisible:NSMakeRange(debugLogTextView.string.length, 0)];
    [debugLogPanel center];
    [debugLogPanel makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)onClearDebugLog:(id)sender {
    [debugLogs removeAllObjects];
    debugLogTextView.string = @"";
    [[NSFileManager defaultManager] removeItemAtURL:MacKeyDebugLogURL() error:nil];
    [self updateDebugLogControls];
}

- (void)onDebugLoggingToggled:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:(debugLoggingSwitch.state == NSControlStateValueOn)
                                            forKey:MacKeyDebugLoggingEnabledKey];
    [self updateDebugLogControls];
}

- (void)onRestart:(id)sender {
    NSURL *appURL = NSBundle.mainBundle.bundleURL;
    if (appURL == nil) {
        MacKeyDebugLog(@"Restart failed: application bundle URL is unavailable.");
        return;
    }

    // A second instance would immediately exit because macKey allows only one
    // process. Launch `open` from a short-lived child after this instance quits
    // so the replacement starts with the same stable /Applications identity.
    NSTask *restartTask = [[NSTask alloc] init];
    restartTask.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    restartTask.arguments = @[@"-c", @"sleep 0.5; exec /usr/bin/open \"$1\"", @"mackey-restart", appURL.path];

    NSError *error = nil;
    if (![restartTask launchAndReturnError:&error]) {
        MacKeyDebugLog([NSString stringWithFormat:@"Restart failed: %@", error.localizedDescription ?: @"unknown launch error"]);
        [MacKeyManager showMessage:nil message:@"Restart failed" subMsg:error.localizedDescription ?: @""];
        return;
    }

    MacKeyDebugLog(@"Restart requested; launching a replacement instance.");
    [NSApp terminate:nil];
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
    [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"AutoTrimClipboardTrailingNewlines"];
    [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"MoveCursorBeforeTeamsImagePaste"];
    [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"CleanTextFormattingBeforeTeamsPaste"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SendKeyStepByStep"];
    vUseSmartSwitchKey = 1;[[NSUserDefaults standardUserDefaults] setInteger:vUseSmartSwitchKey forKey:@"UseSmartSwitchKey"];
    vUpperCaseFirstChar = 0;[[NSUserDefaults standardUserDefaults] setInteger:vUpperCaseFirstChar forKey:@"UpperCaseFirstChar"];
    vTempOffSpelling = 0;[[NSUserDefaults standardUserDefaults] setInteger:vTempOffSpelling forKey:@"vTempOffSpelling"];
    vAllowConsonantZFWJ = 0;[[NSUserDefaults standardUserDefaults] setInteger:vAllowConsonantZFWJ forKey:@"vAllowConsonantZFWJ"];
    vQuickStartConsonant = 0;[[NSUserDefaults standardUserDefaults] setInteger:vQuickStartConsonant forKey:@"vQuickStartConsonant"];
    vQuickEndConsonant = 0;[[NSUserDefaults standardUserDefaults] setInteger:vQuickEndConsonant forKey:@"vQuickEndConsonant"];
    vRememberCode = 1;[[NSUserDefaults standardUserDefaults] setInteger:vRememberCode forKey:@"vRememberCode"];
    vOtherLanguage = 1;[[NSUserDefaults standardUserDefaults] setInteger:vOtherLanguage forKey:@"vOtherLanguage"];
    vTempOffMacKey = 0;[[NSUserDefaults standardUserDefaults] setInteger:vTempOffMacKey forKey:@"vTempOffMacKey"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"vTempOffOhMyKey"];
    vShowIconOnDock = 0;[[NSUserDefaults standardUserDefaults] setInteger:vShowIconOnDock forKey:@"vShowIconOnDock"];
    vFixChromiumBrowser = 0;[[NSUserDefaults standardUserDefaults] setInteger:vFixChromiumBrowser forKey:@"vFixChromiumBrowser"];
    vPerformLayoutCompat = 0;[[NSUserDefaults standardUserDefaults] setInteger:vPerformLayoutCompat forKey:@"vPerformLayoutCompat"];

    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"GrayIcon"];
    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"RunOnStartup"];

    [self fillData];
    [MacKeyBridge notifySettingsChanged];
}

-(void)setRunOnStartup:(BOOL)val {
    SMAppService *service = SMAppService.mainAppService;
    NSError *error = nil;
    BOOL didUpdate = val
        ? [service registerAndReturnError:&error]
        : [service unregisterAndReturnError:&error];
    if (!didUpdate) {
        MacKeyDebugLog([NSString stringWithFormat:@"Could not %@ launch at login: %@",
                     val ? @"enable" : @"disable",
                     error.localizedDescription ?: @"unknown error"]);
    }
}

-(void)setGrayIcon:(BOOL)val {
    [self fillData];
}

-(void)showIconOnDock:(BOOL)val {
    [self updateDockIconVisibility];
}

#pragma mark -Dock icon

-(BOOL)hasVisibleAppWindow {
    return [MacKeyWindowManager shared].hasVisibleWindow;
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

- (void)setCodeTableMenu:(NSMenuItem*)parent {
    NSMenu *sub = [[NSMenu alloc] initWithTitle:@""];
    [sub setAutoenablesItems:NO];
    mnuUnicode = [sub addItemWithTitle:NSLocalizedString(@"Unicode dựng sẵn", nil) action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuUnicode.tag = 0;
    mnuUnicodeComposite = [sub addItemWithTitle:NSLocalizedString(@"Unicode tổ hợp", nil) action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuUnicodeComposite.tag = 3;
    mnuTCVN = [sub addItemWithTitle:@"TCVN3 (ABC)" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuTCVN.tag = 1;
    mnuVNIWindows = [sub addItemWithTitle:@"VNI Windows" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuVNIWindows.tag = 2;
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
    menuInputType.title = intInputType == 0 ? mnuTelex.title
        : (intInputType == 1 ? mnuVNI.title : (intInputType == 2 ? mnuSimpleTelex1.title : mnuSimpleTelex2.title));
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
    menuCodeTable.title = intCode == 0 ? mnuUnicode.title
        : (intCode == 1 ? mnuTCVN.title : (intCode == 2 ? mnuVNIWindows.title : (intCode == 3 ? mnuUnicodeComposite.title : mnuVietnameseLocaleCP1258.title)));
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
    [MacKeyBridge notifySettingsChanged];
    
    if (willNotify)
        OnInputMethodChanged();
}

- (BOOL)applySmartSwitchState:(int)state error:(NSError * _Nullable * _Nullable)error {
    // The engine stores one byte as: bit 0 = Vietnamese, bits 1... = code table.
    // Validate it before changing any visible or input state; old/corrupt saved data
    // must never leave the menu saying V while the engine is passing VNI keys through.
    if (state < 0 || state > 9) {
        MacKeyDebugLog([NSString stringWithFormat:@"Smart switch rejected invalid state %d.", state]);
        if (error) {
            *error = [NSError errorWithDomain:@"MacKey.SmartSwitch"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Dữ liệu chuyển chế độ theo ứng dụng không hợp lệ."}];
        }
        return NO;
    }

    int inputMethod = state & 0x01;
    int codeTable = state >> 1;
    if (codeTable < 0 || codeTable > 4) {
        MacKeyDebugLog([NSString stringWithFormat:@"Smart switch rejected invalid code table %d.", codeTable]);
        if (error) {
            *error = [NSError errorWithDomain:@"MacKey.SmartSwitch"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Bảng mã đã lưu cho ứng dụng không hợp lệ."}];
        }
        return NO;
    }

    @try {
        NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
        [preferences setInteger:inputMethod forKey:@"InputMethod"];
        [preferences setInteger:codeTable forKey:@"CodeTable"];
        vLanguage = inputMethod;
        vCodeTable = codeTable;
        [self fillData];
        [MacKeyManager syncSecureInputFallbackWithVietnameseEnabled:inputMethod == 1];
        RequestNewSession();
        [MacKeyBridge notifySettingsChanged];
        return YES;
    } @catch (NSException *exception) {
        MacKeyDebugLog([NSString stringWithFormat:@"Smart switch exception: %@", exception.reason ?: @"unknown exception"]);
        if (error) {
            *error = [NSError errorWithDomain:@"MacKey.SmartSwitch"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Không thể áp dụng chế độ đã lưu."}];
        }
        return NO;
    }
}

- (void)handleSmartSwitchFailure:(NSString *)reason {
    MacKeyDebugLog([NSString stringWithFormat:@"Smart switch failed; forcing English: %@", reason ?: @"unknown error"]);
    AppDelegate *delegate = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Fail visibly and safely. English passthrough avoids silently claiming that
        // Vietnamese conversion is active after a failed per-app restore.
        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"InputMethod"];
        vLanguage = 0;
        [delegate fillData];
        RequestNewSession();
        [MacKeyBridge notifySettingsChanged];

        [delegate->smartSwitchErrorToast orderOut:nil];
        NSRect contentRect = NSMakeRect(0, 0, 360, 72);
        delegate->smartSwitchErrorToast = [[NSPanel alloc] initWithContentRect:contentRect
                                                                       styleMask:NSWindowStyleMaskBorderless
                                                                         backing:NSBackingStoreBuffered
                                                                           defer:NO];
        delegate->smartSwitchErrorToast.level = NSStatusWindowLevel;
        delegate->smartSwitchErrorToast.opaque = NO;
        delegate->smartSwitchErrorToast.backgroundColor = [NSColor colorWithWhite:0.12 alpha:0.94];
        delegate->smartSwitchErrorToast.hasShadow = YES;
        delegate->smartSwitchErrorToast.ignoresMouseEvents = YES;

        NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 12, 328, 48)];
        label.editable = NO;
        label.selectable = NO;
        label.bordered = NO;
        label.drawsBackground = NO;
        label.textColor = NSColor.whiteColor;
        label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.maximumNumberOfLines = 2;
        label.stringValue = [NSString stringWithFormat:@"Smart switch lỗi — đã chuyển sang English. %@", reason ?: @""];
        [delegate->smartSwitchErrorToast.contentView addSubview:label];

        NSScreen *screen = delegate->statusItem.button.window.screen ?: NSScreen.mainScreen;
        NSRect visibleFrame = screen.visibleFrame;
        [delegate->smartSwitchErrorToast setFrameOrigin:NSMakePoint(NSMaxX(visibleFrame) - NSWidth(contentRect) - 16,
                                                                  NSMaxY(visibleFrame) - NSHeight(contentRect) - 16)];
        [delegate->smartSwitchErrorToast orderFrontRegardless];
        NSPanel *toast = delegate->smartSwitchErrorToast;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [toast orderOut:nil];
        });
    });
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
    [MacKeyBridge notifySettingsChanged];
}

- (void)onCodeTableChanged:(int)index {
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"CodeTable"];
    vCodeTable = index;
    [self fillData];
    [MacKeyBridge notifySettingsChanged];
    OnTableCodeChange();
}

- (void)onCodeSelected:(id)sender {
    NSMenuItem *menuItem = (NSMenuItem*) sender;
    [self onCodeTableChanged:(int)menuItem.tag];
}

-(void)onConvertTool {
    if (vShowIconOnDock)
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [[MacKeyWindowManager shared] showConvertTool];
}

-(void)onQuickConvert {
    if ([MacKeyManager quickConvert]) {
        if (!convertToolDontAlertWhenCompleted) {
            [MacKeyManager showMessage: nil message:NSLocalizedString(@"Chuyển mã thành công!", nil) subMsg:NSLocalizedString(@"Kết quả đã được lưu trong clipboard.", nil)];
        }
    } else {
        [MacKeyManager showMessage: nil message:NSLocalizedString(@"Không có dữ liệu trong clipboard!", nil) subMsg:NSLocalizedString(@"Hãy sao chép một đoạn text để chuyển đổi!", nil)];
    }
}

-(void)onControlPanelSelected {
    if (vShowIconOnDock)
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [[MacKeyWindowManager shared] showSettings];
}

-(void)onMacroSelected {
    if (vShowIconOnDock)
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [[MacKeyWindowManager shared] showMacros];
}

-(void)onAboutSelected {
    if (vShowIconOnDock)
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [[MacKeyWindowManager shared] showAbout];
}

#pragma mark -Short key event
-(void)onSwitchLanguage {
    [self onInputMethodSelected];
    [MacKeyBridge notifySettingsChanged];
}

#pragma mark Reset MacKey after mac computer awake
-(void)receiveWakeNote: (NSNotification*)note {
    [MacKeyManager initEventTap];
    [MacKeyManager refreshSecureInputState];
}

-(void)receiveSleepNote: (NSNotification*)note {
    [MacKeyManager stopEventTap];
}

-(void)receiveActiveSpaceChanged: (NSNotification*)note {
    RequestNewSession();
}

-(void)receiveSessionDidBecomeActive: (NSNotification*)note {
    // This notification is delivered after the user unlocks the screen. The
    // Lock Screen may have held Secure Input while the machine was asleep, so
    // re-check now instead of leaving Apple's temporary input source selected
    // until the watchdog's next pass.
    [MacKeyManager refreshSecureInputState];
}

-(void)activeAppChanged: (NSNotification*)note {
    if (![MacKeyManager isInited]) {
        return;
    }
    if (vUseSmartSwitchKey) {
        OnActiveAppChanged();
    } else {
        MacKeyDebugLog([NSString stringWithFormat:@"Current Key: %@", vLanguage == 1 ? @"Vietnamese" : @"English"]);
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
                                                           selector: @selector(receiveSessionDidBecomeActive:)
                                                               name: NSWorkspaceSessionDidBecomeActiveNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveActiveSpaceChanged:)
                                                               name: NSWorkspaceActiveSpaceDidChangeNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(activeAppChanged:)
                                                               name: NSWorkspaceDidActivateApplicationNotification object: NULL];
}
@end
