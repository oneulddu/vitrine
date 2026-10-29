#pragma once
#include <math.h>
#include <stdint.h>
#include <stdatomic.h>
#include <string.h>
#include <stdbool.h>

// Settings are published off render; the envelope belongs to one output's
// render thread, independently of admission to shared effects.
typedef struct { float gain, threshold, release; } SGOutputSettings;
typedef struct { float gain, limiter; } SGOutputEnvelope;
typedef struct {
    atomic_uint sequence, gain, threshold, release;
} SGOutputPublication;

static inline unsigned SGOutputBits(float value) {
    unsigned bits;
    memcpy(&bits, &value, sizeof bits);
    return bits;
}
static inline float SGOutputFloat(unsigned bits) {
    float value;
    memcpy(&value, &bits, sizeof value);
    return value;
}
static inline void storeFloat(atomic_uint *slot, float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof bits);
    atomic_store(slot, bits);
}
// Serialized writers. Atomic fields make a failed snapshot attempt race-free.
static inline void SGOutputPublish(SGOutputPublication *publication, SGOutputSettings settings) {
    atomic_fetch_add(&publication->sequence, 1);
    atomic_store(&publication->gain, SGOutputBits(settings.gain));
    atomic_store(&publication->threshold, SGOutputBits(settings.threshold));
    atomic_store(&publication->release, SGOutputBits(settings.release));
    atomic_fetch_add(&publication->sequence, 1);
}
// One bounded attempt; retain the last complete settings during publication.
static inline void SGOutputRead(SGOutputPublication *publication, SGOutputSettings *settings) {
    unsigned before = atomic_load(&publication->sequence);
    if (before & 1) return;
    SGOutputSettings next = {
        SGOutputFloat(atomic_load(&publication->gain)),
        SGOutputFloat(atomic_load(&publication->threshold)),
        SGOutputFloat(atomic_load(&publication->release))
    };
    if (before == atomic_load(&publication->sequence)) *settings = next;
}
static inline float SGOutputFrameScale(SGOutputEnvelope *envelope, SGOutputSettings settings,
                                      float gain, float left, float right) {
    float peak = fmaxf(fabsf(left), fabsf(right)) * gain;
    float target = peak > settings.threshold ? settings.threshold / peak : 1;
    envelope->limiter = target < envelope->limiter ? target
        : target + (envelope->limiter - target) * settings.release;
    return gain * envelope->limiter;
}
static inline void SGOutputProcess(SGOutputEnvelope *envelope, SGOutputSettings settings,
                                   float *left, float *right, uint32_t frames) {
    float from = envelope->gain, step = (settings.gain - from) / frames;
    for (uint32_t i = 0; i < frames; ++i) {
        float gain = from == settings.gain ? from : from + step * (i + 1);
        float scale = SGOutputFrameScale(envelope, settings, gain, left[i], right[i]);
        left[i] *= scale;
        right[i] *= scale;
    }
    envelope->gain = settings.gain;
}
