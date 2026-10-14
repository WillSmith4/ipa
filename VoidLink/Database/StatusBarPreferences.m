#import "StatusBarPreferences.h"

NSNotificationName const StatusBarPreferencesDidChangeNotification = @"StatusBarPreferencesDidChangeNotification";
static NSString *const AlwaysHideStatusBarKey = @"voidlink.alwaysHideStatusBar";

@implementation StatusBarPreferences {
    NSUserDefaults *_defaults;
}

+ (instancetype)shared {
    static StatusBarPreferences *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] initWithDefaults:NSUserDefaults.standardUserDefaults]; });
    return shared;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) _defaults = defaults;
    return self;
}

- (BOOL)alwaysHideStatusBar {
    id value = [_defaults objectForKey:AlwaysHideStatusBarKey];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : YES;
}

- (void)setAlwaysHideStatusBar:(BOOL)hidden {
    if (self.alwaysHideStatusBar == hidden) return;
    [_defaults setBool:hidden forKey:AlwaysHideStatusBarKey];
    void (^notify)(void) = ^{
        [NSNotificationCenter.defaultCenter postNotificationName:StatusBarPreferencesDidChangeNotification object:self];
    };
    if (NSThread.isMainThread) notify();
    else dispatch_async(dispatch_get_main_queue(), notify);
}
@end
