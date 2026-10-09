#import <Foundation/Foundation.h>

// Exercise the production termination method with a blocked transport. A
// reconnect completion must run only once the old transport has fully stopped.
static NSLock *initLock;
static id audioPlayerNode, audioEngine;
static dispatch_semaphore_t stopEntered, allowStop;
static int interrupts, stops;
static void LiInterruptConnection(void) { interrupts++; }
static void LiStopConnection(void) {
    stops++;
    dispatch_semaphore_signal(stopEntered);
    dispatch_semaphore_wait(allowStop, DISPATCH_TIME_FOREVER);
}
@interface NSObject (AudioStub)
- (void)stop;
@end
@interface ControllerUtil : NSObject
+ (void)stopAllDualSenseHaptics;
@end
@implementation ControllerUtil
+ (void)stopAllDualSenseHaptics {}
@end
@interface StopHarness : NSOperation
- (void)terminateWithCompletion:(void (^)(void))completion;
@end
@implementation StopHarness {
    dispatch_group_t _terminationGroup;
}
#include "ConnectionStopMethod.inc"
@end

int main(void) {
    @autoreleasepool {
        initLock = [NSLock new];
        stopEntered = dispatch_semaphore_create(0);
        allowStop = dispatch_semaphore_create(0);
        StopHarness *connection = [StopHarness new];
        __block int completions = 0;
        [connection terminateWithCompletion:^{ completions++; }];
        [connection terminateWithCompletion:^{ completions++; }];
        NSCAssert(dispatch_semaphore_wait(stopEntered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0, @"Stop begins");
        NSCAssert(interrupts == 1 && stops == 1 && completions == 0 && connection.isCancelled,
                  @"Duplicate cleanup cannot stop a future connection or finish reconnect early");
        dispatch_semaphore_signal(allowStop);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (completions < 2 && deadline.timeIntervalSinceNow > 0) {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        NSCAssert(completions == 2, @"All completion handlers run after the old connection finishes");
        [connection terminateWithCompletion:^{ completions++; }];
        deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (completions < 3 && deadline.timeIntervalSinceNow > 0) {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        NSCAssert(completions == 3 && interrupts == 1 && stops == 1, @"Late cleanup is harmless");
        NSLog(@"Connection stop: reconnect waits for completion and duplicate cleanup is harmless");
    }
    return 0;
}
