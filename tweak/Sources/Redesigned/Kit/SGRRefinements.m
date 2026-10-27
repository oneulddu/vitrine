// The decisions of SGRRefinements.h, Foundation only.
#import "SGRRefinements.h"

const NSTimeInterval SGRDigitsSettleInterval = 0.15;

#pragma mark - rolling time digits

SGRDigitsChange SGRDigitsChangeFor(NSString *before, NSString *after, BOOL attached, NSTimeInterval sinceLast, BOOL reduceMotion) {
    if ([before isEqualToString:after] || (!before.length && !after.length)) return SGRDigitsChangeNone;
    if (!before.length || !after.length || !attached) return SGRDigitsChangeJump;
    if (sinceLast >= 0 && sinceLast < SGRDigitsSettleInterval) return SGRDigitsChangeJump;
    return reduceMotion ? SGRDigitsChangeFade : SGRDigitsChangeRoll;
}

NSIndexSet *SGRDigitsRolled(NSString *before, NSString *after) {
    if (before.length != after.length) return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, after.length)];
    NSMutableIndexSet *rolled = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < after.length; i++) {
        if ([before characterAtIndex:i] != [after characterAtIndex:i]) [rolled addIndex:i];
    }
    return rolled;
}

#pragma mark - the add button's glyph

SGRAddGlyph SGRAddGlyphFor(BOOL saved, BOOL enabled, BOOL inPlayer, BOOL starOn, BOOL plainCheckOn) {
    if (inPlayer && starOn) {
        if (!enabled) return SGRAddGlyphSpotify;
        return saved ? SGRAddGlyphStarFilled : SGRAddGlyphStarOutline;
    }
    return saved && plainCheckOn ? SGRAddGlyphPlainCheck : SGRAddGlyphSpotify;
}
