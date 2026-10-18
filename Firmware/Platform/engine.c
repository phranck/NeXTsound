#include "nxs_engine.h"
#include "nxs_i2s.h"

#include "pico/flash.h"
#include "pico/multicore.h"
#include "pico/stdlib.h"
#include "pico/util/queue.h"

#include <math.h>

#define NXS_HOST_CONTROL_QUEUE_COUNT 4u
#define NXS_AUDIO_OWNER_START_TIMEOUT_MS 1000u

static nxs_audio_ring_t ring;
static queue_t configuration_queue;
static queue_t result_queue;
static queue_t status_queue;
static queue_t host_control_queue;
static nxs_audio_observation_t latest_observation;
static _Atomic uint32_t transport_state;
static _Atomic uint32_t receive_overruns;
static nxs_audio_maintenance_t maintenance;
static nxs_dsp_configuration_t initial_configuration;
static _Atomic bool owner_started;
static _Atomic bool flash_safe_ready;

static nxs_render_control_t read_control(void) {
    static nxs_render_control_t latest_host;
    for (size_t index = 0; index < NXS_HOST_CONTROL_QUEUE_COUNT; ++index) {
        if (!queue_try_remove(&host_control_queue, &latest_host)) {
            break;
        }
    }
    uint32_t state = atomic_load_explicit(&transport_state, memory_order_acquire);
    nxs_render_control_t control = latest_host;
    control.epoch = state >> 2;
    control.streaming = (state & 1u) != 0;
    control.suspended = (state & 2u) != 0 || nxs_audio_maintenance_requested(&maintenance);
    return control;
}

static void apply_pending(nxs_renderer_t *renderer) {
    nxs_dsp_configuration_t configuration;
    if (renderer->dsp.transition_remaining == 0 && queue_try_remove(&configuration_queue, &configuration)) {
        bool accepted = nxs_dsp_apply(&renderer->dsp, &configuration);
        if (!queue_try_add(&result_queue, &accepted)) {
            panic("Audio ownership acknowledgement queue overflow");
        }
    }
}

static void publish_status(const nxs_renderer_t *renderer, uint32_t maximum_us, uint32_t deadline_misses) {
    nxs_audio_observation_t observation = nxs_renderer_observe(
        renderer, maximum_us, nxs_i2s_stall_count(), atomic_load_explicit(&receive_overruns, memory_order_relaxed), deadline_misses);
    (void)queue_try_add(&status_queue, &observation);
}

static void audio_owner(void) {
    nxs_renderer_t renderer;
    nxs_renderer_init(&renderer, &ring);
    if (!nxs_dsp_apply(&renderer.dsp, &initial_configuration)) {
        panic("Invalid initial DSP configuration");
    }
    atomic_store_explicit(&flash_safe_ready, flash_safe_execute_core_init(), memory_order_release);
    nxs_i2s_init();
    nxs_i2s_start();
    atomic_store_explicit(&owner_started, true, memory_order_release);
    uint32_t maximum_us = 0, deadline_misses = 0;
    bool paused = false;
    for (;;) {
        uint32_t started = time_us_32();
        nxs_render_control_t control = read_control();
        if (paused) {
            if (control.suspended) {
                nxs_audio_maintenance_acknowledge(&maintenance, true);
                __wfe();
                continue;
            }
            nxs_audio_maintenance_acknowledge(&maintenance, false);
            nxs_i2s_start();
            paused = false;
            started = time_us_32();
        }
        apply_pending(&renderer);
        if (!nxs_renderer_process(&renderer, &control, nxs_i2s_next_buffer())) {
            panic("Invalid audio owner controls");
        }
        publish_status(&renderer, maximum_us, deadline_misses);
        uint32_t elapsed = time_us_32() - started;
        if (elapsed > maximum_us) {
            maximum_us = elapsed;
        }
        if (elapsed > NXS_DSP_BLOCK_DEADLINE_US) {
            ++deadline_misses;
        }
        nxs_i2s_send_prepared();
        if (control.suspended && nxs_renderer_is_quiet(&renderer)) {
            nxs_i2s_pause();
            paused = true;
            nxs_audio_maintenance_acknowledge(&maintenance, true);
            publish_status(&renderer, maximum_us, deadline_misses);
            __sev();
        }
    }
}

bool nxs_audio_engine_init(const nxs_snapshot_t *initial) {
    nxs_snapshot_t snapshot = initial ? *initial : nxs_default_snapshot();
    if (!nxs_dsp_prepare(&snapshot, &initial_configuration)) {
        return false;
    }
    nxs_audio_maintenance_init(&maintenance);
    atomic_init(&owner_started, false);
    atomic_init(&flash_safe_ready, false);
    nxs_audio_ring_init(&ring);
    queue_init(&configuration_queue, sizeof(nxs_dsp_configuration_t), 1);
    queue_init(&result_queue, sizeof(bool), 1);
    queue_init(&status_queue, sizeof(nxs_audio_observation_t), 2);
    queue_init(&host_control_queue, sizeof(nxs_render_control_t), NXS_HOST_CONTROL_QUEUE_COUNT);
    atomic_init(&transport_state, 0);
    atomic_init(&receive_overruns, 0);
    latest_observation.status.block_deadline_us = NXS_DSP_BLOCK_DEADLINE_US;
    (void)nxs_audio_engine_host_controls(0, false);
    multicore_launch_core1(audio_owner);
    absolute_time_t deadline = make_timeout_time_ms(NXS_AUDIO_OWNER_START_TIMEOUT_MS);
    while (!atomic_load_explicit(&owner_started, memory_order_acquire)) {
        if (time_reached(deadline)) {
            return false;
        }
        tight_loop_contents();
    }
    return true;
}

void nxs_audio_engine_request_maintenance(bool requested) {
    nxs_audio_maintenance_request(&maintenance, requested);
    __sev();
}

bool nxs_audio_engine_maintenance_ready(void) {
    return nxs_audio_maintenance_ready(&maintenance);
}

bool nxs_audio_engine_flash_ready(void) {
    return atomic_load_explicit(&flash_safe_ready, memory_order_acquire);
}

bool nxs_audio_engine_submit(const nxs_dsp_configuration_t *configuration) {
    bool accepted = queue_try_add(&configuration_queue, configuration);
    if (accepted) {
        __sev();
    }
    return accepted;
}

bool nxs_audio_engine_take_result(bool *accepted) {
    return queue_try_remove(&result_queue, accepted);
}

void nxs_audio_engine_status(nxs_audio_observation_t *observation) {
    while (queue_try_remove(&status_queue, &latest_observation)) {
    }
    *observation = latest_observation;
}

void nxs_audio_engine_transport(bool streaming, bool suspended, uint32_t epoch) {
    uint32_t state = (epoch << 2) | (streaming ? 1u : 0u) | (suspended ? 2u : 0u);
    if (atomic_exchange_explicit(&transport_state, state, memory_order_acq_rel) != state) {
        __sev();
    }
}

bool nxs_audio_engine_host_controls(int16_t volume_q8_db, bool muted) {
    if (!nxs_host_volume_is_valid(volume_q8_db / (float)NXS_HOST_VOLUME_Q8_SCALE)) {
        return false;
    }
    nxs_render_control_t control = {
        .host_gain = powf(10, volume_q8_db / (NXS_HOST_VOLUME_Q8_SCALE * 20.0f)), .host_volume_q8_db = volume_q8_db, .host_muted = muted};
    bool accepted = queue_try_add(&host_control_queue, &control);
    if (accepted) {
        __sev();
    }
    return accepted;
}

bool nxs_audio_engine_receive(const uint8_t *packet, size_t length, uint8_t sample_bytes) {
    float stereo[NXS_AUDIO_USB_MAX_FRAMES * NXS_AUDIO_CHANNELS];
    size_t frames;
    bool accepted = nxs_audio_decode(packet, length, sample_bytes, stereo, NXS_AUDIO_USB_MAX_FRAMES, &frames) &&
                    nxs_audio_ring_write(&ring, stereo, frames);
    if (!accepted) {
        nxs_audio_engine_reject_packet();
    }
    return accepted;
}

void nxs_audio_engine_reject_packet(void) {
    atomic_fetch_add_explicit(&receive_overruns, 1, memory_order_relaxed);
}

uint32_t nxs_audio_engine_feedback(void) {
    return nxs_audio_feedback(nxs_audio_ring_count(&ring));
}
