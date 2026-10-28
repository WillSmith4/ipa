#import <Foundation/Foundation.h>
#import "ApplicationProfileStore.h"
static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
int main(void) {
    @autoreleasepool {
        NSString *suite = [@"voidlink.profiles.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        ApplicationProfileStore *store = [[ApplicationProfileStore alloc] initWithDefaults:defaults];
        [store setProfileIdentifier:@"profile-one" forHostUUID:@" HOST-a\n" appID:@" 101 "];
        ApplicationProfileStore *reopened = [[ApplicationProfileStore alloc] initWithDefaults:[[NSUserDefaults alloc] initWithSuiteName:suite]];
        Check([[reopened profileIdentifierForHostUUID:@"host-A" appID:@"101"] isEqual:@"profile-one"], @"Normalized host/app assignment survives reopening");
        Check(![store profileIdentifierForHostUUID:@"host-b" appID:@"101"], @"Same app ID on another PC remains unassigned");
        Check(![store profileIdentifierForHostUUID:@"host-a" appID:@"102"], @"Other applications remain unassigned");
        [store setProfileIdentifier:@"profile-two" forHostUUID:@"host-a" appID:@"101"];
        Check([[reopened profileIdentifierForHostUUID:@"host-a" appID:@"101"] isEqual:@"profile-two"], @"A second drop overwrites the assignment");
        [store setProfileIdentifier:@"first" forHostUUID:@"a/b" appID:@"c"];
        [store setProfileIdentifier:@"second" forHostUUID:@"a" appID:@"b/c"];
        Check([[store profileIdentifierForHostUUID:@"a/b" appID:@"c"] isEqual:@"first"], @"Encoded composite keys do not collide on separators");
        [store setProfileIdentifier:nil forHostUUID:@"host-a" appID:@"101"];
        Check(![store profileIdentifierForHostUUID:@"host-a" appID:@"101"], @"Deleted profile references can be removed");
        NSDictionary *before = [defaults persistentDomainForName:suite];
        [store setProfileIdentifier:@"invalid" forHostUUID:@" " appID:@"101"];
        [store setProfileIdentifier:@"invalid" forHostUUID:nil appID:@"101"];
        [store setProfileIdentifier:@"invalid" forHostUUID:@"host-a" appID:nil];
        Check([[defaults persistentDomainForName:suite] isEqual:before], @"Incomplete destinations never save an assignment");
        for (id value in before.allValues) { Check([value isKindOfClass:NSString.class], @"Store contains profile IDs only, no settings/layout copies"); }
        [defaults removePersistentDomainForName:suite];
        NSLog(@"Profile assignments: normalization, persistence, host/app isolation, overwrite, removal and invalid destinations passed");
    }
}
