#ifndef NXS_RENDER_H
#define NXS_RENDER_H

#include "nxs_audio.h"

typedef struct {
    uint32_t epoch;
    float host_gain;
    int16_t host_volume_q8_db;
    bool streaming;
    bool suspended;
    bool host_muted;
} nxs_render_control_t;

typedef struct {
    nxs_dsp_t dsp;
    nxs_audio_ring_t *ring;
    nxs_gain_ramp_t host_gain;
    nxs_gain_ramp_t transport_gain;
    nxs_runtime_status_t status;
    uint32_t epoch;
    float last_stereo[NXS_AUDIO_CHANNELS];
    bool streaming;
    bool primed;
    bool reset_pending;
} nxs_renderer_t;

/** The audio owner alone consumes the ring and renders complete mono I2S blocks. */
void nxs_renderer_init(nxs_renderer_t *renderer, nxs_audio_ring_t *ring);
/** Invalid controls leave both the renderer and output unchanged. */
bool nxs_renderer_process(nxs_renderer_t *renderer, const nxs_render_control_t *control, uint32_t *words);
/** The last block is silent and no transport or DSP transition remains. */
bool nxs_renderer_is_quiet(const nxs_renderer_t *renderer);

#endif
