#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <Limelight.h>

// Compile NativeTouchHandler's actual send method against a recording transport.
// UIKit supplies only sample data here; event routing/pressure logic is production code.
enum { UITouchTypeDirect, UITouchTypeIndirect, UITouchTypePencil };
@interface UITouch : NSObject
@property NSInteger type;
@property CGFloat force, maximumPossibleForce, altitudeAngle;
@property CGPoint point;
@property uint8_t pointerId;
- (CGPoint)locationInView:(id)view;
- (CGFloat)azimuthAngleInView:(id)view;
@end
@implementation UITouch
- (CGPoint)locationInView:(id)view { return self.point; }
- (CGFloat)azimuthAngleInView:(id)view { return 1.0; }
@end

@interface UIEvent : NSObject
@property NSUInteger touchCount;
@end
@implementation UIEvent
@end
@interface UITouchUtil : NSObject
+ (NSArray *)touchesIn:(id)view from:(UIEvent *)event;
@end
@implementation UITouchUtil
+ (NSArray *)touchesIn:(id)view from:(UIEvent *)event {
    return event.touchCount == 2 ? @[@1, @2] : @[@1];
}
@end

static BOOL pencilPauses, pencilDrawing;
@interface PencilHandler : NSObject
+ (BOOL)pencilPausesNativeTouch;
+ (BOOL)isDrawing;
@end
@implementation PencilHandler
+ (BOOL)pencilPausesNativeTouch { return pencilPauses; }
+ (BOOL)isDrawing { return pencilDrawing; }
@end

@interface NativeTouchPointer : NSObject
@property BOOL needResetCoords;
@end
@implementation NativeTouchPointer
@end

typedef struct {
    uint8_t type;
    uint32_t pointerId;
    float x, y, pressure, major, minor;
    uint16_t rotation;
} RecordedTouch;
static RecordedTouch output[32];
static NSUInteger outputCount;
int LiSendTouchEvent(uint8_t type, uint32_t pointerId, float x, float y, float pressure,
                     float major, float minor, uint16_t rotation) {
    NSCAssert(outputCount < 32, @"Unexpected event count");
    output[outputCount++] = (RecordedTouch){type, pointerId, x, y, pressure, major, minor, rotation};
    return 0;
}

@interface NativeTouchHarness : NSObject {
    id streamView;
    BOOL activateCoordSelector;
    NSMutableSet *blacklistedTouches;
}
@property BOOL singleTouchDisabled;
@property NativeTouchPointer *pointer;
- (void)sendTouchEvent:(UITouch *)touch withTouchtype:(uint8_t)type withEvent:(UIEvent *)event;
@end
@implementation NativeTouchHarness
@synthesize singleTouchDisabled;
- (instancetype)init {
    if ((self = [super init])) {
        blacklistedTouches = [NSMutableSet set];
        _pointer = [NativeTouchPointer new];
    }
    return self;
}
- (CGPoint)selectCoordsFor:(UITouch *)touch { return touch.point; }
- (CGPoint)adjustCoordinatesForVideoArea:(CGPoint)point { return point; }
- (CGSize)getVideoAreaSize { return CGSizeMake(1000, 500); }
- (uint8_t)retrievePointerIdFromDict:(UITouch *)touch { return touch.pointerId; }
- (NativeTouchPointer *)getPointerObjFromDict:(UITouch *)touch { return self.pointer; }
- (uint16_t)getRotationFromAzimuthAngle:(float)angle { return 123; }
#include "NativeTouchSendMethod.inc"
@end

static void checkEvent(NSUInteger index, uint8_t type, uint32_t pointerId, float pressure) {
    NSCAssert(index < outputCount, @"Missing touch event");
    RecordedTouch event = output[index];
    NSCAssert(event.type == type && event.pointerId == pointerId, @"Type/pointer identity changed");
    NSCAssert(isfinite(event.pressure) && fabsf(event.pressure - pressure) < 0.00001f,
              @"Pressure was %f, expected %f", event.pressure, pressure);
    NSCAssert(event.major == 0 && event.minor == 0, @"Contact area changed");
}

int main(void) {
    @autoreleasepool {
        NativeTouchHarness *handler = [NativeTouchHarness new];
        UIEvent *event = [UIEvent new];
        event.touchCount = 1;
        UITouch *touch = [UITouch new];
        touch.type = UITouchTypeDirect;
        touch.point = CGPointMake(250, 250);
        touch.altitudeAngle = M_PI_2;
        // Devices without pressure, invalid force samples, and real force values.
        const float samples[][3] = {{0, 1, .5}, {0, 0, .5}, {NAN, 1, .5},
            {1, 0, .5}, {-1, 1, .5}, {.2, 1, .2}, {2, 1, 1}};
        for (NSUInteger i = 0; i < sizeof(samples)/sizeof(samples[0]); i++) {
            touch.force = samples[i][0];
            touch.maximumPossibleForce = samples[i][1];
            outputCount = 0;
            [handler sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_DOWN withEvent:event];
            [handler sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_MOVE withEvent:event];
            [handler sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_UP withEvent:event];
            NSCAssert(outputCount == 3, @"A contact must retain DOWN/MOVE/UP order");
            checkEvent(0, LI_TOUCH_EVENT_DOWN, 0, samples[i][2]);
            checkEvent(1, LI_TOUCH_EVENT_MOVE, 0, samples[i][2]);
            checkEvent(2, LI_TOUCH_EVENT_UP, 0, 0);
            for (NSUInteger j = 0; j < outputCount; j++) {
                NSCAssert(output[j].x == .25f && output[j].y == .5f && output[j].rotation == 123,
                          @"Pressure correction must not change coordinates or rotation");
            }
        }
        touch.force = 0;
        touch.maximumPossibleForce = 1;
        touch.altitudeAngle = 0; // no usable altitude/force information for a finger
        outputCount = 0;
        [handler sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_MOVE withEvent:event];
        checkEvent(0, LI_TOUCH_EVENT_MOVE, 0, .5f);
        touch.altitudeAngle = M_PI_2;

        // Every active finger carries positive contact pressure independently.
        outputCount = 0;
        for (uint8_t pointerId = 0; pointerId <= 10; pointerId++) {
            touch.pointerId = pointerId;
            [handler sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_DOWN withEvent:event];
            checkEvent(pointerId, LI_TOUCH_EVENT_DOWN, pointerId, .5f);
        }

        // The relative native-pointer boundary reset includes a new DOWN.
        handler.pointer.needResetCoords = YES;
        touch.pointerId = 4;
        outputCount = 0;
        [handler sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_MOVE withEvent:event];
        NSCAssert(outputCount == 2, @"Keep the native pointer reset sequence");
        checkEvent(0, LI_TOUCH_EVENT_UP, 4, 0);
        checkEvent(1, LI_TOUCH_EVENT_DOWN, 4, .5f);
        NSCAssert(output[1].x == .3f && output[1].y == .4f, @"Reset coordinates changed");
        outputCount = 0;
        [handler sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_UP withEvent:event];
        NSCAssert(outputCount == 1, @"Lifting at the boundary must not synthesize another contact");
        checkEvent(0, LI_TOUCH_EVENT_UP, 4, 0);
        handler.pointer.needResetCoords = NO;
        for (NSNumber *type in @[@(LI_TOUCH_EVENT_HOVER), @(LI_TOUCH_EVENT_CANCEL), @(LI_TOUCH_EVENT_CANCEL_ALL)]) {
            outputCount = 0;
            [handler sendTouchEvent:touch withTouchtype:type.unsignedCharValue withEvent:event];
            checkEvent(0, type.unsignedCharValue, 4, 0);
        }

        // Do not replace pencil/indirect pressure, including a genuine zero.
        for (NSNumber *type in @[@(UITouchTypePencil), @(UITouchTypeIndirect)]) {
            touch.type = type.integerValue;
            touch.force = .4;
            touch.maximumPossibleForce = 2;
            touch.altitudeAngle = M_PI / 6;
            outputCount = 0;
            [handler sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_MOVE withEvent:event];
            checkEvent(0, LI_TOUCH_EVENT_MOVE, 4, .4f);
            touch.force = 0;
            [handler sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_DOWN withEvent:event];
            checkEvent(1, LI_TOUCH_EVENT_DOWN, 4, 0);
        }
        touch.type = UITouchTypeDirect;
        handler.singleTouchDisabled = YES;
        outputCount = 0;
        [handler sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_DOWN withEvent:event];
        NSCAssert(outputCount == 0, @"Existing disabled single-touch filter must remain effective");
        [handler sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_UP withEvent:event];
        checkEvent(0, LI_TOUCH_EVENT_UP, 4, 0);
        handler.singleTouchDisabled = NO;
        pencilPauses = pencilDrawing = YES;
        outputCount = 0;
        [handler sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_MOVE withEvent:event];
        NSCAssert(outputCount == 0, @"Existing Pencil pause filter must remain effective");
        [handler sendTouchEvent:touch withTouchtype:LI_TOUCH_EVENT_UP withEvent:event];
        checkEvent(0, LI_TOUCH_EVENT_UP, 4, 0);
        puts("Native Touch pressure: finger contacts, multitouch, release, boundary reset and Pencil isolation passed");
    }
    return 0;
}
