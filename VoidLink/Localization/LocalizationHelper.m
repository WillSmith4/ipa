//
//  LocalizationHelper.m
//  VoidLink
//
//  Created by True砖家 on 2024/6/30.
//  Copyright © 2024 True砖家 on Bilibili. All rights reserved.
//

#import "LocalizationHelper.h"

@implementation LocalizationHelper

+ (NSString *)localizedTemplateForKey:(NSString *)key {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *localized = [bundle localizedStringForKey:key value:nil table:@"Localizable"];
    if (localized.length > 0 && ![localized isEqualToString:key]) {
        return localized;
    }

    // NSBundle selects a language for the table; it does not fill missing keys
    // from another language. For example, a sparse pl.lproj can otherwise hide
    // the English Enter_PIN_Msg template (including its PIN format argument).
    NSString *developmentLanguage = bundle.developmentLocalization ?: @"en";
    for (NSString *language in @[developmentLanguage, @"en"]) {
        NSString *path = [bundle pathForResource:language ofType:@"lproj"];
        if (path == nil) continue;
        NSBundle *fallbackBundle = [NSBundle bundleWithPath:path];
        NSString *fallback = [fallbackBundle localizedStringForKey:key value:nil table:@"Localizable"];
        if (fallback.length > 0 && ![fallback isEqualToString:key]) {
            return fallback;
        }
    }
    return key;
}

+ (NSString *)localizedStringForKey:(NSString *)key, ... {
    va_list args;
    va_start(args, key);

    NSString *format = [self localizedTemplateForKey:key];
    NSString *result = [[NSString alloc] initWithFormat:format arguments:args];

    va_end(args);
    return result;
}

@end
