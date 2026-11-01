//
//  MacKey.mm
//  macKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai (OpenKey). Additional changes © 2026 Hung Doan. GPL.
//
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Engine.h"
#import "AppDelegate.h"
#import "MacKeyBridge.h"
#import "MacKeyManager.h"

#define FRONT_APP [[NSWorkspace sharedWorkspace] frontmostApplication].bundleIdentifier
#define OTHER_CONTROL_KEY (_flag & kCGEventFlagMaskCommand) || (_flag & kCGEventFlagMaskControl) || \
                            (_flag & kCGEventFlagMaskAlternate) || (_flag & kCGEventFlagMaskSecondaryFn) || \
                            (_flag & kCGEventFlagMaskNumericPad) || (_flag & kCGEventFlagMaskHelp)

#define DYNA_DATA(macro, pos) (macro ? pData->macroData[pos] : pData->charData[pos])
#define MAX_UNICODE_STRING  20
#define EMPTY_HOTKEY 0xFE0000FE
#define LOAD_DATA(VAR, KEY) VAR = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@#KEY]

// Ignore code for Modifier keys and numpad
// Reference: https://eastmanreference.com/complete-list-of-applescript-key-codes
NSDictionary *keyStringToKeyCodeMap = @{
    // Characters from number row
    @"`": @50, @"~": @50, @"1": @18, @"!": @18, @"2": @19, @"@": @19, @"3": @20, @"#": @20, @"4": @21, @"$": @21,
    @"5": @23, @"%": @23, @"6": @22, @"^": @22, @"7": @26, @"&": @26, @"8": @28, @"*": @28, @"9": @25, @"(": @25,
    @"0": @29, @")": @29, @"-": @27, @"_": @27, @"=": @24, @"+": @24,
    // Characters from first keyboard row
    @"q": @12, @"w": @13, @"e": @14, @"r": @15, @"t": @17, @"y": @16, @"u": @32, @"i": @34, @"o": @31, @"p": @35,
    @"[": @33, @"{": @33, @"]": @30, @"}": @30, @"\\": @42, @"|": @42,
    // Characters from second keyboard row
    @"a": @0, @"s": @1, @"d": @2, @"f": @3, @"g": @5, @"h": @4, @"j": @38, @"k": @40, @"l": @37,
    @";": @41, @":": @41, @"'": @39, @"\"": @39,
    // Characters from second third row
    @"z": @6, @"x": @7, @"c": @8, @"v": @9, @"b": @11, @"n": @45, @"m": @46,
    @",": @43, @"<": @43, @".": @47, @">": @47, @"/": @44, @"?": @44
};

extern AppDelegate* appDelegate;
extern int vFixChromiumBrowser;
extern int vPerformLayoutCompat;

extern "C" {
    //app which must sent special empty character
    NSArray* _niceSpaceApp = @[@"com.sublimetext.3",
                               @"com.sublimetext.2",
                             ];
    
    // Known browsers that use the Chromium-style replacement path when the
    // optional browser compatibility setting is enabled.
    NSArray* _unicodeCompoundApp = @[@"com.apple.",
                                     @"com.google.Chrome", @"com.brave.Browser",
                                     @"com.microsoft.edgemac.Dev", @"com.microsoft.edgemac.Beta", @"com.microsoft.Edge.Dev", @"com.microsoft.Edge"];
    NSArray* _recommendWorkaroundDisabledApp = @[@"com.apple.Spotlight"];
    
    CGEventSourceRef myEventSource = NULL;
    vKeyHookState* pData;
    CGEventRef eventBackSpaceDown;
    CGEventRef eventBackSpaceUp;
    UniChar _newChar, _newCharHi;
    CGEventRef _newEventDown, _newEventUp;
    CGKeyCode _keycode;
    CGEventFlags _flag, _lastFlag = 0, _privateFlag;
    CGEventTapProxy _proxy;
    
    Uint16 _newCharString[MAX_UNICODE_STRING];
    Uint16 _newCharSize;
    bool _willContinuteSending = false;
    bool _willSendControlKey = false;
    
    vector<Uint16> _syncKey;
    
    Uint16 _uniChar[2];
    int _i, _j, _k;
    Uint32 _tempChar;
    bool _hasJustUsedHotKey = false;

    int _languageTemp = 0; //use for smart switch key
    vector<Byte> savedSmartSwitchKeyData; ////use for smart switch key
    
    NSString* _frontMostApp = @"UnknownApp";

    // Clipboard Paste needs the system pasteboard for Command-V. Keep the
    // user's original contents for the whole burst of replacement events,
    // rather than taking a new snapshot for every converted character.
    NSArray<NSPasteboardItem *> *_clipboardBeforeCompatibilityPaste;
    NSInteger _compatibilityPasteboardChangeCount = NSNotFound;
    NSUInteger _compatibilityPasteGeneration = 0;
    
    void MacKeyInit() {
        //load saved data
        vFreeMark = 0;//(int)[[NSUserDefaults standardUserDefaults] integerForKey:@"FreeMark"];
        LOAD_DATA(vCodeTable, CodeTable); if (vCodeTable < 0) vCodeTable = 0;
        LOAD_DATA(vCheckSpelling, Spelling);
        LOAD_DATA(vQuickTelex, QuickTelex);
        LOAD_DATA(vUseModernOrthography, ModernOrthography);
        LOAD_DATA(vRestoreIfWrongSpelling, RestoreIfInvalidWord);
        LOAD_DATA(vFixRecommendBrowser, FixRecommendBrowser);
        LOAD_DATA(vUseMacro, UseMacro);
        LOAD_DATA(vUseMacroInEnglishMode, UseMacroInEnglishMode);
        LOAD_DATA(vAutoCapsMacro, vAutoCapsMacro);
        // The legacy global "SendKeyStepByStep" preference is superseded by
        // Compatibility's per-application Send key-by-key mode.
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SendKeyStepByStep"];
        LOAD_DATA(vUseSmartSwitchKey, UseSmartSwitchKey);
        LOAD_DATA(vUpperCaseFirstChar, UpperCaseFirstChar);
        
        LOAD_DATA(vTempOffSpelling, vTempOffSpelling);
        LOAD_DATA(vAllowConsonantZFWJ, vAllowConsonantZFWJ);
        LOAD_DATA(vQuickEndConsonant, vQuickEndConsonant);
        LOAD_DATA(vQuickStartConsonant, vQuickStartConsonant);
        LOAD_DATA(vRememberCode, vRememberCode);
        LOAD_DATA(vOtherLanguage, vOtherLanguage);
        // Migrate the old preference name once so an existing toggle setting survives
        // the internal MacKey rename.
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *legacyTempOffKey = @"vTempOffOhMyKey";
        if ([defaults objectForKey:@"vTempOffMacKey"] == nil) {
            id legacyValue = [defaults objectForKey:legacyTempOffKey];
            if (legacyValue != nil) {
                [defaults setObject:legacyValue forKey:@"vTempOffMacKey"];
            }
        }
        [defaults removeObjectForKey:legacyTempOffKey];
        LOAD_DATA(vTempOffMacKey, vTempOffMacKey);
        
        LOAD_DATA(vFixChromiumBrowser, vFixChromiumBrowser);
        
        LOAD_DATA(vPerformLayoutCompat, vPerformLayoutCompat);
        
        myEventSource = CGEventSourceCreate(kCGEventSourceStatePrivate);
        pData = (vKeyHookState*)vKeyInit();

        eventBackSpaceDown = CGEventCreateKeyboardEvent (myEventSource, 51, true);
        eventBackSpaceUp = CGEventCreateKeyboardEvent (myEventSource, 51, false);
        
        //init and load macro data
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        NSData *data = [prefs objectForKey:@"macroData"];
        initMacroMap((Byte*)data.bytes, (int)data.length);
        
        //init and load smart switch key data
        data = [prefs objectForKey:@"smartSwitchKey"];
        initSmartSwitchKey((Byte*)data.bytes, (int)data.length);
        
        //init convert tool
        convertToolDontAlertWhenCompleted = ![prefs boolForKey:@"convertToolDontAlertWhenCompleted"];
        convertToolToAllCaps = [prefs boolForKey:@"convertToolToAllCaps"];
        convertToolToAllNonCaps = [prefs boolForKey:@"convertToolToAllNonCaps"];
        convertToolToCapsFirstLetter = [prefs boolForKey:@"convertToolToCapsFirstLetter"];
        convertToolToCapsEachWord = [prefs boolForKey:@"convertToolToCapsEachWord"];
        convertToolRemoveMark = [prefs boolForKey:@"convertToolRemoveMark"];
        convertToolFromCode = [prefs integerForKey:@"convertToolFromCode"];
        convertToolToCode = [prefs integerForKey:@"convertToolToCode"];
        convertToolHotKey = (int)[prefs integerForKey:@"convertToolHotKey"];
        if (convertToolHotKey == 0) {
            convertToolHotKey = EMPTY_HOTKEY;
        }
    }
    
    void RequestNewSession() {
        //send event signal to Engine
        vKeyHandleEvent(vKeyEvent::Mouse, vKeyEventState::MouseDown, 0);
        
        if (IS_DOUBLE_CODE(vCodeTable)) { //VNI
            _syncKey.clear();
        }
    }
    
    void queryFrontMostApp() {
        if ([[[NSWorkspace sharedWorkspace] frontmostApplication].bundleIdentifier compare:MACKEY_BUNDLE] != 0) {
            _frontMostApp = [[NSWorkspace sharedWorkspace] frontmostApplication].bundleIdentifier;
            if (_frontMostApp == nil)
                _frontMostApp = [[NSWorkspace sharedWorkspace] frontmostApplication].localizedName != nil ?
                [[NSWorkspace sharedWorkspace] frontmostApplication].localizedName : @"UnknownApp";
        }
    }

    NSString *smartSwitchAppName() {
        NSRunningApplication *frontmostApp = [NSWorkspace sharedWorkspace].frontmostApplication;
        return frontmostApp.localizedName ?: _frontMostApp ?: @"Unknown app";
    }

    NSString *smartSwitchInputMethodName(int inputMethod) {
        return inputMethod == 1 ? @"Vietnamese" : @"English";
    }

    NSString *smartSwitchInputTypeName(int inputType) {
        static NSArray<NSString *> *names = @[@"Telex", @"VNI", @"Simple Telex 1", @"Simple Telex 2"];
        return inputType >= 0 && inputType < (int)names.count ? names[inputType] : @"Unknown";
    }

    NSString *smartSwitchCodeTableName(int codeTable) {
        static NSArray<NSString *> *names = @[@"Unicode", @"TCVN3 (ABC)", @"VNI Windows", @"Unicode composite", @"Vietnamese Locale CP 1258"];
        return codeTable >= 0 && codeTable < (int)names.count ? names[codeTable] : @"Unknown";
    }

    bool isVNIControlKey(CGKeyCode keyCode) {
        switch (keyCode) {
            case 18: case 19: case 20: case 21: case 22:
            case 23: case 25: case 26: case 28: case 29:
                return true;
            default:
                return false;
        }
    }

    NSString *engineResultName(Byte result) {
        switch (result) {
            case vDoNothing: return @"passthrough";
            case vWillProcess: return @"processed";
            case vBreakWord: return @"word break";
            case vRestore: return @"restored";
            case vReplaceMaro: return @"macro";
            case vRestoreAndStartNewSession: return @"restored/new session";
            default: return @"unknown";
        }
    }
    
    NSString* ConvertUtil(NSString* str) {
        return [NSString stringWithUTF8String:convertUtil([str UTF8String]).c_str()];
    }
    
    BOOL containUnicodeCompoundApp(NSString* topApp) {
        if (topApp == nil) return false;
        for (_j = 0; _j < [_unicodeCompoundApp count]; _j++) {
            if ([topApp hasPrefix:[_unicodeCompoundApp objectAtIndex:_j]] || [[_unicodeCompoundApp objectAtIndex:_j] isEqualToString:topApp])
                return true;
        }
        return false;
    }

    NSString *chromiumRuntimeForFrontmostApp(NSString *topApp) {
        static NSMutableDictionary<NSString *, id> *runtimeCache;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            runtimeCache = [NSMutableDictionary dictionary];
        });

        NSRunningApplication *frontmostApp = [NSWorkspace sharedWorkspace].frontmostApplication;
        if (topApp.length == 0 || ![frontmostApp.bundleIdentifier isEqualToString:topApp]) return nil;

        NSString *bundlePath = frontmostApp.bundleURL.path;
        if (bundlePath.length == 0) return nil;

        @synchronized (runtimeCache) {
            id cachedRuntime = runtimeCache[bundlePath];
            if (cachedRuntime != nil) return cachedRuntime == [NSNull null] ? nil : cachedRuntime;

            NSDictionary<NSString *, NSString *> *frameworks = @{
                @"Electron Framework.framework": @"Electron",
                @"Chromium Embedded Framework.framework": @"Chromium Embedded Framework",
                @"Chromium Framework.framework": @"Chromium",
                // New Microsoft Teams is not Electron. Its MSWebView2 runtime
                // uses Chromium's event model and needs the same key path.
                @"MSWebView2.framework": @"Microsoft WebView2",
                @"WebView2.framework": @"WebView2"
            };
            NSString *runtime = nil;
            for (NSString *frameworkName in frameworks) {
                NSString *frameworkPath = [bundlePath stringByAppendingPathComponent:[@"Contents/Frameworks" stringByAppendingPathComponent:frameworkName]];
                if ([[NSFileManager defaultManager] fileExistsAtPath:frameworkPath]) {
                    runtime = frameworks[frameworkName];
                    break;
                }
            }

            runtimeCache[bundlePath] = runtime ?: [NSNull null];
            return runtime;
        }
    }

    NSInteger keyDeliveryModeForApp(NSString *topApp) {
        if (topApp.length == 0) return 0;
        NSDictionary<NSString *, NSNumber *> *modes = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"ApplicationKeyModes"];
        return [modes[topApp] integerValue];
    }

    BOOL shouldSendKeyByKeyForApp(NSString *topApp) {
        return keyDeliveryModeForApp(topApp) == 1;
    }

    BOOL shouldUseClipboardPasteForApp(NSString *topApp) {
        return keyDeliveryModeForApp(topApp) == 2 && vCodeTable == 0;
    }

    BOOL isMicrosoftTeams(NSString *bundleIdentifier) {
        return [bundleIdentifier isEqualToString:@"com.microsoft.teams"] ||
               [bundleIdentifier isEqualToString:@"com.microsoft.teams2"];
    }

    NSUInteger clipboardImageCount(void) {
        NSUInteger imageCount = 0;
        for (NSPasteboardItem *item in NSPasteboard.generalPasteboard.pasteboardItems ?: @[]) {
            for (NSPasteboardType type in item.types) {
                UTType *contentType = [UTType typeWithIdentifier:type];
                if ([contentType conformsToType:UTTypeImage]) {
                    imageCount++;
                    break;
                }
            }
        }
        return imageCount;
    }

    BOOL htmlDataContainsImage(NSData *htmlData) {
        if (htmlData == nil) return NO;
        NSArray<NSNumber *> *encodings = @[
            @(NSUTF8StringEncoding),
            @(NSUTF16StringEncoding),
            @(NSUTF16LittleEndianStringEncoding),
            @(NSUTF16BigEndianStringEncoding),
            @(NSWindowsCP1252StringEncoding)
        ];
        for (NSNumber *encodingValue in encodings) {
            NSString *html = [[NSString alloc] initWithData:htmlData encoding:encodingValue.unsignedIntegerValue];
            if (html == nil) continue;
            for (NSString *marker in @[@"<img", @"<picture", @"<svg", @"data:image/"]) {
                if ([html rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
            }
        }
        return NO;
    }

    BOOL clipboardContainsImageOrAttachment(NSPasteboard *pasteboard) {
        for (NSPasteboardItem *item in pasteboard.pasteboardItems ?: @[]) {
            NSData *htmlData = [item dataForType:NSPasteboardTypeHTML];
            if (htmlData != nil) {
                // Office includes a bitmap/RTFD preview alongside HTML text cells.
                // The HTML representation is authoritative here: only treat it as
                // an image paste when it actually embeds an image element.
                if (htmlDataContainsImage(htmlData)) return YES;
                continue;
            }

            for (NSPasteboardType type in item.types) {
                UTType *contentType = [UTType typeWithIdentifier:type];
                if ([contentType conformsToType:UTTypeImage]) return YES;
            }

            NSData *rtfd = [item dataForType:NSPasteboardTypeRTFD];
            if (rtfd != nil) {
                NSAttributedString *attributedText = [[NSAttributedString alloc] initWithRTFD:rtfd
                                                                            documentAttributes:nil];
                __block BOOL hasAttachment = NO;
                [attributedText enumerateAttribute:NSAttachmentAttributeName
                                             inRange:NSMakeRange(0, attributedText.length)
                                             options:0
                                          usingBlock:^(id value, NSRange range, BOOL *stop) {
                    if (value != nil) {
                        hasAttachment = YES;
                        *stop = YES;
                    }
                }];
                // An RTFD attachment can be either an inline image or an Office
                // preview. The two are indistinguishable without changing the
                // clipboard, so preserve it rather than risk losing user content.
                if (hasAttachment) return YES;
            }
        }
        return NO;
    }

    void postKey(CGKeyCode keyCode, CGEventFlags flags) {
        CGEventRef keyDown = CGEventCreateKeyboardEvent(myEventSource, keyCode, true);
        CGEventRef keyUp = CGEventCreateKeyboardEvent(myEventSource, keyCode, false);
        CGEventSetFlags(keyDown, flags);
        CGEventSetFlags(keyUp, flags);
        CGEventPost(kCGSessionEventTap, keyDown);
        CGEventPost(kCGSessionEventTap, keyUp);
        CFRelease(keyDown);
        CFRelease(keyUp);
    }

    NSArray<NSPasteboardItem *> *copyPasteboardItems(NSPasteboard *pasteboard) {
        NSMutableArray<NSPasteboardItem *> *copies = [NSMutableArray array];
        for (NSPasteboardItem *item in pasteboard.pasteboardItems ?: @[]) {
            NSPasteboardItem *copy = [[NSPasteboardItem alloc] init];
            for (NSPasteboardType type in item.types) {
                NSData *data = [item dataForType:type];
                if (data != nil) [copy setData:data forType:type];
            }
            [copies addObject:copy];
        }
        return copies;
    }

    void markPasteboardItemAsTemporary(NSPasteboardItem *item) {
        // Clipboard managers such as Maccy honor these standard pasteboard markers
        // and omit the item from history. They do not affect data read by Teams.
        NSData *marker = [NSData data];
        [item setData:marker forType:@"org.nspasteboard.TransientType"];
        [item setData:marker forType:@"org.nspasteboard.ConcealedType"];
        [item setData:marker forType:@"org.nspasteboard.AutoGeneratedType"];
    }

    void ignoreNextMaccyClipboardEvent(void) {
        // Maccy records a second history item when a temporary clipboard is
        // restored, because that restoration is another pasteboard change whose
        // foreground source is Teams. Its documented one-shot preference tells it
        // to ignore that generated change.
        CFStringRef maccyBundleIdentifier = CFSTR("org.p0deje.Maccy");
        CFPreferencesSetAppValue(CFSTR("ignoreOnlyNextEvent"), kCFBooleanTrue, maccyBundleIdentifier);
        CFPreferencesAppSynchronize(maccyBundleIdentifier);
    }

    BOOL clipboardContainsRichText(NSPasteboard *pasteboard) {
        for (NSPasteboardItem *item in pasteboard.pasteboardItems ?: @[]) {
            if ([item.types containsObject:NSPasteboardTypeHTML] ||
                [item.types containsObject:NSPasteboardTypeRTF] ||
                [item.types containsObject:NSPasteboardTypeRTFD]) {
                return YES;
            }
        }
        return NO;
    }

    NSString *normalizingSentenceSpacing(NSString *text) {
        // Rich text copied from editors often loses the separator between sentences
        // when it is reduced to plain text. Only split before an uppercase letter so
        // periods in URLs, version numbers, and abbreviations stay intact.
        static NSRegularExpression *sentenceStop;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sentenceStop = [NSRegularExpression regularExpressionWithPattern:@"([.!?])(?=\\p{Lu})"
                                                                      options:0
                                                                        error:nil];
        });
        return [sentenceStop stringByReplacingMatchesInString:text
                                                       options:0
                                                         range:NSMakeRange(0, text.length)
                                                  withTemplate:@"$1 "];
    }

    NSString *htmlStringFromData(NSData *data) {
        for (NSNumber *encoding in @[@(NSUTF8StringEncoding), @(NSUTF16StringEncoding),
                                      @(NSUTF16LittleEndianStringEncoding), @(NSUTF16BigEndianStringEncoding),
                                      @(NSWindowsCP1252StringEncoding)]) {
            NSString *html = [[NSString alloc] initWithData:data encoding:encoding.unsignedIntegerValue];
            if (html != nil) return html;
        }
        return nil;
    }

    NSString *cleanHTMLForTeams(NSString *html) {
        NSString *result = html;

        // Microsoft Word wraps its private file:// image in both VML conditional
        // markup and an ordinary <img> fallback. Remove the entire enclosing
        // paragraph: removing only the <img> leaves its 53pt paragraph behind
        // as a large blank area in Teams. The real attachment is added below
        // from the RTFD representation as an embedded data URL.
        NSRegularExpression *localImageParagraph = [NSRegularExpression regularExpressionWithPattern:@"(?is)<p\\b[^>]*>(?:(?!</?p\\b).)*?<img\\b[^>]*\\bsrc\\s*=\\s*['\"]?file:[^>]*>(?:(?!</?p\\b).)*?</p\\s*>" options:0 error:nil];
        result = [localImageParagraph stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:@""];

        for (NSString *pattern in @[
            @"(?is)<(?:style|script)\\b[^>]*>.*?</(?:style|script)>",
            @"(?is)<!--\\[if.*?<!\\[endif\\]-->",
            @"(?is)<!\\[if[^>]*>.*?<!\\[endif\\]>",
            @"(?is)</?(?:b|strong|i|em|u|s|strike|del|font|span|a)\\b[^>]*>"
        ]) {
            NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
            result = [expression stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:@""];
        }

        // Word's HTML references an image in its private temporary directory.
        // Teams cannot resolve file:// URLs, but reserves their width/height as a
        // blank placeholder. The matching RTFD image is embedded as a data URL.
        NSRegularExpression *localImage = [NSRegularExpression regularExpressionWithPattern:@"(?is)<img\\b[^>]*\\bsrc\\s*=\\s*['\"]?file:[^>]*>" options:0 error:nil];
        result = [localImage stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:@""];

        // Word frequently leaves empty paragraphs before an image attachment.
        // They become several visible blank lines in Teams after HTML is pasted.
        NSRegularExpression *emptyBlock = [NSRegularExpression regularExpressionWithPattern:@"(?is)<(?:p|div)\\b[^>]*>(?:\\s|&nbsp;|<br\\s*/?>)*</(?:p|div)>" options:0 error:nil];
        result = [emptyBlock stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:@""];

        NSRegularExpression *cellExpression = [NSRegularExpression regularExpressionWithPattern:@"(?is)<(?:td|th)\\b[^>]*>" options:0 error:nil];
        if ([cellExpression numberOfMatchesInString:result options:0 range:NSMakeRange(0, result.length)] == 1) {
            for (NSArray<NSString *> *replacement in @[
                @[@"(?is)</?(?:table|thead|tbody|tfoot|tr)\\b[^>]*>", @""],
                @[@"(?is)<(?:td|th)\\b[^>]*>", @"<div>"],
                @[@"(?is)</(?:td|th)\\s*>", @"</div>"]
            ]) {
                NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:replacement[0] options:0 error:nil];
                result = [expression stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:replacement[1]];
            }
        }
        NSRegularExpression *stripAttributes = [NSRegularExpression regularExpressionWithPattern:@"(?is)<(p|div|li|ul|ol|blockquote|table|thead|tbody|tfoot|tr|td|th|pre|code|br|hr|figure|figcaption)\\b[^>]*>" options:0 error:nil];
        return [stripAttributes stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:@"<$1>"];
    }

    NSString *htmlEscapedText(NSString *text) {
        NSString *escaped = [text stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
        escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
        escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
        escaped = [escaped stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
        escaped = [escaped stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
        return [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"<br>"];
    }

    NSData *pngDataForTextAttachment(NSTextAttachment *attachment) {
        NSImage *image = attachment.image;
        NSData *tiffData = image.TIFFRepresentation;
        NSBitmapImageRep *bitmap = tiffData == nil ? nil : [NSBitmapImageRep imageRepWithData:tiffData];
        NSData *pngData = bitmap == nil ? nil : [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (pngData != nil) return pngData;

        NSData *fileData = attachment.fileWrapper.regularFileContents;
        return fileData;
    }

    NSString *htmlImagesFromAttributedOfficeContent(NSAttributedString *richText) {
        NSMutableString *html = [NSMutableString string];
        [richText enumerateAttributesInRange:NSMakeRange(0, richText.length)
                                     options:0
                                  usingBlock:^(NSDictionary<NSAttributedStringKey, id> *attributes,
                                               NSRange range,
                                               BOOL *stop) {
            NSTextAttachment *attachment = attributes[NSAttachmentAttributeName];
            if (attachment != nil) {
                NSData *imageData = pngDataForTextAttachment(attachment);
                if (imageData != nil) {
                    [html appendFormat:@"<img src=\"data:image/png;base64,%@\">", [imageData base64EncodedStringWithOptions:0]];
                }
            }
        }];
        return html;
    }

    NSString *htmlFromAttributedOfficeContent(NSAttributedString *richText) {
        NSMutableString *html = [NSMutableString stringWithString:@"<div>"];
        [richText enumerateAttributesInRange:NSMakeRange(0, richText.length)
                                     options:0
                                  usingBlock:^(NSDictionary<NSAttributedStringKey, id> *attributes,
                                               NSRange range,
                                               BOOL *stop) {
            NSTextAttachment *attachment = attributes[NSAttachmentAttributeName];
            if (attachment != nil) {
                NSData *imageData = pngDataForTextAttachment(attachment);
                if (imageData != nil) {
                    [html appendFormat:@"<img src=\"data:image/png;base64,%@\">", [imageData base64EncodedStringWithOptions:0]];
                }
            } else {
            [html appendString:htmlEscapedText([[richText string] substringWithRange:range])];
            }
        }];
        [html appendString:@"</div>"];
        if ([html rangeOfString:@"<img "].location != NSNotFound) {
            // Word represents paragraph spacing around inline attachments as
            // multiple newline characters. Keep a single separating line.
            NSRegularExpression *extraBreaks = [NSRegularExpression regularExpressionWithPattern:@"(?is)(?:<br>\\s*){2,}" options:0 error:nil];
            return [extraBreaks stringByReplacingMatchesInString:html options:0 range:NSMakeRange(0, html.length) withTemplate:@"<br>"];
        }
        return html;
    }

    NSString *htmlFromOfficePasteboard(NSPasteboard *pasteboard) {
        NSString *htmlFallback = nil;
        for (NSPasteboardItem *item in pasteboard.pasteboardItems ?: @[]) {
            NSData *htmlData = [item dataForType:NSPasteboardTypeHTML];
            NSString *html = htmlStringFromData(htmlData);
            if (html != nil && htmlFallback == nil) htmlFallback = html;

            NSData *richData = [item dataForType:NSPasteboardTypeRTFD] ?: [item dataForType:NSPasteboardTypeRTF];
            if (richData == nil) continue;
            NSAttributedString *richText = [item dataForType:NSPasteboardTypeRTFD] != nil ?
                [[NSAttributedString alloc] initWithRTFD:richData documentAttributes:nil] :
                [[NSAttributedString alloc] initWithRTF:richData documentAttributes:nil];
            NSString *attachmentHTML = htmlImagesFromAttributedOfficeContent(richText);
            if (attachmentHTML.length > 0) {
                // The HTML and RTFD forms of a Word selection are not aligned:
                // HTML has file:// image placeholders while RTFD has real image
                // data. Generate one clean document from RTFD to retain the
                // original text/image sequence without duplicate attachments.
                return htmlFromAttributedOfficeContent(richText);
            }
            if (htmlFallback == nil) {
                html = htmlFromAttributedOfficeContent(richText);
                if (html.length > 0) return html;
            }
        }
        return htmlFallback;
    }

    BOOL prepareCleanHTMLForTeamsPaste(void) {
        NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
        NSString *plainText = [pasteboard stringForType:NSPasteboardTypeString];
        if (plainText == nil || !clipboardContainsRichText(pasteboard)) return NO;
        NSString *html = htmlFromOfficePasteboard(pasteboard);
        if (html == nil) return NO;

        NSArray<NSPasteboardItem *> *originalItems = copyPasteboardItems(pasteboard);
        NSPasteboardItem *cleanedItem = [[NSPasteboardItem alloc] init];
        NSData *cleanedHTML = [cleanHTMLForTeams(html) dataUsingEncoding:NSUTF8StringEncoding];
        if (cleanedHTML == nil) return NO;
        [cleanedItem setData:cleanedHTML forType:NSPasteboardTypeHTML];
        [cleanedItem setString:normalizingSentenceSpacing(plainText) forType:NSPasteboardTypeString];
        markPasteboardItemAsTemporary(cleanedItem);

        ignoreNextMaccyClipboardEvent();
        [pasteboard clearContents];
        if (![pasteboard writeObjects:@[cleanedItem]]) {
            [pasteboard writeObjects:originalItems];
            return NO;
        }
        NSInteger temporaryChangeCount = pasteboard.changeCount;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (pasteboard.changeCount != temporaryChangeCount) return;
            ignoreNextMaccyClipboardEvent();
            [pasteboard clearContents];
            if (originalItems.count > 0) [pasteboard writeObjects:originalItems];
        });
        return YES;
    }

    void prependNewlineToTeamsImagePaste(void) {
        NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
        NSArray<NSPasteboardItem *> *originalItems = copyPasteboardItems(pasteboard);

        // Give Teams a first clipboard item containing only a newline, followed by the
        // original image item(s). This makes the normal paste operation create the text
        // line before the images without issuing an editor command while an attachment is
        // selected.
        NSPasteboardItem *newlineItem = [[NSPasteboardItem alloc] init];
        [newlineItem setString:@"\n" forType:NSPasteboardTypeString];
        markPasteboardItemAsTemporary(newlineItem);
        NSMutableArray<NSPasteboardItem *> *itemsToPaste = [NSMutableArray arrayWithObject:newlineItem];
        [itemsToPaste addObjectsFromArray:originalItems];
        ignoreNextMaccyClipboardEvent();
        [pasteboard clearContents];
        if (![pasteboard writeObjects:itemsToPaste]) {
            [pasteboard writeObjects:originalItems];
            return;
        }

        NSInteger temporaryChangeCount = pasteboard.changeCount;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            if (![[NSUserDefaults standardUserDefaults] boolForKey:@"MoveCursorBeforeTeamsImagePaste"] ||
                !isMicrosoftTeams(NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier)) return;
            // The first Left leaves Teams' attachment selection; the second puts the
            // caret immediately before the pasted image group.
            postKey(kVK_LeftArrow, 0);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                if (isMicrosoftTeams(NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier)) {
                    postKey(kVK_LeftArrow, 0);
                }
            });
        });

        // Restore the user's clipboard after Electron has consumed its asynchronous
        // image paste, unless they copied something else in the meantime.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (pasteboard.changeCount != temporaryChangeCount) return;
            ignoreNextMaccyClipboardEvent();
            [pasteboard clearContents];
            if (originalItems.count > 0) [pasteboard writeObjects:originalItems];
        });
    }

    void recordVietnameseTypingApplication() {
        NSString *bundleIdentifier = FRONT_APP;
        if (bundleIdentifier.length == 0 || [bundleIdentifier isEqualToString:MACKEY_BUNDLE]) return;
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSMutableOrderedSet<NSString *> *applications = [NSMutableOrderedSet orderedSetWithArray:[defaults arrayForKey:@"VietnameseTypingApplications"] ?: @[]];
        if (![applications containsObject:bundleIdentifier]) {
            [applications addObject:bundleIdentifier];
            [defaults setObject:applications.array forKey:@"VietnameseTypingApplications"];
            MacKeyDebugLog([NSString stringWithFormat:@"Compatibility added %@ after Vietnamese typing.", bundleIdentifier]);
            [MacKeyBridge notifySettingsChanged];
        }
    }

    void PostGeneratedEvent(CGEventRef event) {
        if (event == NULL) return;

        // Direct delivery is an explicit per-app choice. Do not infer a mode
        // from Electron/Chromium framework detection: users choose one of the
        // three delivery strategies in Compatibility.
        if (keyDeliveryModeForApp(FRONT_APP) != 0) {
            CGEventPost(kCGSessionEventTap, event);
        } else {
            CGEventTapPostEvent(_proxy, event);
        }
    }

    BOOL isSpotlightVisible() {
        // CGWindowList reports Spotlight's background window even when another
        // application owns the keyboard focus. Treating that as visible caused
        // the selection-replacement path to send Shift-Left in apps such as
        // Teams, leaving the current word selected. Only the frontmost
        // Spotlight application needs this special handling.
        return [NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier isEqualToString:@"com.apple.Spotlight"];
    }

    BOOL shouldUseRecommendWorkaround(NSString* topApp) {
        if (!vFixRecommendBrowser) return false;
        if (isSpotlightVisible()) return false;
        if (topApp == nil) return true;
        return ![_recommendWorkaroundDisabledApp containsObject:topApp];
    }

    BOOL shouldUseSelectionReplacement(NSString* topApp) {
        return isSpotlightVisible() || [_recommendWorkaroundDisabledApp containsObject:topApp];
    }
    
    void saveSmartSwitchKeyData() {
        getSmartSwitchKeySaveData(savedSmartSwitchKeyData);
        NSData* _data = [NSData dataWithBytes:savedSmartSwitchKeyData.data() length:savedSmartSwitchKeyData.size()];
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        [prefs setObject:_data forKey:@"smartSwitchKey"];
    }
    
    void OnActiveAppChanged() { //use for smart switch key; improved on Sep 28th, 2019
        queryFrontMostApp();
        NSString *appName = smartSwitchAppName();
        // Detect and report Chromium wrappers as soon as the app becomes
        // active, rather than waiting for its first converted keystroke.
        NSString *chromiumRuntime = chromiumRuntimeForFrontmostApp(_frontMostApp);
        if (chromiumRuntime != nil) {
            MacKeyDebugLog([NSString stringWithFormat:@"App: %@ is a Chromium wrapper (%@); selected Key Mode controls delivery.", appName, chromiumRuntime]);
        }
        _languageTemp = getAppInputMethodStatus(string(_frontMostApp.UTF8String), vLanguage | (vCodeTable << 1));
        if (_languageTemp == -1) {
            saveSmartSwitchKeyData();
            MacKeyDebugLog([NSString stringWithFormat:@"Switched App: %@ (new entry), Key = %@, Key Type = %@, Code Table = %@.",
                         appName, smartSwitchInputMethodName(vLanguage), smartSwitchInputTypeName(vInputType), smartSwitchCodeTableName(vCodeTable)]);
            return;
        }

        // Restore the complete saved state in one checked operation. The previous
        // code assigned the packed value directly to vLanguage and then toggled the
        // preference, which could desynchronise the engine and V/E status icon.
        int targetState = _languageTemp;
        if (!vRememberCode) {
            targetState = (targetState & 0x01) | (vCodeTable << 1);
        }

        NSError *error = nil;
        @try {
            if (![appDelegate applySmartSwitchState:targetState error:&error]) {
                [appDelegate handleSmartSwitchFailure:error.localizedDescription];
            } else {
                MacKeyDebugLog([NSString stringWithFormat:@"Switched App: %@, Key = %@, Key Type = %@, Code Table = %@.",
                             appName, smartSwitchInputMethodName(targetState & 0x01), smartSwitchInputTypeName(vInputType), smartSwitchCodeTableName(targetState >> 1)]);
            }
        } @catch (NSException *exception) {
            MacKeyDebugLog([NSString stringWithFormat:@"Smart switch dispatch exception: %@", exception.reason ?: @"unknown exception"]);
            [appDelegate handleSmartSwitchFailure:exception.reason];
        }
    }
    
    void OnTableCodeChange() {
        onTableCodeChange();
        if (vRememberCode) {
            queryFrontMostApp();
            setAppInputMethodStatus(string(_frontMostApp.UTF8String), vLanguage | (vCodeTable << 1));
            saveSmartSwitchKeyData();
        }
    }
    
    void OnInputMethodChanged() {
        if (vUseSmartSwitchKey) {
            queryFrontMostApp();
            setAppInputMethodStatus(string(_frontMostApp.UTF8String), vLanguage | (vCodeTable << 1));
            saveSmartSwitchKeyData();
        }
    }
    
    void OnSpellCheckingChanged() {
        vSetCheckSpelling();
    }
    
    void InsertKeyLength(const Uint8& len) {
        _syncKey.push_back(len);
    }
    
    void SendPureCharacter(const Uint16& ch) {
        _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
        _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
        CGEventKeyboardSetUnicodeString(_newEventDown, 1, &ch);
        CGEventKeyboardSetUnicodeString(_newEventUp, 1, &ch);
        PostGeneratedEvent(_newEventDown);
        PostGeneratedEvent(_newEventUp);
        CFRelease(_newEventDown);
        CFRelease(_newEventUp);
        if (IS_DOUBLE_CODE(vCodeTable)) {
            InsertKeyLength(1);
        }
    }
    
    void SendKeyCode(Uint32 data) {
        _newChar = (Uint16)data;
        if (!(data & CHAR_CODE_MASK)) {
            if (IS_DOUBLE_CODE(vCodeTable)) //VNI
                InsertKeyLength(1);
            
            _newEventDown = CGEventCreateKeyboardEvent(myEventSource, _newChar, true);
            _newEventUp = CGEventCreateKeyboardEvent(myEventSource, _newChar, false);
            _privateFlag = CGEventGetFlags(_newEventDown);
            
            if (data & CAPS_MASK) {
                _privateFlag |= kCGEventFlagMaskShift;
            } else {
                _privateFlag &= ~kCGEventFlagMaskShift;
            }
            _privateFlag |= kCGEventFlagMaskNonCoalesced;
            
            CGEventSetFlags(_newEventDown, _privateFlag);
            CGEventSetFlags(_newEventUp, _privateFlag);
            PostGeneratedEvent(_newEventDown);
            PostGeneratedEvent(_newEventUp);
        } else {
            if (vCodeTable == 0) { //unicode 2 bytes code
                _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
                _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
                CGEventKeyboardSetUnicodeString(_newEventDown, 1, &_newChar);
                CGEventKeyboardSetUnicodeString(_newEventUp, 1, &_newChar);
                PostGeneratedEvent(_newEventDown);
                PostGeneratedEvent(_newEventUp);
            } else if (vCodeTable == 1 || vCodeTable == 2 || vCodeTable == 4) { //others such as VNI Windows, TCVN3: 1 byte code
                _newCharHi = HIBYTE(_newChar);
                _newChar = LOBYTE(_newChar);
                
                _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
                _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
                CGEventKeyboardSetUnicodeString(_newEventDown, 1, &_newChar);
                CGEventKeyboardSetUnicodeString(_newEventUp, 1, &_newChar);
                PostGeneratedEvent(_newEventDown);
                PostGeneratedEvent(_newEventUp);
                if (_newCharHi > 32) {
                    if (vCodeTable == 2) //VNI
                        InsertKeyLength(2);
                    CFRelease(_newEventDown);
                    CFRelease(_newEventUp);
                    _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
                    _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
                    CGEventKeyboardSetUnicodeString(_newEventDown, 1, &_newCharHi);
                    CGEventKeyboardSetUnicodeString(_newEventUp, 1, &_newCharHi);
                    PostGeneratedEvent(_newEventDown);
                    PostGeneratedEvent(_newEventUp);
                } else {
                    if (vCodeTable == 2) //VNI
                        InsertKeyLength(1);
                }
            } else if (vCodeTable == 3) { //Unicode Compound
                _newCharHi = (_newChar >> 13);
                _newChar &= 0x1FFF;
                _uniChar[0] = _newChar;
                _uniChar[1] = _newCharHi > 0 ? (_unicodeCompoundMark[_newCharHi - 1]) : 0;
                InsertKeyLength(_newCharHi > 0 ? 2 : 1);
                _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
                _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
                CGEventKeyboardSetUnicodeString(_newEventDown, (_newCharHi > 0 ? 2 : 1), _uniChar);
                CGEventKeyboardSetUnicodeString(_newEventUp, (_newCharHi > 0 ? 2 : 1), _uniChar);
                PostGeneratedEvent(_newEventDown);
                PostGeneratedEvent(_newEventUp);
            }
        }
        CFRelease(_newEventDown);
        CFRelease(_newEventUp);
    }
    
    void SendEmptyCharacter() {
        if (IS_DOUBLE_CODE(vCodeTable)) //VNI or Unicode Compound
            InsertKeyLength(1);
        
        _newChar = 0x202F; //empty char
        if ([_niceSpaceApp containsObject:FRONT_APP]) {
            _newChar = 0x200C; //Unicode character with empty space
        }
        
        _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
        _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
        CGEventKeyboardSetUnicodeString(_newEventDown, 1, &_newChar);
        CGEventKeyboardSetUnicodeString(_newEventUp, 1, &_newChar);
        PostGeneratedEvent(_newEventDown);
        PostGeneratedEvent(_newEventUp);
        CFRelease(_newEventDown);
        CFRelease(_newEventUp);
    }
    
    void SendVirtualKey(const Byte& vKey) {
        CGEventRef eventVkeyDown = CGEventCreateKeyboardEvent (myEventSource, vKey, true);
        CGEventRef eventVkeyUp = CGEventCreateKeyboardEvent (myEventSource, vKey, false);
        
        PostGeneratedEvent(eventVkeyDown);
        PostGeneratedEvent(eventVkeyUp);
        
        CFRelease(eventVkeyDown);
        CFRelease(eventVkeyUp);
    }

    void SendBackspace() {
        PostGeneratedEvent(eventBackSpaceDown);
        PostGeneratedEvent(eventBackSpaceUp);
        
        if (IS_DOUBLE_CODE(vCodeTable)) { //VNI or Unicode Compound
            if (_syncKey.back() > 1) {
                if (!(vCodeTable == 3 && containUnicodeCompoundApp(FRONT_APP))) {
                    PostGeneratedEvent(eventBackSpaceDown);
                    PostGeneratedEvent(eventBackSpaceUp);
                }
            }
            _syncKey.pop_back();
        }
    }
    
    void SendShiftAndLeftArrow() {
        CGEventRef eventVkeyDown = CGEventCreateKeyboardEvent (myEventSource, KEY_LEFT, true);
        CGEventRef eventVkeyUp = CGEventCreateKeyboardEvent (myEventSource, KEY_LEFT, false);
        _privateFlag = CGEventGetFlags(eventVkeyDown);
        _privateFlag |= kCGEventFlagMaskShift;
        CGEventSetFlags(eventVkeyDown, _privateFlag);
        CGEventSetFlags(eventVkeyUp, _privateFlag);
        
        PostGeneratedEvent(eventVkeyDown);
        PostGeneratedEvent(eventVkeyUp);
        
        if (IS_DOUBLE_CODE(vCodeTable)) { //VNI or Unicode Compound
            if (_syncKey.back() > 1) {
                if (!(vCodeTable == 3 && containUnicodeCompoundApp(FRONT_APP))) {
                    PostGeneratedEvent(eventVkeyDown);
                    PostGeneratedEvent(eventVkeyUp);
                }
            }
            _syncKey.pop_back();
        }
        CFRelease(eventVkeyDown);
        CFRelease(eventVkeyUp);
    }
    
    void SendCutKey() {
        CGEventRef eventVkeyDown = CGEventCreateKeyboardEvent (myEventSource, KEY_X, true);
        CGEventRef eventVkeyUp = CGEventCreateKeyboardEvent (myEventSource, KEY_X, false);
        _privateFlag = CGEventGetFlags(eventVkeyDown);
        _privateFlag |= NX_COMMANDMASK;
        CGEventSetFlags(eventVkeyDown, _privateFlag);
        CGEventSetFlags(eventVkeyUp, _privateFlag);
        
        PostGeneratedEvent(eventVkeyDown);
        PostGeneratedEvent(eventVkeyUp);
        
        CFRelease(eventVkeyDown);
        CFRelease(eventVkeyUp);
    }

    BOOL restoreCompatibilityClipboardIfCurrent(void) {
        if (_clipboardBeforeCompatibilityPaste == nil) return NO;

        NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
        if (pasteboard.changeCount != _compatibilityPasteboardChangeCount) {
            _clipboardBeforeCompatibilityPaste = nil;
            _compatibilityPasteboardChangeCount = NSNotFound;
            return NO;
        }

        [pasteboard clearContents];
        if (_clipboardBeforeCompatibilityPaste.count > 0) {
            [pasteboard writeObjects:_clipboardBeforeCompatibilityPaste];
        }
        _clipboardBeforeCompatibilityPaste = nil;
        _compatibilityPasteboardChangeCount = NSNotFound;
        _compatibilityPasteGeneration++;
        return YES;
    }

    NSTimeInterval compatibilityClipboardRestoreDelay(void) {
        // Electron applications (including Zalo) can handle Command-V
        // asynchronously.  If the old clipboard contains an image or a file,
        // restoring it too soon makes the renderer paste that image/file in
        // place of the Vietnamese replacement text.  Text-only clips are
        // consumed promptly, but rich clips need to remain available through
        // Electron's asynchronous paste round-trip.
        for (NSPasteboardItem *item in _clipboardBeforeCompatibilityPaste ?: @[]) {
            for (NSPasteboardType type in item.types) {
                NSString *identifier = type;
                UTType *contentType = [UTType typeWithIdentifier:identifier];
                if ([contentType conformsToType:UTTypeImage] ||
                    [contentType conformsToType:UTTypeFileURL] ||
                    [identifier rangeOfString:@"filepromise" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                    [identifier rangeOfString:@"promised-file" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    return 1.5;
                }
            }
        }
        return 0.25;
    }

    void SendClipboardPaste(const UniChar *characters, NSUInteger length) {
        if (characters == NULL || length == 0) return;

        NSString *replacement = [NSString stringWithCharacters:characters length:length];
        NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;

        // Command-V can only read the general pasteboard; a named pasteboard
        // would not be visible to the destination application. Take a complete
        // snapshot so this compatibility path behaves like an internal,
        // temporary pasteboard and does not replace what the user copied.
        if (_clipboardBeforeCompatibilityPaste == nil || pasteboard.changeCount != _compatibilityPasteboardChangeCount) {
            NSMutableArray<NSPasteboardItem *> *savedItems = [NSMutableArray array];
            for (NSPasteboardItem *item in pasteboard.pasteboardItems ?: @[]) {
                NSPasteboardItem *savedItem = [[NSPasteboardItem alloc] init];
                for (NSPasteboardType type in item.types) {
                    NSData *data = [item dataForType:type];
                    if (data != nil) {
                        [savedItem setData:data forType:type];
                    }
                }
                [savedItems addObject:savedItem];
            }
            _clipboardBeforeCompatibilityPaste = [savedItems copy];
        }

        [pasteboard clearContents];
        if (![pasteboard setString:replacement forType:NSPasteboardTypeString]) {
            if (_clipboardBeforeCompatibilityPaste.count > 0) {
                [pasteboard writeObjects:_clipboardBeforeCompatibilityPaste];
            }
            _clipboardBeforeCompatibilityPaste = nil;
            _compatibilityPasteboardChangeCount = NSNotFound;
            _compatibilityPasteGeneration++;
            return;
        }

        _compatibilityPasteboardChangeCount = pasteboard.changeCount;
        NSUInteger pasteGeneration = ++_compatibilityPasteGeneration;
        NSInteger temporaryPasteboardChangeCount = _compatibilityPasteboardChangeCount;
        NSTimeInterval restoreDelay = compatibilityClipboardRestoreDelay();

        CGEventRef keyDown = CGEventCreateKeyboardEvent(myEventSource, KEY_V, true);
        CGEventRef keyUp = CGEventCreateKeyboardEvent(myEventSource, KEY_V, false);
        CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
        CGEventSetFlags(keyUp, kCGEventFlagMaskCommand);
        PostGeneratedEvent(keyDown);
        PostGeneratedEvent(keyUp);
        CFRelease(keyDown);
        CFRelease(keyUp);

        // Restore only after the latest replacement has been idle. This prevents
        // a word such as "này" from progressively saving its own temporary
        // characters as the user's clipboard. Rich clips need a longer window
        // because Electron may read the general pasteboard after Command-V has
        // returned. A real user Command-V restores the saved clip synchronously
        // above, so normal copy/paste remains immediate.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(restoreDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (pasteGeneration != _compatibilityPasteGeneration) return;
            if (NSPasteboard.generalPasteboard.changeCount != temporaryPasteboardChangeCount) return;
            restoreCompatibilityClipboardIfCurrent();
        });
    }
    
    void SendNewCharString(const bool& dataFromMacro=false, const Uint16& offset=0, const bool& clipboardPaste=false) {
        _j = 0;
        _newCharSize = dataFromMacro ? pData->macroData.size() : pData->newCharCount;
        _willContinuteSending = false;
        _willSendControlKey = false;
        
        if (_newCharSize > 0) {
            for (_k = dataFromMacro ? offset : pData->newCharCount - 1 - offset;
                 dataFromMacro ? _k < pData->macroData.size() : _k >= 0;
                 dataFromMacro ? _k++ : _k--) {
                
                if (_j >= 16) {
                    _willContinuteSending = true;
                    break;
                }
                
                _tempChar = DYNA_DATA(dataFromMacro, _k);
                if (_tempChar & PURE_CHARACTER_MASK) {
                    _newCharString[_j++] = _tempChar;
                    if (IS_DOUBLE_CODE(vCodeTable)) {
                        InsertKeyLength(1);
                    }
                } else if (!(_tempChar & CHAR_CODE_MASK)) {
                    if (IS_DOUBLE_CODE(vCodeTable)) //VNI
                        InsertKeyLength(1);
                    _newCharString[_j++] = keyCodeToCharacter(_tempChar);
                } else {
                    if (vCodeTable == 0) {  //unicode 2 bytes code
                        _newCharString[_j++] = _tempChar;
                    } else if (vCodeTable == 1 || vCodeTable == 2 || vCodeTable == 4) { //others such as VNI Windows, TCVN3: 1 byte code
                        _newChar = _tempChar;
                        _newCharHi = HIBYTE(_newChar);
                        _newChar = LOBYTE(_newChar);
                        _newCharString[_j++] = _newChar;
                        
                        if (_newCharHi > 32) {
                            if (vCodeTable == 2) //VNI
                                InsertKeyLength(2);
                            _newCharString[_j++] = _newCharHi;
                            _newCharSize++;
                        } else {
                            if (vCodeTable == 2) //VNI
                                InsertKeyLength(1);
                        }
                    } else if (vCodeTable == 3) { //Unicode Compound
                        _newChar = _tempChar;
                        _newCharHi = (_newChar >> 13);
                        _newChar &= 0x1FFF;
                        
                        InsertKeyLength(_newCharHi > 0 ? 2 : 1);
                        _newCharString[_j++] = _newChar;
                        if (_newCharHi > 0) {
                            _newCharSize++;
                            _newCharString[_j++] = _unicodeCompoundMark[_newCharHi - 1];
                        }
                        
                    }
                }
            }//end for
        }
        
        if (!_willContinuteSending && (pData->code == vRestore || pData->code == vRestoreAndStartNewSession)) { //if is restore
            if (keyCodeToCharacter(_keycode) != 0) {
                _newCharSize++;
                _newCharString[_j++] = keyCodeToCharacter(_keycode | ((_flag & kCGEventFlagMaskAlphaShift) || (_flag & kCGEventFlagMaskShift) ? CAPS_MASK : 0));
            } else {
                _willSendControlKey = true;
            }
        }
        if (!_willContinuteSending && pData->code == vRestoreAndStartNewSession) {
            startNewSession();
        }
        
        BOOL canPasteReplacement = clipboardPaste && !dataFromMacro && !_willContinuteSending && vCodeTable == 0;
        if (canPasteReplacement) {
            MacKeyDebugLog(@"Clipboard paste compatibility fix applied to the Unicode replacement.");
            SendClipboardPaste(_newCharString, _j);
        } else {
            _newEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
            _newEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);
            CGEventKeyboardSetUnicodeString(_newEventDown, _willContinuteSending ? 16 : _newCharSize - offset, _newCharString);
            CGEventKeyboardSetUnicodeString(_newEventUp, _willContinuteSending ? 16 : _newCharSize - offset, _newCharString);
            PostGeneratedEvent(_newEventDown);
            PostGeneratedEvent(_newEventUp);
            CFRelease(_newEventDown);
            CFRelease(_newEventUp);
        }

        if (_willContinuteSending) {
            SendNewCharString(dataFromMacro, dataFromMacro ? _k : 16, clipboardPaste);
        }
        
        //the case when hCode is vRestore or vRestoreAndStartNewSession, the word is invalid and last key is control key such as TAB, LEFT ARROW, RIGHT ARROW,...
        if (_willSendControlKey) {
            SendKeyCode(_keycode);
        }
    }
            
    bool checkHotKey(int hotKeyData, bool checkKeyCode=true) {
        if ((hotKeyData & (~0x8000)) == EMPTY_HOTKEY)
            return false;
        if (HAS_CONTROL(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskControl))
            return false;
        if (HAS_OPTION(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskAlternate))
            return false;
        if (HAS_COMMAND(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskCommand))
            return false;
        if (HAS_SHIFT(hotKeyData) ^ GET_BOOL(_lastFlag & kCGEventFlagMaskShift))
            return false;
        if (checkKeyCode) {
            if (GET_SWITCH_KEY(hotKeyData) != _keycode)
                return false;
        }
        return true;
    }
    
    void switchLanguage() {
        if (vLanguage == 0)
            vLanguage = 1;
        else
            vLanguage = 0;
        if (HAS_BEEP(vSwitchKeyStatus))
            NSBeep();
        [appDelegate onImputMethodChanged:YES];
        startNewSession();
    }
    
    void handleMacro() {
        //fix autocomplete
        if (shouldUseRecommendWorkaround(FRONT_APP)) {
            SendEmptyCharacter();
            pData->backspaceCount++;
        }
        
        //send backspace
        if (pData->backspaceCount > 0) {
            for (int i = 0; i < pData->backspaceCount; i++) {
                SendBackspace();
            }
        }
        //send real data
        SendNewCharString(true);
        SendKeyCode(_keycode | (_flag & kCGEventFlagMaskShift ? CAPS_MASK : 0));
    }

    // TODO: Research API to convert character into CGKeyCode more elegantly!
    int ConvertKeyStringToKeyCode(NSString *keyString, CGKeyCode fallback) {
        // Infomation about capitalization (shift/caps) is already included
        // in the original CGEvent, only find out which position on keyboard a key is pressed
        NSString *lowercasedKeyString = [keyString lowercaseString];
        if (!lowercasedKeyString) {
            return fallback;
        }
        
        NSNumber *keycode = [keyStringToKeyCodeMap objectForKey:lowercasedKeyString];

        if (keycode) {
            return [keycode intValue];
        }
        return fallback;
    }

    // If conversion fails, return fallbackKeyCode
    CGKeyCode ConvertEventToKeyboadLayoutCompatKeyCode(CGEventRef keyEvent, CGKeyCode fallbackKeyCode) {
        NSEvent *kbLayoutCompatEvent = [NSEvent eventWithCGEvent:keyEvent];
        NSString *kbLayoutCompatKeyString = kbLayoutCompatEvent.charactersIgnoringModifiers;
        return ConvertKeyStringToKeyCode(kbLayoutCompatKeyString,
                                         fallbackKeyCode);
    }

    /**
     * MAIN HOOK entry, very important function.
     * MAIN Callback.
     */
    CGEventRef MacKeyCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
        // Core Graphics turns a tap off if its callback exceeds its deadline,
        // and can also do so during session/user-input transitions. These are
        // notifications, not keyboard events: do not inspect `event` here.
        // Without this branch the menu icon remains Vietnamese while every
        // keystroke is passed through until the app is relaunched.
        if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
            MacKeyDebugLog(type == kCGEventTapDisabledByTimeout ? @"Event tap disabled by timeout; re-enabling." : @"Event tap disabled by user input; re-enabling.");
            [MacKeyManager reenableEventTap];
            return event;
        }

        //dont handle my event
        if (CGEventGetIntegerValueField(event, kCGEventSourceStateID) == CGEventSourceGetSourceStateID(myEventSource)) {
            return event;
        }
        
        _flag = CGEventGetFlags(event);
        _keycode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        
        if (type == kCGEventKeyDown && vPerformLayoutCompat) {
            // If conversion fail, use current keycode
           _keycode = ConvertEventToKeyboadLayoutCompatKeyCode(event, _keycode);
        }

        // If the user pastes immediately after typing, restore the preserved
        // clipboard synchronously before Command-V reaches the target app.
        // Synthetic Command-V events from SendClipboardPaste returned above,
        // so this only applies to a real user paste shortcut.
        if (type == kCGEventKeyDown && _keycode == KEY_V && (_flag & kCGEventFlagMaskCommand)) {
            if (restoreCompatibilityClipboardIfCurrent()) {
                MacKeyDebugLog(@"Restored the user's clipboard before Command-V.");
            }
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CleanTextFormattingBeforeTeamsPaste"] &&
                isMicrosoftTeams(FRONT_APP) && prepareCleanHTMLForTeamsPaste()) {
                return event;
            }
            BOOL clipboardHasImage = clipboardContainsImageOrAttachment(NSPasteboard.generalPasteboard);
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"MoveCursorBeforeTeamsImagePaste"] &&
                isMicrosoftTeams(FRONT_APP) && clipboardHasImage) {
                prependNewlineToTeamsImagePaste();
            }
            return event;
        }
        
        //switch language shortcut; convert hotkey
        if (type == kCGEventKeyDown) {
            if (GET_SWITCH_KEY(vSwitchKeyStatus) != _keycode && GET_SWITCH_KEY(convertToolHotKey) != _keycode) {
                _lastFlag = 0;
            } else {
                if (GET_SWITCH_KEY(vSwitchKeyStatus) == _keycode && checkHotKey(vSwitchKeyStatus, GET_SWITCH_KEY(vSwitchKeyStatus) != 0xFE)){
                    switchLanguage();
                    _lastFlag = 0;
                    _hasJustUsedHotKey = true;
                    return NULL;
                }
                if (GET_SWITCH_KEY(convertToolHotKey) == _keycode && checkHotKey(convertToolHotKey, GET_SWITCH_KEY(convertToolHotKey) != 0xFE)){
                    [appDelegate onQuickConvert];
                    _lastFlag = 0;
                    _hasJustUsedHotKey = true;
                    return NULL;
                }
            }
            _hasJustUsedHotKey = _lastFlag != 0;
        } else if (type == kCGEventFlagsChanged) {
            if (_lastFlag == 0 || _lastFlag < _flag) {
                _lastFlag = _flag;
            } else if (_lastFlag > _flag)  {
                //check switch
                if (checkHotKey(vSwitchKeyStatus, GET_SWITCH_KEY(vSwitchKeyStatus) != 0xFE)) {
                    _lastFlag = 0;
                    switchLanguage();
                    _hasJustUsedHotKey = true;
                    return NULL;
                }
                if (checkHotKey(convertToolHotKey, GET_SWITCH_KEY(convertToolHotKey) != 0xFE)) {
                    _lastFlag = 0;
                    [appDelegate onQuickConvert];
                    _hasJustUsedHotKey = true;
                    return NULL;
                }
                //check temporarily turn off spell checking
                if (vTempOffSpelling && !_hasJustUsedHotKey && _lastFlag & kCGEventFlagMaskControl) {
                    vTempOffSpellChecking();
                }
                if (vTempOffMacKey && !_hasJustUsedHotKey && _lastFlag & kCGEventFlagMaskCommand) {
                    vTempOffEngine();
                }
                _lastFlag = 0;
                _hasJustUsedHotKey = false;
            }
        }

        // Also check correct event hooked
        if ((type != kCGEventKeyDown) && (type != kCGEventKeyUp) &&
            (type != kCGEventLeftMouseDown) && (type != kCGEventRightMouseDown) &&
            (type != kCGEventLeftMouseDragged) && (type != kCGEventRightMouseDragged))
            return event;
        
        _proxy = proxy;
        
        //If is in english mode
        if (vLanguage == 0) {
            if (type == kCGEventKeyDown && vInputType == vVNI && isVNIControlKey(_keycode)) {
                MacKeyDebugLog([NSString stringWithFormat:@"VNI key received but bypassed: current Key = English (key code %d).", _keycode]);
            }
            if (vUseMacro && vUseMacroInEnglishMode && type == kCGEventKeyDown) {
                vEnglishMode((type == kCGEventKeyDown ? vKeyEventState::KeyDown : vKeyEventState::MouseDown),
                             _keycode,
                             (_flag & kCGEventFlagMaskShift) || (_flag & kCGEventFlagMaskAlphaShift),
                             OTHER_CONTROL_KEY);
                
                if (pData->code == vReplaceMaro) { //handle macro in english mode
                    handleMacro();
                    return NULL;
                }
            }
            return event;
        }
        
        //handle mouse
        if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown || type == kCGEventLeftMouseDragged || type == kCGEventRightMouseDragged) {
            RequestNewSession();
            return event;
        }

        //if "turn off Vietnamese when in other language" mode on
        if(vOtherLanguage){
            TISInputSourceRef isource = TISCopyCurrentKeyboardInputSource();
            if (isource != NULL) {
                CFArrayRef languages = (CFArrayRef) TISGetInputSourceProperty(isource, kTISPropertyInputSourceLanguages);
                BOOL isEnglishKeyboard = YES;

                if (languages != NULL && CFArrayGetCount(languages) > 0) {
                    CFStringRef langRef = (CFStringRef)CFArrayGetValueAtIndex(languages, 0);
                    if (langRef != NULL && CFGetTypeID(langRef) == CFStringGetTypeID()) {
                        NSString *currentLanguage = (__bridge NSString *)langRef;
                        isEnglishKeyboard = [currentLanguage hasPrefix:@"en"];
                    }
                }
                // langRef and the language array are borrowed TIS properties;
                // only the input source returned by Copy needs releasing.
                CFRelease(isource);

                if (!isEnglishKeyboard) {
                    // Do not carry an unfinished Vietnamese syllable across a
                    // system-layout change when this opt-in safeguard is on.
                    RequestNewSession();
                    if (type == kCGEventKeyDown && vInputType == vVNI && isVNIControlKey(_keycode)) {
                        MacKeyDebugLog(@"VNI key bypassed because the system keyboard layout is not English.");
                    }
                    return event;
                }
            }
        }
        
        //handle keyboard
        if (type == kCGEventKeyDown) {
            // Compatibility only lists apps where the user has started typing
            // in Vietnamese. Smart Switch may learn English-only apps too,
            // but those should not appear here.
            if (!OTHER_CONTROL_KEY && _keycode <= 50) {
                recordVietnameseTypingApplication();
            }
            //send event signal to Engine
            vKeyHandleEvent(vKeyEvent::Keyboard,
                            vKeyEventState::KeyDown,
                            _keycode,
                            _flag & kCGEventFlagMaskShift ? 1 : (_flag & kCGEventFlagMaskAlphaShift ? 2 : 0),
                            OTHER_CONTROL_KEY);
            if (vInputType == vVNI && isVNIControlKey(_keycode)) {
                MacKeyDebugLog([NSString stringWithFormat:@"VNI key received: key code %d, engine result = %@.", _keycode, engineResultName(pData->code)]);
            }
            if (pData->code == vDoNothing) { //do nothing
                if (IS_DOUBLE_CODE(vCodeTable)) { //VNI
                    if (pData->extCode == 1) { //break key
                        _syncKey.clear();
                    } else if (pData->extCode == 2) { //delete key
                        if (_syncKey.size() > 0) {
                            if (_syncKey.back() > 1 && (vCodeTable == 2 || !containUnicodeCompoundApp(FRONT_APP))) {
                                //send one more backspace
                                PostGeneratedEvent(eventBackSpaceDown);
                                PostGeneratedEvent(eventBackSpaceUp);
                            }
                            _syncKey.pop_back();
                        }
                       
                    } else if (pData->extCode == 3) { //normal key
                        InsertKeyLength(1);
                    }
                }
                return event;
            } else if (pData->code == vWillProcess || pData->code == vRestore || pData->code == vRestoreAndStartNewSession) { //handle result signal
                
                BOOL useClipboardPaste = shouldUseClipboardPasteForApp(FRONT_APP);

                if (shouldUseSelectionReplacement(FRONT_APP) && pData->backspaceCount > 0) {
                    for (_i = 0; _i < pData->backspaceCount; _i++) {
                        SendShiftAndLeftArrow();
                    }
                    pData->backspaceCount = 0;
                }
                
                //send backspace
                if (pData->backspaceCount > 0 && pData->backspaceCount < MAX_BUFF) {
                    for (_i = 0; _i < pData->backspaceCount; _i++) {
                        SendBackspace();
                    }
                }
                
                //send new character
                // Replacement delivery is entirely selected per application:
                // Default uses the standard Unicode event, Send key-by-key
                // sends individual events, and Clipboard Paste uses Command-V.
                if (useClipboardPaste) {
                    SendNewCharString(false, 0, true);
                } else if (!shouldSendKeyByKeyForApp(FRONT_APP)) {
                    SendNewCharString();
                } else {
                    if (pData->newCharCount > 0 && pData->newCharCount <= MAX_BUFF) {
                        for (int i = pData->newCharCount - 1; i >= 0; i--) {
                            SendKeyCode(pData->charData[i]);
                        }
                    }
                    if (pData->code == vRestore || pData->code == vRestoreAndStartNewSession) {
                        SendKeyCode(_keycode | ((_flag & kCGEventFlagMaskAlphaShift) || (_flag & kCGEventFlagMaskShift) ? CAPS_MASK : 0));
                    }
                    if (pData->code == vRestoreAndStartNewSession) {
                        startNewSession();
                    }
                }
            } else if (pData->code == vReplaceMaro) { //MACRO
                handleMacro();
            }
            
            return NULL;
        }
        
        return event;
    }
}
