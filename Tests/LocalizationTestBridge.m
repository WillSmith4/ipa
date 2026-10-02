#import "LocalizationTestBridge.h"

NSString *TestObjectiveCPINMessage(void) {
    return [LocalizationHelper localizedStringForKey:@"Enter_PIN_Msg", @"0123"];
}
