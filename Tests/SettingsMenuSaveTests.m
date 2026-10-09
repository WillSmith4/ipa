#import <Foundation/Foundation.h>
#import "ApplicationSettingsStore.h"

// Exercise the production button handlers without UIKit animations, using the
// real store to check that Disconnect never persists the current app draft.
typedef NS_ENUM(NSInteger, FrontViewPosition) { FrontViewPositionLeft, FrontViewPositionRight };
typedef NS_ENUM(NSInteger, SettingsMenuMode) { AllSettings, FavoriteSettings, RemoveSettingItem };
@class MenuHarness;
@interface SaveDelegate : NSObject
@property ApplicationSettingsStore *store;
@property NSDictionary *values;
@property NSInteger saves;
- (void)revealControllerWillCollapseSettings:(MenuHarness *)menu;
@end
@implementation SaveDelegate
- (void)revealControllerWillCollapseSettings:(MenuHarness *)menu {
    self.saves++;
    [self.store commitWithSettings:self.values profile:@{}];
}
@end

@interface MenuHarness : NSObject
@property SaveDelegate *delegate;
@property BOOL isStreaming;
@property FrontViewPosition frontViewPosition;
- (void)foldRearView;
- (void)disconnectRemoteSession;
@end
@implementation MenuHarness
- (void)setFrontViewPosition:(FrontViewPosition)position animated:(BOOL)animated { _frontViewPosition = position; }
- (SettingsMenuMode)getSettingsMenuMode { return AllSettings; }
- (void)doneRemoveSettingItemSelected {}
- (void)allSettingSelected {}
- (void)favoriteSettingSelected {}
#include "SettingsMenuButtonMethods.inc"
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) {
    @autoreleasepool {
        NSString *suite = [@"voidlink.menu.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        SaveDelegate *delegate = [SaveDelegate new];
        delegate.store = [[ApplicationSettingsStore alloc] initWithDefaults:defaults];
        delegate.values = @{@"bitrate": @35000};
        ApplicationSettingsStore *reader = [[ApplicationSettingsStore alloc] initWithDefaults:defaults];
        NSDictionary *global = @{@"bitrate": @20000};
        MenuHarness *menu = [MenuHarness new];
        menu.delegate = delegate;
        menu.isStreaming = YES;
        __block NSInteger disconnects = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:@"SessionDisconnectedBySettingsMenuNotification"
            object:menu queue:nil usingBlock:^(NSNotification *note) { disconnects++; }];

        [delegate.store beginWithHostUUID:@"host" appID:@"app"];
        menu.frontViewPosition = FrontViewPositionRight;
        [delegate.store stageValues:delegate.values previousValues:global domain:@"settings"
                 sessionIdentifier:delegate.store.sessionIdentifier];
        [menu disconnectRemoteSession];
        [reader beginWithHostUUID:@"host" appID:@"app"];
        Check(delegate.saves == 0 && disconnects == 1 && menu.frontViewPosition == FrontViewPositionLeft,
              @"Disconnect closes the panel and ends the session without pressing Save");
        Check([[reader valuesForDomain:@"settings" defaults:global] isEqual:global],
              @"Opening, editing and disconnecting cannot create an app override");

        menu.frontViewPosition = FrontViewPositionRight;
        [menu foldRearView];
        [reader beginWithHostUUID:@"host" appID:@"app"];
        Check(delegate.saves == 1 && disconnects == 1 &&
              [[reader valuesForDomain:@"settings" defaults:global] isEqual:delegate.values],
              @"The collapse button saves the app and keeps the connection");
        delegate.values = @{@"bitrate": @50000};
        menu.frontViewPosition = FrontViewPositionRight;
        [menu disconnectRemoteSession];
        [reader beginWithHostUUID:@"host" appID:@"app"];
        Check(delegate.saves == 1 && [[[reader valuesForDomain:@"settings" defaults:global] objectForKey:@"bitrate"] intValue] == 35000,
              @"Disconnect cannot overwrite previously saved app settings");

        [delegate.store restoreDefaults];
        menu.frontViewPosition = FrontViewPositionRight;
        [menu foldRearView];
        [delegate.store beginWithHostUUID:@"host" appID:@"app"];
        menu.frontViewPosition = FrontViewPositionRight;
        [menu disconnectRemoteSession];
        [reader beginWithHostUUID:@"host" appID:@"app"];
        NSDictionary *updatedGlobal = @{@"bitrate": @40000};
        Check([[reader valuesForDomain:@"settings" defaults:updatedGlobal] isEqual:updatedGlobal],
              @"Restore then disconnect in another session preserves inheritance of future defaults");
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        [defaults removePersistentDomainForName:suite];
        NSLog(@"Settings menu: collapse saves; disconnect preserves existing overrides and default inheritance");
    }
    return 0;
}
