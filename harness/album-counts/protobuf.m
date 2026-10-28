// Ad-block's common wire codec: reject overflowing varints without changing valid edit/round-trip behavior.
#import "Shared/AdBlock/Protobuf.h"
static void check(BOOL ok, const char *why) {
    if (!ok) { fprintf(stderr, "FAIL protobuf: %s\n", why); exit(1); }
}
int main(void) {
    @autoreleasepool {
        const uint8_t overflow[11] = {0x08, 0x80,0x80,0x80, 0x80,0x80,0x80, 0x80,0x80,0x80, 0x02};
        check(SGPBParse([NSData dataWithBytes:overflow length:sizeof(overflow)]) == nil, "tenth byte cannot wrap bit 64");
        const uint8_t maximum[] = {0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01};
        NSData *maxData = [NSData dataWithBytes:maximum length:sizeof(maximum)];
        check(SGPBFirst(SGPBParse(maxData), 1).varint == UINT64_MAX, "valid uint64 maximum is unchanged");
        const uint8_t nonminimal[] = {0x08, 0x80, 0x00};
        check(SGPBParse([NSData dataWithBytes:nonminimal length:sizeof(nonminimal)]) != nil, "existing acceptance of redundant zero is unchanged");
        const uint8_t nested[] = {0x0a,0x02,0x08,0x01, 0x12,0x03,'a','d','s', 0x1d,0x11,0x22,0x33,0x44};
        NSData *original = [NSData dataWithBytes:nested length:sizeof(nested)];
        check([SGPBSerialize(SGPBParse(original)) isEqual:original], "unknown bytes and fixed fields round-trip");
        NSData *edited = SGPBEdit(original, @[@1], ^NSData *(NSData *inner) {
            return SGPBSerialize(@[SGPBVarint(1, 0)]);
        });
        const uint8_t expected[] = {0x0a,0x02,0x08,0x00, 0x12,0x03,'a','d','s', 0x1d,0x11,0x22,0x33,0x44};
        check([edited isEqual:[NSData dataWithBytes:expected length:sizeof(expected)]], "nested ad-block edit preserves unrelated fields");
        puts("ad-block protobuf: 5 checks passed");
    }
    return 0;
}
