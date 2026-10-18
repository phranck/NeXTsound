#include "nxs_device.h"
#include "nxs_protocol_test.h"

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
    CHECK(device.generation == 1 && device.active.attenuation_db == -24);
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
    CHECK(device.generation == 1 && device.active.attenuation_db == -24);
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

int main(void) {
    test_discovery();
    test_apply_acknowledgement_and_duplicates();
    test_busy_failure_and_disconnect();
    test_malformed_requests_do_not_mutate_state();
    return nxs_test_finish("Device control");
}
