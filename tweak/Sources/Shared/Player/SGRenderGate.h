#pragma once
#include <stdatomic.h>
#include <stdbool.h>

// One render owner, with admission closed by a serialized control-side writer.
// Render uses one CAS and one release; it never waits. Closing keeps an admitted
// reader visible until it leaves, including when Close races with Leave.
enum { SGRenderGateReading = 1, SGRenderGateClosed = 2 };
typedef struct { atomic_uint state; } SGRenderGate;
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "render admission must be lock-free");

static inline bool SGRenderGateEnter(SGRenderGate *gate) {
    unsigned idle = 0;
    return atomic_compare_exchange_strong_explicit(&gate->state, &idle, SGRenderGateReading,
                                                   memory_order_acquire, memory_order_relaxed);
}
static inline void SGRenderGateLeave(SGRenderGate *gate) {
    atomic_fetch_and_explicit(&gate->state, ~SGRenderGateReading, memory_order_release);
}
// Control only: Close, wait for Idle, mutate/publish, then Open. Writers serialize
// outside this primitive. Closing does not itself wait.
static inline void SGRenderGateClose(SGRenderGate *gate) {
    atomic_fetch_or_explicit(&gate->state, SGRenderGateClosed, memory_order_acq_rel);
}
static inline bool SGRenderGateIdle(SGRenderGate *gate) {
    return !(atomic_load_explicit(&gate->state, memory_order_acquire) & SGRenderGateReading);
}
static inline void SGRenderGateOpen(SGRenderGate *gate) {
    atomic_store_explicit(&gate->state, 0, memory_order_release);
}
