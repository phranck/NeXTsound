#ifndef NXS_AUDIO_H
#define NXS_AUDIO_H

#include "nxs_dsp.h"
#include <stdatomic.h>

#define NXS_AUDIO_RING_FRAMES 512u
#define NXS_AUDIO_TARGET_FRAMES (4u * NXS_DSP_BLOCK_FRAMES)
#define NXS_AUDIO_USB_MAX_FRAMES (NXS_DSP_BLOCK_FRAMES + 1u)
#define NXS_AUDIO_CHANNELS 2u
#define NXS_HOST_VOLUME_Q8_SCALE 256u
#define NXS_HOST_VOLUME_MIN_Q8_DB ((int16_t)(NXS_HOST_VOLUME_MIN_DB * NXS_HOST_VOLUME_Q8_SCALE))
#define NXS_HOST_VOLUME_MAX_Q8_DB ((int16_t)(NXS_HOST_VOLUME_MAX_DB * NXS_HOST_VOLUME_Q8_SCALE))
#define NXS_I2S_BITS_PER_SLOT 32u
#define NXS_I2S_CYCLES_PER_FRAME (NXS_AUDIO_CHANNELS * NXS_I2S_BITS_PER_SLOT * 2u)

typedef struct {
    _Atomic uint32_t read_index;
    _Atomic uint32_t write_index;
    float stereo[NXS_AUDIO_RING_FRAMES * NXS_AUDIO_CHANNELS];
} nxs_audio_ring_t;

typedef struct {
    _Atomic uint32_t request_token;
    _Atomic uint32_t acknowledged_token;
    uint32_t next_token;
} nxs_audio_maintenance_t;

void nxs_audio_maintenance_init(nxs_audio_maintenance_t *maintenance);
/** Control owner only. Repeated requests keep their token until released. */
void nxs_audio_maintenance_request(nxs_audio_maintenance_t *maintenance, bool requested);
bool nxs_audio_maintenance_requested(const nxs_audio_maintenance_t *maintenance);
/** Audio owner acknowledges only after stopping DMA/PIO and clears before output restart. */
void nxs_audio_maintenance_acknowledge(nxs_audio_maintenance_t *maintenance, bool paused);
bool nxs_audio_maintenance_ready(const nxs_audio_maintenance_t *maintenance);

typedef struct {
    float value;
    float target;
    float step;
    uint32_t remaining;
} nxs_gain_ramp_t;

void nxs_gain_init(nxs_gain_ramp_t *ramp, float value);
void nxs_gain_target(nxs_gain_ramp_t *ramp, float target);
float nxs_gain_next(nxs_gain_ramp_t *ramp);

/** One producer and one consumer. Discard belongs to the consumer. */
void nxs_audio_ring_init(nxs_audio_ring_t *ring);
size_t nxs_audio_ring_count(const nxs_audio_ring_t *ring);
bool nxs_audio_ring_write(nxs_audio_ring_t *ring, const float *stereo, size_t frames);
size_t nxs_audio_ring_read(nxs_audio_ring_t *ring, float *stereo, size_t frames);
void nxs_audio_ring_discard(nxs_audio_ring_t *ring);
/** USB PCM16 and packed PCM24. Invalid packets leave output and frame count unchanged. */
bool nxs_audio_decode(const uint8_t *packet, size_t length, uint8_t sample_bytes, float *stereo, size_t capacity, size_t *frames);
uint32_t nxs_audio_i2s_sample(float mono);
/** The nominal rate in 16.16 samples per USB frame, which the host keeps while the ring sits at its target. */
uint32_t nxs_audio_nominal_feedback(void);
/** Manual feedback in 16.16 samples per USB frame. */
uint32_t nxs_audio_feedback(size_t queued_frames);

#endif
