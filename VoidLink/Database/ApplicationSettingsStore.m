#import "ApplicationSettingsStore.h"
#include <math.h>

@implementation ApplicationSettingsStore {
    NSUserDefaults *_defaults;
    NSString *_key;
    NSString *_sessionIdentifier;
    NSMutableDictionary *_settings;
    NSMutableDictionary *_profile;
    BOOL _inheritsDefaults;
}

+ (instancetype)shared {
    static ApplicationSettingsStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [[self alloc] initWithDefaults:NSUserDefaults.standardUserDefaults]; });
    return store;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) _defaults = defaults;
    return self;
}

+ (NSArray<NSString *> *)settingsKeys {
    // Only settings editable in the streaming sidebar; connection-only options
    // (codec, HDR, pacing, renderer, etc.) always come from global settings.
    return @[@"width", @"height", @"resolutionSelected", @"framerate", @"bitrate",
        @"interpolationMaximumDimension", @"interpolationMaximumPixelCount",
        @"touchMode", @"pointerVelocityModeDivider", @"touchPointerVelocityFactor",
        @"mousePointerVelocityFactor", @"delayLeftClick", @"localStreamPanEnabled",
        @"localStreamZoomEnabled", @"longPressAction", @"doubleTapDragAction",
        @"passthroughGestures", @"ctrlDownForPinch", @"pinchSensitivity",
        @"swipeAction", @"pinchInAction", @"pinchOutAction", @"rotationAction",
        @"rotationSensitivity", @"onscreenControls", @"buttonVisualFeedback", @"touchPointTracking",
        @"enableControllerNavigation", @"streamingRadialMenuDelay", @"streamingRadialMenuButton",
        @"customStreamingRadialMenuButtonPosition", @"controllerMouseStick",
        @"controllerMouseLeftButton", @"controllerMouseRightButton",
        @"controllerMousePointerVelocity", @"controllerMouseExpo", @"swapABXYButtons",
        @"hapticEngine", @"gyroMode", @"gyroSensitivity", @"pencilTickMode",
        @"pencilTickIntervalUs", @"pencilTipOffsetX", @"pencilTipOffsetY",
        @"keyboardToggleFingers", @"slideToSettingsScreenEdge", @"slideToSettingsDistance",
        @"edgeSlidingSensitivity", @"localMousePointerMode", @"reverseMouseWheelDirection",
        @"globeAsEscape", @"localVolume", @"redirectMic", @"micVolume", @"muteInBackground",
        @"audioConfig", @"statsOverlayLevel", @"statsOverlayEnabled",
        @"backgroundSessionTimer", @"appTheme", @"showKeyboardToolbar", @"softKeyboardHeight",
        @"relativeTouchSlideThreshold", @"singleTapSensitivity", @"leftClickDelayMs", @"enableGraphs"];
}

+ (NSArray<NSString *> *)profileKeys {
    return @[@"touchMode", @"pointerVelocityModeDivider", @"touchPointerVelocityFactor",
        @"dualSenseTransient", @"physicalLeftStickMinOffset", @"physicalRightStickMinOffset",
        @"controllerGyroSwitchMode", @"controllerGyroSwitchHold", @"controllerGyroSwitchToggle",
        @"reverseGyroHoldButton", @"useBuiltinGyro", @"swapYawAndRoll", @"mapGyroTo",
        @"yawPitchToRightStick", @"rollToLeftStick", @"gyroSensitivityYaw", @"gyroSensitivityPitch",
        @"gyroSensitivityRoll", @"gyroToStickMinOffset", @"synthesizePhysicalStick",
        @"pressureCurveEnabled", @"pressureCurvePoints", @"phase1StrokeSampleIndexEnd",
        @"strokeEqualizationStrength", @"doubleTapShorcutEnabled", @"brushShortcut",
        @"eraserShortcut", @"squeezeShorcutEnabled", @"squeezeStartShortcut", @"squeezeEndShortcut",
        @"pencilAndHoverMode", @"pencilPausesNativeTouch", @"disablePencilSlideGestures"];
}

static NSDictionary *FilteredValues(NSDictionary *values, NSArray *keys) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        id value = values[key];
        if ([value isKindOfClass:NSString.class] ||
            ([value isKindOfClass:NSNumber.class] && isfinite([value doubleValue])) ||
            ([value isKindOfClass:NSArray.class] &&
             [NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListBinaryFormat_v1_0])) {
            result[key] = value;
        }
    }
    return result;
}

- (NSString *)sessionIdentifier { @synchronized (self) { return _sessionIdentifier; } }
- (BOOL)active { return self.sessionIdentifier != nil; }

- (void)beginWithHostUUID:(NSString *)hostUUID appID:(NSString *)appID {
    @synchronized (self) {
        [self endSession];
        NSString *host = [[hostUUID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
        NSString *app = [appID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!host.length || !app.length) return;
        _key = [NSString stringWithFormat:@"voidlink.appSettings.v1.%@.%@",
                [[host dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0],
                [[app dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0]];
        NSDictionary *record = [_defaults dictionaryForKey:_key];
        _settings = [FilteredValues([record[@"settings"] isKindOfClass:NSDictionary.class] ? record[@"settings"] : @{}, self.class.settingsKeys) mutableCopy];
        _profile = [FilteredValues([record[@"profile"] isKindOfClass:NSDictionary.class] ? record[@"profile"] : @{}, self.class.profileKeys) mutableCopy];
        _sessionIdentifier = NSUUID.UUID.UUIDString;
    }
}

- (void)endSession {
    @synchronized (self) {
        _key = nil;
        _sessionIdentifier = nil;
        _settings = nil;
        _profile = nil;
        _inheritsDefaults = NO;
    }
}

- (NSDictionary *)valuesForDomain:(NSString *)domain defaults:(NSDictionary *)defaults {
    @synchronized (self) {
        NSMutableDictionary *result = [defaults mutableCopy];
        NSDictionary *overrides = [domain isEqualToString:@"profile"] ? _profile : _settings;
        for (NSString *key in overrides) {
            id value = overrides[key], fallback = defaults[key];
            // Ignore malformed or obsolete stored values instead of sending them to KVC.
            if (([fallback isKindOfClass:NSNumber.class] && [value isKindOfClass:NSNumber.class]) ||
                ([fallback isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class]) ||
                ([fallback isKindOfClass:NSArray.class] && [value isKindOfClass:NSArray.class])) result[key] = value;
        }
        return result;
    }
}

- (void)stageValues:(NSDictionary *)values previousValues:(NSDictionary *)previous
            domain:(NSString *)domain sessionIdentifier:(NSString *)identifier {
    @synchronized (self) {
        if (!identifier || ![_sessionIdentifier isEqualToString:identifier]) return;
        BOOL profile = [domain isEqualToString:@"profile"];
        NSDictionary *filtered = FilteredValues(values, profile ? self.class.profileKeys : self.class.settingsKeys);
        NSMutableDictionary *draft = profile ? _profile : _settings;
        for (NSString *key in filtered) {
            if (![filtered[key] isEqual:previous[key]]) {
                draft[key] = filtered[key];
                _inheritsDefaults = NO;
            }
        }
    }
}

- (void)commitWithSettings:(NSDictionary *)settings profile:(NSDictionary *)profile {
    @synchronized (self) {
        if (!_key) return;
        if (_inheritsDefaults) {
            [_defaults removeObjectForKey:_key];
            return;
        }
        _settings = [FilteredValues(settings, self.class.settingsKeys) mutableCopy];
        _profile = [FilteredValues(profile, self.class.profileKeys) mutableCopy];
        [_defaults setObject:@{@"settings": _settings, @"profile": _profile} forKey:_key];
    }
}

- (void)restoreDefaults {
    @synchronized (self) {
        if (!_key) return;
        [_settings removeAllObjects];
        [_profile removeAllObjects];
        [_defaults removeObjectForKey:_key];
        _inheritsDefaults = YES;
        // Invalidate edits captured before the reset, including auxiliary editors.
        _sessionIdentifier = NSUUID.UUID.UUIDString;
    }
}

+ (BOOL)requiresReconnectFrom:(NSDictionary *)previous to:(NSDictionary *)updated {
    for (NSString *key in @[@"width", @"height", @"framerate"]) {
        if ([previous[key] integerValue] != [updated[key] integerValue]) return YES;
    }
    return NO;
}
@end
