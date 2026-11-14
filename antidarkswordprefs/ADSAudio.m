#import "ADSAudio.h"

@implementation ADSAudioBuffer
- (instancetype)init {
    if ((self = [super init])) {
        atomic_init(&readIndex, 0);
        atomic_init(&writeIndex, 0);
        atomic_init(&playBGM, false);
        producerLock = (os_unfair_lock)OS_UNFAIR_LOCK_INIT;
    }
    return self;
}
@end

void ADSEnqueueSound(ADSAudioBuffer *buffer, float frequency, float frequency2,
                     float duration, float sweep, float sweep2) {
    if (!buffer) return;
    os_unfair_lock_lock(&buffer->producerLock);
    unsigned write = atomic_load_explicit(&buffer->writeIndex, memory_order_relaxed);
    unsigned read = atomic_load_explicit(&buffer->readIndex, memory_order_acquire);
    if (write - read < 16) {
        buffer->commands[write & 15] = (ADSSoundCommand){frequency, frequency2, duration, sweep, sweep2};
        atomic_store_explicit(&buffer->writeIndex, write + 1, memory_order_release);
    } // Full mailbox drops a sound effect instead of blocking the audio thread.
    os_unfair_lock_unlock(&buffer->producerLock);
}
