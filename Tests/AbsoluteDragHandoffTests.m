#import <Foundation/Foundation.h>

// Compile the actual Objective-C delayed-click and handoff methods. Only the
// transport and the already separately tested Swift input bridge are replaced.
enum { BUTTON_ACTION_PRESS = 7, BUTTON_ACTION_RELEASE = 8, BUTTON_LEFT = 1, BUTTON_RIGHT = 3 };
static NSMutableArray<NSString *> *events;
static void (^onLeftPress)(void);
static void LiSendMouseButtonEvent(int action, int button) {
    [events addObject:[NSString stringWithFormat:@"%d:%d", button, action]];
    if (action == BUTTON_ACTION_PRESS && button == BUTTON_LEFT && onLeftPress) {
        void (^callback)(void) = onLeftPress;
        onLeftPress = nil;
        callback();
    }
}

@interface GestureLongPressAction : NSObject
- (void)cancel;
@end
@implementation GestureLongPressAction
- (void)cancel {}
@end

@interface GestureDoubleTapDragAction : NSObject
@property int button;
- (void)begin;
@end
@implementation GestureDoubleTapDragAction
- (void)begin { LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, self.button); }
@end

@interface AbsoluteDragHarness : NSObject {
    NSUInteger inputGeneration;
    BOOL pendingLeftClick, pendingLeftRelease;
    NSTimeInterval leftClickDelay;
    NSTimer *longPressTimer;
    GestureLongPressAction *longPressAction;
    GestureDoubleTapDragAction *doubleTapDragAction;
}
- (instancetype)initWithDelay:(double)delay button:(int)button;
- (void)beginDoubleTapDrag;
- (void)sendShortMouseLeftButtonClickEvent;
@end

@implementation AbsoluteDragHarness
- (instancetype)initWithDelay:(double)delay button:(int)button {
    if ((self = [super init])) {
        leftClickDelay = delay;
        longPressAction = [GestureLongPressAction new];
        doubleTapDragAction = [GestureDoubleTapDragAction new];
        doubleTapDragAction.button = button;
    }
    return self;
}
#include "AbsoluteDragHandoffMethods.inc"
@end

static void settleCallbacks(void) {
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
}
static void check(NSArray *expected) {
    NSCAssert([events isEqualToArray:expected], @"Unexpected input sequence: %@; expected %@", events, expected);
}

int main(void) {
    @autoreleasepool {
        events = [NSMutableArray array];
        // The first click is still pending when the second touch arrives.
        for (NSNumber *button in @[@1, @2, @3]) {
            [events removeAllObjects];
            AbsoluteDragHarness *handler = [[AbsoluteDragHarness alloc] initWithDelay:0.02 button:button.intValue];
            [handler sendShortMouseLeftButtonClickEvent];
            NSCAssert(events.count == 0, @"Keep the user's existing left-click delay");
            [handler beginDoubleTapDrag];
            NSArray *expected = @[@"1:7", @"1:8", [NSString stringWithFormat:@"%@:7", button]];
            check(expected);
            settleCallbacks();
            check(expected); // neither a late left press nor right release may leak
        }

        // Reproduce handoff after the first down but before its queued release.
        [events removeAllObjects];
        AbsoluteDragHarness *handler = [[AbsoluteDragHarness alloc] initWithDelay:0 button:3];
        onLeftPress = ^{ [handler beginDoubleTapDrag]; };
        [handler sendShortMouseLeftButtonClickEvent];
        settleCallbacks();
        check(@[@"1:7", @"1:8", @"3:7"]);

        // If the ordinary first click already finished, never synthesize another.
        [events removeAllObjects];
        handler = [[AbsoluteDragHarness alloc] initWithDelay:0 button:2];
        [handler sendShortMouseLeftButtonClickEvent];
        settleCallbacks();
        check(@[@"1:7", @"1:8", @"3:8"]);
        [handler beginDoubleTapDrag];
        settleCallbacks();
        check(@[@"1:7", @"1:8", @"3:8", @"2:7"]);
        puts("Single Point drag: pending first clicks and stale releases cannot interrupt the selected input");
    }
    return 0;
}
