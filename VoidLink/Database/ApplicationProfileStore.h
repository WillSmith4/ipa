#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Stores only a reference to an existing Game Profile, never settings or layout copies.
@interface ApplicationProfileStore : NSObject
@property (class, nonatomic, readonly) ApplicationProfileStore *shared;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (nullable NSString *)profileIdentifierForHostUUID:(nullable NSString *)hostUUID appID:(nullable NSString *)appID;
- (void)setProfileIdentifier:(nullable NSString *)identifier forHostUUID:(nullable NSString *)hostUUID appID:(nullable NSString *)appID;
@end
NS_ASSUME_NONNULL_END
