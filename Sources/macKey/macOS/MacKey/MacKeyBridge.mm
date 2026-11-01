//
//  MacKeyBridge.mm
//  macKey
//
//  Objective-C++ so it can reach the C++ engine; the header it publishes is plain
//  Objective-C so Swift can import it. See MacKeyBridge.h for why this exists.
//

#import "MacKeyBridge.h"
#import "AppDelegate.h"
#import "MacKeyManager.h"
#import "MJAccessibilityUtils.h"

#include "Engine.h"
#include "ConvertTool.h"

extern AppDelegate *appDelegate;

// Defined inside an extern "C" block in MacKey.mm, so they must be declared as C here
// too or this translation unit looks for mangled names.
extern "C" void MacKeyInit(void);
extern "C" void OnSpellCheckingChanged(void);
extern "C" void RequestNewSession(void);

// Settings the macOS app owns rather than the cross-platform engine, so they are
// defined in AppDelegate.m instead of being declared in Engine.h.
extern int vFixChromiumBrowser;
extern int vPerformLayoutCompat;
extern int vShowIconOnDock;

NSNotificationName const MacKeySettingsDidChangeNotification = @"MacKeySettingsDidChangeNotification";

static NSString *keyDeliveryModeDescription(MacKeyApplicationKeyDeliveryMode mode) {
    switch (mode) {
        case MacKeyApplicationKeyDeliveryModeKeyByKey:
            return @"Send key-by-key";
        case MacKeyApplicationKeyDeliveryModeClipboardPaste:
            return @"Clipboard paste";
        case MacKeyApplicationKeyDeliveryModeDefault:
        default:
            return @"Default";
    }
}

#pragma mark - Toggle table

/// What one toggle needs in order to be read and written.
///
/// `invertedKey` covers the two settings whose stored form is the opposite of what the
/// UI shows: "check for updates on startup" is stored as DontCheckUpdate, and the convert
/// tool stores "don't alert when finished". Keeping the inversion in the table means the
/// rest of the app can talk about the setting the way a person would.
typedef struct {
    MacKeyToggle toggle;
    int *engineGlobal;      // NULL for settings the engine never reads
    __unsafe_unretained NSString *key;
    BOOL invertedKey;
} MacKeyToggleSpec;

static const MacKeyToggleSpec *specFor(MacKeyToggle toggle) {
    static MacKeyToggleSpec specs[] = {
        {MacKeyToggleFreeMark,                 &vFreeMark,               @"FreeMark",              NO},
        {MacKeyToggleModernOrthography,        &vUseModernOrthography,   @"ModernOrthography",     NO},
        {MacKeyToggleCheckSpelling,            &vCheckSpelling,          @"Spelling",              NO},
        {MacKeyToggleQuickTelex,               &vQuickTelex,             @"QuickTelex",            NO},
        {MacKeyToggleRestoreIfInvalidWord,     &vRestoreIfWrongSpelling, @"RestoreIfInvalidWord",  NO},
        {MacKeyToggleTempOffSpelling,          &vTempOffSpelling,        @"vTempOffSpelling",      NO},
        {MacKeyToggleAllowConsonantZFWJ,       &vAllowConsonantZFWJ,     @"vAllowConsonantZFWJ",   NO},
        {MacKeyToggleFixRecommendBrowser,      &vFixRecommendBrowser,    @"FixRecommendBrowser",   NO},
        {MacKeyToggleFixChromiumBrowser,       &vFixChromiumBrowser,     @"vFixChromiumBrowser",   NO},
        {MacKeyTogglePerformLayoutCompat,      &vPerformLayoutCompat,    @"vPerformLayoutCompat",  NO},
        {MacKeyToggleUseMacro,                 &vUseMacro,               @"UseMacro",              NO},
        {MacKeyToggleUseMacroInEnglishMode,    &vUseMacroInEnglishMode,  @"UseMacroInEnglishMode", NO},
        {MacKeyToggleAutoCapsMacro,            &vAutoCapsMacro,          @"vAutoCapsMacro",        NO},
        {MacKeyToggleAutoTrimClipboardTrailingNewlines, NULL,            @"AutoTrimClipboardTrailingNewlines", NO},
        {MacKeyToggleUseVietnameseInputSourceDuringSecureInput, NULL,    @"UseVietnameseInputSourceDuringSecureInput", NO},
        {MacKeyToggleMoveCursorBeforeTeamsImagePaste, NULL,              @"MoveCursorBeforeTeamsImagePaste", NO},
        {MacKeyToggleCleanTextFormattingBeforeTeamsPaste, NULL,          @"CleanTextFormattingBeforeTeamsPaste", NO},
        {MacKeyToggleUseSmartSwitchKey,        &vUseSmartSwitchKey,      @"UseSmartSwitchKey",     NO},
        {MacKeyToggleUpperCaseFirstChar,       &vUpperCaseFirstChar,     @"UpperCaseFirstChar",    NO},
        {MacKeyToggleQuickStartConsonant,      &vQuickStartConsonant,    @"vQuickStartConsonant",  NO},
        {MacKeyToggleQuickEndConsonant,        &vQuickEndConsonant,      @"vQuickEndConsonant",    NO},
        {MacKeyToggleRememberCode,             &vRememberCode,           @"vRememberCode",         NO},
        {MacKeyToggleOtherLanguage,            &vOtherLanguage,          @"vOtherLanguage",        NO},
        {MacKeyToggleTempOffMacKey,           &vTempOffMacKey,         @"vTempOffMacKey",       NO},
        {MacKeyToggleShowIconOnDock,           &vShowIconOnDock,         @"vShowIconOnDock",       NO},
        {MacKeyToggleShowUIOnStartup,          NULL,                     @"ShowUIOnStartup",       NO},
        {MacKeyToggleRunOnStartup,             NULL,                     @"RunOnStartup",          NO},
        {MacKeyToggleGrayIcon,                 NULL,                     @"GrayIcon",              NO},
        {MacKeyToggleCheckUpdateOnStartup,     NULL,                     @"DontCheckUpdate",       YES},
        {MacKeyToggleConvertAlertWhenCompleted, NULL,                    @"convertToolDontAlertWhenCompleted", NO},
        {MacKeyToggleConvertRemoveMark,        NULL,                     @"convertToolRemoveMark", NO},
    };
    for (size_t i = 0; i < sizeof(specs) / sizeof(specs[0]); i++) {
        if (specs[i].toggle == toggle) {
            return &specs[i];
        }
    }
    NSCAssert(NO, @"unknown toggle %ld", (long)toggle);
    return NULL;
}

static NSUserDefaults *defaults(void) {
    return [NSUserDefaults standardUserDefaults];
}

@implementation MacKeyMacro

- (instancetype)initWithText:(NSString *)text content:(NSString *)content {
    if ((self = [super init])) {
        _text = [text copy];
        _content = [content copy];
    }
    return self;
}

@end

@implementation MacKeyApplicationKeyMode

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                                    name:(NSString *)name
                                    icon:(NSImage *)icon
                        keyDeliveryMode:(MacKeyApplicationKeyDeliveryMode)keyDeliveryMode {
    if ((self = [super init])) {
        _bundleIdentifier = [bundleIdentifier copy];
        _name = [name copy];
        _icon = icon;
        _keyDeliveryMode = keyDeliveryMode;
    }
    return self;
}

@end

@implementation MacKeyBridge

#pragma mark - Toggles

+ (BOOL)isToggleOn:(MacKeyToggle)toggle {
    const MacKeyToggleSpec *spec = specFor(toggle);
    if (!spec) {
        return NO;
    }
    BOOL stored = [defaults() integerForKey:spec->key] != 0;
    if (toggle == MacKeyToggleConvertAlertWhenCompleted) {
        // The defaults key is named for the engine global's meaning but has always
        // stored the checkbox state; the engine global is the inverse of it.
        return stored;
    }
    return spec->invertedKey ? !stored : stored;
}

+ (void)setOn:(BOOL)value toggle:(MacKeyToggle)toggle {
    const MacKeyToggleSpec *spec = specFor(toggle);
    if (!spec) {
        return;
    }
    NSInteger stored = spec->invertedKey ? !value : value;
    [defaults() setInteger:stored forKey:spec->key];
    if (spec->engineGlobal) {
        *spec->engineGlobal = value ? 1 : 0;
    }

    switch (toggle) {
        case MacKeyToggleCheckSpelling:
            OnSpellCheckingChanged();
            break;
        case MacKeyToggleRunOnStartup:
            [appDelegate setRunOnStartup:value];
            break;
        case MacKeyToggleGrayIcon:
            [appDelegate setGrayIcon:value];
            break;
        case MacKeyToggleShowIconOnDock:
            [appDelegate showIconOnDock:value];
            break;
        case MacKeyToggleConvertAlertWhenCompleted:
            convertToolDontAlertWhenCompleted = !value;
            break;
        case MacKeyToggleConvertRemoveMark:
            convertToolRemoveMark = value;
            break;
        case MacKeyToggleUseVietnameseInputSourceDuringSecureInput:
            [MacKeyManager secureInputFallbackSettingDidChange];
            break;
        default:
            break;
    }
    [self notifySettingsChanged];
}

#pragma mark - Input mode

+ (BOOL)vietnameseEnabled {
    return [defaults() integerForKey:@"InputMethod"] == 1;
}

+ (void)toggleInputMethod {
    [appDelegate onInputMethodSelected];
}

+ (NSInteger)inputType {
    return [defaults() integerForKey:@"InputType"];
}

+ (void)setInputType:(NSInteger)index {
    [appDelegate onInputTypeSelectedIndex:(int)index];
}

+ (NSInteger)codeTable {
    return [defaults() integerForKey:@"CodeTable"];
}

+ (void)setCodeTable:(NSInteger)index {
    [appDelegate onCodeTableChanged:(int)index];
}

+ (NSArray<NSString *> *)tableCodeNames {
    return [MacKeyManager getTableCodes];
}

+ (NSArray<NSString *> *)inputTypeNames {
    return @[@"Telex", @"VNI", @"Simple Telex 1", @"Simple Telex 2"];
}

#pragma mark - Hotkeys

+ (int)switchKey {
    return vSwitchKeyStatus;
}

+ (void)setSwitchKey:(int)packed {
    vSwitchKeyStatus = packed;
    [defaults() setInteger:packed forKey:@"SwitchKeyStatus"];
    [self notifySettingsChanged];
}

+ (int)convertHotKey {
    return convertToolHotKey;
}

+ (void)setConvertHotKey:(int)packed {
    convertToolHotKey = packed;
    [defaults() setInteger:packed forKey:@"convertToolHotKey"];
    // The menu item spells the hotkey out, so it has to be rebuilt with the new keys.
    [appDelegate setQuickConvertString];
    [self notifySettingsChanged];
}

#pragma mark - Convert tool

+ (MacKeyConvertCase)convertCase {
    if (convertToolToAllCaps)         return MacKeyConvertCaseAllCaps;
    if (convertToolToAllNonCaps)      return MacKeyConvertCaseAllLower;
    if (convertToolToCapsFirstLetter) return MacKeyConvertCaseFirstLetter;
    if (convertToolToCapsEachWord)    return MacKeyConvertCaseEachWord;
    return MacKeyConvertCaseUnchanged;
}

+ (void)setConvertCase:(MacKeyConvertCase)value {
    convertToolToAllCaps = (value == MacKeyConvertCaseAllCaps);
    convertToolToAllNonCaps = (value == MacKeyConvertCaseAllLower);
    convertToolToCapsFirstLetter = (value == MacKeyConvertCaseFirstLetter);
    convertToolToCapsEachWord = (value == MacKeyConvertCaseEachWord);
    [defaults() setInteger:convertToolToAllCaps forKey:@"convertToolToAllCaps"];
    [defaults() setInteger:convertToolToAllNonCaps forKey:@"convertToolToAllNonCaps"];
    [defaults() setInteger:convertToolToCapsFirstLetter forKey:@"convertToolToCapsFirstLetter"];
    [defaults() setInteger:convertToolToCapsEachWord forKey:@"convertToolToCapsEachWord"];
    [self notifySettingsChanged];
}

+ (NSInteger)convertFromCode {
    return convertToolFromCode;
}

+ (void)setConvertFromCode:(NSInteger)index {
    convertToolFromCode = (Uint8)index;
    [defaults() setInteger:index forKey:@"convertToolFromCode"];
    [self notifySettingsChanged];
}

+ (NSInteger)convertToCode {
    return convertToolToCode;
}

+ (void)setConvertToCode:(NSInteger)index {
    convertToolToCode = (Uint8)index;
    [defaults() setInteger:index forKey:@"convertToolToCode"];
    [self notifySettingsChanged];
}

+ (BOOL)convertClipboard {
    return [MacKeyManager quickConvert];
}

#pragma mark - Macros

+ (NSArray<MacKeyMacro *> *)macros {
    std::vector<std::vector<Uint32>> keys;
    std::vector<std::string> texts;
    std::vector<std::string> contents;
    getAllMacro(keys, texts, contents);

    NSMutableArray<MacKeyMacro *> *result = [NSMutableArray arrayWithCapacity:texts.size()];
    for (size_t i = 0; i < texts.size() && i < contents.size(); i++) {
        NSString *text = [NSString stringWithUTF8String:texts[i].c_str()];
        NSString *content = [NSString stringWithUTF8String:contents[i].c_str()];
        if (text && content) {
            [result addObject:[[MacKeyMacro alloc] initWithText:text content:content]];
        }
    }
    return result;
}

+ (BOOL)hasMacro:(NSString *)text {
    return hasMacro(std::string(text.UTF8String));
}

/// Persist the macro table. The engine keeps it in memory and serialises on demand;
/// only this method knows it lands in the "macroData" default.
+ (void)saveMacros {
    std::vector<Byte> data;
    getMacroSaveData(data);
    [defaults() setObject:[NSData dataWithBytes:data.data() length:data.size()] forKey:@"macroData"];
    [self notifySettingsChanged];
}

+ (void)setMacro:(NSString *)text content:(NSString *)content {
    addMacro(std::string(text.UTF8String), std::string(content.UTF8String));
    [self saveMacros];
}

+ (void)deleteMacro:(NSString *)text {
    if (deleteMacro(std::string(text.UTF8String))) {
        [self saveMacros];
    }
}

+ (BOOL)importMacrosFromPath:(NSString *)path keepingExisting:(BOOL)keepExisting {
    readFromFile(std::string(path.UTF8String), keepExisting);
    [self saveMacros];
    return YES;
}

+ (BOOL)exportMacrosToPath:(NSString *)path {
    saveToFile(std::string(path.UTF8String));
    return YES;
}

#pragma mark - Compatibility

+ (NSArray<MacKeyApplicationKeyMode *> *)applicationKeyModes {
    NSDictionary<NSString *, NSNumber *> *savedModes = [defaults() dictionaryForKey:@"ApplicationKeyModes"] ?: @{};
    NSMutableOrderedSet<NSString *> *bundleIdentifiers = [NSMutableOrderedSet orderedSetWithArray:[defaults() arrayForKey:@"VietnameseTypingApplications"] ?: @[]];

    // Smart Switch learns every app that receives focus. Compatibility should
    // instead show only apps where the user actually pressed a normal typing
    // key while Vietnamese mode was active (recorded by MacKey.mm).

    NSMutableArray<MacKeyApplicationKeyMode *> *result = [NSMutableArray arrayWithCapacity:bundleIdentifiers.count];
    NSArray<NSRunningApplication *> *runningApplications = [NSWorkspace sharedWorkspace].runningApplications;
    for (NSString *bundleIdentifier in bundleIdentifiers) {
        NSRunningApplication *running = nil;
        for (NSRunningApplication *candidate in runningApplications) {
            if ([candidate.bundleIdentifier isEqualToString:bundleIdentifier]) {
                running = candidate;
                break;
            }
        }
        // Smart Switch remembers bundle identifiers after an app has been used.
        // Do not keep showing stale rows after that app has been uninstalled. A
        // running app is retained even if Launch Services has not indexed it yet.
        NSURL *applicationURL = running.bundleURL ?: [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleIdentifier];
        if (applicationURL == nil && running == nil) continue;
        NSBundle *applicationBundle = applicationURL ? [NSBundle bundleWithURL:applicationURL] : nil;
        NSString *name = running.localizedName ?: [applicationBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        if (name.length == 0) name = bundleIdentifier;
        NSImage *icon = running.icon ?: (applicationURL ? [[NSWorkspace sharedWorkspace] iconForFile:applicationURL.path] : nil);
        if (icon == nil) icon = [NSImage imageNamed:NSImageNameApplicationIcon];
        [result addObject:[[MacKeyApplicationKeyMode alloc] initWithBundleIdentifier:bundleIdentifier
                                                                              name:name
                                                                              icon:icon
                                                                  keyDeliveryMode:(MacKeyApplicationKeyDeliveryMode)[savedModes[bundleIdentifier] integerValue]]];
    }
    [result sortUsingComparator:^NSComparisonResult(MacKeyApplicationKeyMode *left, MacKeyApplicationKeyMode *right) {
        return [left.name localizedCaseInsensitiveCompare:right.name];
    }];
    return result;
}

+ (void)setKeyDeliveryMode:(MacKeyApplicationKeyDeliveryMode)mode forApplication:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) return;
    NSMutableDictionary<NSString *, NSNumber *> *savedModes = [[defaults() dictionaryForKey:@"ApplicationKeyModes"] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (mode != MacKeyApplicationKeyDeliveryModeDefault) {
        savedModes[bundleIdentifier] = @(mode);
    } else {
        [savedModes removeObjectForKey:bundleIdentifier];
    }
    [defaults() setObject:savedModes forKey:@"ApplicationKeyModes"];
    // The keyboard callback reads this setting for every generated replacement.
    // Close any in-progress composition so the very next key cannot use the
    // delivery strategy selected before this change.
    RequestNewSession();
    MacKeyDebugLog([NSString stringWithFormat:@"Compatibility mode applied immediately: %@ = %@.",
                 bundleIdentifier, keyDeliveryModeDescription(mode)]);
    [self notifySettingsChanged];
}

#pragma mark - Whole-app actions

+ (void)restoreDefaultSettings {
    [appDelegate loadDefaultConfig];
    // loadDefaultConfig covers the engine's own settings. Compatibility also
    // stores per-app state outside the engine, so clear it rather than leaving
    // a reset-looking UI with old delivery choices and remembered apps.
    [defaults() removeObjectForKey:@"ApplicationKeyModes"];
    [defaults() removeObjectForKey:@"VietnameseTypingApplications"];
    [defaults() setBool:NO forKey:@"UseVietnameseInputSourceDuringSecureInput"];
    [defaults() setBool:NO forKey:@"MoveCursorBeforeTeamsImagePaste"];
    [defaults() setBool:NO forKey:@"CleanTextFormattingBeforeTeamsPaste"];
    [MacKeyManager secureInputFallbackSettingDidChange];

    // These two are app-level settings, not engine globals.
    [defaults() setInteger:0 forKey:@"ShowUIOnStartup"];
    [defaults() setInteger:1 forKey:@"RunOnStartup"];
    [appDelegate setRunOnStartup:YES];
    [self notifySettingsChanged];
}

+ (void)loadSettingsOnly {
    MacKeyInit();
}

+ (void)notifySettingsChanged {
    if ([NSThread isMainThread]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:MacKeySettingsDidChangeNotification object:nil];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:MacKeySettingsDidChangeNotification object:nil];
        });
    }
}

#pragma mark - App info

+ (NSString *)versionSummary {
    NSBundle *bundle = [NSBundle mainBundle];
    return [NSString stringWithFormat:@"%@ (%@)",
            [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
            [bundle objectForInfoDictionaryKey:@"CFBundleVersion"]];
}

+ (BOOL)accessibilityGranted {
    return MJAccessibilityIsEnabled();
}

+ (void)openAccessibilitySettings {
    MJAccessibilityOpenPanel();
}

@end
