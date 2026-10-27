#import "../album-notes/catalog-boundary.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/AnimatedArtwork/SGMotionCatalog.h"
#import "Shared/AnimatedArtwork/SGMotionClip.h"

int main(int argc, const char **argv) {
    @autoreleasepool {
        CHECK(argc == 2);
        CatalogStart(@(argv[1]));
        // Device facts: 145 releases across three pages. Fillers are synthetic;
        // the two matching titles remain the named fixture facts, not live data.
        NSMutableDictionary *expanded = [CatalogFixture mutableCopy];
        NSMutableDictionary *pages = [expanded[@"artistAlbumPages"] mutableCopy];
        NSMutableArray *second = [pages[@"479756766"][@"25"][@"data"] mutableCopy];
        [second addObject:@{@"attributes": @{@"name": @"Starboy"}}];
        for (NSUInteger index = 3; index < 100; index++)
            [second addObject:@{@"attributes": @{@"name": [NSString stringWithFormat:@"Fixture second %lu", (unsigned long)index]}}];
        NSMutableArray *third = [NSMutableArray array];
        for (NSUInteger index = 0; index < 20; index++)
            [third addObject:@{@"attributes": @{@"name": [NSString stringWithFormat:@"Fixture third %lu", (unsigned long)index]}}];
        pages[@"479756766"] = @{
            @"25": @{@"data": second, @"next": @"/v1/catalog/us/artists/479756766/albums?offset=125"},
            @"125": @{@"data": third}};
        expanded[@"artistAlbumPages"] = pages;
        CatalogFixture = expanded;
        NSMutableArray *records = [NSMutableArray array];
        for (NSDictionary *record in CatalogFixture[@"results"][@"artists"][@"data"]) {
            NSMutableDictionary *joined = [record mutableCopy];
            joined[@"relationships"] = @{@"albums": CatalogFixture[@"artistAlbums"][record[@"id"]]};
            [records addObject:joined];
        }
        CHECK([SGMotionArtistMatch(records, @"Fixture Echo", @[@"Signals", @"Quiet"])[@"id"] isEqual:@"echo-right"]);
        CHECK(SGMotionArtistMatch(records, @"Fixture Echo", @[@"Signals"]) == nil);
        CHECK(SGMotionArtistMatch(records, @"Fixture Echo", @[@"Signals", @"Signals"]) == nil);
        CHECK(SGMotionArtistMatch(records, @"Unknown", @[@"Signals", @"Quiet"]) == nil);
        NSMutableDictionary *tie = [records[0] mutableCopy];
        tie[@"relationships"] = records[1][@"relationships"];
        CHECK(SGMotionArtistMatch(@[tie, records[1]], @"Fixture Echo", @[@"Signals", @"Quiet"]) == nil);
        NSDictionary *folded = @{@"id": @"folded", @"attributes": @{@"name": @"\u200eＴｈｅ Ｗｅｅｋｎｄ\u200e"},
            @"relationships": @{@"albums": @{@"data": @[
                @{@"attributes": @{@"name": @"After Hours (Deluxe)"}},
                @{@"attributes": @{@"name": @"Out Of Time - EP"}}]}}};
        CHECK([SGMotionArtistMatch(@[folded], @"The Weeknd", @[@"AFTER HOURS", @"Out Of Time feat. Tomoko Aran"])[@"id"] isEqual:@"folded"]);
        NSDictionary *withTitles = @{@"id": @"namesake", @"attributes": @{@"name": @"Same Name"},
            @"relationships": @{@"albums": @{@"data": @[
                @{@"attributes": @{@"name": @"Anchor"}},
                @{@"attributes": @{@"name": @"Stay"}},
                @{@"attributes": @{@"name": @"Run"}}]}}};
        CHECK(SGMotionArtistMatch(@[withTitles], @"Same Name", @[@"Anchor", @"Stay with Me"]) == nil);
        CHECK(SGMotionArtistMatch(@[withTitles], @"Same Name", @[@"Anchor", @"Run with Me"]) == nil);
        for (NSString *credit in @[@"Stay (with Guest)", @"Stay [with Guest]", @"Stay (feat. Guest)",
            @"Stay [feat. Guest]", @"Stay (ft. Guest)", @"Stay [ft. Guest]", @"Stay feat. Guest", @"Stay ft. Guest"])
            CHECK([SGMotionArtistMatch(@[withTitles], @"Same Name", @[@"Anchor", credit])[@"id"] isEqual:@"namesake"]);
        CHECK(SGMotionArtistMatch(@[withTitles], @"Same Name", @[@"Anchor", @"Stay (with Guest"]) == nil);

        __block NSUInteger done = 0;
        SGMotionArtistArtwork(@"Fixture Echo", @[@"Signals", @"Quiet"], 720, YES, YES, ^(UIImage *image, NSURL *file, SGMotionArtistArtworkOutcome waiting) {
            CHECK(!waiting);
            CHECK(image.size.width == 1 && [file.path isEqual:@"/fixture/clip.mp4"]); done++;
        });
        SGMotionArtistLogo(@"Fixture Echo", 720, ^(UIImage *logo) { done++; });
        CatalogWait(^BOOL { return done == 2; });
        CHECK(CatalogSearches == 1 && CatalogAlbumRequests == 2 && CatalogDownloads == 1);
        CHECK([CatalogAssetPaths containsObject:@"/right-720x720.png"]);
        CHECK([CatalogAssetPaths containsObject:@"/right/master.m3u8"]);
        CHECK(![CatalogAssetPaths containsObject:@"/wrong/master.m3u8"]);
        NSUInteger media = CatalogMediaRequests;
        SGMotionArtistArtwork(@"Fixture Echo", @[@"Signals"], 720, YES, YES, ^(UIImage *image, NSURL *file, SGMotionArtistArtworkOutcome waiting) {
            CHECK(waiting);
            CHECK(image == nil && file == nil); done++;
        });
        CHECK(done == 3 && CatalogMediaRequests == media);
        CatalogLowData = YES;
        SGMotionArtistArtwork(@"Fixture Still", @[@"First", @"Second"], 720, YES, YES, ^(UIImage *image, NSURL *file, SGMotionArtistArtworkOutcome waiting) {
            CHECK(!waiting);
            CHECK(image.size.width == 1 && file == nil); done++;
        });
        CatalogWait(^BOOL { return done == 4; });
        CHECK(CatalogSearches == 2 && CatalogAlbumRequests == 3 && CatalogDownloads == 1);
        CHECK(CatalogArtistRequests == 2);
        SGMotionArtistArtwork(@"The Weeknd", @[@"After Hours", @"Unmatched"], 720, YES, YES,
            ^(UIImage *image, NSURL *file, SGMotionArtistArtworkOutcome waiting) { CHECK(waiting == SGMotionArtistArtworkNeedsEvidence && !image && !file); done++; });
        CatalogWait(^BOOL { return done == 5; });
        CHECK(CatalogAlbumRequests == 8 && CatalogArtistRequests == 2);
        SGMotionArtistArtwork(@"The Weeknd", @[@"After Hours", @"Out Of Time with Tomoko Aran", @"Starboy"], 720, YES, YES,
            ^(UIImage *image, NSURL *file, SGMotionArtistArtworkOutcome waiting) {
                CHECK(!waiting && image.size.width == 1 && [file.path isEqual:@"/fixture/clip.mp4"]); done++;
            });
        CatalogWait(^BOOL { return done == 6; });
        CHECK(CatalogSearches == 3 && CatalogAlbumRequests == 8 && CatalogArtistRequests == 3);
        CHECK([CatalogAssetPaths containsObject:@"/weeknd/master.m3u8"]);
        CHECK([CatalogAssetPaths containsObject:@"/weeknd-720x720.png"]);
        SGMotionArtistArtwork(@"The Weeknd", @[@"After Hours", @"Out Of Time"], 720, NO, YES,
            ^(UIImage *image, NSURL *file, SGMotionArtistArtworkOutcome waiting) { CHECK(!waiting && file); done++; });
        CatalogWait(^BOOL { return done == 7; });
        CHECK(CatalogSearches == 3 && CatalogAlbumRequests == 8 && CatalogArtistRequests == 3);
        SGMotionArtistArtwork(@"Budget Artist", @[@"First", @"Second"], 720, YES, YES,
            ^(UIImage *image, NSURL *file, SGMotionArtistArtworkOutcome waiting) { CHECK(waiting == SGMotionArtistArtworkMetadataFailed && !image && !file); done++; });
        CatalogWait(^BOOL { return done == 8; });
        CHECK(CatalogAlbumRequests == 11 && CatalogArtistRequests == 3);
        SGMotionArtistArtwork(@"Failure Artist", @[@"First", @"Second"], 720, NO, YES,
            ^(UIImage *image, NSURL *file, SGMotionArtistArtworkOutcome outcome) {
                CHECK(outcome == SGMotionArtistArtworkMetadataFailed && !file); done++;
            });
        CatalogWait(^BOOL { return done == 9; });
        CHECK(CatalogAlbumRequests == 13 && CatalogArtistRequests == 3);
        // A new page can retry the failed exact namesake. The successful main
        // candidate remains cached; its releases need no second request.
        NSMutableDictionary *recovered = [CatalogFixture mutableCopy];
        NSMutableDictionary *statuses = [recovered[@"artistAlbumStatuses"] mutableCopy];
        statuses[@"retry-error"] = @404;
        statuses[@"nonexact-error"] = @200;
        recovered[@"artistAlbumStatuses"] = statuses;
        CatalogFixture = recovered;
        SGMotionArtistArtwork(@"Failure Artist", @[@"First", @"Second"], 720, NO, YES,
            ^(UIImage *image, NSURL *file, SGMotionArtistArtworkOutcome outcome) {
                CHECK(outcome == SGMotionArtistArtworkFinished && file); done++;
            });
        CatalogWait(^BOOL { return done == 10; });
        CHECK(CatalogAlbumRequests == 14 && CatalogArtistRequests == 4);
        SGMotionArtistArtwork(@"The Weeknd Tribute", @[@"First", @"Second"], 720, NO, YES,
            ^(UIImage *image, NSURL *file, SGMotionArtistArtworkOutcome outcome) {
                CHECK(outcome == SGMotionArtistArtworkNeedsEvidence && !file); done++;
            });
        CatalogWait(^BOOL { return done == 11; });
        CHECK(CatalogAlbumRequests == 15 && CatalogArtistRequests == 4);
        puts("artist artwork: 145-release match + 404/empty namesakes succeeds; non-exact failure excluded; exact network failure blocks and retries only its uncached lookup on a new page");
        puts("artist artwork: Weeknd namesake marks, credits/suffixes, 25-release pagination, resource-only motion, cached re-match and 3-page budget passed");
        CHECK(SGMotionHeaderMayPlay(YES, YES, NO, NO, YES));
        CHECK(!SGMotionHeaderMayPlay(YES, YES, YES, NO, YES));
        CHECK(!SGMotionHeaderMayPlay(YES, YES, NO, YES, YES));
        CHECK(!SGMotionHeaderMayPlay(NO, YES, NO, NO, YES));
        CHECK(!SGMotionHeaderMayPlay(YES, NO, NO, NO, YES));
        CHECK(!SGMotionHeaderMayPlay(YES, YES, NO, NO, NO));
        CatalogFinish();
        puts("artist artwork: namesakes, insufficient/tied evidence, motion/still independence, shared logo query, Low Data requests and playback gates passed");
    }
    return 0;
}
