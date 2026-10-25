// Compile the real callbacks in this translation unit so the harness can supply
// AudioUnit-owned buffers and pause retirement at the loaded-reader boundary.
// Assertions concern output samples, ownership admission and live-unit access.
#import <UIKit/UIKit.h>
#include <pthread.h>
#include <unistd.h>
#import "SpeedPitch.m"

SPTPlayerState *SGPlayerState(void) { return nil; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {}

static int testFailures;
static void expect(BOOL ok, const char *name) {
    printf("%s %s\n", ok ? "ok" : "FAIL", name);
    testFailures += !ok;
}

static void formatAt(Format *format, double rate) {
    uint64_t bits;
    memcpy(&bits, &rate, sizeof bits);
    atomic_store(&format->rateBits, bits);
    atomic_store(&format->channels, 2);
    atomic_store(&format->bytes, 4);
    atomic_store(&format->flags, kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved);
}

static void renderConstant(Output *output, float *left, float *right, BOOL pre) {
    const UInt32 frames = 1024;
    for (UInt32 i = 0; i < frames; ++i) left[i] = right[i] = 1;
    struct { AudioBufferList list; AudioBuffer second; } data =
        {{2, {{1, frames * sizeof(float), left}}}, {1, frames * sizeof(float), right}};
    AudioTimeStamp stamp = {0};
    AudioUnitRenderActionFlags flags = kAudioUnitRenderAction_PreRender;
    if (pre) rendered(output, &flags, &stamp, 0, frames, &data.list);
    flags = kAudioUnitRenderAction_PostRender;
    rendered(output, &flags, &stamp, 0, frames, &data.list);
}

static BOOL samplesEqual(float *left, float *right, float expected) {
    for (unsigned i = 0; i < 1024; ++i)
        if (fabsf(left[i] - expected) > 0.000001f || fabsf(right[i] - expected) > 0.000001f) return NO;
    return YES;
}

static atomic_bool stopNonowner, nonownerStarted;
static void *nonowner(void *context) {
    AudioUnit unit = context;
    atomic_store(&nonownerStarted, true);
    while (!atomic_load(&stopNonowner)) {
        if (SGPlayerBeginProcessing(unit)) SGPlayerEndProcessing();
    }
    return NULL;
}

static atomic_bool readerLoaded, releaseReader, replacementStarted, replacementFinished, renderSucceeded;
static void *retainedReader(void *context) {
    AudioUnit output = context;
    if (!SGPlayerBeginProcessing(output)) return NULL;
    SGTimePitch *unit = atomic_load(&sg_inPlace);
    atomic_store(&readerLoaded, true);
    while (!atomic_load(&releaseReader)) {}
    float left[1024] = {0}, right[1024] = {0};
    float *lanes[] = {left, right};
    atomic_store(&renderSucceeded, SGTimePitchProcess(unit, lanes, 1024));
    SGPlayerEndProcessing();
    return NULL;
}
static void *replaceUnit(void *context) {
    atomic_store(&replacementStarted, true);
    SGTimePitch *unit = unitForFormat();
    atomic_store(&replacementFinished, unit && SGTimePitchSampleRate(unit) == 44100);
    return NULL;
}

static void runTests(void) {
    Output *output = outputFor((AudioUnit)(uintptr_t)1);
    formatAt(&output->hardware, 48000);
    atomic_store(&sg_music, output);
    float left[1024], right[1024];
    SGPlayerSetOutputControl(YES, -12, 0, 60);
    renderConstant(output, left, right, YES); // settle gain ramp
    closeProcessing();
    renderConstant(output, left, right, YES);
    expect(samplesEqual(left, right, 0.25118864f), "closed admission still applies -12 dB output gain");
    SGPlayerSetGain(0.25);
    for (unsigned i = 0; i < 30; ++i) renderConstant(output, left, right, YES);
    expect(samplesEqual(left, right, 0.06279716f), "closed admission still applies sleep attenuation after output gain");
    SGPlayerSetGain(1);
    for (unsigned i = 0; i < 30; ++i) renderConstant(output, left, right, YES);
    SGPlayerSetOutputControl(YES, 0, -12, 60);
    renderConstant(output, left, right, YES);
    renderConstant(output, left, right, YES);
    expect(samplesEqual(left, right, 0.25118864f), "closed admission still applies standalone limiter");
    // A buffer started as music must retain control even if handoff finishes
    // between its feed and post-render.
    output->musicBuffer = YES;
    atomic_store(&sg_music, NULL);
    renderConstant(output, left, right, NO);
    expect(samplesEqual(left, right, 0.25118864f), "old output's in-flight music buffer retains limiter after handoff");
    SGPlayerSetOutputControl(YES, -12, 0, 60);
    renderConstant(output, left, right, YES); // a complete nonmusic buffer
    atomic_store(&sg_music, output);
    renderConstant(output, left, right, YES);
    expect(samplesEqual(left, right, 0.25118864f), "newly selected output starts at configured gain on its first buffer");
    openProcessing();

    pthread_t noise;
    pthread_create(&noise, NULL, nonowner, (void *)(uintptr_t)2);
    while (!atomic_load(&nonownerStarted)) usleep(100);
    unsigned refused = 0;
    for (unsigned i = 0; i < 1000000; ++i) {
        if (SGPlayerBeginProcessing(atomic_load(&output->unit))) SGPlayerEndProcessing();
        else ++refused;
    }
    atomic_store(&stopNonowner, true);
    pthread_join(noise, NULL);
    expect(refused == 0, "nonowner callbacks never refuse concurrent music admission");

    // B was last rendered at unity, then stopped while A completed a fade.
    Output *second = outputFor((AudioUnit)(uintptr_t)2);
    formatAt(&second->hardware, 48000);
    SGPlayerSetOutputControl(NO, 0, 0, 60);
    atomic_store(&output->running, true);
    renderConstant(second, left, right, YES);
    SGPlayerSetGain(0.25);
    for (unsigned i = 0; i < 30; ++i) renderConstant(output, left, right, YES);
    atomic_store(&second->running, true);
    markEvent(second);
    reselect(NO, nil);
    // Repeated selection, with no render on B between any of these changes.
    markEvent(output);
    reselect(NO, nil);
    markEvent(second);
    reselect(NO, nil);
    renderConstant(second, left, right, YES);
    expect(samplesEqual(left, right, 0.25f), "repeated handoffs before B's first render cannot restore its stale unity level");
    // Starts carry no saved gain. The timer can advance again before render.
    atomic_store(&second->sleepStarting, true); // startOutput's notification
    atomic_store(&second->sleepStarting, true); // another start before rendering
    SGPlayerSetGain(0.125);
    renderConstant(second, left, right, YES);
    expect(samplesEqual(left, right, 0.125f), "repeated starts use the latest global fade level, not a pending transfer");
    SGPlayerSetGain(0.0625);
    markEvent(output);
    reselect(NO, nil);
    renderConstant(output, left, right, YES);
    expect(samplesEqual(left, right, 0.0625f), "selection starts directly at the current global fade level");
    SGPlayerSetGain(1);
    atomic_store(&second->running, false);
    atomic_store(&second->unit, NULL);
    atomic_store(&output->running, false);

    SGTimePitch *initial = unitForFormat();
    expect(initial != NULL, "initial pitch unit created");
    if (initial) {
        atomic_store(&sg_engaged, true);
        pthread_t reader, writer;
        pthread_create(&reader, NULL, retainedReader, (void *)(uintptr_t)1);
        while (!atomic_load(&readerLoaded)) usleep(100);
        formatAt(&output->hardware, 44100);
        pthread_create(&writer, NULL, replaceUnit, NULL);
        while (!atomic_load(&replacementStarted)) usleep(100);
        usleep(150000);
        expect(!atomic_load(&replacementFinished), "production format retirement waits for loaded render reader");
        atomic_store(&releaseReader, true);
        pthread_join(reader, NULL);
        pthread_join(writer, NULL);
        expect(atomic_load(&renderSucceeded) && atomic_load(&replacementFinished),
               "old unit renders safely before replacement completes");
        disengage();
        SGTimePitchFree(atomic_exchange(&sg_inPlace, NULL));
    }
    atomic_store(&sg_music, NULL);
    atomic_store(&output->unit, NULL);
    printf("RESULT failures=%d\n", testFailures);
    fflush(stdout);
    exit(testFailures ? 1 : 0);
}

@interface OutputHarness : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation OutputHarness
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{ runTests(); });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, @"OutputHarness"); }
}
