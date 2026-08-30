//
//  OhMyKeyBridge.mm
//  OhMyKey
//
//  Objective-C++ so it can reach the C++ engine; the header it publishes is plain
//  Objective-C so Swift can import it. See OhMyKeyBridge.h for why this exists.
//

#import "OhMyKeyBridge.h"
#import "AppDelegate.h"
#import "OhMyKeyManager.h"
#import "MJAccessibilityUtils.h"

#include "Engine.h"
#include "ConvertTool.h"

extern AppDelegate *appDelegate;

// Defined inside an extern "C" block in OhMyKey.mm, so they must be declared as C here
// too or this translation unit looks for mangled names.
extern "C" void OhMyKeyInit(void);
extern "C" void OnSpellCheckingChanged(void);

// Settings the macOS app owns rather than the cross-platform engine, so they are
// defined in AppDelegate.m instead of being declared in Engine.h.
extern int vSendKeyStepByStep;
extern int vFixChromiumBrowser;
extern int vPerformLayoutCompat;
extern int vShowIconOnDock;

NSNotificationName const OMKSettingsDidChangeNotification = @"OMKSettingsDidChangeNotification";

#pragma mark - Toggle table

/// What one toggle needs in order to be read and written.
///
/// `invertedKey` covers the two settings whose stored form is the opposite of what the
/// UI shows: "check for updates on startup" is stored as DontCheckUpdate, and the convert
/// tool stores "don't alert when finished". Keeping the inversion in the table means the
/// rest of the app can talk about the setting the way a person would.
typedef struct {
    OMKToggle toggle;
    int *engineGlobal;      // NULL for settings the engine never reads
    __unsafe_unretained NSString *key;
    BOOL invertedKey;
} OMKToggleSpec;

static const OMKToggleSpec *specFor(OMKToggle toggle) {
    static OMKToggleSpec specs[] = {
        {OMKToggleFreeMark,                 &vFreeMark,               @"FreeMark",              NO},
        {OMKToggleModernOrthography,        &vUseModernOrthography,   @"ModernOrthography",     NO},
        {OMKToggleCheckSpelling,            &vCheckSpelling,          @"Spelling",              NO},
        {OMKToggleQuickTelex,               &vQuickTelex,             @"QuickTelex",            NO},
        {OMKToggleRestoreIfInvalidWord,     &vRestoreIfWrongSpelling, @"RestoreIfInvalidWord",  NO},
        {OMKToggleTempOffSpelling,          &vTempOffSpelling,        @"vTempOffSpelling",      NO},
        {OMKToggleAllowConsonantZFWJ,       &vAllowConsonantZFWJ,     @"vAllowConsonantZFWJ",   NO},
        {OMKToggleFixRecommendBrowser,      &vFixRecommendBrowser,    @"FixRecommendBrowser",   NO},
        {OMKToggleFixChromiumBrowser,       &vFixChromiumBrowser,     @"vFixChromiumBrowser",   NO},
        {OMKToggleSendKeyStepByStep,        &vSendKeyStepByStep,      @"SendKeyStepByStep",     NO},
        {OMKTogglePerformLayoutCompat,      &vPerformLayoutCompat,    @"vPerformLayoutCompat",  NO},
        {OMKToggleUseMacro,                 &vUseMacro,               @"UseMacro",              NO},
        {OMKToggleUseMacroInEnglishMode,    &vUseMacroInEnglishMode,  @"UseMacroInEnglishMode", NO},
        {OMKToggleAutoCapsMacro,            &vAutoCapsMacro,          @"vAutoCapsMacro",        NO},
        {OMKToggleUseSmartSwitchKey,        &vUseSmartSwitchKey,      @"UseSmartSwitchKey",     NO},
        {OMKToggleUpperCaseFirstChar,       &vUpperCaseFirstChar,     @"UpperCaseFirstChar",    NO},
        {OMKToggleQuickStartConsonant,      &vQuickStartConsonant,    @"vQuickStartConsonant",  NO},
        {OMKToggleQuickEndConsonant,        &vQuickEndConsonant,      @"vQuickEndConsonant",    NO},
        {OMKToggleRememberCode,             &vRememberCode,           @"vRememberCode",         NO},
        {OMKToggleOtherLanguage,            &vOtherLanguage,          @"vOtherLanguage",        NO},
        {OMKToggleTempOffOhMyKey,           &vTempOffOhMyKey,         @"vTempOffOhMyKey",       NO},
        {OMKToggleShowIconOnDock,           &vShowIconOnDock,         @"vShowIconOnDock",       NO},
        {OMKToggleShowUIOnStartup,          NULL,                     @"ShowUIOnStartup",       NO},
        {OMKToggleRunOnStartup,             NULL,                     @"RunOnStartup",          NO},
        {OMKToggleGrayIcon,                 NULL,                     @"GrayIcon",              NO},
        {OMKToggleCheckUpdateOnStartup,     NULL,                     @"DontCheckUpdate",       YES},
        {OMKToggleConvertAlertWhenCompleted, NULL,                    @"convertToolDontAlertWhenCompleted", NO},
        {OMKToggleConvertRemoveMark,        NULL,                     @"convertToolRemoveMark", NO},
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

@implementation OMKMacro

- (instancetype)initWithText:(NSString *)text content:(NSString *)content {
    if ((self = [super init])) {
        _text = [text copy];
        _content = [content copy];
    }
    return self;
}

@end

@implementation OMKBridge

#pragma mark - Toggles

+ (BOOL)isToggleOn:(OMKToggle)toggle {
    const OMKToggleSpec *spec = specFor(toggle);
    if (!spec) {
        return NO;
    }
    BOOL stored = [defaults() integerForKey:spec->key] != 0;
    if (toggle == OMKToggleConvertAlertWhenCompleted) {
        // The defaults key is named for the engine global's meaning but has always
        // stored the checkbox state; the engine global is the inverse of it.
        return stored;
    }
    return spec->invertedKey ? !stored : stored;
}

+ (void)setOn:(BOOL)value toggle:(OMKToggle)toggle {
    const OMKToggleSpec *spec = specFor(toggle);
    if (!spec) {
        return;
    }
    NSInteger stored = spec->invertedKey ? !value : value;
    [defaults() setInteger:stored forKey:spec->key];
    if (spec->engineGlobal) {
        *spec->engineGlobal = value ? 1 : 0;
    }

    switch (toggle) {
        case OMKToggleCheckSpelling:
            OnSpellCheckingChanged();
            break;
        case OMKToggleRunOnStartup:
            [appDelegate setRunOnStartup:value];
            break;
        case OMKToggleGrayIcon:
            [appDelegate setGrayIcon:value];
            break;
        case OMKToggleShowIconOnDock:
            [appDelegate showIconOnDock:value];
            break;
        case OMKToggleConvertAlertWhenCompleted:
            convertToolDontAlertWhenCompleted = !value;
            break;
        case OMKToggleConvertRemoveMark:
            convertToolRemoveMark = value;
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
    return [OhMyKeyManager getTableCodes];
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

+ (OMKConvertCase)convertCase {
    if (convertToolToAllCaps)         return OMKConvertCaseAllCaps;
    if (convertToolToAllNonCaps)      return OMKConvertCaseAllLower;
    if (convertToolToCapsFirstLetter) return OMKConvertCaseFirstLetter;
    if (convertToolToCapsEachWord)    return OMKConvertCaseEachWord;
    return OMKConvertCaseUnchanged;
}

+ (void)setConvertCase:(OMKConvertCase)value {
    convertToolToAllCaps = (value == OMKConvertCaseAllCaps);
    convertToolToAllNonCaps = (value == OMKConvertCaseAllLower);
    convertToolToCapsFirstLetter = (value == OMKConvertCaseFirstLetter);
    convertToolToCapsEachWord = (value == OMKConvertCaseEachWord);
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
    return [OhMyKeyManager quickConvert];
}

#pragma mark - Macros

+ (NSArray<OMKMacro *> *)macros {
    std::vector<std::vector<Uint32>> keys;
    std::vector<std::string> texts;
    std::vector<std::string> contents;
    getAllMacro(keys, texts, contents);

    NSMutableArray<OMKMacro *> *result = [NSMutableArray arrayWithCapacity:texts.size()];
    for (size_t i = 0; i < texts.size() && i < contents.size(); i++) {
        NSString *text = [NSString stringWithUTF8String:texts[i].c_str()];
        NSString *content = [NSString stringWithUTF8String:contents[i].c_str()];
        if (text && content) {
            [result addObject:[[OMKMacro alloc] initWithText:text content:content]];
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

#pragma mark - Whole-app actions

+ (void)restoreDefaultSettings {
    [appDelegate loadDefaultConfig];
    // loadDefaultConfig covers the engine's own settings; these two are the app's.
    [defaults() setInteger:0 forKey:@"ShowUIOnStartup"];
    [defaults() setInteger:1 forKey:@"RunOnStartup"];
    [appDelegate setRunOnStartup:YES];
    [self notifySettingsChanged];
}

+ (void)loadSettingsOnly {
    OhMyKeyInit();
}

+ (void)notifySettingsChanged {
    if ([NSThread isMainThread]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:OMKSettingsDidChangeNotification object:nil];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:OMKSettingsDidChangeNotification object:nil];
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
