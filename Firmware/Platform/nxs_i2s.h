#ifndef NXS_I2S_H
#define NXS_I2S_H

#include "nxs_audio.h"

#define NXS_I2S_DATA_PIN 6u
#define NXS_I2S_BCLK_PIN 14u
#define NXS_I2S_LRCLK_PIN 15u

/** The audio core owns this single-DMA, double-buffered output. */
void nxs_i2s_init(void);
void nxs_i2s_start(void);
void nxs_i2s_pause(void);
uint32_t *nxs_i2s_next_buffer(void);
void nxs_i2s_send_prepared(void);
uint32_t nxs_i2s_stall_count(void);

#endif
