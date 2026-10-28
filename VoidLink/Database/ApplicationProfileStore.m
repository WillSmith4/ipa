#import "ApplicationProfileStore.h"

@implementation ApplicationProfileStore {
    NSUserDefaults *_defaults;
}
+ (instancetype)shared {
    static ApplicationProfileStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [[self alloc] initWithDefaults:NSUserDefaults.standardUserDefaults]; });
    return store;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) { _defaults = defaults; }
    return self;
}
- (NSString *)keyForHostUUID:(NSString *)hostUUID appID:(NSString *)appID {
    NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *host = [[hostUUID stringByTrimmingCharactersInSet:spaces] lowercaseString];
    NSString *app = [appID stringByTrimmingCharactersInSet:spaces];
    if (host.length == 0 || app.length == 0) { return nil; }
    NSString *encodedHost = [[host dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    NSString *encodedApp = [[app dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    return [NSString stringWithFormat:@"VoidLink.ApplicationGameProfile.v1.%@.%@", encodedHost, encodedApp];
}
- (NSString *)profileIdentifierForHostUUID:(NSString *)hostUUID appID:(NSString *)appID {
    NSString *key = [self keyForHostUUID:hostUUID appID:appID];
    return key ? [_defaults stringForKey:key] : nil;
}
- (void)setProfileIdentifier:(NSString *)identifier forHostUUID:(NSString *)hostUUID appID:(NSString *)appID {
    NSString *key = [self keyForHostUUID:hostUUID appID:appID];
    if (!key) { return; }
    if (identifier.length) { [_defaults setObject:identifier forKey:key]; }
    else { [_defaults removeObjectForKey:key]; }
}
@end
