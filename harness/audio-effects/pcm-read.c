#include "Shared/Player/SGPCMRead.h"
#include <stdio.h>

static unsigned failures;
#define CHECK(condition) do { \
    if (!(condition)) { fprintf(stderr, "FAIL: %s\n", #condition); ++failures; } \
} while (0)

int main(void) {
    const int16_t shorts[] = {-32768, -16384, 0, 16384, 32767};
    CHECK(SGPCMReadSample(shorts, 0, 2, false, 0) == -1.0f);
    CHECK(SGPCMReadSample(shorts, 1, 2, false, 0) == -0.5f);
    CHECK(SGPCMReadSample(shorts, 2, 2, false, 0) == 0.0f);
    CHECK(SGPCMReadSample(shorts, 3, 2, false, 0) == 0.5f);
    CHECK(SGPCMReadSample(shorts, 4, 2, false, 0) == 0.999969482421875f);

    const int32_t integers[] = {INT32_MIN, -1073741824, 0, 1073741824, INT32_MAX};
    CHECK(SGPCMReadSample(integers, 0, 4, false, 0) == -1.0f);
    CHECK(SGPCMReadSample(integers, 1, 4, false, 0) == -0.5f);
    CHECK(SGPCMReadSample(integers, 2, 4, false, 0) == 0.0f);
    CHECK(SGPCMReadSample(integers, 3, 4, false, 0) == 0.5f);
    CHECK(SGPCMReadSample(integers, 4, 4, false, 0) == 1.0f);

    const int32_t fixed[] = {-33554432, 8388608, 25165824};
    CHECK(SGPCMReadSample(fixed, 0, 4, false, 24) == -2.0f);
    CHECK(SGPCMReadSample(fixed, 1, 4, false, 24) == 0.5f);
    CHECK(SGPCMReadSample(fixed, 2, 4, false, 24) == 1.5f);
    const float floats[] = {-2.25f, 0.0f, 1.5f};
    CHECK(SGPCMReadSample(floats, 0, 4, true, 0) == -2.25f);
    CHECK(SGPCMReadSample(floats, 1, 4, true, 0) == 0.0f);
    CHECK(SGPCMReadSample(floats, 2, 4, true, 24) == 1.5f);

    float samples[4] = {0};
    struct { AudioBufferList list; AudioBuffer second; } split = {
        {2, {{1, 8, samples}}}, {1, 8, samples + 2}
    };
    CHECK(SGPCMLayoutFits(&split.list, 2, 2, 4, true));
    split.second.mDataByteSize = 12;
    CHECK(!SGPCMLayoutFits(&split.list, 2, 2, 4, true));
    split.second.mDataByteSize = 4;
    CHECK(!SGPCMLayoutFits(&split.list, 2, 2, 4, true));
    split.second.mDataByteSize = 8;
    split.second.mData = NULL;
    CHECK(!SGPCMLayoutFits(&split.list, 2, 2, 4, true));
    split.second.mData = samples + 2;
    CHECK(!SGPCMLayoutFits(&split.list, 2, 1, 4, true));

    AudioBufferList interleaved = {1, {{2, 16, samples}}};
    CHECK(SGPCMLayoutFits(&interleaved, 2, 2, 4, false));
    interleaved.mBuffers[0].mDataByteSize = 20;
    CHECK(!SGPCMLayoutFits(&interleaved, 2, 2, 4, false));
    interleaved.mBuffers[0].mDataByteSize = 16;
    interleaved.mBuffers[0].mNumberChannels = 1;
    CHECK(!SGPCMLayoutFits(&interleaved, 2, 2, 4, false));
    interleaved.mBuffers[0].mDataByteSize = 4;
    CHECK(SGPCMLayoutFits(&interleaved, 2, 1, 2, false));
    CHECK(!SGPCMLayoutFits(&split.list, 2, 2, 4, false));
    printf("PCM reader/layout: %u failures\n", failures);
    return failures ? 1 : 0;
}
