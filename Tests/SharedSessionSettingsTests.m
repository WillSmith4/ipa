#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#define Settings NSManagedObject
#define Log(level, ...) NSLog(__VA_ARGS__)
@interface NSObject (TestAppDelegate)
- (void)saveContext;
@end
@interface SharedSettingsHarness : NSObject
@property NSManagedObjectContext *managedObjectContext;
@property id appDelegate;
@end
@implementation SharedSettingsHarness
- (NSArray *)fetchRecords:(NSString *)entity {
    return [_managedObjectContext executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:entity] error:nil];
}
- (void)initializeGestureActions:(NSManagedObject *)settings {}
#include "SessionSettingsDataMethods.inc"
@end
#undef Settings
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:[NSURL fileURLWithPath:@(argv[1])]];
        // Use plain managed objects so this harness needs no UIKit app delegate.
        for (NSEntityDescription *entity in model.entities) { entity.managedObjectClassName = @"NSManagedObject"; }
        NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        NSCAssert([coordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:nil], @"Create test database");
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        context.persistentStoreCoordinator = coordinator;
        SharedSettingsHarness *sidebar = [SharedSettingsHarness new]; sidebar.managedObjectContext = context;
        SharedSettingsHarness *mainMenu = [SharedSettingsHarness new]; mainMenu.managedObjectContext = context;
        NSManagedObject *settings = [sidebar retrieveSettings];
        [settings setValue:@35000 forKey:@"bitrate"];
        [sidebar saveData];
        NSCAssert([mainMenu retrieveSettings] == settings, @"Sidebar and main menu use the same persisted settings row");
        NSCAssert([[[mainMenu retrieveSettings] valueForKey:@"bitrate"] intValue] == 35000, @"Sidebar changes reach main settings");
        [[mainMenu retrieveSettings] setValue:@45000 forKey:@"bitrate"];
        [mainMenu saveData];
        NSCAssert([[[sidebar retrieveSettings] valueForKey:@"bitrate"] intValue] == 45000, @"Later main settings changes reach the sidebar");
        NSCAssert([sidebar fetchRecords:@"Settings"].count == 1, @"No per-app settings rows are created");
        NSLog(@"Shared session settings: same Core Data row, bidirectional edits and no app overrides passed");
    }
}
