//
//  AppDelegate.h
//  OhMyKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai (OpenKey). Fork: OhMyKey © 2026 Hung Doan. GPL.
//

#import <Cocoa/Cocoa.h>
#import "ViewController.h"

#define OHMYKEY_BUNDLE @"com.hungdoansy.ohmykey"

//Bundle id used by OpenKey, the project OhMyKey was forked from. Settings live in
//the preferences domain named after the bundle id, so renaming the app orphaned
//them; we copy them across once on first launch. See migrateLegacyDefaultsIfNeeded.
#define OHMYKEY_LEGACY_BUNDLE @"com.tuyenmai.openkey"
#define OHMYKEY_MIGRATED_KEY @"OhMyKeyMigratedFromOpenKey"

@interface AppDelegate : NSObject <NSApplicationDelegate>

-(void)onImputMethodChanged:(BOOL)willNotify;
-(void)onInputMethodSelected;

-(void)askPermission;

-(void)onInputTypeSelectedIndex:(int)index;
-(void)onCodeTableChanged:(int)index;

-(void)setRunOnStartup:(BOOL)val;
-(void)loadDefaultConfig;

-(void)setGrayIcon:(BOOL)val;

-(void)onMacroSelected;
-(void)onQuickConvert;
-(void)setQuickConvertString;

-(void)showIconOnDock:(BOOL)val;
@end

