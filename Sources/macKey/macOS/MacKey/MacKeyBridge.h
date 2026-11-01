//
//  MacKeyBridge.h
//  macKey
//
//  The single door between the SwiftUI layer and the engine.
//
//  The engine is C++ (std::string, std::vector) and its settings live in plain C
//  globals that the key-event callback reads live, mirrored into NSUserDefaults.
//  Neither can be handed to Swift directly, and the old view controllers open-coded
//  "write the default, assign the global, then call the one side effect that setting
//  needs" at every checkbox - which is exactly the kind of thing that rots. Here each
//  setting is named once and written in one place, so a new UI cannot forget a step.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted (on the main thread) whenever a setting changes, including changes made from
/// the status-bar menu or by a hotkey. The SwiftUI layer re-reads everything on this.
extern NSNotificationName const MacKeySettingsDidChangeNotification;

/// Every on/off setting in the app. The raw values are not persisted anywhere - the
/// defaults key each one maps to is an implementation detail of MacKeyBridge.mm.
typedef NS_ENUM(NSInteger, MacKeyToggle) {
    MacKeyToggleFreeMark,
    MacKeyToggleModernOrthography,
    MacKeyToggleCheckSpelling,
    MacKeyToggleQuickTelex,
    MacKeyToggleRestoreIfInvalidWord,
    MacKeyToggleTempOffSpelling,
    MacKeyToggleAllowConsonantZFWJ,
    MacKeyToggleFixRecommendBrowser,
    MacKeyToggleFixChromiumBrowser,
    MacKeyTogglePerformLayoutCompat,
    MacKeyToggleUseMacro,
    MacKeyToggleUseMacroInEnglishMode,
    MacKeyToggleAutoCapsMacro,
    MacKeyToggleAutoTrimClipboardTrailingNewlines,
    MacKeyToggleUseVietnameseInputSourceDuringSecureInput,
    MacKeyToggleMoveCursorBeforeTeamsImagePaste,
    MacKeyToggleCleanTextFormattingBeforeTeamsPaste,
    MacKeyToggleUseSmartSwitchKey,
    MacKeyToggleUpperCaseFirstChar,
    MacKeyToggleQuickStartConsonant,
    MacKeyToggleQuickEndConsonant,
    MacKeyToggleRememberCode,
    MacKeyToggleOtherLanguage,
    MacKeyToggleTempOffMacKey,
    MacKeyToggleShowIconOnDock,
    MacKeyToggleShowUIOnStartup,
    MacKeyToggleRunOnStartup,
    MacKeyToggleGrayIcon,
    MacKeyToggleCheckUpdateOnStartup,
    MacKeyToggleConvertAlertWhenCompleted,
    MacKeyToggleConvertRemoveMark,
};

/// The convert tool's letter-case options are mutually exclusive, but the engine stores
/// them as four independent bools. Modelling them as one choice here keeps the "turn the
/// other three off" rule in one place instead of in four checkbox handlers.
typedef NS_ENUM(NSInteger, MacKeyConvertCase) {
    MacKeyConvertCaseUnchanged = 0,
    MacKeyConvertCaseAllCaps,
    MacKeyConvertCaseAllLower,
    MacKeyConvertCaseFirstLetter,
    MacKeyConvertCaseEachWord,
};

/// One row of the macro (gõ tắt) table.
@interface MacKeyMacro : NSObject
@property (nonatomic, copy, readonly) NSString *text;
@property (nonatomic, copy, readonly) NSString *content;
- (instancetype)initWithText:(NSString *)text content:(NSString *)content;
@end

typedef NS_ENUM(NSInteger, MacKeyApplicationKeyDeliveryMode) {
    MacKeyApplicationKeyDeliveryModeDefault = 0,
    MacKeyApplicationKeyDeliveryModeKeyByKey = 1,
    MacKeyApplicationKeyDeliveryModeClipboardPaste = 2,
};

/// One application shown in Compatibility. Its delivery mode overrides the
/// normal replacement delivery for that application only.
@interface MacKeyApplicationKeyMode : NSObject
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) NSImage *icon;
@property (nonatomic, readonly) MacKeyApplicationKeyDeliveryMode keyDeliveryMode;
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                                    name:(NSString *)name
                                    icon:(NSImage *)icon
                        keyDeliveryMode:(MacKeyApplicationKeyDeliveryMode)keyDeliveryMode;
@end

@interface MacKeyBridge : NSObject

#pragma mark - Toggles

+ (BOOL)isToggleOn:(MacKeyToggle)toggle NS_SWIFT_NAME(isOn(_:));
+ (void)setOn:(BOOL)value toggle:(MacKeyToggle)toggle NS_SWIFT_NAME(setOn(_:toggle:));

#pragma mark - Input mode

/// YES when Vietnamese input is active, NO for English passthrough.
@property (class, nonatomic, readonly) BOOL vietnameseEnabled;
+ (void)toggleInputMethod;

/// 0 Telex, 1 VNI, 2 Simple Telex 1, 3 Simple Telex 2.
@property (class, nonatomic, readonly) NSInteger inputType;
+ (void)setInputType:(NSInteger)index;

/// Index into +tableCodeNames.
@property (class, nonatomic, readonly) NSInteger codeTable;
+ (void)setCodeTable:(NSInteger)index;

@property (class, nonatomic, readonly) NSArray<NSString *> *tableCodeNames;
@property (class, nonatomic, readonly) NSArray<NSString *> *inputTypeNames;

#pragma mark - Hotkeys

/// Packed as: bits 0-7 key code, 8 control, 9 option, 10 command, 11 shift,
/// 15 beep on switch, 24-31 the character to display. 0xFE means "no key".
@property (class, nonatomic, readonly) int switchKey;
+ (void)setSwitchKey:(int)packed;

@property (class, nonatomic, readonly) int convertHotKey;
+ (void)setConvertHotKey:(int)packed;

#pragma mark - Convert tool

@property (class, nonatomic, readonly) MacKeyConvertCase convertCase;
+ (void)setConvertCase:(MacKeyConvertCase)value;

@property (class, nonatomic, readonly) NSInteger convertFromCode;
+ (void)setConvertFromCode:(NSInteger)index;

@property (class, nonatomic, readonly) NSInteger convertToCode;
+ (void)setConvertToCode:(NSInteger)index;

/// Converts the clipboard in place. NO when the clipboard holds nothing convertible.
+ (BOOL)convertClipboard;

#pragma mark - Macros

@property (class, nonatomic, readonly) NSArray<MacKeyMacro *> *macros;
+ (BOOL)hasMacro:(NSString *)text;
+ (void)setMacro:(NSString *)text content:(NSString *)content;
+ (void)deleteMacro:(NSString *)text;
+ (BOOL)importMacrosFromPath:(NSString *)path keepingExisting:(BOOL)keepExisting;
+ (BOOL)exportMacrosToPath:(NSString *)path;

#pragma mark - Compatibility

+ (NSArray<MacKeyApplicationKeyMode *> *)applicationKeyModes;
+ (void)setKeyDeliveryMode:(MacKeyApplicationKeyDeliveryMode)mode forApplication:(NSString *)bundleIdentifier;

#pragma mark - Whole-app actions

+ (void)restoreDefaultSettings;

/// Re-reads the engine settings into the app without installing the event tap. Only
/// used by the UI-preview harness; the normal launch path goes through the event tap.
+ (void)loadSettingsOnly;

/// Tells the UI that something outside it changed a setting.
+ (void)notifySettingsChanged;

#pragma mark - App info

@property (class, nonatomic, readonly) NSString *versionSummary;
@property (class, nonatomic, readonly) BOOL accessibilityGranted;
+ (void)openAccessibilitySettings;

@end

NS_ASSUME_NONNULL_END
