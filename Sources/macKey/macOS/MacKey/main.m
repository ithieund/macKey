//
//  main.m
//  MacKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai (OpenKey). Additional changes © 2026 Hung Doan. GPL.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // The storyboard used to instantiate the delegate. Now that the UI is built in
        // code there is no storyboard, so main owns it - and it has to outlive this
        // scope, hence the static.
        static AppDelegate *delegate;
        delegate = [[AppDelegate alloc] init];
        [NSApplication sharedApplication].delegate = delegate;
    }
    return NSApplicationMain(argc, argv);
}
