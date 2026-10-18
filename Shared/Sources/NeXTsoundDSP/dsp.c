/*
 * SPDX-License-Identifier: GPL-3.0-only
 *
 * The transposed direct-form biquad step is adapted from WeebLabs/DSPi,
 * firmware/DSPi/dsp_biquad.h at 5d4dd00f82637fdf8d275f80aeaff0fd7b62719a.
 * NeXTsound adaptation dated 2026-10-18 uses a bounded mono chain without
 * upstream routing or platform-specific loop unrolling. See LICENSE.
 */

#include "nxs_dsp.h"

#include <math.h>
#include <string.h>

static const double pi = 3.14159265358979323846;

static nxs_biquad_coefficients_t identity(void) {
    return (nxs_biquad_coefficients_t){{1.0f, 0.0f, 0.0f}, {0.0f, 0.0f}};
}

static nxs_biquad_coefficients_t high_pass(double frequency_hz) {
    double angular = 2.0 * pi * frequency_hz / NXS_SAMPLE_RATE_HZ;
    double cosine = cos(angular);
    double alpha = sin(angular) / sqrt(2.0);
    double normalization = 1.0 + alpha;
    float outer = (float)((1.0 + cosine) / (2.0 * normalization));
    return (nxs_biquad_coefficients_t){{outer, (float)(-(1.0 + cosine) / normalization), outer},
                                       {(float)(-2.0 * cosine / normalization), (float)((1.0 - alpha) / normalization)}};
}

static nxs_biquad_coefficients_t peaking(const nxs_eq_band_t *band) {
    if (!band->enabled || band->gain_db == 0.0f) {
        return identity();
    }
    double angular = 2.0 * pi * band->frequency_hz / NXS_SAMPLE_RATE_HZ;
    double amplitude = pow(10.0, band->gain_db / 40.0);
    double alpha = sin(angular) / (2.0 * band->quality);
    double normalization = 1.0 + alpha / amplitude;
    float middle = (float)(-2.0 * cos(angular) / normalization);
    return (nxs_biquad_coefficients_t){
        {(float)((1.0 + alpha * amplitude) / normalization), middle, (float)((1.0 - alpha * amplitude) / normalization)},
        {middle, (float)((1.0 - alpha / amplitude) / normalization)}};
}

bool nxs_dsp_prepare(const nxs_snapshot_t *snapshot, nxs_dsp_configuration_t *configuration) {
    if (!configuration || !nxs_snapshot_is_valid(snapshot)) {
        return false;
    }
    nxs_dsp_configuration_t candidate = {0};
    candidate.filters[0] = snapshot->high_pass_enabled ? high_pass(snapshot->high_pass_hz) : identity();
    for (size_t band_index = 0; band_index < NXS_EQ_BAND_COUNT; ++band_index) {
        candidate.filters[band_index + 1] = peaking(&snapshot->bands[band_index]);
    }
    candidate.attenuation = powf(10.0f, snapshot->attenuation_db / 20.0f);
    candidate.ceiling = powf(10.0f, snapshot->limiter_threshold_db / 20.0f);
    candidate.release = expf(-1000.0f / (snapshot->limiter_release_ms * NXS_SAMPLE_RATE_HZ));
    candidate.muted = snapshot->muted != 0;
    *configuration = candidate;
    return true;
}

static void reset_chain_history(nxs_dsp_chain_t *chain) {
    memset(chain->delay, 0, sizeof(chain->delay));
    chain->limiter_gain = 1.0f;
}

void nxs_dsp_init(nxs_dsp_t *engine) {
    if (!engine) {
        return;
    }
    memset(engine, 0, sizeof(*engine));
    nxs_snapshot_t initial = nxs_default_snapshot();
    nxs_dsp_prepare(&initial, &engine->chains[0].configuration);
    reset_chain_history(&engine->chains[0]);
}

void nxs_dsp_reset_history(nxs_dsp_t *engine) {
    if (!engine) {
        return;
    }
    for (size_t chain = 0; chain < 2; ++chain) {
        reset_chain_history(&engine->chains[chain]);
    }
    engine->meter = (nxs_dsp_meter_t){0};
}

bool nxs_dsp_apply(nxs_dsp_t *engine, const nxs_dsp_configuration_t *configuration) {
    if (!engine || !configuration || engine->transition_remaining != 0) {
        return false;
    }
    nxs_dsp_configuration_t prepared = *configuration;
    nxs_dsp_chain_t *destination = &engine->chains[1u - engine->active_chain];
    memset(destination, 0, sizeof(*destination));
    destination->configuration = prepared;
    destination->limiter_gain = 1.0f;
    engine->transition_remaining = NXS_DSP_TRANSITION_FRAMES;
    return true;
}

static float flush_tiny(float value) {
    return fabsf(value) < 1.0e-20f ? 0.0f : value;
}

static float biquad(nxs_dsp_chain_t *chain, size_t filter_index, float sample) {
    const nxs_biquad_coefficients_t *coefficients = &chain->configuration.filters[filter_index];
    float *delay = chain->delay[filter_index];
    float output = coefficients->numerator[0] * sample + delay[0];
    delay[0] = flush_tiny(coefficients->numerator[1] * sample - coefficients->denominator[0] * output + delay[1]);
    delay[1] = flush_tiny(coefficients->numerator[2] * sample - coefficients->denominator[1] * output);
    return output;
}

static float clamp(float sample, float ceiling) {
    return fmaxf(-ceiling, fminf(ceiling, sample));
}

static float process_chain(nxs_dsp_chain_t *chain, float sample) {
    for (size_t filter_index = 0; filter_index < NXS_DSP_FILTER_COUNT; ++filter_index) {
        sample = biquad(chain, filter_index, sample);
    }
    sample *= chain->configuration.attenuation;
    if (!isfinite(sample)) {
        reset_chain_history(chain);
        return 0.0f;
    }
    float magnitude = fabsf(sample);
    float target = magnitude > chain->configuration.ceiling ? chain->configuration.ceiling / magnitude : 1.0f;
    if (target < chain->limiter_gain) {
        chain->limiter_gain = target;
    } else {
        chain->limiter_gain = target + chain->configuration.release * (chain->limiter_gain - target);
    }
    return chain->configuration.muted ? 0.0f : clamp(sample * chain->limiter_gain, chain->configuration.ceiling);
}

static float normalized(float sample) {
    return isfinite(sample) ? clamp(sample, 1.0f) : 0.0f;
}

bool nxs_dsp_process(nxs_dsp_t *engine, const float *stereo, float *mono, size_t frames) {
    if (!engine || frames > NXS_DSP_BLOCK_FRAMES || (frames != 0 && (!stereo || !mono))) {
        return false;
    }
    engine->meter = (nxs_dsp_meter_t){0};
    for (size_t frame_index = 0; frame_index < frames; ++frame_index) {
        float left = normalized(stereo[frame_index * 2]);
        float right = normalized(stereo[frame_index * 2 + 1]);
        engine->meter.input_peak = fmaxf(engine->meter.input_peak, fmaxf(fabsf(left), fabsf(right)));
        float sample = 0.5f * (left + right);
        nxs_dsp_chain_t *active = &engine->chains[engine->active_chain];
        float output = process_chain(active, sample);
        if (engine->transition_remaining != 0) {
            nxs_dsp_chain_t *next = &engine->chains[1u - engine->active_chain];
            float next_output = process_chain(next, sample);
            float progress = (float)(NXS_DSP_TRANSITION_FRAMES - engine->transition_remaining + 1u) / NXS_DSP_TRANSITION_FRAMES;
            output = output + progress * (next_output - output);
            output = clamp(output, next->configuration.ceiling);
            if (--engine->transition_remaining == 0) {
                engine->active_chain = 1u - engine->active_chain;
            }
        }
        mono[frame_index] = output;
        engine->meter.output_peak = fmaxf(engine->meter.output_peak, fabsf(output));
    }
    return true;
}

double nxs_dsp_eq_magnitude(const nxs_dsp_configuration_t *configuration, double frequency_hz) {
    if (!configuration || !isfinite(frequency_hz) || frequency_hz <= 0.0 || frequency_hz >= NXS_SAMPLE_RATE_HZ / 2.0) {
        return NAN;
    }
    double angular = 2.0 * pi * frequency_hz / NXS_SAMPLE_RATE_HZ;
    double cosine = cos(angular), sine = sin(angular);
    double cosine_double = cos(2.0 * angular), sine_double = sin(2.0 * angular);
    double magnitude = 1.0;
    for (size_t filter_index = 0; filter_index < NXS_DSP_FILTER_COUNT; ++filter_index) {
        const nxs_biquad_coefficients_t *coefficients = &configuration->filters[filter_index];
        double numerator_real =
            coefficients->numerator[0] + coefficients->numerator[1] * cosine + coefficients->numerator[2] * cosine_double;
        double numerator_imaginary = -coefficients->numerator[1] * sine - coefficients->numerator[2] * sine_double;
        double denominator_real = 1.0 + coefficients->denominator[0] * cosine + coefficients->denominator[1] * cosine_double;
        double denominator_imaginary = -coefficients->denominator[0] * sine - coefficients->denominator[1] * sine_double;
        magnitude *= sqrt((numerator_real * numerator_real + numerator_imaginary * numerator_imaginary) /
                          (denominator_real * denominator_real + denominator_imaginary * denominator_imaginary));
    }
    return magnitude;
}
