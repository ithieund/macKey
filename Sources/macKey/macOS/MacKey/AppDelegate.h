//
//  AppDelegate.h
//  MacKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai (OpenKey). Additional changes © 2026 Hung Doan. GPL.
//

#import <Cocoa/Cocoa.h>

#define MACKEY_BUNDLE @"vn.ithieund.mackey"

/// Thread-safe in-app diagnostics. The status-bar Debug menu exposes these entries
/// and persists them to ~/Library/Logs/macKey/Debug.log for later investigation.
FOUNDATION_EXPORT void MacKeyDebugLog(NSString * _Nonnull message);

@interface AppDelegate : NSObject <NSApplicationDelegate>

-(void)onImputMethodChanged:(BOOL)willNotify;
-(void)onInputMethodSelected;
/// Applies a saved Smart-switch state without toggling the current value. Returns NO
/// when the state is corrupt or could not be reflected in the status UI.
-(BOOL)applySmartSwitchState:(int)state error:(NSError * _Nullable * _Nullable)error;
/// Falls back to English, updates the status icon, and presents a non-blocking error toast.
-(void)handleSmartSwitchFailure:(NSString * _Nullable)reason;
-(void)appendDebugLog:(NSString * _Nonnull)message;

-(void)askPermission;

-(void)onInputTypeSelectedIndex:(int)index;
-(void)onCodeTableChanged:(int)index;

-(void)setRunOnStartup:(BOOL)val;
-(void)loadDefaultConfig;

-(void)setGrayIcon:(BOOL)val;

-(void)onControlPanelSelected;
-(void)onMacroSelected;
-(void)onConvertTool;
-(void)onAboutSelected;
-(void)onQuickConvert;
-(void)setQuickConvertString;

-(void)showIconOnDock:(BOOL)val;
@end
