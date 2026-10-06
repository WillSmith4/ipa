#import <CoreData/CoreData.h>

// Keep the old attributes in the model so lightweight migration can recover
// both bindings. A nil unified binding makes this migration run exactly once.
static inline void InitializeUnifiedRotationSettings(NSManagedObject *settings) {
    if ([settings valueForKey:@"rotationAction"] != nil) return;
    NSString *left = [settings valueForKey:@"rotateLeftAction"];
    NSString *right = [settings valueForKey:@"rotateRightAction"];
    [settings setValue:(left != nil && [left isEqualToString:right] ? left : @"MOUSE_MIDDLE")
                forKey:@"rotationAction"];
    BOOL movesCursor = [[settings valueForKey:@"rotateLeftMovesCursor"] boolValue] ||
                       [[settings valueForKey:@"rotateRightMovesCursor"] boolValue];
    [settings setValue:@(movesCursor) forKey:@"rotationMovesCursor"];
}

// Convert the previous on/off choice once. A fresh install defaults to right click.
static inline void InitializeLongPressSettings(NSManagedObject *settings) {
    if ([settings valueForKey:@"longPressAction"] != nil) return;
    [settings setValue:([[settings valueForKey:@"singlePointLongPressRightClick"] boolValue]
                        ? @"MOUSE_RIGHT" : @"NONE") forKey:@"longPressAction"];
}
