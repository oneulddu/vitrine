#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <pthread.h>
#include <unistd.h>
#include "Shared/Player/SGTimePitch.h"
#include "Shared/Player/SGRenderGate.h"

// Observe ownership at the AudioComponent service boundary, not private fields.
static atomic_int liveUnits;
OSStatus AudioComponentInstanceNew(AudioComponent component, AudioComponentInstance *instance) {
    static OSStatus (*realNew)(AudioComponent, AudioComponentInstance *);
    if (!realNew) realNew = dlsym(RTLD_NEXT, "AudioComponentInstanceNew");
    OSStatus status = realNew(component, instance);
    if (!status) atomic_fetch_add(&liveUnits, 1);
    return status;
}
OSStatus AudioComponentInstanceDispose(AudioComponentInstance instance) {
    static OSStatus (*realDispose)(AudioComponentInstance);
    if (!realDispose) realDispose = dlsym(RTLD_NEXT, "AudioComponentInstanceDispose");
    OSStatus status = realDispose(instance);
    if (!status) atomic_fetch_sub(&liveUnits, 1);
    return status;
}

static OSStatus source(void *context, UInt32 frames, AudioBufferList *data) {
    for (UInt32 c = 0; c < data->mNumberBuffers; ++c)
        memset(data->mBuffers[c].mData, 0, frames * sizeof(float));
    return noErr;
}

typedef struct {
    SGRenderGate gate;
    _Atomic(SGTimePitch *) current;
    atomic_bool loaded, closed, release, retired, rendered;
} Lifetime;

static void *heldRender(void *context) {
    Lifetime *test = context;
    if (!SGRenderGateEnter(&test->gate)) return NULL;
    SGTimePitch *unit = atomic_load(&test->current);
    atomic_store(&test->loaded, true);
    // Test double pauses after loading, before touching the retained unit.
    while (!atomic_load(&test->release)) {}
    float left[1024] = {0}, right[1024] = {0};
    float *lanes[] = {left, right};
    atomic_store(&test->rendered, SGTimePitchProcess(unit, lanes, 1024));
    SGRenderGateLeave(&test->gate);
    return NULL;
}

static void *retire(void *context) {
    Lifetime *test = context;
    SGRenderGateClose(&test->gate);
    atomic_store(&test->closed, true);
    while (!SGRenderGateIdle(&test->gate)) usleep(100);
    SGTimePitchFree(atomic_exchange(&test->current, NULL));
    atomic_store(&test->retired, true);
    return NULL;
}

static bool concurrentLifetime(void) {
    Lifetime test = {0};
    atomic_store(&test.current, SGTimePitchCreate(48000, 2, NULL, NULL));
    if (!atomic_load(&test.current)) return false;
    pthread_t render, writer;
    pthread_create(&render, NULL, heldRender, &test);
    while (!atomic_load(&test.loaded)) usleep(100);
    pthread_create(&writer, NULL, retire, &test);
    while (!atomic_load(&test.closed)) usleep(100);
    usleep(150000); // exceeds the obsolete bounded waitFor
    bool retained = !atomic_load(&test.retired) && atomic_load(&liveUnits) > 0;
    atomic_store(&test.release, true);
    pthread_join(render, NULL);
    pthread_join(writer, NULL);
    bool ok = retained && atomic_load(&test.rendered) && atomic_load(&test.retired) && atomic_load(&liveUnits) == 0;
    printf("%s concurrent retirement preserves a loaded unit until render exits\n", ok ? "ok" : "FAIL");
    return ok;
}

int main(void) {
    @autoreleasepool {
        if (!concurrentLifetime()) return 1;
        for (unsigned iteration = 0; iteration < 40; ++iteration) {
            double rate = iteration % 2 ? 44100 : 48000;
            SGTimePitch *unit = SGTimePitchCreate(rate, 2, iteration % 3 ? source : NULL, NULL);
            if (!unit) { fprintf(stderr, "FAIL create at %.0f Hz\n", rate); return 1; }
            float left[1024] = {0}, right[1024] = {0};
            struct { AudioBufferList list; AudioBuffer second; } data = {{2, {{1, sizeof left, left}}}, {1, sizeof right, right}};
            SGRenderGate gate = {0};
            if (!SGRenderGateEnter(&gate)) return 1;
            bool ok;
            if (iteration % 3) ok = SGTimePitchRender(unit, 1024, &data.list) == noErr;
            else {
                float *lanes[] = {left, right};
                ok = SGTimePitchProcess(unit, lanes, 1024);
            }
            SGRenderGateClose(&gate);
            if (SGRenderGateIdle(&gate)) { fprintf(stderr, "FAIL admitted render lost\n"); return 1; }
            SGRenderGateLeave(&gate);
            if (!SGRenderGateIdle(&gate)) return 1;
            SGTimePitchFree(unit);
            if (!ok || atomic_load(&liveUnits) != 0) {
                fprintf(stderr, "FAIL render/retirement at iteration %u, live units %d\n", iteration, atomic_load(&liveUnits));
                return 1;
            }
        }
        puts("ok alternating rates and pull/in-place lifetimes leave no live AudioUnits");
        return 0;
    }
}
