//
//  AboutViewController.m
//  OhMyKey
//
//  Created by Tuyen on 2/15/19.
//  Copyright © 2019 Tuyen Mai (OpenKey). Fork: OhMyKey © 2026 Hung Doan. GPL.
//

#import "AboutViewController.h"
#import "OhMyKeyManager.h"

@interface AboutViewController ()

@end

@implementation AboutViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    
    self.VersionInfo.stringValue = [NSString stringWithFormat:@"Phiên bản %@ (build %@) - Ngày cập nhật %@",
                                    [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"],
                                    [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleVersion"],
                                    [OhMyKeyManager getBuildDate]] ;
    
    NSInteger dontCheckUpdate = [[NSUserDefaults standardUserDefaults] integerForKey:@"DontCheckUpdate"];
    self.CheckUpdateOnStatus.state = dontCheckUpdate ? NSControlStateValueOff :NSControlStateValueOn;
}

- (IBAction)onHomePage:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString:@"https://github.com/hungdoansy/OhMyKey"]];
}

- (IBAction)onFanPage:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString:@"https://github.com/hungdoansy/OhMyKey/issues"]];
}

- (IBAction)onLatestReleaseVersion:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString:@"https://github.com/hungdoansy/OhMyKey/releases"]];
}

- (IBAction)onCheckUpdateOnStartup:(NSButton *)sender {
    NSInteger val = sender.state == NSControlStateValueOn ? 0 : 1;
    [[NSUserDefaults standardUserDefaults] setInteger:val forKey:@"DontCheckUpdate"];
}

- (IBAction)onCheckNewVersion:(id)sender {
    
    self.CheckNewVersionButton.title = @"Đang kiểm tra...";
    self.CheckNewVersionButton.enabled = false;
    
    [OhMyKeyManager checkNewVersion: self.view.window callbackFunc:^{
        self.CheckNewVersionButton.enabled = true;
        self.CheckNewVersionButton.title = @"Kiểm tra bản mới...";
    }];
}

@end
