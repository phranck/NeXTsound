#include "nxs_i2s.h"

#include "hardware/clocks.h"
#include "hardware/dma.h"
#include "hardware/pio.h"
#include "i2s.pio.h"
#include "pico/stdlib.h"

#include <string.h>

static PIO audio_pio = pio0;
static uint state_machine;
static uint program_offset;
static uint dma_channel;
static pio_sm_config state_configuration;
static dma_channel_config_t dma_configuration;
static uint32_t output_buffers[2][NXS_DSP_BLOCK_FRAMES * NXS_AUDIO_CHANNELS];
static uint active_buffer;
static uint32_t stall_count;

_Static_assert(NXS_I2S_LRCLK_PIN == NXS_I2S_BCLK_PIN + 1, "I2S side-set pins must be consecutive");
_Static_assert(((uint64_t)NXS_SYSTEM_CLOCK_HZ * 256u) % (NXS_SAMPLE_RATE_HZ * NXS_I2S_CYCLES_PER_FRAME) == 0,
               "The chosen clock requires an exact 16.8 PIO divider");

static uint32_t pin_mask(void) {
    return (1u << NXS_I2S_DATA_PIN) | (1u << NXS_I2S_BCLK_PIN) | (1u << NXS_I2S_LRCLK_PIN);
}

void nxs_i2s_init(void) {
    state_machine = (uint)pio_claim_unused_sm(audio_pio, true);
    int offset = pio_add_program(audio_pio, &nxs_i2s_program);
    if (offset < 0 || clock_get_hz(clk_sys) != NXS_SYSTEM_CLOCK_HZ) {
        panic("Invalid I2S program or clock");
    }
    program_offset = (uint)offset;
    state_configuration = nxs_i2s_program_get_default_config(program_offset);
    sm_config_set_out_pins(&state_configuration, NXS_I2S_DATA_PIN, 1);
    sm_config_set_sideset_pins(&state_configuration, NXS_I2S_BCLK_PIN);
    sm_config_set_out_shift(&state_configuration, false, true, NXS_I2S_BITS_PER_SLOT);
    sm_config_set_fifo_join(&state_configuration, PIO_FIFO_JOIN_TX);
    uint32_t divisor = (uint32_t)(((uint64_t)NXS_SYSTEM_CLOCK_HZ * 256u) / (NXS_SAMPLE_RATE_HZ * NXS_I2S_CYCLES_PER_FRAME));
    sm_config_set_clkdiv_int_frac8(&state_configuration, divisor >> 8, (uint8_t)divisor);
    pio_gpio_init(audio_pio, NXS_I2S_DATA_PIN);
    pio_gpio_init(audio_pio, NXS_I2S_BCLK_PIN);
    pio_gpio_init(audio_pio, NXS_I2S_LRCLK_PIN);
    if (pio_sm_set_consecutive_pindirs(audio_pio, state_machine, NXS_I2S_DATA_PIN, 1, true) != PICO_OK ||
        pio_sm_set_consecutive_pindirs(audio_pio, state_machine, NXS_I2S_BCLK_PIN, 2, true) != PICO_OK) {
        panic("Invalid I2S pins");
    }
    dma_channel = (uint)dma_claim_unused_channel(true);
    dma_configuration = dma_channel_get_default_config(dma_channel);
    channel_config_set_transfer_data_size(&dma_configuration, DMA_SIZE_32);
    channel_config_set_read_increment(&dma_configuration, true);
    channel_config_set_write_increment(&dma_configuration, false);
    channel_config_set_dreq(&dma_configuration, pio_get_dreq(audio_pio, state_machine, true));
    dma_channel_configure(dma_channel, &dma_configuration, &audio_pio->txf[state_machine], output_buffers[0],
                          dma_encode_transfer_count(NXS_DSP_BLOCK_FRAMES * NXS_AUDIO_CHANNELS), false);
}

void nxs_i2s_start(void) {
    memset(output_buffers, 0, sizeof(output_buffers));
    active_buffer = 0;
    if (pio_sm_init(audio_pio, state_machine, program_offset, &state_configuration) != PICO_OK) {
        panic("I2S state machine initialization failed");
    }
    pio_sm_set_pins_with_mask(audio_pio, state_machine, 0, pin_mask());
    dma_channel_set_config(dma_channel, &dma_configuration, false);
    dma_channel_transfer_from_buffer_now(dma_channel, output_buffers[0],
                                         dma_encode_transfer_count(NXS_DSP_BLOCK_FRAMES * NXS_AUDIO_CHANNELS));
    uint32_t started = time_us_32();
    while (pio_sm_is_tx_fifo_empty(audio_pio, state_machine)) {
        if (time_us_32() - started > NXS_DSP_BLOCK_DEADLINE_US) {
            panic("I2S DMA did not prefill the FIFO");
        }
    }
    audio_pio->fdebug = 1u << (PIO_FDEBUG_TXSTALL_LSB + state_machine);
    pio_sm_set_enabled(audio_pio, state_machine, true);
}

void nxs_i2s_pause(void) {
    dma_channel_wait_for_finish_blocking(dma_channel);
    uint32_t started = time_us_32();
    uint32_t drained = 1u << (PIO_FDEBUG_TXSTALL_LSB + state_machine);
    while (!(audio_pio->fdebug & drained)) {
        if (time_us_32() - started > NXS_DSP_BLOCK_DEADLINE_US) {
            ++stall_count;
            break;
        }
    }
    dma_channel_config_t disabled = dma_configuration;
    channel_config_set_enable(&disabled, false);
    dma_channel_set_config(dma_channel, &disabled, false);
    dma_channel_abort(dma_channel);
    pio_sm_set_enabled(audio_pio, state_machine, false);
    pio_sm_clear_fifos(audio_pio, state_machine);
    pio_sm_set_pins_with_mask(audio_pio, state_machine, 0, pin_mask());
}

uint32_t *nxs_i2s_next_buffer(void) {
    return output_buffers[1u - active_buffer];
}

void nxs_i2s_send_prepared(void) {
    dma_channel_wait_for_finish_blocking(dma_channel);
    uint32_t stalled = 1u << (PIO_FDEBUG_TXSTALL_LSB + state_machine);
    if (audio_pio->fdebug & stalled) {
        ++stall_count;
        audio_pio->fdebug = stalled;
    }
    active_buffer = 1u - active_buffer;
    dma_channel_transfer_from_buffer_now(dma_channel, output_buffers[active_buffer],
                                         dma_encode_transfer_count(NXS_DSP_BLOCK_FRAMES * NXS_AUDIO_CHANNELS));
}

uint32_t nxs_i2s_stall_count(void) {
    return stall_count;
}
