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
