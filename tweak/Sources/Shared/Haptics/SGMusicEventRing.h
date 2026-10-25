// One render-thread producer, one haptic-thread consumer. No allocation, locks or messages.
#import <stdatomic.h>
#import "SGMusicAnalyzer.h"

enum { SGMusicEventRingCapacity = 1024 };
typedef struct {
    SGMusicEvent events[SGMusicEventRingCapacity];
    atomic_uint head, tail;
} SGMusicEventRing;

static inline bool SGMusicEventRingPush(SGMusicEventRing *ring, const SGMusicEvent *event) {
    unsigned head = atomic_load_explicit(&ring->head, memory_order_relaxed);
    unsigned tail = atomic_load_explicit(&ring->tail, memory_order_acquire);
    if (head - tail >= SGMusicEventRingCapacity) return false;
    ring->events[head % SGMusicEventRingCapacity] = *event;
    atomic_store_explicit(&ring->head, head + 1, memory_order_release);
    return true;
}

static inline bool SGMusicEventRingPop(SGMusicEventRing *ring, SGMusicEvent *event) {
    unsigned tail = atomic_load_explicit(&ring->tail, memory_order_relaxed);
    unsigned head = atomic_load_explicit(&ring->head, memory_order_acquire);
    if (tail == head) return false;
    *event = ring->events[tail % SGMusicEventRingCapacity];
    atomic_store_explicit(&ring->tail, tail + 1, memory_order_release);
    return true;
}

// Consumer only: stop listening, or discard events when the engine cannot start.
static inline void SGMusicEventRingDiscard(SGMusicEventRing *ring) {
    unsigned head = atomic_load_explicit(&ring->head, memory_order_acquire);
    atomic_store_explicit(&ring->tail, head, memory_order_release);
}
