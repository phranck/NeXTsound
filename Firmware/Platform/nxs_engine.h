#ifndef NXS_ENGINE_H
#define NXS_ENGINE_H

#include "nxs_render.h"

/** Initialize on the control core, then transfer DSP and output ownership to core 1. */
void nxs_audio_engine_init(void);
bool nxs_audio_engine_submit(const nxs_dsp_configuration_t *configuration);
bool nxs_audio_engine_take_result(bool *accepted);
void nxs_audio_engine_status(nxs_runtime_status_t *status);
void nxs_audio_engine_transport(bool streaming, bool suspended, uint32_t epoch);
bool nxs_audio_engine_host_controls(int16_t volume_q8_db, bool muted);
bool nxs_audio_engine_receive(const uint8_t *packet, size_t length, uint8_t sample_bytes);
void nxs_audio_engine_reject_packet(void);
uint32_t nxs_audio_engine_feedback(void);

#endif
