#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "ApplicationSettingsStore.h"

static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

// Compile the production DataManager read/write methods against a real Core
// Data model. Only the UIKit AppDelegate and database lookup are substituted.
#define Settings NSManagedObject
#define Log(level, ...) NSLog(__VA_ARGS__)
@interface NSObject (TestAppDelegate)
- (void)saveContext;
@end
@interface SettingsDataHarness : NSObject
- (instancetype)initWithGlobal:(NSManagedObject *)global;
- (Settings *)retrieveSettings;
- (Settings *)retrieveGlobalSettings;
- (void)saveData;
@end
@implementation SettingsDataHarness {
    NSManagedObjectContext *_managedObjectContext;
    id _appDelegate;
    Settings *_global;
    Settings *_sessionSettings;
    NSDictionary *_sessionSettingsBaseline;
    NSString *_settingsSessionIdentifier;
}
- (instancetype)initWithGlobal:(NSManagedObject *)global {
    if ((self = [super init])) { _global = global; _managedObjectContext = global.managedObjectContext; }
    return self;
}
- (Settings *)retrieveGlobalSettings { return _global; }
#include "SessionSettingsDataMethods.inc"
@end
#undef Settings

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *suite = [@"voidlink.settings.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        ApplicationSettingsStore *store = [[ApplicationSettingsStore alloc] initWithDefaults:defaults];
        NSDictionary *global = @{@"width": @1920, @"height": @1080, @"framerate": @60,
            @"bitrate": @20000, @"touchMode": @1, @"rotationAction": @"MOUSE_MIDDLE",
            @"preferredCodec": @2, @"enableHdr": @NO, @"enableYUV444": @NO,
            @"framePacingMode": @1, @"asyncFrameDequeue": @NO, @"renderingBackend": @0,
            @"unlockDisplayOrientation": @NO, @"uniqueId": @"shared-client"};
        NSDictionary *profile = @{@"touchMode": @1, @"pencilPausesNativeTouch": @YES,
            @"gyroSensitivityYaw": @1, @"brushShortcut": @"B"};
        Check([[store valuesForDomain:@"settings" defaults:global] isEqual:global], @"Main settings use global values");
        [store beginWithHostUUID:@" PC-A " appID:@" 10 "];
        NSString *token = store.sessionIdentifier;
        NSMutableDictionary *edited = [global mutableCopy];
        edited[@"width"] = @2560; edited[@"height"] = @1440;
        edited[@"bitrate"] = @35000; edited[@"touchMode"] = @2;
        edited[@"preferredCodec"] = @3; edited[@"enableHdr"] = @YES;
        edited[@"framePacingMode"] = @3; edited[@"unlockDisplayOrientation"] = @YES;
        [store stageValues:edited previousValues:global domain:@"settings" sessionIdentifier:token];
        NSMutableDictionary *controls = [profile mutableCopy];
        controls[@"touchMode"] = @2; controls[@"brushShortcut"] = @"E";
        [store stageValues:controls previousValues:profile domain:@"profile" sessionIdentifier:token];
        NSDictionary *effective = [store valuesForDomain:@"settings" defaults:global];
        Check([effective[@"width"] intValue] == 2560, @"Session draft is used by stream readers");
        Check([effective[@"preferredCodec"] intValue] == 2 && ![effective[@"enableHdr"] boolValue] &&
              [effective[@"framePacingMode"] intValue] == 1 && ![effective[@"unlockDisplayOrientation"] boolValue], @"Connection-only settings are shared");
        ApplicationSettingsStore *reopened = [[ApplicationSettingsStore alloc] initWithDefaults:defaults];
        [reopened beginWithHostUUID:@"pc-a" appID:@"10"];
        Check([[reopened valuesForDomain:@"settings" defaults:global] isEqual:global], @"Draft does not persist before closing Settings");
        [store commitWithSettings:effective profile:controls];
        [reopened beginWithHostUUID:@"pc-a" appID:@"10"];
        Check([[reopened valuesForDomain:@"settings" defaults:global] isEqual:effective], @"Closing saves the app on this host");
        Check([[[reopened valuesForDomain:@"profile" defaults:profile] objectForKey:@"brushShortcut"] isEqual:@"E"], @"OSC/Pencil settings persist for the app");
        for (NSArray *identity in @[@[@"pc-a", @"11"], @[@"pc-b", @"10"]]) {
            [reopened beginWithHostUUID:identity[0] appID:identity[1]];
            Check([[reopened valuesForDomain:@"settings" defaults:global] isEqual:global], @"Other apps and hosts remain independent");
        }
        [store restoreDefaults];
        [store stageValues:edited previousValues:global domain:@"settings" sessionIdentifier:token];
        Check([[store valuesForDomain:@"settings" defaults:global] isEqual:global], @"Reset rejects stale edits");
        [store stageValues:global previousValues:global domain:@"settings" sessionIdentifier:store.sessionIdentifier];
        [store commitWithSettings:global profile:profile];
        [reopened beginWithHostUUID:@"pc-a" appID:@"10"];
        NSMutableDictionary *newDefaults = [global mutableCopy]; newDefaults[@"bitrate"] = @40000;
        Check([[reopened valuesForDomain:@"settings" defaults:newDefaults] isEqual:newDefaults], @"Restore removes the override and follows future main settings");
        NSMutableDictionary *touchOnly = [global mutableCopy]; touchOnly[@"touchMode"] = @2; touchOnly[@"bitrate"] = @35000;
        Check(![ApplicationSettingsStore requiresReconnectFrom:global to:touchOnly], @"Touch and bitrate do not reconnect");
        Check([ApplicationSettingsStore requiresReconnectFrom:global to:edited], @"Resolution reconnects");
        touchOnly[@"framerate"] = @120;
        Check([ApplicationSettingsStore requiresReconnectFrom:global to:touchOnly], @"FPS reconnects");
        [store endSession];
        [store stageValues:edited previousValues:global domain:@"settings" sessionIdentifier:token];
        Check(!store.active && [[store valuesForDomain:@"settings" defaults:global] isEqual:global], @"Leaving the stream restores global settings");
        [store beginWithHostUUID:@" " appID:@"10"];
        Check(!store.active, @"Missing host identity cannot create an app record");

        // Real Core Data integration: two writers must merge independent edits,
        // and no in-session value may leak into the shared persistent object.
        NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:
            [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]];
        for (NSEntityDescription *entity in model.entities) entity.managedObjectClassName = @"NSManagedObject";
        NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        Check([coordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:nil] != nil, @"Core Data model loads");
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        context.persistentStoreCoordinator = coordinator;
        NSManagedObject *row = [NSEntityDescription insertNewObjectForEntityForName:@"Settings" inManagedObjectContext:context];
        [row setValuesForKeysWithDictionary:global];
        [context save:nil];
        NSString *hostID = NSUUID.UUID.UUIDString;
        ApplicationSettingsStore *shared = ApplicationSettingsStore.shared;
        [shared beginWithHostUUID:hostID appID:@"42"];
        SettingsDataHarness *first = [[SettingsDataHarness alloc] initWithGlobal:row];
        SettingsDataHarness *second = [[SettingsDataHarness alloc] initWithGlobal:row];
        NSManagedObject *a = [first retrieveSettings], *b = [second retrieveSettings];
        Check(a.managedObjectContext == nil && b.managedObjectContext == nil, @"App settings are detached from global Core Data");
        [a setValue:@2560 forKey:@"width"];
        [b setValue:@"Q" forKey:@"rotationAction"];
        [first saveData]; [second saveData];
        NSManagedObject *saved = [first retrieveSettings];
        Check([[saved valueForKey:@"width"] intValue] == 2560 && [[saved valueForKey:@"rotationAction"] isEqual:@"Q"], @"Independent DataManagers merge edits");
        Check([[row valueForKey:@"width"] intValue] == 1920 && [[row valueForKey:@"rotationAction"] isEqual:@"MOUSE_MIDDLE"], @"Global row remains intact");
        [saved setValue:@17 forKey:@"localRadialMenuButton"];
        NSManagedObject *nextStep = [first retrieveSettings];
        [nextStep setValue:@18 forKey:@"streamingRadialMenuButton"];
        [first saveData];
        saved = [first retrieveSettings];
        Check([[saved valueForKey:@"localRadialMenuButton"] intValue] == 17 &&
              [[saved valueForKey:@"streamingRadialMenuButton"] intValue] == 18,
              @"Multi-step controller capture keeps earlier choices until the final save");
        [saved setValue:@120 forKey:@"framerate"];
        [shared endSession]; [first saveData];
        Check([[row valueForKey:@"framerate"] intValue] == 60, @"Late session save cannot overwrite globals");
        Check([first retrieveSettings] == row, @"Main settings return to their original object");
        [[first retrieveSettings] setValue:@30 forKey:@"framerate"]; [first saveData];
        Check([[row valueForKey:@"framerate"] intValue] == 30, @"Main settings still save normally");
        [defaults removePersistentDomainForName:suite];
        NSLog(@"Application settings: host/app isolation, restore, shared settings, reconnect decisions and Core Data integration passed");
    }
    return 0;
}
