// The list rules of either look's recent accent colors (Native/Appearance/AccentHistory.m,
// Redesigned/Kit/SGRAccentHistory.m) and where album play counts show (Redesigned/Album/AlbumPlaysPlace.m),
// including the old switch it replaces. Plain Foundation; the settings are set in a volatile argument domain, so
// nothing is written to disk.
#import "Native/Appearance/Appearance.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Album/Album.h"
#import "Core/SGPrefs.h"
#import "../harness-fail.h"

static NSUInteger sg_checks;

static void expectList(NSArray<NSNumber *> *got, NSArray<NSNumber *> *want, NSString *what) {
    sg_checks++;
    if (![got isEqualToArray:want]) HARNESS_FAIL(@"%@: got %@, want %@", what, got, want);
}

// The recent-color rules shared by both looks, against either look's functions; `own` is the look's default.
static void checkRecents(NSString *look, NSArray<NSNumber *> *(*from)(id), NSArray<NSNumber *> *(*adding)(NSArray<NSNumber *> *, NSInteger, NSInteger),
                         NSInteger own) {
    NSString *(^name)(NSString *) = ^NSString *(NSString *what) { return [NSString stringWithFormat:@"%@ %@", look, what]; };
    expectList(from(nil), @[], name(@"nothing stored"));
    expectList(from(@"#123456"), @[], name(@"not a list"));
    expectList(from(@[@0x123456, @"#ABCDEF", @YES, @1.5, @(-1), @0x1000000, @(own), @{}, @0x123456, @0xABCDEF]),
               @[@0x123456, @0xABCDEF], name(@"invalid, default and repeated entries ignored"));
    expectList(from(@[@1, @2, @3, @4, @5, @6, @7, @8, @9, @10]), @[@1, @2, @3, @4, @5, @6, @7, @8], name(@"at most 8 read"));

    expectList(adding(@[], 0x112233, own), @[@0x112233], name(@"first color"));
    expectList(adding(@[@0xA, @0xB], 0xC, 0xA), @[@0xC, @0xA, @0xB], name(@"new color first"));
    expectList(adding(@[@0xA, @0xB, @0xC], 0xC, 0xA), @[@0xC, @0xA, @0xB], name(@"listed color moved to the front, not repeated"));
    expectList(adding(@[@1, @2, @3, @4, @5, @6, @7, @8], 9, 1), @[@9, @1, @2, @3, @4, @5, @6, @7], name(@"9th drops the oldest"));
    expectList(adding(@[@0xA, @0xB], 0xB, 0xB), @[@0xA, @0xB], name(@"the current color again changes nothing"));
    expectList(adding(@[@0xA], own, 0xA), @[@0xA], name(@"default not saved"));
    expectList(adding(@[@0xA], -1, 0xA), @[@0xA], name(@"negative not saved"));
    expectList(adding(@[@0xA], 0x1000000, 0xA), @[@0xA], name(@"out of range not saved"));
}

// The defaults as an import or a past version left them: only these keys, in the argument domain.
static void setStored(NSDictionary<NSString *, id> *values) {
    [NSUserDefaults.standardUserDefaults setVolatileDomain:values forName:NSArgumentDomain];
    SGPrefsChanged();
}

static void expectPlace(NSDictionary<NSString *, id> *stored, SGRAlbumPlayCountsPlace want, NSString *what) {
    setStored(stored);
    sg_checks++;
    SGRAlbumPlayCountsPlace got = SGRAlbumPlayCountsWhere();
    if (got != want) HARNESS_FAIL(@"play counts %@: got %ld, want %ld", what, (long)got, (long)want);
}

int main(void) {
    @autoreleasepool {
        checkRecents(@"native", SGAccentRecentFrom, SGAccentRecentAdding, 0x1ED760);
        checkRecents(@"redesign", SGRAccentRecentFrom, SGRAccentRecentAdding, 0x37F200);
        // The redesign also leaves out Spotify's green, its Spotify preset.
        expectList(SGRAccentRecentFrom(@[@0x1ED760, @0x37F200, @0xFA2D48]), @[@0xFA2D48], @"redesign: both greens ignored");
        expectList(SGRAccentRecentAdding(@[], 0x1ED760, 0x37F200), @[], @"redesign: Spotify's green not saved");
        // The native look's history is its own: the redesign's default is an ordinary color there.
        expectList(SGAccentRecentAdding(@[], 0x37F200, 0x1ED760), @[@0x37F200], @"native: the redesign's green is a color");

        NSString *old = @"spotifyglass.redesign.album.playCounts", *place = @"spotifyglass.redesign.album.playCounts.place";
        expectPlace(@{}, SGRAlbumPlayCountsInRow, @"nothing stored");
        expectPlace(@{old: @YES}, SGRAlbumPlayCountsInRow, @"old switch on");
        expectPlace(@{old: @NO}, SGRAlbumPlayCountsOff, @"old switch off");
        expectPlace(@{old: @NO, place: @2}, SGRAlbumPlayCountsInMenu, @"choice In menu over old off");
        expectPlace(@{old: @YES, place: @0}, SGRAlbumPlayCountsOff, @"choice Off over old on");
        expectPlace(@{old: @NO, place: @1}, SGRAlbumPlayCountsInRow, @"choice In the row over old off");
        expectPlace(@{old: @NO, place: @7}, SGRAlbumPlayCountsOff, @"invalid choice falls back to old off");
        expectPlace(@{old: @YES, place: @(-1)}, SGRAlbumPlayCountsInRow, @"invalid choice falls back to old on");
        expectPlace(@{@"spotifyglass.stock": @YES}, SGRAlbumPlayCountsOff, @"after a reset, nothing stored is off");
        setStored(@{});
        printf("ui-refinements rules: %lu checks passed\n", (unsigned long)sg_checks);
    }
    return 0;
}
