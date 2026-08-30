//
//  AboutViewController.h
//  OhMyKey
//
//  Created by Tuyen on 2/15/19.
//  Copyright © 2019 Tuyen Mai (OpenKey). Fork: OhMyKey © 2026 Hung Doan. GPL.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface AboutViewController : NSViewController
@property (weak) IBOutlet NSTextField *VersionInfo;
@property (weak) IBOutlet NSButton *CheckNewVersionButton;
@property (weak) IBOutlet NSButton *CheckUpdateOnStatus;

@end

NS_ASSUME_NONNULL_END
