#pragma once
#include <CoreAudio/CoreAudioTypes.h>
#include <stdbool.h>
#include <stdint.h>

// Shared PCM reads; callers own format validation and render admission.
static inline float SGPCMReadSample(const void *data, UInt32 index, UInt32 bytes, bool isFloat, UInt32 fraction) {
    if (bytes == 4) {
        if (isFloat) return ((const float *)data)[index];
        int32_t value = ((const int32_t *)data)[index];
        return fraction ? (float)((double)value / (double)(1u << fraction)) : (float)(value / 2147483648.0);
    }
    return ((const int16_t *)data)[index] / 32768.0f;
}

// Exact-sized buffers only. SpeedPitch's larger-buffer validation stays separate.
static inline bool SGPCMLayoutFits(const AudioBufferList *data, UInt32 frames, UInt32 channels, UInt32 bytes, bool split) {
    bool fits = split ? data->mNumberBuffers == channels : data->mNumberBuffers == 1 && data->mBuffers[0].mNumberChannels == channels;
    for (UInt32 b = 0; fits && b < data->mNumberBuffers; b++) {
        fits = data->mBuffers[b].mData && data->mBuffers[b].mDataByteSize == frames * bytes * (split ? 1 : channels);
    }
    return fits;
}
