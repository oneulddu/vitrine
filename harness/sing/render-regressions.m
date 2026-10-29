// Deterministic render-contract checks. Seed the rings as a completed separator window, with the
// worker stopped, and stand in for AUReverb2 (unavailable on macOS). No test-only production API.
#ifndef SG_SING_ENGINE_SOURCE
#define SG_SING_ENGINE_SOURCE "../../tweak/Sources/Shared/Sing/SGSingEngine.m"
#endif
#import SG_SING_ENGINE_SOURCE
#include <stdio.h>

struct SGDSPReverb { uint64_t rendered; };
SGDSPReverb *SGDSPReverbCreate(double rate, int preset, float amount) { return calloc(1, sizeof(SGDSPReverb)); }
void SGDSPReverbSetSend(SGDSPReverb *room, int preset) {}
void SGDSPReverbReset(SGDSPReverb *room) {}
void SGDSPReverbFree(void *room) { free(room); }
// A unity wet return makes the sum independently predictable and records actual DSP activity.
void SGDSPReverbRun(void *state, float *left, float *right, uint32_t frames) {
    ((SGDSPReverb *)state)->rendered += frames;
}

static int failures;
#define CHECK(condition, message) do { \
    if (!(condition)) { fprintf(stderr, "FAIL: %s\n", message); failures++; } \
    else printf("ok: %s\n", message); \
} while (0)

static OSStatus pullVocal(void *context, UInt32 frames, float *left, float *right, UInt32 *sounding) {
    float amplitude = *(float *)context;
    for (UInt32 i = 0; i < frames; i++) left[i] = right[i] = amplitude;
    if (sounding) *sounding = frames;
    return noErr;
}

static SGSingEngine *fixture(float amplitude, float angle, float room) {
    SGSingEngine *engine = SGSingEngineCreate();
    if (!engine) { fprintf(stderr, "engine allocation failed\n"); exit(1); }
    pthread_mutex_lock(&engine->lock);
    atomic_store(&engine->alive, false);
    pthread_cond_signal(&engine->wake);
    pthread_mutex_unlock(&engine->lock);
    pthread_join(engine->worker, NULL);
    engine->worker = NULL;
    // A centered vocal is all of the original mix; three seconds are buffered and separated.
    for (unsigned i = 0; i < kRing; i++)
        engine->left[i] = engine->right[i] = engine->vocalsLeft[i] = engine->vocalsRight[i] = amplitude;
    atomic_store(&engine->written, 3 * kSGSingRate);
    atomic_store(&engine->ready, 3 * kSGSingRate);
    atomic_store(&engine->hasSeparator, true);
    atomic_store(&engine->on, true);
    atomic_store(&engine->mixing, true);
    atomic_store(&engine->targetLead, 3 * kSGSingRate);
    engine->running = engine->wasWorking = engine->established = true;
    engine->amount = 1;
    engine->voiceAngle = angle;
    engine->sendGain = room / 2;
    SGSingEngineSetVoiceAngle(engine, angle);
    SGSingEngineSetSpatial(engine, true, 1, room, 1);
    return engine;
}

static void headroom(void) {
    float left[1024], right[1024], amplitude = 0.9f;
    SGSingEngine *engine = fixture(amplitude, M_PI_2, 0);
    SGSingEngineRender(engine, 1024, left, right, pullVocal, &amplitude);
    // Equal-power right pan: 0.9 * sqrt(2) * sin(3*pi/8), followed by output gain 0.5.
    CHECK(fabsf(right[1023] * 0.5f - 0.587953334f) < 1e-6f,
          "spatial near-ear peak survives downstream attenuation");
    SGSingEngineDestroy(engine);
    engine = fixture(amplitude, 0, 1);
    SGSingEngineRender(engine, 1024, left, right, pullVocal, &amplitude);
    CHECK(fabsf(left[1023] * 0.5f - 0.675f) < 1e-6f &&
          fabsf(right[1023] * 0.5f - 0.675f) < 1e-6f,
          "dry plus wet return survives downstream attenuation");
    SGSingEngineDestroy(engine);
}

static void tail(void) {
    float left[1024], right[1024], amplitude = 0.9f;
    SGSingEngine *engine = fixture(amplitude, 0, 1);
    SGSingEngineRender(engine, 1024, left, right, pullVocal, &amplitude);
    CHECK(engine->room->rendered > 0, "Room processes a feeding voice");
    SGSingEngineSetOn(engine, false);
    bool continuous = true;
    bool ringing = false;
    // More than the 100 ms vocal fade plus the four-second tail, retaining the buffered lead.
    for (unsigned frame = 0; frame < 5 * kSGSingRate; frame += 1024) {
        uint64_t before = engine->room->rendered;
        SGSingEngineRender(engine, 1024, left, right, pullVocal, &amplitude);
        if (frame >= 3 * kSGSingRate && frame < 3 * kSGSingRate + 1024)
            ringing = engine->room->rendered > before;
        if (frame > kSGSingRate)
            for (unsigned i = 0; i < 1024; i++)
                continuous &= fabsf(left[i] - 0.9f) < 1e-6f && fabsf(right[i] - 0.9f) < 1e-6f;
    }
    CHECK(continuous && SGSingEngineLead(engine) > 2, "Sing off keeps buffered dry output continuous");
    CHECK(ringing, "Room continues ringing during its four-second tail");
    uint64_t rendered = engine->room->rendered;
    SGSingEngineRender(engine, 1024, left, right, pullVocal, &amplitude);
    CHECK(engine->room->rendered == rendered, "Room is inactive after voice stops and tail expires");
    SGSingEngineDestroy(engine);
}

int main(void) {
    @autoreleasepool { headroom(); tail(); }
    return failures ? 1 : 0;
}
