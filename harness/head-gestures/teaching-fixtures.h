// Synthetic recorded attitudes, 25 Hz, serialized exactly like headphone recordings.
// No AirPods capture is claimed. Shared by the host replay and the simulator's persistence checks.
#import <Foundation/Foundation.h>
typedef NS_ENUM(int, TeachingFixture) {
    TeachingNod, TeachingShake, TeachingSingleNod, TeachingWalk, TeachingWalkWithNod,
    TeachingMixedNod, TeachingSmallShake, TeachingWalkWithSmallShake
};

static NSData *teachingMotion(TeachingFixture kind) {
    BOOL ordinary = kind == TeachingWalk || kind == TeachingWalkWithNod || kind == TeachingWalkWithSmallShake;
    int samples = ordinary ? 500 : 75;
    NSMutableData *data = [NSMutableData data];
    for (int i = 0; i < samples; i++) {
        double t = i / 25.0, pitch = 0.1, yaw = 3;
        double phase = t - (ordinary ? 5 : 0.5);
        if (ordinary) {
            pitch += 0.05 * sin(2 * M_PI * 2 * t);
            yaw += 0.03 * sin(2 * M_PI * t);
        }
        if ((kind == TeachingNod || kind == TeachingMixedNod || kind == TeachingSingleNod || kind == TeachingWalkWithNod) &&
            phase >= 0 && phase < (kind == TeachingSingleNod ? 0.4 : 0.8)) {
            double wave = sin(M_PI * phase / 0.4);
            pitch = 0.1 - 0.35 * wave * wave;
            yaw = 3;
        }
        if (kind == TeachingShake && phase >= 0 && phase < 0.8)
            yaw += 0.21 * sin(2 * M_PI * 2.5 * phase);
        if ((kind == TeachingMixedNod || kind == TeachingSmallShake || kind == TeachingWalkWithSmallShake) &&
            phase >= 0 && phase < 0.8)
            yaw += 0.09 * sin(2 * M_PI * 2.5 * phase);
        double values[] = {100 + t, pitch, remainder(yaw, 2 * M_PI)};
        [data appendBytes:values length:sizeof values];
    }
    return data;
}

static NSArray<NSData *> *teachingFive(TeachingFixture kind, int recognized) {
    NSMutableArray *motions = [NSMutableArray array];
    for (int i = 0; i < 5; i++)
        [motions addObject:teachingMotion(i < recognized ? kind : TeachingSingleNod)];
    return motions;
}
