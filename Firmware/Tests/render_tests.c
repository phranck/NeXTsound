#include "nxs_render.h"
#include "nxs_test.h"

#include <math.h>
#include <string.h>

typedef struct {
    nxs_audio_ring_t ring;
    nxs_renderer_t renderer;
    nxs_render_control_t control;
    uint32_t words[NXS_DSP_BLOCK_FRAMES * NXS_AUDIO_CHANNELS];
} fixture_t;

static void process(fixture_t *fixture) {
    CHECK(nxs_renderer_process(&fixture->renderer, &fixture->control, fixture->words));
    for (size_t frame = 0; frame < NXS_DSP_BLOCK_FRAMES; ++frame) {
        CHECK(fixture->words[frame * 2] == fixture->words[frame * 2 + 1]);
    }
}

static void enqueue(fixture_t *fixture, size_t frames) {
    float stereo[NXS_AUDIO_RING_FRAMES * NXS_AUDIO_CHANNELS];
    for (size_t frame = 0; frame < frames; ++frame) {
        stereo[frame * 2] = 0.25f;
        stereo[frame * 2 + 1] = 0.125f;
    }
    CHECK(nxs_audio_ring_write(&fixture->ring, stereo, frames));
}

static void initialize(fixture_t *fixture) {
    memset(fixture, 0, sizeof(*fixture));
    nxs_audio_ring_init(&fixture->ring);
    nxs_renderer_init(&fixture->renderer, &fixture->ring);
    fixture->control.host_gain = 1;
    fixture->control.epoch = 1;
    nxs_snapshot_t snapshot = nxs_default_snapshot();
    snapshot.muted = 0;
    snapshot.high_pass_enabled = 0;
    snapshot.attenuation_db = 0;
    nxs_dsp_configuration_t configuration;
    CHECK(nxs_dsp_prepare(&snapshot, &configuration));
    CHECK(nxs_dsp_apply(&fixture->renderer.dsp, &configuration));
    for (size_t block = 0; block < 5; ++block) {
        process(fixture);
    }
    fixture->control.streaming = true;
    ++fixture->control.epoch;
    process(fixture);
    enqueue(fixture, NXS_AUDIO_TARGET_FRAMES);
    for (size_t block = 0; block < 6; ++block) {
        enqueue(fixture, NXS_DSP_BLOCK_FRAMES);
        process(fixture);
    }
    CHECK(fixture->words[NXS_DSP_BLOCK_FRAMES * 2 - 1] == nxs_audio_i2s_sample(0.1875f));
}

static void check_silent(const fixture_t *fixture) {
    for (size_t word = 0; word < NXS_DSP_BLOCK_FRAMES * NXS_AUDIO_CHANNELS; ++word) {
        CHECK(fixture->words[word] == 0);
    }
}

static void test_boot_and_invalid_control(void) {
    fixture_t fixture = {0};
    nxs_audio_ring_init(&fixture.ring);
    nxs_renderer_init(&fixture.renderer, &fixture.ring);
    fixture.control = (nxs_render_control_t){.epoch = 1, .host_gain = 1, .streaming = true};
    process(&fixture);
    enqueue(&fixture, NXS_AUDIO_TARGET_FRAMES);
    process(&fixture);
    check_silent(&fixture);
    CHECK(fixture.renderer.status.underrun_count == 0);
    nxs_renderer_t before;
    memcpy(&before, &fixture.renderer, sizeof(before));
    fixture.control.host_gain = NAN;
    CHECK(!nxs_renderer_process(&fixture.renderer, &fixture.control, fixture.words));
    CHECK(memcmp(&before, &fixture.renderer, sizeof(before)) == 0);
    fixture.control.host_gain = 1;
    fixture.control.host_volume_q8_db = 1;
    CHECK(!nxs_renderer_process(&fixture.renderer, &fixture.control, fixture.words));
}

static void test_mute_and_volume_without_profile_changes(void) {
    fixture_t fixture;
    initialize(&fixture);
    fixture.control.host_muted = true;
    for (size_t block = 0; block < 6; ++block) {
        enqueue(&fixture, NXS_DSP_BLOCK_FRAMES);
        process(&fixture);
    }
    check_silent(&fixture);
    CHECK(fixture.renderer.status.host_muted == 1);
    CHECK(!fixture.renderer.dsp.chains[fixture.renderer.dsp.active_chain].configuration.muted);
    fixture.control.host_muted = false;
    fixture.control.host_volume_q8_db = -6 * 256;
    fixture.control.host_gain = powf(10.0f, -6.0f / 20.0f);
    for (size_t block = 0; block < 6; ++block) {
        enqueue(&fixture, NXS_DSP_BLOCK_FRAMES);
        process(&fixture);
    }
    CHECK(fixture.words[NXS_DSP_BLOCK_FRAMES * 2 - 1] == nxs_audio_i2s_sample(0.1875f * fixture.control.host_gain));
    CHECK(fixture.renderer.status.host_volume_db == -6 && fixture.renderer.status.underrun_count == 0);
}

static void test_stop_suspend_resume_and_epoch(void) {
    fixture_t fixture;
    initialize(&fixture);
    fixture.control.suspended = true;
    ++fixture.control.epoch;
    uint32_t previous = fixture.words[NXS_DSP_BLOCK_FRAMES * 2 - 1];
    for (size_t block = 0; block < 6; ++block) {
        process(&fixture);
        for (size_t frame = 0; frame < NXS_DSP_BLOCK_FRAMES; ++frame) {
            uint32_t word = fixture.words[frame * 2];
            CHECK(word <= previous);
            CHECK(previous - word < 0x00200000u);
            previous = word;
        }
    }
    check_silent(&fixture);
    CHECK(nxs_renderer_is_quiet(&fixture.renderer));
    CHECK(nxs_audio_ring_count(&fixture.ring) == 0);
    CHECK(fixture.renderer.status.streaming == 0 && fixture.renderer.status.underrun_count == 0);
    fixture.control.suspended = false;
    ++fixture.control.epoch;
    process(&fixture);
    enqueue(&fixture, NXS_AUDIO_TARGET_FRAMES);
    for (size_t block = 0; block < 6; ++block) {
        enqueue(&fixture, NXS_DSP_BLOCK_FRAMES);
        process(&fixture);
    }
    CHECK(fixture.words[NXS_DSP_BLOCK_FRAMES * 2 - 1] == nxs_audio_i2s_sample(0.1875f));
    fixture.control.streaming = false;
    for (size_t block = 0; block < 6; ++block) {
        process(&fixture);
    }
    CHECK(nxs_renderer_is_quiet(&fixture.renderer));
    check_silent(&fixture);
}

static void test_underrun_drains_and_reprimes(void) {
    fixture_t fixture;
    initialize(&fixture);
    for (size_t block = 0; block < 11; ++block) {
        process(&fixture);
    }
    CHECK(fixture.renderer.status.underrun_count == 1);
    CHECK(nxs_renderer_is_quiet(&fixture.renderer));
    check_silent(&fixture);
    enqueue(&fixture, NXS_AUDIO_TARGET_FRAMES);
    for (size_t block = 0; block < 6; ++block) {
        enqueue(&fixture, NXS_DSP_BLOCK_FRAMES);
        process(&fixture);
    }
    CHECK(fixture.words[NXS_DSP_BLOCK_FRAMES * 2 - 1] == nxs_audio_i2s_sample(0.1875f));
    CHECK(fixture.renderer.status.underrun_count == 1);
}

int main(void) {
    test_boot_and_invalid_control();
    test_mute_and_volume_without_profile_changes();
    test_stop_suspend_resume_and_epoch();
    test_underrun_drains_and_reprimes();
    return nxs_test_finish("Audio renderer");
}
