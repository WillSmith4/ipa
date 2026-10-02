//
//  LocalizationHelper.h
//  VoidLink
//
//  Created by True砖家 on 2024/6/30.
//  Copyright © 2024 True砖家 on Bilibili. All rights reserved.
//

#ifndef LocalizationHelper_h
#define LocalizationHelper_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LocalizationHelper : NSObject

// Resolve a template before formatting. Partial translations fall back per key
// to the development language, then English, then the readable source string.
+ (NSString *)localizedTemplateForKey:(NSString *)key
    NS_SWIFT_NAME(localizedTemplate(forKey:));

// Method to get localized string with format arguments
+ (NSString *)localizedStringForKey:(NSString *)key, ... NS_FORMAT_FUNCTION(1,2);

@end

NS_ASSUME_NONNULL_END

#endif /* LocalizationHelper_h */
