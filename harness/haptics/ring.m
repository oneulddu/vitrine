#import <Foundation/Foundation.h>
#import <pthread.h>
#import <sched.h>
#import "Shared/Haptics/SGMusicEventRing.h"

static SGMusicEventRing ring;
enum { kEvents = 1000000 };

static void require(BOOL ok, const char *what) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", what); exit(1); }
}

static void *produce(void *unused) {
    for (unsigned i = 1; i <= kEvents; i++) {
        SGMusicEvent event = {i, 0.25f, 0.75f, SGMusicEventKick};
        while (!SGMusicEventRingPush(&ring, &event)) sched_yield();
    }
    return NULL;
}

int main(void) {
    SGMusicEvent event = {7, 0.25f, 0.75f, SGMusicEventKick}, read;
    require(!SGMusicEventRingPop(&ring, &read), "an empty ring has no event");
    for (unsigned i = 0; i < SGMusicEventRingCapacity; i++) {
        require(SGMusicEventRingPush(&ring, &event), "capacity is available");
    }
    require(!SGMusicEventRingPush(&ring, &event), "a full ring refuses another event");
    SGMusicEventRingDiscard(&ring);
    require(!SGMusicEventRingPop(&ring, &read), "discard empties the consumer's pending events");
    pthread_t producer;
    require(pthread_create(&producer, NULL, produce, NULL) == 0, "producer starts");
    for (unsigned i = 1; i <= kEvents; i++) {
        while (!SGMusicEventRingPop(&ring, &read)) sched_yield();
        require(read.hostTime == i && read.intensity == 0.25f && read.sharpness == 0.75f && read.kind == SGMusicEventKick,
                "a consumed event is complete and in order across ring reuse");
    }
    require(pthread_join(producer, NULL) == 0, "producer finishes");
    require(!SGMusicEventRingPop(&ring, &read), "every published event was consumed exactly once");
    puts("PASS: event ring capacity, discard, and 1000000 concurrent ordered events");
    return 0;
}
