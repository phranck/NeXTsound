#include "nxs_protocol.h"
#include "nxs_test.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static void test_golden_message(const char *fixture_path) {
    uint8_t expected[NXS_REPORT_SIZE];
    nxs_test_read_hex(fixture_path, expected, sizeof(expected));
    nxs_message_t request = {0};
    request.operation = NXS_OPERATION_CAPABILITIES;
    request.request_id = 0x01020304;
    request.generation = 0x11223344;
    uint8_t report[NXS_REPORT_SIZE];
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    CHECK(memcmp(report, expected, sizeof(report)) == 0);
    nxs_message_t decoded;
    CHECK(nxs_message_decode(expected, sizeof(expected), &decoded) == NXS_RESULT_OK);
    CHECK(decoded.request_id == request.request_id);
    CHECK(decoded.generation == request.generation);
    CHECK(decoded.operation == request.operation);
    CHECK(decoded.payload_length == 0);
}

static void test_message_rejection(void) {
    nxs_message_t request = {0};
    request.operation = NXS_OPERATION_READ_STATE;
    request.request_id = 1;
    uint8_t report[NXS_REPORT_SIZE];
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    nxs_message_t destination;
    memset(&destination, 0xa5, sizeof(destination));
    nxs_message_t previous;
    memcpy(&previous, &destination, sizeof(previous));
    for (size_t length = 0; length < NXS_REPORT_SIZE; ++length) {
        CHECK(nxs_message_decode(report, length, &destination) == NXS_RESULT_INVALID_REPORT);
        CHECK(memcmp(&destination, &previous, sizeof(destination)) == 0);
    }
    const size_t invalid_offsets[] = {0, 4, 8, 10, 255};
    for (size_t offset_index = 0; offset_index < sizeof(invalid_offsets) / sizeof(invalid_offsets[0]); ++offset_index) {
        size_t offset = invalid_offsets[offset_index];
        uint8_t saved = report[offset];
        report[offset] = 0xff;
        CHECK(nxs_message_decode(report, sizeof(report), &destination) == NXS_RESULT_INVALID_REPORT);
        CHECK(memcmp(&destination, &previous, sizeof(destination)) == 0);
        report[offset] = saved;
    }
    report[1] = 2;
    CHECK(nxs_message_decode(report, sizeof(report), &destination) == NXS_RESULT_UNSUPPORTED_VERSION);
    report[1] = NXS_PROTOCOL_MAJOR;
    report[3] = 0xff;
    CHECK(nxs_message_decode(report, sizeof(report), &destination) == NXS_RESULT_UNKNOWN_OPERATION);
    CHECK(nxs_message_decode(NULL, sizeof(report), &destination) == NXS_RESULT_INVALID_REPORT);
    CHECK(nxs_message_decode(report, sizeof(report), NULL) == NXS_RESULT_INVALID_REPORT);
    request.request_id = 0;
    memset(report, 0xa5, sizeof(report));
    uint8_t previous_report[NXS_REPORT_SIZE];
    memcpy(previous_report, report, sizeof(report));
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_INVALID_REPORT);
    CHECK(memcmp(report, previous_report, sizeof(report)) == 0);
    request.request_id = 1;
    request.result = NXS_RESULT_BUSY;
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_INVALID_REPORT);
    request.flags = NXS_FLAG_RESPONSE;
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
}

static void test_snapshot_roundtrip(void) {
    nxs_snapshot_t original = nxs_default_snapshot();
    original.profile_revision = 0x01020304;
    for (size_t byte_index = 0; byte_index < sizeof(original.profile_id); ++byte_index) {
        original.profile_id[byte_index] = (uint8_t)byte_index;
    }
    original.bands[2].gain_db = 3.5f;
    CHECK(original.muted == 1);
    uint8_t first[NXS_SNAPSHOT_SIZE];
    uint8_t second[NXS_SNAPSHOT_SIZE];
    CHECK(nxs_snapshot_encode(&original, first, sizeof(first)) == NXS_RESULT_OK);
    CHECK(first[16] == 4 && first[17] == 3 && first[18] == 2 && first[19] == 1);
    CHECK(first[24] == 0 && first[25] == 0 && first[26] == 0xa0 && first[27] == 0x42);
    nxs_snapshot_t decoded;
    CHECK(nxs_snapshot_decode(first, sizeof(first), &decoded) == NXS_RESULT_OK);
    CHECK(nxs_snapshot_encode(&decoded, second, sizeof(second)) == NXS_RESULT_OK);
    CHECK(memcmp(first, second, sizeof(first)) == 0);
}

static void test_snapshot_rejection(void) {
    nxs_snapshot_t original = nxs_default_snapshot();
    const float invalid_values[] = {NAN, INFINITY, -INFINITY, 0.0f, 25000.0f};
    for (size_t value_index = 0; value_index < sizeof(invalid_values) / sizeof(invalid_values[0]); ++value_index) {
        original.bands[0].frequency_hz = invalid_values[value_index];
        CHECK(!nxs_snapshot_is_valid(&original));
    }
    original = nxs_default_snapshot();
    original.muted = 2;
    CHECK(!nxs_snapshot_is_valid(&original));
    original = nxs_default_snapshot();
    uint8_t payload[NXS_SNAPSHOT_SIZE];
    CHECK(nxs_snapshot_encode(&original, payload, sizeof(payload)) == NXS_RESULT_OK);
    nxs_snapshot_t destination;
    memset(&destination, 0xa5, sizeof(destination));
    nxs_snapshot_t previous;
    memcpy(&previous, &destination, sizeof(previous));
    payload[22] = 1;
    CHECK(nxs_snapshot_decode(payload, sizeof(payload), &destination) == NXS_RESULT_INVALID_REPORT);
    CHECK(memcmp(&destination, &previous, sizeof(destination)) == 0);
    payload[22] = 0;
    payload[27] = 0x7f;
    payload[26] = 0xc0;
    CHECK(nxs_snapshot_decode(payload, sizeof(payload), &destination) == NXS_RESULT_INVALID_PARAMETERS);
    CHECK(memcmp(&destination, &previous, sizeof(destination)) == 0);
    CHECK(nxs_snapshot_decode(payload, sizeof(payload) - 1, &destination) == NXS_RESULT_INVALID_REPORT);
}

static nxs_capabilities_t test_capabilities(void) {
    nxs_capabilities_t capabilities = nxs_default_capabilities();
    strcpy(capabilities.device_serial, "TESTDEVICE");
    strcpy(capabilities.firmware_version, "test");
    return capabilities;
}

static void test_capability_validation(void) {
    nxs_capabilities_t original = test_capabilities();
    uint8_t payload[NXS_CAPABILITIES_SIZE];
    CHECK(nxs_capabilities_encode(&original, payload, sizeof(payload)) == NXS_RESULT_OK);
    nxs_capabilities_t decoded;
    CHECK(nxs_capabilities_decode(payload, sizeof(payload), &decoded) == NXS_RESULT_OK);
    CHECK(strcmp(decoded.device_serial, original.device_serial) == 0);
    CHECK(decoded.sample_rate_hz == NXS_SAMPLE_RATE_HZ);
    CHECK(decoded.device_name[0] == 0);
    payload[104] = 1;
    CHECK(nxs_capabilities_decode(payload, sizeof(payload), &decoded) == NXS_RESULT_INVALID_PARAMETERS);
    strcpy(original.device_name, "Bedroom SoundBox");
    CHECK(nxs_capabilities_encode(&original, payload, sizeof(payload)) == NXS_RESULT_OK);
    CHECK(nxs_capabilities_decode(payload, sizeof(payload), &decoded) == NXS_RESULT_OK);
    CHECK(strcmp(decoded.device_name, original.device_name) == 0);
    original.feature_flags = NXS_FEATURE_PERSISTENCE;
    CHECK(nxs_capabilities_encode(&original, payload, sizeof(payload)) == NXS_RESULT_INVALID_PARAMETERS);
    original.feature_flags = NXS_FEATURE_FLASH_VERIFIED;
    CHECK(nxs_capabilities_encode(&original, payload, sizeof(payload)) == NXS_RESULT_INVALID_PARAMETERS);
    original.feature_flags |= NXS_FEATURE_PERSISTENCE;
    original.flash_size_bytes = 4 * 1024 * 1024;
    CHECK(nxs_capabilities_encode(&original, payload, sizeof(payload)) == NXS_RESULT_OK);
    original.ranges[NXS_PARAMETER_EQ_GAIN_DB].maximum = NAN;
    CHECK(nxs_capabilities_encode(&original, payload, sizeof(payload)) == NXS_RESULT_INVALID_PARAMETERS);
}

static void test_runtime_status(void) {
    CHECK(nxs_host_volume_is_valid(-80));
    CHECK(nxs_host_volume_is_valid(0));
    CHECK(!nxs_host_volume_is_valid(-80.1f));
    CHECK(!nxs_host_volume_is_valid(0.1f));
    CHECK(!nxs_host_volume_is_valid(NAN));
    CHECK(!nxs_host_volume_is_valid(INFINITY));
    CHECK(!nxs_host_volume_is_valid(-INFINITY));
    nxs_runtime_status_t original = {0};
    original.persisted_generation = 17;
    original.block_deadline_us = 1000;
    original.max_processing_us = 100;
    original.input_peak = 1.0f;
    original.output_peak = 0.5f;
    original.host_volume_db = -24.0f;
    original.host_muted = 1;
    uint8_t payload[NXS_RUNTIME_STATUS_SIZE];
    CHECK(nxs_runtime_status_encode(&original, payload, sizeof(payload)) == NXS_RESULT_OK);
    nxs_runtime_status_t decoded;
    CHECK(nxs_runtime_status_decode(payload, sizeof(payload), &decoded) == NXS_RESULT_OK);
    CHECK(decoded.persisted_generation == original.persisted_generation);
    CHECK(decoded.output_peak == original.output_peak);
    payload[39] = 1;
    CHECK(nxs_runtime_status_decode(payload, sizeof(payload), &decoded) == NXS_RESULT_INVALID_REPORT);
    original.input_peak = INFINITY;
    CHECK(nxs_runtime_status_encode(&original, payload, sizeof(payload)) == NXS_RESULT_INVALID_PARAMETERS);
}

static void test_diagnostic_payload(void) {
    nxs_runtime_diagnostics_t original = {.ring_underrun_count = 0x12345678u,
                                          .i2s_stall_count = 2,
                                          .rejected_packet_count = UINT32_MAX,
                                          .dsp_failure_count = 4,
                                          .deadline_miss_count = 5,
                                          .usb_suspend_count = 6,
                                          .usb_resume_count = 7};
    const uint8_t expected[NXS_RUNTIME_DIAGNOSTICS_SIZE] = {1, 0, 32, 0, 0x78, 0x56, 0x34, 0x12, 2, 0, 0, 0, 0xff, 0xff, 0xff, 0xff,
                                                            4, 0, 0,  0, 5,    0,    0,    0,    6, 0, 0, 0, 7,    0,    0,    0};
    uint8_t payload[NXS_RUNTIME_DIAGNOSTICS_SIZE];
    CHECK(nxs_runtime_diagnostics_encode(&original, payload, sizeof(payload)) == NXS_RESULT_OK);
    CHECK(memcmp(payload, expected, sizeof(payload)) == 0);
    nxs_runtime_diagnostics_t decoded;
    CHECK(nxs_runtime_diagnostics_decode(payload, sizeof(payload), &decoded) == NXS_RESULT_OK);
    CHECK(memcmp(&original, &decoded, sizeof(original)) == 0);
    for (size_t length = 0; length < sizeof(payload); ++length) {
        CHECK(nxs_runtime_diagnostics_decode(payload, length, &decoded) == NXS_RESULT_INVALID_REPORT);
        CHECK(memcmp(&original, &decoded, sizeof(original)) == 0);
    }
    payload[0] = 2;
    CHECK(nxs_runtime_diagnostics_decode(payload, sizeof(payload), &decoded) == NXS_RESULT_UNSUPPORTED_VERSION);
    CHECK(memcmp(&original, &decoded, sizeof(original)) == 0);
    payload[0] = 1;
    payload[2] = 31;
    CHECK(nxs_runtime_diagnostics_decode(payload, sizeof(payload), &decoded) == NXS_RESULT_INVALID_REPORT);
    CHECK(memcmp(&original, &decoded, sizeof(original)) == 0);
    CHECK(nxs_runtime_diagnostics_decode(NULL, sizeof(payload), &decoded) == NXS_RESULT_INVALID_REPORT);
    CHECK(nxs_runtime_diagnostics_decode(expected, sizeof(expected), NULL) == NXS_RESULT_INVALID_REPORT);
    memset(payload, 0xa5, sizeof(payload));
    CHECK(nxs_runtime_diagnostics_encode(NULL, payload, sizeof(payload)) == NXS_RESULT_INVALID_REPORT);
    CHECK(payload[0] == 0xa5 && payload[31] == 0xa5);
    CHECK(nxs_runtime_diagnostics_encode(&original, payload, sizeof(payload) - 1) == NXS_RESULT_INVALID_REPORT);
    CHECK(nxs_runtime_diagnostics_encode(&original, NULL, sizeof(payload)) == NXS_RESULT_INVALID_REPORT);
}

static void test_optional_protocol_revision(void) {
    nxs_message_t request = {.operation = NXS_OPERATION_CAPABILITIES, .request_id = 99};
    uint8_t report[NXS_REPORT_SIZE];
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    CHECK(report[2] == 0);
    report[2] = 1;
    nxs_message_t decoded;
    CHECK(nxs_message_decode(report, sizeof(report), &decoded) == NXS_RESULT_OK);
    CHECK(decoded.protocol_minor == 1);
    report[3] = NXS_OPERATION_DIAGNOSTICS;
    CHECK(nxs_message_decode(report, sizeof(report), &decoded) == NXS_RESULT_OK);
    CHECK(nxs_message_encode(&decoded, report, sizeof(report)) == NXS_RESULT_OK && report[2] == 1);
    decoded.protocol_minor = 0;
    CHECK(nxs_message_encode(&decoded, report, sizeof(report)) == NXS_RESULT_UNSUPPORTED_VERSION);
    report[2] = 0;
    CHECK(nxs_message_decode(report, sizeof(report), &decoded) == NXS_RESULT_UNSUPPORTED_VERSION);
    report[2] = 2;
    CHECK(nxs_message_decode(report, sizeof(report), &decoded) == NXS_RESULT_UNSUPPORTED_VERSION);
}

/** The operation numbers are wire values that installed firmware and apps already exchange. */
static void test_operation_numbers(void) {
    CHECK(NXS_OPERATION_STATUS == 5);
    CHECK(NXS_OPERATION_SET_NAME == 6);
    CHECK(NXS_OPERATION_DIAGNOSTICS == 7);
}

static void test_device_name(void) {
    char empty[NXS_DEVICE_NAME_LENGTH] = {0};
    CHECK(nxs_device_name_is_valid(empty));
    uint8_t payload[NXS_DEVICE_NAME_LENGTH];
    CHECK(nxs_device_name_encode(empty, payload, sizeof(payload)) == NXS_RESULT_OK);
    char decoded[NXS_DEVICE_NAME_LENGTH];
    CHECK(nxs_device_name_decode(payload, sizeof(payload), decoded) == NXS_RESULT_OK);
    CHECK(decoded[0] == 0);

    char name[NXS_DEVICE_NAME_LENGTH] = {0};
    strcpy(name, "Office SoundBox");
    CHECK(nxs_device_name_is_valid(name));
    CHECK(nxs_device_name_encode(name, payload, sizeof(payload)) == NXS_RESULT_OK);
    CHECK(payload[strlen(name)] == 0);
    CHECK(nxs_device_name_decode(payload, sizeof(payload), decoded) == NXS_RESULT_OK);
    CHECK(strcmp(decoded, name) == 0);

    char too_long[NXS_DEVICE_NAME_LENGTH];
    memset(too_long, 'A', sizeof(too_long));
    CHECK(!nxs_device_name_is_valid(too_long));
    CHECK(nxs_device_name_encode(too_long, payload, sizeof(payload)) == NXS_RESULT_INVALID_PARAMETERS);

    char control_character[NXS_DEVICE_NAME_LENGTH] = {0};
    control_character[0] = '\n';
    CHECK(!nxs_device_name_is_valid(control_character));
    CHECK(nxs_device_name_encode(control_character, payload, sizeof(payload)) == NXS_RESULT_INVALID_PARAMETERS);

    CHECK(nxs_device_name_decode(payload, sizeof(payload) - 1, decoded) == NXS_RESULT_INVALID_REPORT);
}

int main(int argument_count, char **arguments) {
    CHECK(argument_count == 2);
    test_golden_message(arguments[1]);
    test_message_rejection();
    test_snapshot_roundtrip();
    test_snapshot_rejection();
    test_capability_validation();
    test_runtime_status();
    test_optional_protocol_revision();
    test_operation_numbers();
    test_diagnostic_payload();
    test_device_name();
    return nxs_test_finish("Protocol");
}
