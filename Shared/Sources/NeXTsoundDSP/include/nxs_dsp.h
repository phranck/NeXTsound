#ifndef NXS_DSP_H
#define NXS_DSP_H

#include "nxs_protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

#define NXS_DSP_FILTER_COUNT (NXS_EQ_BAND_COUNT + 1u)
#define NXS_DSP_BLOCK_FRAMES 48u
#define NXS_DSP_TRANSITION_FRAMES (5u * NXS_DSP_BLOCK_FRAMES)
#define NXS_DSP_BLOCK_DEADLINE_US (NXS_DSP_BLOCK_FRAMES * 1000000u / NXS_SAMPLE_RATE_HZ)

typedef struct {
    float numerator[3];
    float denominator[2];
} nxs_biquad_coefficients_t;

typedef struct {
    nxs_biquad_coefficients_t filters[NXS_DSP_FILTER_COUNT];
    float attenuation;
    float ceiling;
    float release;
    bool muted;
} nxs_dsp_configuration_t;

typedef struct {
    nxs_dsp_configuration_t configuration;
    float delay[NXS_DSP_FILTER_COUNT][2];
    float limiter_gain;
} nxs_dsp_chain_t;

typedef struct {
    float input_peak;
    float output_peak;
} nxs_dsp_meter_t;

typedef struct {
    nxs_dsp_chain_t chains[2];
    nxs_dsp_meter_t meter;
    uint32_t transition_remaining;
    uint8_t active_chain;
} nxs_dsp_t;

/** Compute off the audio thread. Rejection leaves the destination unchanged. */
bool nxs_dsp_prepare(const nxs_snapshot_t *snapshot, nxs_dsp_configuration_t *configuration);
/** Initialize a muted engine. The caller owns the engine on the audio thread. */
void nxs_dsp_init(nxs_dsp_t *engine);
/** Apply a prepared configuration at a block boundary. False means a transition is already active. */
bool nxs_dsp_apply(nxs_dsp_t *engine, const nxs_dsp_configuration_t *configuration);
/** Process at most one bounded block of normalized interleaved stereo into mono. */
bool nxs_dsp_process(nxs_dsp_t *engine, const float *stereo, float *mono, size_t frames);
/** Linear high-pass/EQ magnitude only. Invalid frequencies return NaN. */
double nxs_dsp_eq_magnitude(const nxs_dsp_configuration_t *configuration, double frequency_hz);

#ifdef __cplusplus
}
#endif
#endif
