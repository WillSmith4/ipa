#import <Foundation/Foundation.h>
#import "ApplicationSettingsStore.h"

typedef NS_ENUM(NSInteger, FrontViewPosition) { FrontViewPositionLeft, FrontViewPositionRight };
static NSMutableArray *sent;
@interface HttpResponse : NSObject
@property NSInteger statusCode;
@property NSString *statusMessage;
@end
@implementation HttpResponse @end
@interface HttpRequest : NSObject
@property HttpResponse *response;
@property NSNumber *bitrate;
+ (instancetype)requestForResponse:(HttpResponse *)response withUrlRequest:(NSNumber *)bitrate;
@end
@implementation HttpRequest
+ (instancetype)requestForResponse:(HttpResponse *)response withUrlRequest:(NSNumber *)bitrate {
    HttpRequest *request = [self new]; request.response = response; request.bitrate = bitrate; return request;
}
@end
@interface HttpManager : NSObject
@property NSString *host;
- (instancetype)initWithHost:(NSString *)host;
- (NSNumber *)newBirateRequest:(NSInteger)bitrate forClient:(NSString *)client;
- (void)executeRequestSynchronously:(HttpRequest *)request;
@end
@implementation HttpManager
- (instancetype)initWithHost:(NSString *)host { if ((self = [super init])) _host = host; return self; }
- (NSNumber *)newBirateRequest:(NSInteger)bitrate forClient:(NSString *)client {
    NSCAssert(!NSThread.isMainThread, @"HTTPS discovery must not block menu interaction");
    return @(bitrate);
}
- (void)executeRequestSynchronously:(HttpRequest *)request {
    NSCAssert(!NSThread.isMainThread, @"Network must not block menu interaction");
    [sent addObject:@[self.host, request.bitrate]];
    request.response.statusCode = 200;
}
@end
@interface TemporaryApp : NSObject
@property NSString *host;
@end
@implementation TemporaryApp @end
@interface SettingsViewController : NSObject
@property NSObject *mainFrameViewController;
@property NSInteger saves;
- (void)saveSettings;
@end
@implementation SettingsViewController
- (void)saveSettings { self.saves++; }
@end
@interface SWRevealViewController : NSObject
@property SettingsViewController *rearViewController;
@property BOOL isStreaming;
@end
@implementation SWRevealViewController @end
@interface ControllerNavigator : NSObject
+ (void)persistUINavigationHighlight;
@end
@implementation ControllerNavigator
+ (void)persistUINavigationHighlight {}
@end
@interface TestButton : NSObject
@property BOOL enabled;
@end
@implementation TestButton @end
@interface MainHarness : NSObject {
@public
    BOOL _sessionSettingsMenu, _pendingSettingsReconnect;
    NSNumber *_pendingSettingsBitrate;
    dispatch_queue_t _settingsBitrateQueue;
    TemporaryApp *launchedApp;
    TestButton *_settingsButton, *_upButton;
    FrontViewPosition currentPosition;
}
@property SettingsViewController *settingsViewController;
@property BOOL isStreaming;
- (void)applySavedSessionBitrate:(NSInteger)bitrate;
- (void)revealController:(SWRevealViewController *)menu didMoveToPosition:(FrontViewPosition)position;
- (void)reconnectAfterSettingsChange;
@end
@implementation MainHarness
- (void)reconnectAfterSettingsChange {}
#include "SessionBitrateMethods.inc"
@end

int main(void) {
    @autoreleasepool {
        sent = [NSMutableArray array];
        ApplicationSettingsStore *store = ApplicationSettingsStore.shared;
        [store beginWithHostUUID:@"bitrate-test-host" appID:@"bitrate-test-app"];
        MainHarness *main = [MainHarness new]; main.isStreaming = YES;
        main->launchedApp = [TemporaryApp new]; main->launchedApp.host = @"host-A";
        main->_settingsBitrateQueue = dispatch_queue_create("bitrate-test", DISPATCH_QUEUE_SERIAL);
        SWRevealViewController *menu = [SWRevealViewController new]; menu.isStreaming = YES;
        menu.rearViewController = [SettingsViewController new];
        main->_sessionSettingsMenu = YES;
        main->_pendingSettingsBitrate = @35000;
        [main revealController:menu didMoveToPosition:FrontViewPositionRight];
        dispatch_sync(main->_settingsBitrateQueue, ^{});
        NSCAssert(sent.count == 0, @"Opening settings cannot apply bitrate");
        [main revealController:menu didMoveToPosition:FrontViewPositionLeft];
        dispatch_sync(main->_settingsBitrateQueue, ^{});
        NSCAssert([sent isEqual:@[@[@"host-A", @35000]]] && main->_pendingSettingsBitrate == nil,
                  @"Apply exactly the committed bitrate after collapse without reconnecting");
        main->_sessionSettingsMenu = YES; // Disconnect has no pending saved bitrate
        [main revealController:menu didMoveToPosition:FrontViewPositionLeft];
        dispatch_sync(main->_settingsBitrateQueue, ^{});
        NSCAssert(sent.count == 1 && menu.rearViewController.saves == 0, @"Disconnect cannot save/apply a draft");

        dispatch_suspend(main->_settingsBitrateQueue);
        [main applySavedSessionBitrate:40000];
        main->launchedApp.host = @"host-B";
        dispatch_resume(main->_settingsBitrateQueue);
        dispatch_sync(main->_settingsBitrateQueue, ^{});
        NSCAssert([sent.lastObject isEqual:@[@"host-A", @40000]], @"Queued request captures its host");
        dispatch_suspend(main->_settingsBitrateQueue);
        [main applySavedSessionBitrate:45000];
        [store endSession];
        dispatch_resume(main->_settingsBitrateQueue);
        dispatch_sync(main->_settingsBitrateQueue, ^{});
        NSCAssert(sent.count == 2, @"Stale requests cannot affect another session");
        NSLog(@"Session bitrate: committed value applies after collapse, no UI blocking, no request on disconnect or stale session");
    }
}
