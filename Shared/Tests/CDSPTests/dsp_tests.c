#include "nxs_dsp.h"
#include "nxs_test.h"

#include <math.h>
#include <string.h>

static nxs_snapshot_t flat_snapshot(void) {
    nxs_snapshot_t snapshot = nxs_default_snapshot();
    snapshot.muted = 0;
    snapshot.attenuation_db = 0.0f;
    snapshot.limiter_threshold_db = -1.0f;
    return snapshot;
}

static void configure(nxs_dsp_t *engine, const nxs_snapshot_t *snapshot) {
    nxs_dsp_init(engine);
    nxs_dsp_configuration_t configuration;
    CHECK(nxs_dsp_prepare(snapshot, &configuration));
    CHECK(nxs_dsp_apply(engine, &configuration));
    float stereo[NXS_DSP_BLOCK_FRAMES * 2] = {0};
    float mono[NXS_DSP_BLOCK_FRAMES];
    for (size_t block = 0; block < NXS_DSP_TRANSITION_FRAMES / NXS_DSP_BLOCK_FRAMES; ++block) {
        CHECK(nxs_dsp_process(engine, stereo, mono, NXS_DSP_BLOCK_FRAMES));
    }
    CHECK(engine->transition_remaining == 0);
}

static void test_initial_mute_and_averaging(void) {
    nxs_dsp_t engine;
    nxs_dsp_init(&engine);
    float stereo[] = {0.5f, 0.5f, -0.5f, -0.5f, 0.5f, -0.5f, 0.5f, 0.0f};
    float mono[4];
    CHECK(nxs_dsp_process(&engine, stereo, mono, 4));
    for (size_t index = 0; index < 4; ++index) {
        CHECK(mono[index] == 0.0f);
    }
    nxs_snapshot_t snapshot = flat_snapshot();
    configure(&engine, &snapshot);
    CHECK(nxs_dsp_process(&engine, stereo, mono, 4));
    CHECK(fabsf(mono[0] - 0.5f) < 1.0e-6f);
    CHECK(fabsf(mono[1] + 0.5f) < 1.0e-6f);
    CHECK(mono[2] == 0.0f);
    CHECK(fabsf(mono[3] - 0.25f) < 1.0e-6f);
    CHECK(engine.meter.input_peak == 0.5f && engine.meter.output_peak == 0.5f);
}

static void test_filter_response(void) {
    nxs_snapshot_t snapshot = flat_snapshot();
    nxs_dsp_configuration_t configuration;
    CHECK(nxs_dsp_prepare(&snapshot, &configuration));
    CHECK(fabs(nxs_dsp_eq_magnitude(&configuration, 1000.0) - 1.0) < 1.0e-6);
    snapshot.bands[2].gain_db = 6.0f;
    CHECK(nxs_dsp_prepare(&snapshot, &configuration));
    CHECK(fabs(20.0 * log10(nxs_dsp_eq_magnitude(&configuration, 1000.0)) - 6.0) < 0.001);
    snapshot.bands[2].gain_db = -6.0f;
    CHECK(nxs_dsp_prepare(&snapshot, &configuration));
    CHECK(fabs(20.0 * log10(nxs_dsp_eq_magnitude(&configuration, 1000.0)) + 6.0) < 0.001);
    snapshot.bands[2].enabled = 0;
    snapshot.high_pass_enabled = 1;
    snapshot.high_pass_hz = 100.0f;
    CHECK(nxs_dsp_prepare(&snapshot, &configuration));
    CHECK(fabs(20.0 * log10(nxs_dsp_eq_magnitude(&configuration, 100.0)) + 3.0103) < 0.02);
    CHECK(nxs_dsp_eq_magnitude(&configuration, 10.0) < 0.011);
    CHECK(nxs_dsp_eq_magnitude(&configuration, 1000.0) > 0.99);
    CHECK(isnan(nxs_dsp_eq_magnitude(&configuration, NAN)));
    CHECK(isnan(nxs_dsp_eq_magnitude(&configuration, 0)));
    CHECK(isnan(nxs_dsp_eq_magnitude(&configuration, 24000)));
}

static void test_configuration_alias(void) {
    nxs_dsp_t engine;
    nxs_dsp_init(&engine);
    nxs_snapshot_t snapshot = flat_snapshot();
    nxs_dsp_configuration_t *slot = &engine.chains[1].configuration;
    CHECK(nxs_dsp_prepare(&snapshot, slot));
    float expected_ceiling = slot->ceiling;
    CHECK(nxs_dsp_apply(&engine, slot));
    CHECK(engine.chains[1].configuration.ceiling == expected_ceiling);
}

static double measured_gain(const nxs_snapshot_t *snapshot, double frequency) {
    nxs_dsp_t engine;
    configure(&engine, snapshot);
    double input_energy = 0, output_energy = 0;
    float stereo[NXS_DSP_BLOCK_FRAMES * 2], mono[NXS_DSP_BLOCK_FRAMES];
    for (size_t block = 0; block < 500; ++block) {
        for (size_t frame = 0; frame < NXS_DSP_BLOCK_FRAMES; ++frame) {
            size_t sample_index = block * NXS_DSP_BLOCK_FRAMES + frame;
            float sample = (float)(0.001 * sin(6.283185307179586 * frequency * sample_index / NXS_SAMPLE_RATE_HZ));
            stereo[frame * 2] = stereo[frame * 2 + 1] = sample;
        }
        CHECK(nxs_dsp_process(&engine, stereo, mono, NXS_DSP_BLOCK_FRAMES));
        if (block >= 250) {
            for (size_t frame = 0; frame < NXS_DSP_BLOCK_FRAMES; ++frame) {
                input_energy += (double)stereo[frame * 2] * stereo[frame * 2];
                output_energy += (double)mono[frame] * mono[frame];
            }
        }
    }
    return sqrt(output_energy / input_energy);
}

static void test_processed_signals_match_response(void) {
    nxs_snapshot_t snapshot = flat_snapshot();
    snapshot.high_pass_enabled = 1;
    snapshot.high_pass_hz = 100;
    snapshot.bands[2].gain_db = 6;
    nxs_dsp_configuration_t configuration;
    CHECK(nxs_dsp_prepare(&snapshot, &configuration));
    const double frequencies[] = {100, 1000, 10000};
    for (size_t index = 0; index < sizeof(frequencies) / sizeof(frequencies[0]); ++index) {
        double expected = nxs_dsp_eq_magnitude(&configuration, frequencies[index]);
        CHECK(fabs(measured_gain(&snapshot, frequencies[index]) / expected - 1.0) < 0.002);
    }
    nxs_dsp_t engine;
    configure(&engine, &snapshot);
    float stereo[NXS_DSP_BLOCK_FRAMES * 2], mono[NXS_DSP_BLOCK_FRAMES];
    for (size_t index = 0; index < NXS_DSP_BLOCK_FRAMES * 2; ++index) {
        stereo[index] = 0.1f;
    }
    for (size_t block = 0; block < 200; ++block) {
        CHECK(nxs_dsp_process(&engine, stereo, mono, NXS_DSP_BLOCK_FRAMES));
    }
    /* Float32 delay states allow a small DC residue; require 100 dB rejection relative to the 0.1 input. */
    CHECK(fabsf(mono[NXS_DSP_BLOCK_FRAMES - 1]) < 0.1f * 1.0e-5f);
}

static void test_limiter_and_release(void) {
    nxs_snapshot_t snapshot = flat_snapshot();
    snapshot.limiter_threshold_db = -12.0f;
    snapshot.limiter_release_ms = 10.0f;
    nxs_dsp_t engine;
    configure(&engine, &snapshot);
    float stereo[] = {1.0f, 1.0f};
    float mono[1];
    float ceiling = powf(10.0f, -12.0f / 20.0f);
    CHECK(nxs_dsp_process(&engine, stereo, mono, 1));
    CHECK(mono[0] <= ceiling && fabsf(mono[0] - ceiling) < 1.0e-6f);
    stereo[0] = stereo[1] = 0.1f;
    for (size_t frame = 0; frame < NXS_SAMPLE_RATE_HZ / 10; ++frame) {
        CHECK(nxs_dsp_process(&engine, stereo, mono, 1));
        CHECK(isfinite(mono[0]) && fabsf(mono[0]) <= ceiling);
    }
    CHECK(mono[0] > 0.099f);
}

static void test_transition_and_busy(void) {
    nxs_snapshot_t snapshot = flat_snapshot();
    nxs_dsp_t engine;
    configure(&engine, &snapshot);
    snapshot.attenuation_db = -6.0f;
    nxs_dsp_configuration_t configuration;
    CHECK(nxs_dsp_prepare(&snapshot, &configuration));
    CHECK(nxs_dsp_apply(&engine, &configuration));
    CHECK(!nxs_dsp_apply(&engine, &configuration));
    float stereo[] = {0.1f, 0.1f};
    float mono[1];
    float previous = 0.1f;
    for (size_t frame = 0; frame < NXS_DSP_TRANSITION_FRAMES; ++frame) {
        CHECK(nxs_dsp_process(&engine, stereo, mono, 1));
        CHECK(mono[0] <= previous + 1.0e-6f && fabsf(mono[0] - previous) < 0.001f);
        previous = mono[0];
    }
    CHECK(fabsf(mono[0] - 0.1f * powf(10.0f, -6.0f / 20.0f)) < 1.0e-6f);
    snapshot.muted = 1;
    CHECK(nxs_dsp_prepare(&snapshot, &configuration));
    CHECK(nxs_dsp_apply(&engine, &configuration));
    for (size_t frame = 0; frame < NXS_DSP_TRANSITION_FRAMES; ++frame) {
        CHECK(nxs_dsp_process(&engine, stereo, mono, 1));
    }
    CHECK(mono[0] == 0.0f);
}

static void test_invalid_data_and_bounds(void) {
    nxs_snapshot_t snapshot = flat_snapshot();
    nxs_dsp_configuration_t configuration;
    CHECK(nxs_dsp_prepare(&snapshot, &configuration));
    nxs_dsp_configuration_t previous;
    memcpy(&previous, &configuration, sizeof(previous));
    snapshot.bands[0].quality = NAN;
    CHECK(!nxs_dsp_prepare(&snapshot, &configuration));
    CHECK(memcmp(&configuration, &previous, sizeof(previous)) == 0);
    CHECK(!nxs_dsp_prepare(NULL, &configuration));
    CHECK(!nxs_dsp_prepare(&snapshot, NULL));
    snapshot = flat_snapshot();
    nxs_dsp_t engine;
    configure(&engine, &snapshot);
    float stereo[] = {NAN, INFINITY, -INFINITY, 0.1f, 20.0f, -20.0f};
    float mono[3];
    CHECK(nxs_dsp_process(&engine, stereo, mono, 3));
    CHECK(mono[0] == 0.0f && fabsf(mono[1] - 0.05f) < 1.0e-6f && mono[2] == 0.0f);
    nxs_dsp_t saved;
    memcpy(&saved, &engine, sizeof(engine));
    CHECK(!nxs_dsp_process(&engine, stereo, mono, NXS_DSP_BLOCK_FRAMES + 1));
    CHECK(memcmp(&saved, &engine, sizeof(engine)) == 0);
    CHECK(!nxs_dsp_process(&engine, NULL, mono, 1));
    CHECK(!nxs_dsp_process(&engine, stereo, NULL, 1));
}

static void test_history_reset_preserves_settings(void) {
    nxs_snapshot_t snapshot = flat_snapshot();
    snapshot.high_pass_enabled = 1;
    snapshot.high_pass_hz = 100;
    nxs_dsp_t engine, reference;
    configure(&engine, &snapshot);
    configure(&reference, &snapshot);
    float stereo[NXS_DSP_BLOCK_FRAMES * 2], mono[NXS_DSP_BLOCK_FRAMES], expected[NXS_DSP_BLOCK_FRAMES];
    for (size_t index = 0; index < NXS_DSP_BLOCK_FRAMES * 2; ++index) {
        stereo[index] = 0.1f;
    }
    for (size_t block = 0; block < 10; ++block) {
        CHECK(nxs_dsp_process(&engine, stereo, mono, NXS_DSP_BLOCK_FRAMES));
    }
    nxs_dsp_reset_history(&engine);
    CHECK(engine.meter.output_peak == 0 && engine.transition_remaining == 0);
    CHECK(nxs_dsp_process(&engine, stereo, mono, NXS_DSP_BLOCK_FRAMES));
    CHECK(nxs_dsp_process(&reference, stereo, expected, NXS_DSP_BLOCK_FRAMES));
    CHECK(memcmp(mono, expected, sizeof(mono)) == 0);
}

static void test_maximum_configuration(void) {
    nxs_snapshot_t snapshot = flat_snapshot();
    snapshot.high_pass_enabled = 1;
    snapshot.high_pass_hz = 20;
    snapshot.limiter_threshold_db = -36;
    for (size_t band = 0; band < NXS_EQ_BAND_COUNT; ++band) {
        snapshot.bands[band].frequency_hz = 20;
        snapshot.bands[band].gain_db = 12;
        snapshot.bands[band].quality = 10;
    }
    nxs_dsp_t engine;
    configure(&engine, &snapshot);
    float ceiling = powf(10, -36.0f / 20.0f);
    float stereo[NXS_DSP_BLOCK_FRAMES * 2];
    float mono[NXS_DSP_BLOCK_FRAMES];
    for (size_t block = 0; block < 2000; ++block) {
        for (size_t frame = 0; frame < NXS_DSP_BLOCK_FRAMES; ++frame) {
            float sample = sinf((float)(block * NXS_DSP_BLOCK_FRAMES + frame) * 0.00261799388f);
            stereo[frame * 2] = stereo[frame * 2 + 1] = sample;
        }
        CHECK(nxs_dsp_process(&engine, stereo, mono, NXS_DSP_BLOCK_FRAMES));
        for (size_t frame = 0; frame < NXS_DSP_BLOCK_FRAMES; ++frame) {
            CHECK(isfinite(mono[frame]) && fabsf(mono[frame]) <= ceiling);
        }
    }
}

static void test_parameter_corners(void) {
    for (unsigned int corner = 0; corner < 16; ++corner) {
        nxs_snapshot_t snapshot = flat_snapshot();
        snapshot.high_pass_enabled = 1;
        snapshot.high_pass_hz = corner & 1u ? 5000.0f : 20.0f;
        for (size_t band = 0; band < NXS_EQ_BAND_COUNT; ++band) {
            snapshot.bands[band].frequency_hz = corner & 2u ? 20000.0f : 20.0f;
            snapshot.bands[band].gain_db = corner & 4u ? 12.0f : -12.0f;
            snapshot.bands[band].quality = corner & 8u ? 10.0f : 0.2f;
        }
        nxs_dsp_t engine;
        configure(&engine, &snapshot);
        uint32_t noise_state = 1;
        float stereo[NXS_DSP_BLOCK_FRAMES * 2], mono[NXS_DSP_BLOCK_FRAMES];
        float ceiling = powf(10.0f, snapshot.limiter_threshold_db / 20.0f);
        for (size_t block = 0; block < 128; ++block) {
            for (size_t frame = 0; frame < NXS_DSP_BLOCK_FRAMES; ++frame) {
                noise_state = noise_state * 1664525u + 1013904223u;
                float sample = (float)(noise_state >> 8) / 8388608.0f - 1.0f;
                stereo[frame * 2] = stereo[frame * 2 + 1] = sample;
            }
            CHECK(nxs_dsp_process(&engine, stereo, mono, NXS_DSP_BLOCK_FRAMES));
            for (size_t frame = 0; frame < NXS_DSP_BLOCK_FRAMES; ++frame) {
                CHECK(isfinite(mono[frame]) && fabsf(mono[frame]) <= ceiling);
            }
        }
    }
}

int main(void) {
    test_initial_mute_and_averaging();
    test_filter_response();
    test_configuration_alias();
    test_processed_signals_match_response();
    test_limiter_and_release();
    test_transition_and_busy();
    test_invalid_data_and_bounds();
    test_history_reset_preserves_settings();
    test_maximum_configuration();
    test_parameter_corners();
    return nxs_test_finish("DSP");
}
