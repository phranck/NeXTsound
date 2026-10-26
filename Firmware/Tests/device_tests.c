#include "nxs_device.h"
#include "nxs_protocol_test.h"

#include <math.h>
#include <string.h>

static void init(nxs_device_t *device) {
    CHECK(nxs_device_init(device, "TESTDEVICE", "test"));
    CHECK(device->active.muted == 1 && device->generation == 1);
}

static void send(nxs_device_t *device, nxs_operation_t operation, uint32_t identifier, uint32_t generation,
                 const nxs_snapshot_t *snapshot) {
    uint8_t report[NXS_REPORT_SIZE];
    nxs_test_request(operation, identifier, generation, snapshot, report);
    CHECK(nxs_device_receive(device, report, sizeof(report)));
}

static nxs_message_t response(nxs_device_t *device, uint32_t identifier, nxs_result_t result) {
    uint8_t report[NXS_REPORT_SIZE];
    CHECK(nxs_device_response(device, report, sizeof(report)));
    return nxs_test_response(report, identifier, result);
}

static void send_name(nxs_device_t *device, uint32_t identifier, uint32_t generation, const char *name) {
    nxs_message_t request = {0};
    request.operation = NXS_OPERATION_SET_NAME;
    request.request_id = identifier;
    request.generation = generation;
    request.payload_length = NXS_DEVICE_NAME_LENGTH;
    if (name) {
        size_t length = strlen(name) < NXS_DEVICE_NAME_LENGTH ? strlen(name) : NXS_DEVICE_NAME_LENGTH - 1;
        memcpy(request.payload, name, length);
    }
    uint8_t report[NXS_REPORT_SIZE];
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    CHECK(nxs_device_receive(device, report, sizeof(report)));
}

static void test_discovery(void) {
    nxs_device_t device;
    init(&device);
    send(&device, NXS_OPERATION_CAPABILITIES, 1, 0, NULL);
    nxs_message_t reply = response(&device, 1, NXS_RESULT_OK);
    nxs_capabilities_t capabilities;
    CHECK(nxs_capabilities_decode(reply.payload, reply.payload_length, &capabilities) == NXS_RESULT_OK);
    CHECK(capabilities.feature_flags == 0 && capabilities.flash_size_bytes == 0);
    send(&device, NXS_OPERATION_READ_STATE, 2, 0, NULL);
    reply = response(&device, 2, NXS_RESULT_OK);
    nxs_snapshot_t snapshot;
    CHECK(nxs_snapshot_decode(reply.payload, reply.payload_length, &snapshot) == NXS_RESULT_OK);
    CHECK(snapshot.muted == 1 && reply.generation == 1);
    send(&device, NXS_OPERATION_PERSIST_STATE, 3, 1, NULL);
    response(&device, 3, NXS_RESULT_STORAGE_UNAVAILABLE);
}

static void test_apply_acknowledgement_and_duplicates(void) {
    nxs_device_t device;
    init(&device);
    send(&device, NXS_OPERATION_READ_STATE, 1, 0, NULL);
    nxs_snapshot_t snapshot = nxs_default_snapshot();
    snapshot.attenuation_db = -12;
    send(&device, NXS_OPERATION_APPLY_STATE, 2, 1, &snapshot);
    CHECK(device.generation == 1 && device.active.attenuation_db == nxs_default_snapshot().attenuation_db);
    CHECK(nxs_device_pending_configuration(&device) != NULL);
    response(&device, 1, NXS_RESULT_OK);
    send(&device, NXS_OPERATION_APPLY_STATE, 2, 1, &snapshot);
    CHECK(device.generation == 1);
    CHECK(nxs_device_complete_apply(&device, NXS_RESULT_OK));
    nxs_message_t reply = response(&device, 2, NXS_RESULT_OK);
    CHECK(reply.generation == 2 && device.active.attenuation_db == -12);
    send(&device, NXS_OPERATION_APPLY_STATE, 2, 1, &snapshot);
    response(&device, 2, NXS_RESULT_OK);
    CHECK(device.generation == 2 && !device.apply_pending);
    snapshot.attenuation_db = -6;
    send(&device, NXS_OPERATION_APPLY_STATE, 2, 2, &snapshot);
    response(&device, 2, NXS_RESULT_INVALID_REPORT);
    CHECK(device.active.attenuation_db == -12 && !device.apply_pending);
    send(&device, NXS_OPERATION_APPLY_STATE, 3, 1, &snapshot);
    response(&device, 3, NXS_RESULT_STALE_GENERATION);
    CHECK(device.generation == 2 && !device.apply_pending);
    for (uint32_t identifier = 10; identifier < 20; ++identifier) {
        send(&device, NXS_OPERATION_STATUS, identifier, 0, NULL);
    }
    send(&device, NXS_OPERATION_APPLY_STATE, 2, 1, &snapshot);
    response(&device, 2, NXS_RESULT_STALE_GENERATION);
    CHECK(device.generation == 2);
}

/* The board takes a Master Volume above full scale, up to the end of the shared range, which the limiter then catches. */
static void test_apply_gain_above_full_scale(void) {
    nxs_device_t device;
    init(&device);
    send(&device, NXS_OPERATION_READ_STATE, 1, 0, NULL);
    nxs_snapshot_t snapshot = nxs_default_snapshot();
    snapshot.attenuation_db = nxs_parameter_range(NXS_PARAMETER_ATTENUATION_DB).maximum;
    CHECK(snapshot.attenuation_db > 0.0f);
    send(&device, NXS_OPERATION_APPLY_STATE, 2, 1, &snapshot);
    response(&device, 1, NXS_RESULT_OK);
    CHECK(nxs_device_complete_apply(&device, NXS_RESULT_OK));
    nxs_message_t reply = response(&device, 2, NXS_RESULT_OK);
    CHECK(reply.generation == 2 && device.active.attenuation_db == snapshot.attenuation_db);
}

static void test_busy_failure_and_disconnect(void) {
    nxs_device_t device;
    init(&device);
    nxs_snapshot_t snapshot = nxs_default_snapshot();
    snapshot.attenuation_db = -10;
    send(&device, NXS_OPERATION_APPLY_STATE, 1, 1, &snapshot);
    send(&device, NXS_OPERATION_APPLY_STATE, 2, 1, &snapshot);
    response(&device, 2, NXS_RESULT_BUSY);
    CHECK(nxs_device_complete_apply(&device, NXS_RESULT_BUSY));
    response(&device, 1, NXS_RESULT_BUSY);
    CHECK(device.generation == 1 && device.active.attenuation_db == nxs_default_snapshot().attenuation_db);
    send(&device, NXS_OPERATION_APPLY_STATE, 3, 1, &snapshot);
    nxs_device_reset_session(&device);
    CHECK(nxs_device_complete_apply(&device, NXS_RESULT_OK));
    CHECK(device.generation == 2 && device.active.attenuation_db == -10);
    uint8_t report[NXS_REPORT_SIZE];
    CHECK(!nxs_device_response(&device, report, sizeof(report)));
    send(&device, NXS_OPERATION_READ_STATE, 1, 0, NULL);
    nxs_message_t reply = response(&device, 1, NXS_RESULT_OK);
    CHECK(reply.generation == 2);
    device.generation = UINT32_MAX;
    send(&device, NXS_OPERATION_APPLY_STATE, 4, UINT32_MAX, &snapshot);
    response(&device, 4, NXS_RESULT_BUSY);
    CHECK(!device.apply_pending && device.generation == UINT32_MAX);
}

static void test_malformed_requests_do_not_mutate_state(void) {
    nxs_device_t device;
    init(&device);
    nxs_device_t before;
    memcpy(&before, &device, sizeof(before));
    uint8_t report[NXS_REPORT_SIZE] = {0};
    CHECK(!nxs_device_receive(&device, report, sizeof(report)));
    CHECK(memcmp(&before, &device, sizeof(before)) == 0);
    nxs_message_t request = {0};
    request.operation = NXS_OPERATION_APPLY_STATE;
    request.request_id = 1;
    request.generation = 1;
    request.payload_length = NXS_SNAPSHOT_SIZE;
    CHECK(nxs_snapshot_encode(&device.active, request.payload, request.payload_length) == NXS_RESULT_OK);
    request.payload[22] = 1;
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    CHECK(nxs_device_receive(&device, report, sizeof(report)));
    response(&device, 1, NXS_RESULT_INVALID_PARAMETERS);
    CHECK(device.generation == 1 && device.active.muted == 1 && !device.apply_pending);
    request.flags = NXS_FLAG_RESPONSE;
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    memcpy(&before, &device, sizeof(before));
    CHECK(!nxs_device_receive(&device, report, sizeof(report)));
    CHECK(memcmp(&before, &device, sizeof(before)) == 0);
}

static void test_storage_boot_and_audio_status(void) {
    nxs_device_t device, before;
    init(&device);
    memcpy(&before, &device, sizeof(before));
    CHECK(!nxs_device_configure_storage(NULL, NXS_FLASH_SUPPORTED_BYTES, true, NULL));
    CHECK(!nxs_device_configure_storage(&device, 0, true, NULL));
    CHECK(!nxs_device_configure_storage(&device, NXS_FLASH_SUPPORTED_BYTES / 2, true, NULL));
    CHECK(memcmp(&before, &device, sizeof(before)) == 0);
    nxs_stored_state_t restored = {.snapshot = nxs_default_snapshot(), .generation = 0};
    CHECK(!nxs_device_configure_storage(&device, NXS_FLASH_SUPPORTED_BYTES, true, &restored));
    restored.generation = 19;
    restored.snapshot.high_pass_hz = NAN;
    CHECK(!nxs_device_configure_storage(&device, NXS_FLASH_SUPPORTED_BYTES, true, &restored));
    CHECK(memcmp(&before, &device, sizeof(before)) == 0);
    restored.snapshot = nxs_default_snapshot();
    restored.snapshot.attenuation_db = -9;
    CHECK(nxs_device_configure_storage(&device, NXS_FLASH_SUPPORTED_BYTES, true, &restored));
    CHECK(device.generation == 19 && device.status.persisted_generation == 19 && device.status.storage_available);
    CHECK(device.active.attenuation_db == -9 && device.active.muted == 1);
    send(&device, NXS_OPERATION_CAPABILITIES, 1, 0, NULL);
    nxs_message_t reply = response(&device, 1, NXS_RESULT_OK);
    nxs_capabilities_t capabilities;
    CHECK(nxs_capabilities_decode(reply.payload, reply.payload_length, &capabilities) == NXS_RESULT_OK);
    CHECK(capabilities.flash_size_bytes == NXS_FLASH_SUPPORTED_BYTES);
    CHECK(capabilities.feature_flags == (NXS_FEATURE_FLASH_VERIFIED | NXS_FEATURE_PERSISTENCE));
    CHECK(!nxs_device_configure_storage(&device, 0, false, NULL));
    nxs_runtime_status_t audio = {.underrun_count = 3,
                                  .input_peak = 0.25f,
                                  .output_peak = 0.125f,
                                  .host_volume_db = -12,
                                  .host_muted = 1,
                                  .block_deadline_us = NXS_DSP_BLOCK_DEADLINE_US};
    CHECK(nxs_device_update_audio_status(&device, &audio));
    CHECK(device.status.persisted_generation == 19 && device.status.storage_available);
    CHECK(device.status.underrun_count == 3 && device.status.host_volume_db == -12 && device.status.host_muted);
    memcpy(&before, &device, sizeof(before));
    audio.input_peak = NAN;
    CHECK(!nxs_device_update_audio_status(&device, &audio));
    CHECK(memcmp(&before, &device, sizeof(before)) == 0);
    CHECK(!nxs_device_update_audio_status(NULL, &audio));
    CHECK(!nxs_device_update_audio_status(&device, NULL));

    init(&device);
    CHECK(nxs_device_configure_storage(&device, NXS_FLASH_SUPPORTED_BYTES, false, &restored));
    CHECK(device.capabilities.feature_flags == (NXS_FEATURE_FLASH_VERIFIED | NXS_FEATURE_DIAGNOSTICS) && !device.status.storage_available);
    CHECK(device.generation == 19 && device.status.persisted_generation == 19);
    send(&device, NXS_OPERATION_PERSIST_STATE, 1, 19, NULL);
    response(&device, 1, NXS_RESULT_STORAGE_UNAVAILABLE);
}

static void test_persistence_acknowledgement(void) {
    nxs_device_t device;
    init(&device);
    CHECK(nxs_device_configure_storage(&device, NXS_FLASH_SUPPORTED_BYTES, true, NULL));
    nxs_stored_state_t pending = {.generation = 777};
    CHECK(!nxs_device_pending_persistence(&device, &pending) && pending.generation == 777);
    send(&device, NXS_OPERATION_READ_STATE, 1, 0, NULL);
    send(&device, NXS_OPERATION_PERSIST_STATE, 2, 1, NULL);
    CHECK(device.persistence_pending && !device.apply_pending && device.status.persisted_generation == 0);
    CHECK(nxs_device_pending_persistence(&device, &pending));
    CHECK(pending.generation == 1 && pending.snapshot.attenuation_db == nxs_default_snapshot().attenuation_db &&
          pending.snapshot.muted == 1);
    response(&device, 1, NXS_RESULT_OK);
    send(&device, NXS_OPERATION_PERSIST_STATE, 2, 1, NULL);
    nxs_snapshot_t next = nxs_default_snapshot();
    next.attenuation_db = -12;
    send(&device, NXS_OPERATION_APPLY_STATE, 3, 1, &next);
    response(&device, 3, NXS_RESULT_BUSY);
    send(&device, NXS_OPERATION_PERSIST_STATE, 4, 1, NULL);
    response(&device, 4, NXS_RESULT_BUSY);
    send(&device, NXS_OPERATION_STATUS, 2, 0, NULL);
    response(&device, 2, NXS_RESULT_INVALID_REPORT);
    CHECK(!nxs_device_complete_apply(&device, NXS_RESULT_OK));
    CHECK(!nxs_device_complete_persistence(&device, (nxs_result_t)9));
    CHECK(device.persistence_pending && device.status.persisted_generation == 0);
    CHECK(nxs_device_complete_persistence(&device, NXS_RESULT_OK));
    nxs_message_t reply = response(&device, 2, NXS_RESULT_OK);
    CHECK(reply.generation == 1 && device.generation == 1 && device.status.persisted_generation == 1);
    CHECK(!device.persistence_pending);
    send(&device, NXS_OPERATION_PERSIST_STATE, 2, 1, NULL);
    response(&device, 2, NXS_RESULT_OK);
    CHECK(!device.persistence_pending);
    send(&device, NXS_OPERATION_APPLY_STATE, 6, 1, &next);
    send(&device, NXS_OPERATION_PERSIST_STATE, 7, 1, NULL);
    response(&device, 7, NXS_RESULT_BUSY);
    CHECK(nxs_device_complete_apply(&device, NXS_RESULT_OK));
    send(&device, NXS_OPERATION_PERSIST_STATE, 8, 1, NULL);
    response(&device, 8, NXS_RESULT_STALE_GENERATION);
    send(&device, NXS_OPERATION_PERSIST_STATE, 9, 2, NULL);
    CHECK(nxs_device_pending_persistence(&device, &pending) && pending.generation == 2);
    CHECK(nxs_device_complete_persistence(&device, NXS_RESULT_STORAGE_FAILED));
    response(&device, 9, NXS_RESULT_STORAGE_FAILED);
    CHECK(device.status.persisted_generation == 1 && device.generation == 2);
    send(&device, NXS_OPERATION_PERSIST_STATE, 9, 2, NULL);
    response(&device, 9, NXS_RESULT_STORAGE_FAILED);
    CHECK(!device.persistence_pending);
    send(&device, NXS_OPERATION_PERSIST_STATE, 10, 2, NULL);
    CHECK(nxs_device_complete_persistence(&device, NXS_RESULT_OK));
    response(&device, 10, NXS_RESULT_OK);
    CHECK(device.status.persisted_generation == 2 && device.generation == 2);
    CHECK(!nxs_device_complete_persistence(&device, NXS_RESULT_OK));
    CHECK(!nxs_device_pending_persistence(NULL, &pending));
    CHECK(!nxs_device_pending_persistence(&device, NULL));
}

static void test_persistence_session_reset(void) {
    nxs_device_t device;
    init(&device);
    CHECK(nxs_device_configure_storage(&device, NXS_FLASH_SUPPORTED_BYTES, true, NULL));
    send(&device, NXS_OPERATION_PERSIST_STATE, 1, 1, NULL);
    nxs_device_reset_session(&device);
    CHECK(device.persistence_pending);
    send(&device, NXS_OPERATION_CAPABILITIES, 1, 0, NULL);
    nxs_message_t reply = response(&device, 1, NXS_RESULT_OK);
    CHECK(reply.operation == NXS_OPERATION_CAPABILITIES);
    CHECK(nxs_device_complete_persistence(&device, NXS_RESULT_OK));
    reply = response(&device, 1, NXS_RESULT_OK);
    CHECK(reply.operation == NXS_OPERATION_CAPABILITIES);
    send(&device, NXS_OPERATION_STATUS, 2, 0, NULL);
    reply = response(&device, 2, NXS_RESULT_OK);
    nxs_runtime_status_t status;
    CHECK(nxs_runtime_status_decode(reply.payload, reply.payload_length, &status) == NXS_RESULT_OK);
    CHECK(status.persisted_generation == 1 && status.storage_available && reply.generation == 1);
}

static void test_diagnostics_are_read_only_and_versioned(void) {
    nxs_device_t device;
    init(&device);
    nxs_runtime_diagnostics_t diagnostics = {.ring_underrun_count = 2, .usb_suspend_count = 3};
    CHECK(nxs_device_update_diagnostics(&device, &diagnostics));
    CHECK(!nxs_device_update_diagnostics(NULL, &diagnostics));
    CHECK(!nxs_device_update_diagnostics(&device, NULL));
    nxs_message_t request = {.operation = NXS_OPERATION_DIAGNOSTICS, .protocol_minor = 1, .request_id = 100};
    uint8_t report[NXS_REPORT_SIZE], first_reply[NXS_REPORT_SIZE];
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    CHECK(nxs_device_receive(&device, report, sizeof(report)));
    nxs_message_t reply = response(&device, 100, NXS_RESULT_OK);
    CHECK(reply.protocol_minor == 1 && reply.generation == 1);
    nxs_runtime_diagnostics_t decoded;
    CHECK(nxs_runtime_diagnostics_decode(reply.payload, reply.payload_length, &decoded) == NXS_RESULT_OK);
    CHECK(decoded.ring_underrun_count == 2 && decoded.usb_suspend_count == 3);
    CHECK(nxs_device_response(&device, first_reply, sizeof(first_reply)));
    diagnostics.ring_underrun_count = 9;
    CHECK(nxs_device_update_diagnostics(&device, &diagnostics));
    CHECK(nxs_device_receive(&device, report, sizeof(report)));
    uint8_t replay[NXS_REPORT_SIZE];
    CHECK(nxs_device_response(&device, replay, sizeof(replay)));
    CHECK(memcmp(replay, first_reply, sizeof(replay)) == 0);
    request.request_id = 101;
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    CHECK(nxs_device_receive(&device, report, sizeof(report)));
    reply = response(&device, 101, NXS_RESULT_OK);
    CHECK(nxs_runtime_diagnostics_decode(reply.payload, reply.payload_length, &decoded) == NXS_RESULT_OK &&
          decoded.ring_underrun_count == 9);
    request.request_id = 102;
    request.payload_length = 1;
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    CHECK(nxs_device_receive(&device, report, sizeof(report)));
    response(&device, 102, NXS_RESULT_INVALID_PARAMETERS);
    CHECK(device.active.muted == 1 && device.active.attenuation_db == nxs_default_snapshot().attenuation_db && device.generation == 1);
    CHECK(!device.apply_pending && !device.persistence_pending && device.status.persisted_generation == 0);
    request.operation = NXS_OPERATION_CAPABILITIES;
    request.payload_length = 0;
    request.request_id = 103;
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    CHECK(nxs_device_receive(&device, report, sizeof(report)));
    reply = response(&device, 103, NXS_RESULT_OK);
    nxs_capabilities_t capabilities;
    CHECK(nxs_capabilities_decode(reply.payload, reply.payload_length, &capabilities) == NXS_RESULT_OK);
    CHECK(capabilities.feature_flags == NXS_FEATURE_DIAGNOSTICS);
    request.protocol_minor = 0;
    request.request_id = 104;
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    CHECK(nxs_device_receive(&device, report, sizeof(report)));
    reply = response(&device, 104, NXS_RESULT_OK);
    CHECK(reply.protocol_minor == 0);
    CHECK(nxs_capabilities_decode(reply.payload, reply.payload_length, &capabilities) == NXS_RESULT_OK && capabilities.feature_flags == 0);
}

static void test_deferred_replies_echo_protocol_revision(void) {
    nxs_device_t device;
    init(&device);
    CHECK(nxs_device_configure_storage(&device, NXS_FLASH_SUPPORTED_BYTES, true, NULL));
    nxs_message_t request = {.operation = NXS_OPERATION_APPLY_STATE,
                             .protocol_minor = 1,
                             .request_id = 201,
                             .generation = 1,
                             .payload_length = NXS_SNAPSHOT_SIZE};
    CHECK(nxs_snapshot_encode(&device.active, request.payload, request.payload_length) == NXS_RESULT_OK);
    uint8_t report[NXS_REPORT_SIZE];
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    CHECK(nxs_device_receive(&device, report, sizeof(report)) && device.apply_pending);
    CHECK(nxs_device_complete_apply(&device, NXS_RESULT_OK));
    nxs_message_t reply = response(&device, 201, NXS_RESULT_OK);
    CHECK(reply.protocol_minor == 1 && reply.generation == 2);
    request.operation = NXS_OPERATION_PERSIST_STATE;
    request.request_id = 202;
    request.generation = 2;
    request.payload_length = 0;
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    CHECK(nxs_device_receive(&device, report, sizeof(report)) && device.persistence_pending);
    CHECK(nxs_device_complete_persistence(&device, NXS_RESULT_OK));
    reply = response(&device, 202, NXS_RESULT_OK);
    CHECK(reply.protocol_minor == 1 && reply.generation == 2 && device.status.persisted_generation == 2);
}

static void test_set_name(void) {
    nxs_device_t device;
    init(&device);
    send_name(&device, 1, 1, "Bedroom SoundBox");
    response(&device, 1, NXS_RESULT_STORAGE_UNAVAILABLE);
    CHECK(!device.name_pending);
    nxs_device_reset_session(&device);

    CHECK(nxs_device_configure_storage(&device, NXS_FLASH_SUPPORTED_BYTES, true, NULL));
    send_name(&device, 2, 0, "Bedroom SoundBox");
    response(&device, 2, NXS_RESULT_STALE_GENERATION);
    CHECK(!device.name_pending);

    nxs_snapshot_t next = nxs_default_snapshot();
    next.attenuation_db = -12;
    send(&device, NXS_OPERATION_APPLY_STATE, 3, 1, &next);
    send_name(&device, 4, 1, "Bedroom SoundBox");
    response(&device, 4, NXS_RESULT_BUSY);
    CHECK(!device.name_pending);
    CHECK(nxs_device_complete_apply(&device, NXS_RESULT_OK));
    response(&device, 3, NXS_RESULT_OK);
    CHECK(device.generation == 2);

    send_name(&device, 5, 2, "\n");
    response(&device, 5, NXS_RESULT_INVALID_PARAMETERS);
    CHECK(!device.name_pending);

    nxs_stored_state_t pending = {.generation = 777};
    send_name(&device, 6, 2, "Bedroom SoundBox");
    CHECK(device.name_pending && !device.apply_pending && !device.persistence_pending);
    send(&device, NXS_OPERATION_PERSIST_STATE, 7, 2, NULL);
    response(&device, 7, NXS_RESULT_BUSY);
    send_name(&device, 8, 2, "Office SoundBox");
    response(&device, 8, NXS_RESULT_BUSY);
    CHECK(nxs_device_pending_persistence(&device, &pending));
    CHECK(pending.generation == 3 && strcmp(pending.device_name, "Bedroom SoundBox") == 0);
    CHECK(nxs_device_complete_persistence(&device, NXS_RESULT_OK));
    nxs_message_t reply = response(&device, 6, NXS_RESULT_OK);
    CHECK(reply.generation == 3 && device.generation == 3 && device.status.persisted_generation == 3);
    CHECK(!device.name_pending && strcmp(device.capabilities.device_name, "Bedroom SoundBox") == 0);

    send(&device, NXS_OPERATION_CAPABILITIES, 9, 0, NULL);
    reply = response(&device, 9, NXS_RESULT_OK);
    nxs_capabilities_t capabilities;
    CHECK(nxs_capabilities_decode(reply.payload, reply.payload_length, &capabilities) == NXS_RESULT_OK);
    CHECK(strcmp(capabilities.device_name, "Bedroom SoundBox") == 0);

    send_name(&device, 10, 3, NULL);
    CHECK(nxs_device_pending_persistence(&device, &pending));
    CHECK(pending.generation == 4 && pending.device_name[0] == 0);
    CHECK(nxs_device_complete_persistence(&device, NXS_RESULT_STORAGE_FAILED));
    response(&device, 10, NXS_RESULT_STORAGE_FAILED);
    CHECK(device.generation == 3 && strcmp(device.capabilities.device_name, "Bedroom SoundBox") == 0);
}

static void send_message(nxs_device_t *device, nxs_operation_t operation, uint32_t identifier, uint32_t generation, const uint8_t *payload,
                         uint16_t length) {
    nxs_message_t request = {.operation = operation,
                             .protocol_minor = NXS_METADATA_PROTOCOL_MINOR,
                             .request_id = identifier,
                             .generation = generation,
                             .payload_length = length};
    memcpy(request.payload, payload, length);
    uint8_t report[NXS_REPORT_SIZE];
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    CHECK(nxs_device_receive(device, report, sizeof(report)));
}

static void send_metadata_part(nxs_device_t *device, uint32_t identifier, uint32_t generation, uint8_t part,
                               const uint8_t block[NXS_METADATA_SIZE]) {
    uint8_t payload[NXS_METADATA_WRITE_SIZE] = {part};
    memcpy(payload + 4, block + part * NXS_METADATA_PART_SIZE, NXS_METADATA_PART_SIZE);
    send_message(device, NXS_OPERATION_WRITE_METADATA, identifier, generation, payload, sizeof(payload));
}

/** Reads both parts with the identifiers `first_identifier` and the one after it, and decodes the block. */
static nxs_owner_metadata_t read_metadata(nxs_device_t *device, uint32_t first_identifier) {
    uint8_t block[NXS_METADATA_SIZE];
    for (uint8_t part = 0; part < NXS_METADATA_PART_COUNT; ++part) {
        send_message(device, NXS_OPERATION_READ_METADATA, first_identifier + part, 0, &part, 1);
        nxs_message_t reply = response(device, first_identifier + part, NXS_RESULT_OK);
        CHECK(reply.payload_length == NXS_METADATA_PART_SIZE);
        memcpy(block + part * NXS_METADATA_PART_SIZE, reply.payload, NXS_METADATA_PART_SIZE);
    }
    nxs_owner_metadata_t metadata;
    CHECK(nxs_owner_metadata_decode(block, sizeof(block), &metadata) == NXS_RESULT_OK);
    return metadata;
}

static uint16_t feature_flags(nxs_device_t *device, uint32_t identifier, uint8_t protocol_minor) {
    nxs_message_t request = {.operation = NXS_OPERATION_CAPABILITIES, .protocol_minor = protocol_minor, .request_id = identifier};
    uint8_t report[NXS_REPORT_SIZE];
    CHECK(nxs_message_encode(&request, report, sizeof(report)) == NXS_RESULT_OK);
    CHECK(nxs_device_receive(device, report, sizeof(report)));
    nxs_message_t reply = response(device, identifier, NXS_RESULT_OK);
    nxs_capabilities_t capabilities;
    CHECK(nxs_capabilities_decode(reply.payload, reply.payload_length, &capabilities) == NXS_RESULT_OK);
    return capabilities.feature_flags;
}

static nxs_owner_metadata_t sample_metadata(uint32_t serial_number) {
    nxs_owner_metadata_t metadata = {.date = 20261024u, .has_serial_number = true, .serial_number = serial_number};
    memcpy(metadata.owner, "Bench owner", strlen("Bench owner"));
    memcpy(metadata.note, "First line\nSecond line", strlen("First line\nSecond line"));
    return metadata;
}

static void test_owner_metadata_boot_and_refusals(void) {
    nxs_device_t device;
    init(&device);
    nxs_owner_metadata_t empty = {0}, metadata = sample_metadata(1);
    uint8_t block[NXS_METADATA_SIZE];
    CHECK(nxs_owner_metadata_encode(&metadata, block, sizeof(block)) == NXS_RESULT_OK);
    send_metadata_part(&device, 1, 1, 0, block);
    response(&device, 1, NXS_RESULT_STORAGE_UNAVAILABLE);
    nxs_owner_metadata_t current = read_metadata(&device, 2);
    CHECK(nxs_test_metadata_equal(&current, &empty));
    nxs_device_reset_session(&device);
    CHECK(nxs_device_configure_storage(&device, NXS_FLASH_SUPPORTED_BYTES, true, NULL));
    CHECK(feature_flags(&device, 4, 1) & NXS_FEATURE_METADATA);
    CHECK(!(feature_flags(&device, 5, 0) & NXS_FEATURE_METADATA));

    send_metadata_part(&device, 10, 1, 1, block);
    response(&device, 10, NXS_RESULT_INVALID_PARAMETERS);
    send_metadata_part(&device, 11, 1, 0, block);
    response(&device, 11, NXS_RESULT_OK);
    CHECK(device.generation == 1 && !device.metadata_pending);
    current = read_metadata(&device, 12);
    CHECK(nxs_test_metadata_equal(&current, &empty));
    nxs_device_reset_session(&device);
    send_metadata_part(&device, 14, 1, 1, block);
    response(&device, 14, NXS_RESULT_INVALID_PARAMETERS);

    send_metadata_part(&device, 15, 1, 0, block);
    response(&device, 15, NXS_RESULT_OK);
    nxs_snapshot_t next = nxs_default_snapshot();
    next.attenuation_db = -12;
    send(&device, NXS_OPERATION_APPLY_STATE, 16, 1, &next);
    CHECK(nxs_device_complete_apply(&device, NXS_RESULT_OK));
    response(&device, 16, NXS_RESULT_OK);
    send_metadata_part(&device, 17, 2, 1, block);
    response(&device, 17, NXS_RESULT_INVALID_PARAMETERS);
    send_metadata_part(&device, 18, 1, 1, block);
    response(&device, 18, NXS_RESULT_STALE_GENERATION);

    uint8_t invalid[NXS_METADATA_SIZE];
    memcpy(invalid, block, sizeof(invalid));
    invalid[8] = 0x80;
    send_metadata_part(&device, 19, 2, 0, invalid);
    response(&device, 19, NXS_RESULT_OK);
    send_metadata_part(&device, 20, 2, 1, invalid);
    response(&device, 20, NXS_RESULT_INVALID_PARAMETERS);
    CHECK(!device.metadata_pending && device.generation == 2);

    uint8_t payload[NXS_METADATA_WRITE_SIZE] = {2};
    send_message(&device, NXS_OPERATION_WRITE_METADATA, 21, 2, payload, sizeof(payload));
    response(&device, 21, NXS_RESULT_INVALID_PARAMETERS);
    payload[0] = 0;
    payload[1] = 1;
    send_message(&device, NXS_OPERATION_WRITE_METADATA, 22, 2, payload, sizeof(payload));
    response(&device, 22, NXS_RESULT_INVALID_PARAMETERS);
    payload[1] = 0;
    send_message(&device, NXS_OPERATION_WRITE_METADATA, 23, 2, payload, sizeof(payload) - 1);
    response(&device, 23, NXS_RESULT_INVALID_PARAMETERS);
    uint8_t part = NXS_METADATA_PART_COUNT;
    send_message(&device, NXS_OPERATION_READ_METADATA, 24, 0, &part, 1);
    response(&device, 24, NXS_RESULT_INVALID_PARAMETERS);
    send_message(&device, NXS_OPERATION_READ_METADATA, 25, 0, &part, 0);
    response(&device, 25, NXS_RESULT_INVALID_PARAMETERS);
    CHECK(!device.metadata_pending && device.generation == 2);

    init(&device);
    nxs_stored_state_t restored = {.snapshot = nxs_default_snapshot(), .generation = 7, .metadata = metadata};
    CHECK(nxs_device_configure_storage(&device, NXS_FLASH_SUPPORTED_BYTES, true, &restored));
    current = read_metadata(&device, 30);
    CHECK(nxs_test_metadata_equal(&current, &metadata));
}

static void test_owner_metadata_write(void) {
    nxs_device_t device;
    init(&device);
    CHECK(nxs_device_configure_storage(&device, NXS_FLASH_SUPPORTED_BYTES, true, NULL));
    nxs_owner_metadata_t metadata = sample_metadata(1);
    uint8_t block[NXS_METADATA_SIZE];
    CHECK(nxs_owner_metadata_encode(&metadata, block, sizeof(block)) == NXS_RESULT_OK);
    send_metadata_part(&device, 1, 1, 0, block);
    response(&device, 1, NXS_RESULT_OK);
    send_metadata_part(&device, 2, 1, 1, block);
    CHECK(device.metadata_pending);
    nxs_stored_state_t pending;
    CHECK(nxs_device_pending_persistence(&device, &pending));
    CHECK(pending.generation == 2 && nxs_test_metadata_equal(&pending.metadata, &metadata));
    send_name(&device, 3, 1, "Bedroom SoundBox");
    response(&device, 3, NXS_RESULT_BUSY);
    send_metadata_part(&device, 2, 1, 1, block);
    CHECK(nxs_device_complete_persistence(&device, NXS_RESULT_OK));
    nxs_message_t reply = response(&device, 2, NXS_RESULT_OK);
    CHECK(reply.generation == 2 && device.generation == 2 && device.status.persisted_generation == 2 && !device.metadata_pending);
    nxs_owner_metadata_t current = read_metadata(&device, 4);
    CHECK(nxs_test_metadata_equal(&current, &metadata));

    send_name(&device, 6, 2, "Bedroom SoundBox");
    CHECK(nxs_device_pending_persistence(&device, &pending));
    CHECK(nxs_test_metadata_equal(&pending.metadata, &metadata));
    CHECK(nxs_device_complete_persistence(&device, NXS_RESULT_OK));
    response(&device, 6, NXS_RESULT_OK);
    CHECK(device.generation == 3);

    nxs_owner_metadata_t next = sample_metadata(2);
    CHECK(nxs_owner_metadata_encode(&next, block, sizeof(block)) == NXS_RESULT_OK);
    send_metadata_part(&device, 7, 3, 0, block);
    response(&device, 7, NXS_RESULT_OK);
    send_metadata_part(&device, 8, 3, 1, block);
    CHECK(nxs_device_complete_persistence(&device, NXS_RESULT_STORAGE_FAILED));
    response(&device, 8, NXS_RESULT_STORAGE_FAILED);
    CHECK(device.generation == 3);
    current = read_metadata(&device, 9);
    CHECK(nxs_test_metadata_equal(&current, &metadata));
}

int main(void) {
    test_discovery();
    test_apply_acknowledgement_and_duplicates();
    test_apply_gain_above_full_scale();
    test_busy_failure_and_disconnect();
    test_malformed_requests_do_not_mutate_state();
    test_storage_boot_and_audio_status();
    test_persistence_acknowledgement();
    test_persistence_session_reset();
    test_diagnostics_are_read_only_and_versioned();
    test_deferred_replies_echo_protocol_revision();
    test_set_name();
    test_owner_metadata_boot_and_refusals();
    test_owner_metadata_write();
    return nxs_test_finish("Device control");
}
