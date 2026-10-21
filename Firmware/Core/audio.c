#include "nxs_audio.h"

#include <math.h>

_Static_assert((NXS_AUDIO_RING_FRAMES & (NXS_AUDIO_RING_FRAMES - 1u)) == 0, "Audio ring requires a power-of-two capacity");
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Audio ring requires lock-free 32-bit indices");

void nxs_audio_maintenance_init(nxs_audio_maintenance_t *maintenance) {
    atomic_init(&maintenance->request_token, 0);
    atomic_init(&maintenance->acknowledged_token, 0);
    maintenance->next_token = 0;
}

void nxs_audio_maintenance_request(nxs_audio_maintenance_t *maintenance, bool requested) {
    if (!requested) {
        atomic_store_explicit(&maintenance->request_token, 0, memory_order_release);
    } else if (atomic_load_explicit(&maintenance->request_token, memory_order_relaxed) == 0) {
        uint32_t previous_ack = atomic_load_explicit(&maintenance->acknowledged_token, memory_order_acquire);
        do {
            ++maintenance->next_token;
        } while (maintenance->next_token == 0 || maintenance->next_token == previous_ack);
        atomic_store_explicit(&maintenance->request_token, maintenance->next_token, memory_order_release);
    }
}

bool nxs_audio_maintenance_requested(const nxs_audio_maintenance_t *maintenance) {
    return atomic_load_explicit(&maintenance->request_token, memory_order_acquire) != 0;
}

void nxs_audio_maintenance_acknowledge(nxs_audio_maintenance_t *maintenance, bool paused) {
    uint32_t token = paused ? atomic_load_explicit(&maintenance->request_token, memory_order_acquire) : 0;
    atomic_store_explicit(&maintenance->acknowledged_token, token, memory_order_release);
}

bool nxs_audio_maintenance_ready(const nxs_audio_maintenance_t *maintenance) {
    uint32_t requested = atomic_load_explicit(&maintenance->request_token, memory_order_acquire);
    return requested != 0 && requested == atomic_load_explicit(&maintenance->acknowledged_token, memory_order_acquire);
}

void nxs_audio_ring_init(nxs_audio_ring_t *ring) {
    atomic_init(&ring->read_index, 0);
    atomic_init(&ring->write_index, 0);
}

size_t nxs_audio_ring_count(const nxs_audio_ring_t *ring) {
    uint32_t read = atomic_load_explicit(&ring->read_index, memory_order_acquire);
    uint32_t write = atomic_load_explicit(&ring->write_index, memory_order_acquire);
    return (uint32_t)(write - read);
}

bool nxs_audio_ring_write(nxs_audio_ring_t *ring, const float *stereo, size_t frames) {
    if (!ring || frames > NXS_AUDIO_RING_FRAMES || (frames && !stereo)) {
        return false;
    }
    uint32_t write = atomic_load_explicit(&ring->write_index, memory_order_relaxed);
    uint32_t read = atomic_load_explicit(&ring->read_index, memory_order_acquire);
    if (frames > NXS_AUDIO_RING_FRAMES - (uint32_t)(write - read)) {
        return false;
    }
    for (size_t frame = 0; frame < frames; ++frame) {
        size_t slot = ((write + (uint32_t)frame) & (NXS_AUDIO_RING_FRAMES - 1u)) * NXS_AUDIO_CHANNELS;
        for (size_t channel = 0; channel < NXS_AUDIO_CHANNELS; ++channel) {
            ring->stereo[slot + channel] = stereo[frame * NXS_AUDIO_CHANNELS + channel];
        }
    }
    atomic_store_explicit(&ring->write_index, write + (uint32_t)frames, memory_order_release);
    return true;
}

size_t nxs_audio_ring_read(nxs_audio_ring_t *ring, float *stereo, size_t frames) {
    if (!ring || !stereo || frames > NXS_AUDIO_RING_FRAMES) {
        return 0;
    }
    uint32_t read = atomic_load_explicit(&ring->read_index, memory_order_relaxed);
    uint32_t write = atomic_load_explicit(&ring->write_index, memory_order_acquire);
    uint32_t available = write - read;
    if (frames > available) {
        frames = available;
    }
    for (size_t frame = 0; frame < frames; ++frame) {
        size_t slot = ((read + (uint32_t)frame) & (NXS_AUDIO_RING_FRAMES - 1u)) * NXS_AUDIO_CHANNELS;
        for (size_t channel = 0; channel < NXS_AUDIO_CHANNELS; ++channel) {
            stereo[frame * NXS_AUDIO_CHANNELS + channel] = ring->stereo[slot + channel];
        }
    }
    atomic_store_explicit(&ring->read_index, read + (uint32_t)frames, memory_order_release);
    return frames;
}

void nxs_audio_ring_discard(nxs_audio_ring_t *ring) {
    uint32_t write = atomic_load_explicit(&ring->write_index, memory_order_acquire);
    atomic_store_explicit(&ring->read_index, write, memory_order_release);
}

bool nxs_audio_decode(const uint8_t *packet, size_t length, uint8_t sample_bytes, float *stereo, size_t capacity, size_t *frames) {
    if (!frames || (sample_bytes != 2 && sample_bytes != 3)) {
        return false;
    }
    size_t frame_bytes = sample_bytes * NXS_AUDIO_CHANNELS;
    size_t count = length / frame_bytes;
    if (length % frame_bytes != 0 || count > capacity || count > NXS_AUDIO_USB_MAX_FRAMES || (length && (!packet || !stereo))) {
        return false;
    }
    for (size_t sample = 0; sample < count * NXS_AUDIO_CHANNELS; ++sample) {
        uint32_t raw = 0;
        for (uint8_t byte = 0; byte < sample_bytes; ++byte) {
            raw |= (uint32_t)packet[sample * sample_bytes + byte] << (byte * 8);
        }
        uint32_t sign_bit = 1u << (sample_bytes * 8 - 1);
        int32_t signed_sample = (int32_t)raw;
        if (raw & sign_bit) {
            signed_sample -= (int32_t)(sign_bit * 2u);
        }
        stereo[sample] = (float)signed_sample / (float)sign_bit;
    }
    *frames = count;
    return true;
}

uint32_t nxs_audio_i2s_sample(float mono) {
    if (!isfinite(mono)) {
        return 0;
    }
    if (mono >= 1.0f) {
        return UINT32_C(0x7fffffff);
    }
    if (mono <= -1.0f) {
        return UINT32_C(0x80000000);
    }
    return (uint32_t)(int32_t)(mono * 2147483648.0f);
}

static float gain_bound(float value) {
    return isfinite(value) ? fmaxf(0, fminf(1, value)) : 0;
}

void nxs_gain_init(nxs_gain_ramp_t *ramp, float value) {
    *ramp = (nxs_gain_ramp_t){0};
    ramp->value = ramp->target = gain_bound(value);
}

void nxs_gain_target(nxs_gain_ramp_t *ramp, float target) {
    target = gain_bound(target);
    if (target != ramp->target) {
        ramp->target = target;
        ramp->remaining = NXS_DSP_TRANSITION_FRAMES;
        ramp->step = (target - ramp->value) / NXS_DSP_TRANSITION_FRAMES;
    }
}

float nxs_gain_next(nxs_gain_ramp_t *ramp) {
    if (ramp->remaining != 0) {
        ramp->value += ramp->step;
        if (--ramp->remaining == 0) {
            ramp->value = ramp->target;
        }
    }
    return gain_bound(ramp->value);
}

uint32_t nxs_audio_feedback(size_t queued_frames) {
    if (queued_frames > NXS_AUDIO_RING_FRAMES) {
        queued_frames = NXS_AUDIO_RING_FRAMES;
    }
    int32_t error = (int32_t)NXS_AUDIO_TARGET_FRAMES - (int32_t)queued_frames;
    int32_t correction = error * 64;
    const int32_t maximum_correction = 16384;
    if (correction > maximum_correction) {
        correction = maximum_correction;
    } else if (correction < -maximum_correction) {
        correction = -maximum_correction;
    }
    return (uint32_t)((int32_t)nxs_audio_nominal_feedback() + correction);
}

uint32_t nxs_audio_nominal_feedback(void) {
    return (uint32_t)(((uint64_t)NXS_SAMPLE_RATE_HZ << 16) / 1000u);
}
