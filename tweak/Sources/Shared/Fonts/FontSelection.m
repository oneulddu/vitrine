#import "Fonts.h"
#import "Core/SGPrefs.h"

NSArray *SGFontSelectionSnapshot(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    // NSNull preserves absent preferences, distinct from explicit values including the default zero.
    return @[[store objectForKey:SGKeyAppFont] ?: NSNull.null,
             [store objectForKey:SGKeyAppFontFamily] ?: NSNull.null,
             [store objectForKey:SGKeyAppFontLibrary] ?: NSNull.null];
}

BOOL SGFontSelectionUnchanged(NSArray *snapshot) {
    return !SGRestartPending() && [snapshot isEqual:SGFontSelectionSnapshot()];
}
