#import <Foundation/Foundation.h>
#import "StatusBarPreferences.h"
#import "ApplicationSettingsStore.h"

static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) {
    @autoreleasepool {
        NSString *suite = [@"voidlink.statusbar.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        StatusBarPreferences *preferences = [[StatusBarPreferences alloc] initWithDefaults:defaults];
        Check(preferences.alwaysHideStatusBar, @"New and existing installations hide the status bar by default");
        __block NSInteger changes = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:StatusBarPreferencesDidChangeNotification
            object:preferences queue:nil usingBlock:^(NSNotification *note) {
                Check(NSThread.isMainThread, @"Appearance updates run on the main thread");
                changes++;
            }];
        preferences.alwaysHideStatusBar = NO;
        Check(!preferences.alwaysHideStatusBar && changes == 1, @"Disabling hiding immediately notifies UIKit observers");
        StatusBarPreferences *reopened = [[StatusBarPreferences alloc] initWithDefaults:
            [[NSUserDefaults alloc] initWithSuiteName:suite]];
        Check(!reopened.alwaysHideStatusBar, @"Explicit Off survives reopening the preference store");
        preferences.alwaysHideStatusBar = NO;
        Check(changes == 1, @"Unchanged values do not cause repeated appearance updates");

        ApplicationSettingsStore *apps = [[ApplicationSettingsStore alloc] initWithDefaults:defaults];
        [apps beginWithHostUUID:@"pc-a" appID:@"game-a"];
        [apps commitWithSettings:@{@"width": @1920} profile:@{}];
        [apps restoreDefaults];
        [apps endSession];
        [apps beginWithHostUUID:@"pc-b" appID:@"game-b"];
        Check(!preferences.alwaysHideStatusBar, @"Save, Restore Defaults and switching games cannot reset shared status bar visibility");
        [apps endSession];

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ preferences.alwaysHideStatusBar = YES; });
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (changes < 2 && deadline.timeIntervalSinceNow > 0) {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        Check(changes == 2 && reopened.alwaysHideStatusBar, @"Re-enabling persists and delivers a main-thread update");
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        [defaults removePersistentDomainForName:suite];
        NSLog(@"Status bar: default On, persistent Off/On, shared app/stream scope and main-thread updates passed");
    }
    return 0;
}
