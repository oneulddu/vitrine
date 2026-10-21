#pragma once
#import <Foundation/Foundation.h>

// Reuse Vitrine's language, resources and checked English fallback.
// The key is stable; only the displayed value is translated.
NSString *SAPL(NSString *key,NSString *english) NS_FORMAT_ARGUMENT(2);
