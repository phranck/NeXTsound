#include "nxs_render.h"

#include <math.h>
#include <string.h>

void nxs_renderer_init(nxs_renderer_t *renderer, nxs_audio_ring_t *ring) {
    memset(renderer, 0, sizeof(*renderer));
    renderer->ring = ring;
    renderer->epoch = UINT32_MAX;
    renderer->status.block_deadline_us = NXS_DSP_BLOCK_DEADLINE_US;
    nxs_dsp_init(&renderer->dsp);
    nxs_gain_init(&renderer->host_gain, 0);
    nxs_gain_init(&renderer->transport_gain, 0);
}

static void synchronize_transport(nxs_renderer_t *renderer, const nxs_render_control_t *control) {
    bool streaming = control->streaming && !control->suspended;
    if (control->epoch != renderer->epoch || streaming != renderer->streaming) {
        renderer->epoch = control->epoch;
        renderer->streaming = streaming;
        renderer->primed = false;
        renderer->reset_pending = true;
        nxs_audio_ring_discard(renderer->ring);
    }
    if (!streaming) {
        nxs_audio_ring_discard(renderer->ring);
    }
    if (renderer->reset_pending && renderer->transport_gain.value == 0 && renderer->transport_gain.remaining == 0) {
        nxs_dsp_reset_history(&renderer->dsp);
        memset(renderer->last_stereo, 0, sizeof(renderer->last_stereo));
        renderer->reset_pending = false;
    }
}

static void read_frames(nxs_renderer_t *renderer, float *stereo) {
    size_t received = 0;
    if (renderer->streaming && !renderer->reset_pending) {
        if (!renderer->primed && nxs_audio_ring_count(renderer->ring) >= NXS_AUDIO_TARGET_FRAMES) {
            renderer->primed = true;
        }
        if (renderer->primed) {
            received = nxs_audio_ring_read(renderer->ring, stereo, NXS_DSP_BLOCK_FRAMES);
            if (received != NXS_DSP_BLOCK_FRAMES) {
                ++renderer->status.underrun_count;
                renderer->primed = false;
                renderer->reset_pending = true;
            }
        }
    }
    if (received != 0) {
        memcpy(renderer->last_stereo, stereo + (received - 1) * NXS_AUDIO_CHANNELS, sizeof(renderer->last_stereo));
    }
    /* Repeat only while the output envelope drains. Quiescence clears this history before re-priming. */
    for (size_t frame = received; frame < NXS_DSP_BLOCK_FRAMES; ++frame) {
        memcpy(stereo + frame * NXS_AUDIO_CHANNELS, renderer->last_stereo, sizeof(renderer->last_stereo));
    }
}

static float encode_output(nxs_renderer_t *renderer, const float *mono, uint32_t *words) {
    float peak = 0;
    for (size_t frame = 0; frame < NXS_DSP_BLOCK_FRAMES; ++frame) {
        float sample = mono[frame] * nxs_gain_next(&renderer->transport_gain);
        peak = fmaxf(peak, fabsf(sample));
        uint32_t word = nxs_audio_i2s_sample(sample);
        words[frame * NXS_AUDIO_CHANNELS] = word;
        words[frame * NXS_AUDIO_CHANNELS + 1] = word;
    }
    return peak;
}

bool nxs_renderer_process(nxs_renderer_t *renderer, const nxs_render_control_t *control, uint32_t *words) {
    if (!renderer || !control || !words || !isfinite(control->host_gain) || control->host_gain < 0 || control->host_gain > 1 ||
        !nxs_host_volume_is_valid(control->host_volume_q8_db / (float)NXS_HOST_VOLUME_Q8_SCALE)) {
        return false;
    }
    synchronize_transport(renderer, control);
    float stereo[NXS_DSP_BLOCK_FRAMES * NXS_AUDIO_CHANNELS], mono[NXS_DSP_BLOCK_FRAMES];
    read_frames(renderer, stereo);
    nxs_gain_target(&renderer->host_gain, control->host_gain);
    nxs_gain_target(&renderer->transport_gain,
                    renderer->streaming && renderer->primed && !renderer->reset_pending && !control->host_muted ? 1 : 0);
    for (size_t frame = 0; frame < NXS_DSP_BLOCK_FRAMES; ++frame) {
        float gain = nxs_gain_next(&renderer->host_gain);
        stereo[frame * NXS_AUDIO_CHANNELS] *= gain;
        stereo[frame * NXS_AUDIO_CHANNELS + 1] *= gain;
    }
    if (!nxs_dsp_process(&renderer->dsp, stereo, mono, NXS_DSP_BLOCK_FRAMES)) {
        memset(mono, 0, sizeof(mono));
        ++renderer->status.overrun_count;
    }
    renderer->status.input_peak = renderer->dsp.meter.input_peak;
    renderer->status.output_peak = encode_output(renderer, mono, words);
    renderer->status.host_volume_db = control->host_volume_q8_db / (float)NXS_HOST_VOLUME_Q8_SCALE;
    renderer->status.host_muted = control->host_muted;
    renderer->status.streaming = renderer->streaming;
    return true;
}

nxs_audio_observation_t nxs_renderer_observe(const nxs_renderer_t *renderer, uint32_t maximum_us, uint32_t i2s_stalls,
                                             uint32_t rejected_packets, uint32_t deadline_misses) {
    nxs_audio_observation_t observation = {.status = renderer->status,
                                           .diagnostics = {.ring_underrun_count = renderer->status.underrun_count,
                                                           .i2s_stall_count = i2s_stalls,
                                                           .rejected_packet_count = rejected_packets,
                                                           .dsp_failure_count = renderer->status.overrun_count,
                                                           .deadline_miss_count = deadline_misses}};
    observation.status.underrun_count += i2s_stalls;
    observation.status.overrun_count += rejected_packets + deadline_misses;
    observation.status.max_processing_us = maximum_us;
    return observation;
}

bool nxs_renderer_is_quiet(const nxs_renderer_t *renderer) {
    return renderer->status.output_peak == 0 && renderer->transport_gain.value == 0 && renderer->transport_gain.remaining == 0 &&
           renderer->dsp.transition_remaining == 0 && !renderer->reset_pending;
}
