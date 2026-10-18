#include "nxs_audio.h"
#include "nxs_test.h"

#include <math.h>
#include <pthread.h>
#include <sched.h>
#include <string.h>

static void test_pcm_conversion(void) {
    const uint8_t pcm16[] = {0xff, 0x7f, 0, 0x80, 0, 0, 0, 0x40};
    float stereo[4];
    size_t frames = 99;
    CHECK(nxs_audio_decode(pcm16, sizeof(pcm16), 2, stereo, 2, &frames));
    CHECK(frames == 2 && stereo[0] == 32767.0f / 32768.0f && stereo[1] == -1);
    CHECK(stereo[2] == 0 && stereo[3] == 0.5f);
    const uint8_t pcm24[] = {0xff, 0xff, 0x7f, 0, 0, 0x80, 0, 0, 0, 0, 0, 0x40};
    CHECK(nxs_audio_decode(pcm24, sizeof(pcm24), 3, stereo, 2, &frames));
    CHECK(frames == 2 && stereo[0] == 8388607.0f / 8388608.0f && stereo[1] == -1);
    CHECK(stereo[2] == 0 && stereo[3] == 0.5f);
    float previous[4];
    memcpy(previous, stereo, sizeof(previous));
    frames = 99;
    CHECK(!nxs_audio_decode(pcm24, sizeof(pcm24) - 1, 3, stereo, 2, &frames));
    CHECK(frames == 99 && memcmp(previous, stereo, sizeof(previous)) == 0);
    CHECK(!nxs_audio_decode(pcm24, sizeof(pcm24), 4, stereo, 2, &frames));
    CHECK(!nxs_audio_decode(pcm24, sizeof(pcm24), 3, stereo, 1, &frames));
    CHECK(nxs_audio_i2s_sample(0.5f) == UINT32_C(0x40000000));
    CHECK(nxs_audio_i2s_sample(-0.5f) == UINT32_C(0xc0000000));
    CHECK(nxs_audio_i2s_sample(1.0f) == UINT32_C(0x7fffffff));
    CHECK(nxs_audio_i2s_sample(-1.0f) == UINT32_C(0x80000000));
    CHECK(nxs_audio_i2s_sample(NAN) == 0 && nxs_audio_i2s_sample(INFINITY) == 0);
}

static void test_ring_wrap_and_discard(void) {
    nxs_audio_ring_t ring;
    nxs_audio_ring_init(&ring);
    atomic_store(&ring.read_index, UINT32_MAX - 31u);
    atomic_store(&ring.write_index, UINT32_MAX - 31u);
    float input[NXS_AUDIO_RING_FRAMES * NXS_AUDIO_CHANNELS];
    float output[NXS_AUDIO_RING_FRAMES * NXS_AUDIO_CHANNELS];
    for (size_t index = 0; index < NXS_AUDIO_RING_FRAMES * NXS_AUDIO_CHANNELS; ++index) {
        input[index] = (float)index;
    }
    CHECK(nxs_audio_ring_write(&ring, input, NXS_AUDIO_RING_FRAMES));
    CHECK(nxs_audio_ring_count(&ring) == NXS_AUDIO_RING_FRAMES);
    CHECK(!nxs_audio_ring_write(&ring, input, 1));
    CHECK(nxs_audio_ring_read(&ring, output, NXS_AUDIO_RING_FRAMES) == NXS_AUDIO_RING_FRAMES);
    CHECK(memcmp(input, output, sizeof(input)) == 0 && nxs_audio_ring_count(&ring) == 0);
    CHECK(nxs_audio_ring_write(&ring, input, 100));
    CHECK(nxs_audio_ring_read(&ring, output, 40) == 40);
    nxs_audio_ring_discard(&ring);
    CHECK(nxs_audio_ring_count(&ring) == 0);
    CHECK(nxs_audio_ring_read(&ring, output, 1) == 0);
}

typedef struct {
    nxs_audio_ring_t ring;
    _Atomic bool failed;
} concurrent_fixture_t;

static void *producer(void *context) {
    concurrent_fixture_t *fixture = context;
    for (uint32_t sequence = 0; sequence < 10000; ++sequence) {
        float stereo[2] = {(float)sequence, -(float)sequence};
        while (!nxs_audio_ring_write(&fixture->ring, stereo, 1)) {
            sched_yield();
        }
    }
    return NULL;
}

static void *consumer(void *context) {
    concurrent_fixture_t *fixture = context;
    for (uint32_t sequence = 0; sequence < 10000; ++sequence) {
        float stereo[2];
        while (nxs_audio_ring_read(&fixture->ring, stereo, 1) == 0) {
            sched_yield();
        }
        if (stereo[0] != (float)sequence || stereo[1] != -(float)sequence) {
            atomic_store(&fixture->failed, true);
        }
    }
    return NULL;
}

static void test_concurrent_ring(void) {
    concurrent_fixture_t fixture;
    nxs_audio_ring_init(&fixture.ring);
    atomic_init(&fixture.failed, false);
    pthread_t producer_thread, consumer_thread;
    CHECK(pthread_create(&producer_thread, NULL, producer, &fixture) == 0);
    CHECK(pthread_create(&consumer_thread, NULL, consumer, &fixture) == 0);
    CHECK(pthread_join(producer_thread, NULL) == 0);
    CHECK(pthread_join(consumer_thread, NULL) == 0);
    CHECK(!atomic_load(&fixture.failed) && nxs_audio_ring_count(&fixture.ring) == 0);
}

static void test_feedback(void) {
    uint32_t nominal = 48u << 16;
    CHECK(nxs_audio_feedback(NXS_AUDIO_TARGET_FRAMES) == nominal);
    CHECK(nxs_audio_feedback(0) > nominal);
    CHECK(nxs_audio_feedback(NXS_AUDIO_RING_FRAMES) < nominal);
    for (size_t count = 0; count <= NXS_AUDIO_RING_FRAMES; ++count) {
        uint32_t feedback = nxs_audio_feedback(count);
        CHECK(feedback >= nominal - 16384u && feedback <= nominal + 16384u);
    }
    double fractional_samples = 0;
    size_t queued = 0;
    for (size_t frame = 0; frame < 10000; ++frame) {
        fractional_samples += (double)nxs_audio_feedback(queued) / 65536.0;
        size_t received = (size_t)fractional_samples;
        fractional_samples -= received;
        queued += received;
        size_t consumed = queued < NXS_DSP_BLOCK_FRAMES ? queued : NXS_DSP_BLOCK_FRAMES;
        queued -= consumed;
        CHECK(queued < NXS_AUDIO_RING_FRAMES);
    }
    CHECK(queued >= NXS_AUDIO_TARGET_FRAMES - 2 && queued <= NXS_AUDIO_TARGET_FRAMES + 2);
}

static void test_gain_ramps(void) {
    nxs_gain_ramp_t ramp;
    nxs_gain_init(&ramp, 0);
    nxs_gain_target(&ramp, 1);
    float previous = 0;
    for (size_t frame = 0; frame < NXS_DSP_TRANSITION_FRAMES; ++frame) {
        float value = nxs_gain_next(&ramp);
        CHECK(value >= previous && value <= 1);
        CHECK(value - previous < 0.005f);
        previous = value;
    }
    CHECK(ramp.value == 1 && ramp.remaining == 0);
    nxs_gain_target(&ramp, NAN);
    for (size_t frame = 0; frame < NXS_DSP_TRANSITION_FRAMES; ++frame) {
        CHECK(nxs_gain_next(&ramp) >= 0);
    }
    CHECK(ramp.value == 0 && ramp.remaining == 0);
}

static void test_maintenance_tokens(void) {
    nxs_audio_maintenance_t maintenance;
    nxs_audio_maintenance_init(&maintenance);
    CHECK(!nxs_audio_maintenance_requested(&maintenance) && !nxs_audio_maintenance_ready(&maintenance));
    nxs_audio_maintenance_request(&maintenance, true);
    uint32_t first = atomic_load(&maintenance.request_token);
    CHECK(first != 0 && nxs_audio_maintenance_requested(&maintenance));
    CHECK(!nxs_audio_maintenance_ready(&maintenance));
    nxs_audio_maintenance_acknowledge(&maintenance, true);
    CHECK(nxs_audio_maintenance_ready(&maintenance));
    nxs_audio_maintenance_request(&maintenance, true);
    CHECK(atomic_load(&maintenance.request_token) == first && nxs_audio_maintenance_ready(&maintenance));
    nxs_audio_maintenance_request(&maintenance, false);
    CHECK(!nxs_audio_maintenance_requested(&maintenance) && !nxs_audio_maintenance_ready(&maintenance));
    nxs_audio_maintenance_request(&maintenance, true);
    CHECK(atomic_load(&maintenance.request_token) != first);
    CHECK(!nxs_audio_maintenance_ready(&maintenance));
    nxs_audio_maintenance_acknowledge(&maintenance, false);
    CHECK(!nxs_audio_maintenance_ready(&maintenance));
    nxs_audio_maintenance_acknowledge(&maintenance, true);
    CHECK(nxs_audio_maintenance_ready(&maintenance));
    nxs_audio_maintenance_request(&maintenance, false);
    maintenance.next_token = UINT32_MAX;
    atomic_store(&maintenance.acknowledged_token, 1);
    nxs_audio_maintenance_request(&maintenance, true);
    CHECK(atomic_load(&maintenance.request_token) == 2 && !nxs_audio_maintenance_ready(&maintenance));
    nxs_audio_maintenance_acknowledge(&maintenance, true);
    CHECK(nxs_audio_maintenance_ready(&maintenance));
}

int main(void) {
    test_maintenance_tokens();
    test_pcm_conversion();
    test_ring_wrap_and_discard();
    test_concurrent_ring();
    test_feedback();
    test_gain_ramps();
    return nxs_test_finish("Audio buffer");
}
