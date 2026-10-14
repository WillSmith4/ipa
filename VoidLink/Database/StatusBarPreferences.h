#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const StatusBarPreferencesDidChangeNotification;

// Shared app appearance, independent of host/application streaming profiles.
@interface StatusBarPreferences : NSObject
@property (class, nonatomic, readonly) StatusBarPreferences *shared;
@property (nonatomic) BOOL alwaysHideStatusBar;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
@end

NS_ASSUME_NONNULL_END
