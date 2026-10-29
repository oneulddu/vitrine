// Exercise the real Logos hook through the builder's input, with a Foundation-only Spotify double.
#import <Foundation/Foundation.h>
#import "AdBlock.h"
#include <stdlib.h>
#include <string.h>

BOOL SGHidden(NSString *key) {
    const char *value = getenv([key isEqualToString:SGKeyHideAds] ? "HIDE_ADS" : "HIDE_UPSELLS");
    return value && strcmp(value, "1") == 0;
}
void SGRequireClasses(NSArray<NSString *> *names) {}
void SGAdBlockCountOne(NSString *label) {}
void SGAdBlockSawOne(NSString *label) {}

@interface HUBViewModelBuilderImplementation : NSObject
@property (nonatomic, copy) NSDictionary *received;
- (void)addJSONDictionary:(NSDictionary *)dictionary;
@end
@implementation HUBViewModelBuilderImplementation
- (void)addJSONDictionary:(NSDictionary *)dictionary { self.received = dictionary; }
@end

static int failures;
static void check(id actual, id expected, NSString *label) {
    BOOL ok = [actual isEqual:expected];
    printf("%s %s\n", ok ? "ok  " : "FAIL", label.UTF8String);
    if (!ok) NSLog(@"got %@; expected %@", actual, expected);
    failures += !ok;
}

int main(void) {
    @autoreleasepool {
        BOOL hideAds = SGHidden(SGKeyHideAds);
        BOOL hideUpsells = SGHidden(SGKeyHideUpsells);
        printf("Hide ads=%d, Hide upsells=%d\n", hideAds, hideUpsells);
        HUBViewModelBuilderImplementation *builder = [HUBViewModelBuilderImplementation new];
        NSDictionary *ordinary = @{@"id": @"playlist", @"title": @"Marquee sponsored promoted favorites"};
        for (NSString *flag in @[@"ad", @"is_ad", @"is_sponsored"]) {
            NSDictionary *ad = @{@"id": @"tile", @"metadata": @{flag: @YES}};
            NSArray *input = @[ordinary, ad];
            NSArray *expected = hideAds ? @[ordinary] : input;
            [builder addJSONDictionary:@{@"body": input, @"overlays": input, @"sections": input, @"header": ad}];
            for (NSString *root in @[@"body", @"overlays", @"sections"]) {
                check(builder.received[root], expected, [NSString stringWithFormat:@"%@ in %@", flag, root]);
            }
            check(builder.received[@"header"] ?: NSNull.null, hideAds ? NSNull.null : ad,
                  [flag stringByAppendingString:@" header"]);
            for (NSString *child in @[@"children", @"rows", @"body"]) {
                [builder addJSONDictionary:@{@"body": @[@{@"id": @"parent", child: input}]}];
                check(builder.received[@"body"], @[@{@"id": @"parent", child: expected}],
                      [NSString stringWithFormat:@"%@ nested %@", flag, child]);
            }
            // Explicit flags share one value contract in each dictionary the hook inspects.
            for (NSString *scope in @[@"metadata", @"custom", @"logging"]) {
                for (id value in @[@NO, @0, @"false", @"0", @"", @"yes", @"2", NSNull.null, @[], @{}]) {
                    NSDictionary *notAd = @{@"id": @"tile", scope: @{flag: value}};
                    [builder addJSONDictionary:@{@"body": @[notAd]}];
                    check(builder.received[@"body"], @[notAd],
                          [NSString stringWithFormat:@"%@.%@ false/unsupported value %@ stays", scope, flag, value]);
                }
                for (id value in @[@YES, @1, @2, @-1, @0.5, @"true", @"1"]) {
                    NSDictionary *flagged = @{@"id": @"tile", scope: @{flag: value}};
                    [builder addJSONDictionary:@{@"body": @[flagged]}];
                    check(builder.received[@"body"], hideAds ? @[] : @[flagged],
                          [NSString stringWithFormat:@"%@.%@ true value %@ obeys Hide ads", scope, flag, value]);
                }
            }
        }
        NSDictionary *textAd = @{@"component": @{@"namespace": @"advertisement", @"name": @"tile"}};
        [builder addJSONDictionary:@{@"body": @[textAd]}];
        check(builder.received[@"body"], hideAds ? @[] : @[textAd], @"textual ad obeys Hide ads");
        NSDictionary *upsell = @{@"component": @{@"namespace": @"premium", @"name": @"banner"}};
        [builder addJSONDictionary:@{@"body": @[upsell]}];
        check(builder.received[@"body"], hideUpsells ? @[] : @[upsell], @"premium banner obeys Hide upsells");
    }
    printf("%d failed\n", failures);
    return failures ? EXIT_FAILURE : EXIT_SUCCESS;
}
