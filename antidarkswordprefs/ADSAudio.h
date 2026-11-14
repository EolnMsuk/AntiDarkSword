#pragma once
#import <Foundation/Foundation.h>
#include <stdatomic.h>
#include <os/lock.h>

typedef struct {
    float bgmPhase;
    float bgmPhase2;
    float bgmPhase3;
    float sfxPhase;
    float sfxFreq;
    float sfxDur;
    float sfxEnvInit;
    float sfxFreq2;
    float sfxPhase2;
    float sfxDur2;
    float bgmTime;
    float bgmTime2;
    int bgmIdx;
    int bgmIdx2;
    int playBGM;
    float sfxSweepRate;
    float sfxSweep2Rate;
} ADSSynthState;

typedef struct {
    float frequency, frequency2, duration, sweep, sweep2;
} ADSSoundCommand;

// The render block retains this owner. Its synth fields are audio-thread-only;
// UI commands cross a bounded ring and BGM uses a lock-free atomic flag.
@interface ADSAudioBuffer : NSObject {
@public
    ADSSynthState state;
    ADSSoundCommand commands[16];
    _Atomic unsigned readIndex;
    _Atomic unsigned writeIndex;
    _Atomic bool playBGM;
    os_unfair_lock producerLock; // UI producers only; render never takes this lock
}
@end

void ADSEnqueueSound(ADSAudioBuffer *buffer, float frequency, float frequency2,
                     float duration, float sweep, float sweep2);

_Static_assert(ATOMIC_INT_LOCK_FREE == 2 && ATOMIC_BOOL_LOCK_FREE == 2, "Audio mailbox requires lock-free atomics");
static inline void ADSApplyAudioCommands(__unsafe_unretained ADSAudioBuffer *buffer) {
    ADSSynthState *synth = &buffer->state;
    synth->playBGM = atomic_load_explicit(&buffer->playBGM, memory_order_relaxed);
    unsigned read = atomic_load_explicit(&buffer->readIndex, memory_order_relaxed);
    unsigned write = atomic_load_explicit(&buffer->writeIndex, memory_order_acquire);
    while (read != write) { // at most sixteen commands per render invocation
        ADSSoundCommand command = buffer->commands[read & 15];
        synth->sfxFreq = command.frequency;
        synth->sfxFreq2 = command.frequency2;
        synth->sfxDur = synth->sfxEnvInit = command.duration;
        synth->sfxDur2 = command.frequency2 > 0 ? command.duration : 0;
        synth->sfxPhase = synth->sfxPhase2 = 0;
        synth->sfxSweepRate = command.sweep;
        synth->sfxSweep2Rate = command.sweep2;
        atomic_store_explicit(&buffer->readIndex, ++read, memory_order_release);
    }
}

