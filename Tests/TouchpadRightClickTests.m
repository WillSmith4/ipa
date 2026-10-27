#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

// Compile the actual handler methods. Drive the two UIKit callback orderings
// explicitly and drain queued callbacks without relying on wall-clock timing.
enum { BUTTON_ACTION_PRESS = 7, BUTTON_ACTION_RELEASE = 8, BUTTON_LEFT = 1, BUTTON_RIGHT = 3 };
enum { UIGestureRecognizerStatePossible, UIGestureRecognizerStateRecognized };
static const float QUICK_TAP_TIME_INTERVAL = 0.2;
static NSMutableArray *immediate, *delayed, *events;
static void enqueueImmediate(dispatch_queue_t queue, dispatch_block_t block) { [immediate addObject:[block copy]]; }
static void enqueueDelayed(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block) { [delayed addObject:[block copy]]; }
#define dispatch_async enqueueImmediate
#define dispatch_after enqueueDelayed
#define Log(...) ((void)0)
static void LiSendMouseButtonEvent(int action, int button) {
    [events addObject:[NSString stringWithFormat:@"%d:%d", button, action]];
}
@interface UIEvent : NSObject @end
@implementation UIEvent @end
@interface CustomTapGestureRecognizer : NSObject
@property NSInteger state;
@end
@implementation CustomTapGestureRecognizer @end
@interface TouchPadGestureHandler : NSObject
+ (void)cancel;
@end
@implementation TouchPadGestureHandler
+ (void)cancel {}
@end

@interface TouchpadRightClickHarness : NSObject {
    NSUInteger inputGeneration, rightClickGeneration;
    BOOL multiTouchesDetected, quickTapDetected, mousePointerMoved;
    id touchLockedForMouseMove;
}
@property CustomTapGestureRecognizer *mouseRightClickTapRecognizer;
- (void)mouseRightClick;
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)sendLongMouseLeftButtonClickEvent;
@end
@implementation TouchpadRightClickHarness
#include "TouchpadRightClickMethods.inc"
@end

static void drain(NSMutableArray *queue) {
    while (queue.count) {
        dispatch_block_t block = queue.firstObject;
        [queue removeObjectAtIndex:0];
        block();
    }
}
static void check(NSArray *expected) {
    NSCAssert([events isEqualToArray:expected], @"Unexpected input: %@; expected %@", events, expected);
}
static TouchpadRightClickHarness *makeHandler(void) {
    NSCAssert(!immediate.count && !delayed.count, @"Each sequence must finish its callbacks");
    [events removeAllObjects];
    TouchpadRightClickHarness *handler = [TouchpadRightClickHarness new];
    handler.mouseRightClickTapRecognizer = [CustomTapGestureRecognizer new];
    handler.mouseRightClickTapRecognizer.state = UIGestureRecognizerStateRecognized;
    return handler;
}

int main(void) {
    @autoreleasepool {
        immediate = [NSMutableArray array]; delayed = [NSMutableArray array]; events = [NSMutableArray array];
        UIEvent *event = [UIEvent new];
        for (NSNumber *cancelFirst in @[@NO, @YES]) {
            TouchpadRightClickHarness *handler = makeHandler();
            [handler sendLongMouseLeftButtonClickEvent]; // Any queued left click must still be cancelled.
            if (cancelFirst.boolValue) [handler touchesCancelled:[NSSet set] withEvent:event];
            [handler mouseRightClick];
            if (!cancelFirst.boolValue) [handler touchesCancelled:[NSSet set] withEvent:event];
            // UIKit can reset the recognizer before the queued click executes.
            handler.mouseRightClickTapRecognizer.state = UIGestureRecognizerStatePossible;
            drain(immediate);
            check(@[@"1:8", @"3:7"]);
            drain(delayed);
            check(@[@"1:8", @"3:7", @"3:8"]);
        }

        TouchpadRightClickHarness *handler = makeHandler();
        [handler mouseRightClick];
        drain(immediate);
        [handler touchesCancelled:[NSSet set] withEvent:event];
        check(@[@"3:7", @"1:8"]); // Own completion cannot shorten its click pulse.
        drain(delayed);
        check(@[@"3:7", @"1:8", @"3:8"]);

        // Teardown must always cancel, even while the recognizer says Recognized.
        // Other recognizers/system interruptions must cancel too.
        for (NSNumber *explicitCancel in @[@NO, @YES]) {
            for (NSNumber *alreadyPressed in @[@NO, @YES]) {
                handler = makeHandler();
                [handler mouseRightClick];
                if (alreadyPressed.boolValue) drain(immediate);
                if (!explicitCancel.boolValue) handler.mouseRightClickTapRecognizer.state = UIGestureRecognizerStatePossible;
                [handler touchesCancelled:[NSSet set] withEvent:explicitCancel.boolValue ? nil : event];
                NSArray *expected = alreadyPressed.boolValue ? @[@"3:7", @"1:8", @"3:8"] : @[@"1:8", @"3:8"];
                check(expected);
                drain(immediate); drain(delayed);
                check(expected);
            }
        }
        puts("Touchpad right click: both recognition/cancellation orders, one pulse, unchanged left cancellation, teardown and interruption passed");
    }
    return 0;
}
