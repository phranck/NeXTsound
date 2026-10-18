#include "hardware/clocks.h"
#include "nxs_dsp.h"
#include "pico/stdlib.h"

static nxs_dsp_t engine;
static volatile uint32_t probe_processing_us;
static volatile uint32_t probe_clock_hz;
static volatile float probe_output_peak;

int main(void) {
    set_sys_clock_hz(NXS_SYSTEM_CLOCK_HZ, true);
    probe_clock_hz = clock_get_hz(clk_sys);
    if (probe_clock_hz != NXS_SYSTEM_CLOCK_HZ) {
        panic("Unexpected system clock");
    }
    nxs_dsp_init(&engine);
    nxs_snapshot_t settings = nxs_default_snapshot();
    settings.high_pass_enabled = 1;
    for (size_t band = 0; band < NXS_EQ_BAND_COUNT; ++band) {
        settings.bands[band].gain_db = 12.0f;
        settings.bands[band].quality = 10.0f;
    }
    nxs_dsp_configuration_t configuration;
    if (!nxs_dsp_prepare(&settings, &configuration) || !nxs_dsp_apply(&engine, &configuration)) {
        panic("Invalid DSP probe configuration");
    }
    float stereo[NXS_DSP_BLOCK_FRAMES * 2];
    float mono[NXS_DSP_BLOCK_FRAMES];
    for (size_t frame = 0; frame < NXS_DSP_BLOCK_FRAMES; ++frame) {
        stereo[frame * 2] = stereo[frame * 2 + 1] = frame & 1u ? 0.25f : -0.25f;
    }
    while (true) {
        uint32_t start = time_us_32();
        if (!nxs_dsp_process(&engine, stereo, mono, NXS_DSP_BLOCK_FRAMES)) {
            panic("DSP probe block rejected");
        }
        uint32_t elapsed = time_us_32() - start;
        if (elapsed > probe_processing_us) {
            probe_processing_us = elapsed;
        }
        probe_output_peak = engine.meter.output_peak;
        sleep_us(NXS_DSP_BLOCK_DEADLINE_US);
    }
}
