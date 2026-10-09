#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Session-only overrides. Global Core Data settings and OSC profiles stay intact.
@interface ApplicationSettingsStore : NSObject
@property (class, nonatomic, readonly) ApplicationSettingsStore *shared;
@property (nonatomic, readonly, nullable) NSString *sessionIdentifier;
@property (nonatomic, readonly) BOOL active;
+ (NSArray<NSString *> *)settingsKeys;
+ (NSArray<NSString *> *)profileKeys;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (void)beginWithHostUUID:(NSString *)hostUUID appID:(NSString *)appID;
- (void)endSession;
- (NSDictionary *)valuesForDomain:(NSString *)domain defaults:(NSDictionary *)defaults;
- (void)stageValues:(NSDictionary *)values previousValues:(NSDictionary *)previous
            domain:(NSString *)domain sessionIdentifier:(nullable NSString *)identifier;
- (void)commitWithSettings:(NSDictionary *)settings profile:(NSDictionary *)profile;
- (void)restoreDefaults;
+ (BOOL)requiresReconnectFrom:(NSDictionary *)previous to:(NSDictionary *)updated;
@end

NS_ASSUME_NONNULL_END
