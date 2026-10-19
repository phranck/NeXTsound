#include "nxs_engine.h"
#include "nxs_protocol_test.h"
#include "nxs_usb.h"
#include "tusb.h"

#include <string.h>

static struct {
    bool mounted;
    bool streaming;
    bool suspended;
    bool allow_submit;
    bool allow_host;
    bool has_job;
    bool result_ready;
    bool result;
    bool short_read;
    bool host_muted;
    bool maintenance_requested;
    bool maintenance_ready;
    nxs_usb_reset_request_t reset_request;
    unsigned int storage_erases;
    unsigned int storage_programs;
    uint8_t storage[NXS_STORAGE_SLOT_COUNT][NXS_STORAGE_SECTOR_BYTES];
    int16_t host_volume;
    uint32_t epoch;
    unsigned int submitted;
    unsigned int rejected;
    size_t received_frames;
    uint32_t feedback;
    uint8_t fifo[2048];
    uint16_t available;
    uint8_t reply[64];
    uint16_t reply_length;
} mock;

nxs_usb_reset_request_t nxs_usb_pending_reset(void) {
    return mock.reset_request;
}

void nxs_audio_engine_request_maintenance(bool requested) {
    if (requested && !mock.maintenance_requested) {
        mock.maintenance_ready = false;
    }
    mock.maintenance_requested = requested;
}

bool nxs_audio_engine_maintenance_ready(void) {
    return mock.maintenance_requested && mock.maintenance_ready;
}

bool tud_mounted(void) {
    return mock.mounted;
}

bool nxs_audio_engine_submit(const nxs_dsp_configuration_t *configuration) {
    CHECK(configuration != NULL);
    if (!mock.allow_submit) {
        return false;
    }
    CHECK(!mock.has_job);
    mock.has_job = true;
    ++mock.submitted;
    return true;
}

bool nxs_audio_engine_take_result(bool *accepted) {
    if (!mock.result_ready) {
        return false;
    }
    *accepted = mock.result;
    mock.result_ready = false;
    mock.has_job = false;
    return true;
}

void nxs_audio_engine_status(nxs_runtime_status_t *status) {
    *status = (nxs_runtime_status_t){.block_deadline_us = NXS_DSP_BLOCK_DEADLINE_US,
                                     .host_volume_db = mock.host_volume / (float)NXS_HOST_VOLUME_Q8_SCALE,
                                     .host_muted = mock.host_muted,
                                     .streaming = mock.streaming && !mock.suspended};
}

void nxs_audio_engine_transport(bool streaming, bool suspended, uint32_t epoch) {
    mock.streaming = streaming;
    mock.suspended = suspended;
    mock.epoch = epoch;
}

bool nxs_audio_engine_host_controls(int16_t volume, bool muted) {
    if (!mock.allow_host || !nxs_host_volume_is_valid(volume / (float)NXS_HOST_VOLUME_Q8_SCALE)) {
        return false;
    }
    mock.host_volume = volume;
    mock.host_muted = muted;
    return true;
}

bool nxs_audio_engine_receive(const uint8_t *packet, size_t length, uint8_t sample_bytes) {
    float stereo[NXS_AUDIO_USB_MAX_FRAMES * NXS_AUDIO_CHANNELS];
    size_t frames;
    CHECK(nxs_audio_decode(packet, length, sample_bytes, stereo, NXS_AUDIO_USB_MAX_FRAMES, &frames));
    mock.received_frames += frames;
    return true;
}

void nxs_audio_engine_reject_packet(void) {
    ++mock.rejected;
}

uint32_t nxs_audio_engine_feedback(void) {
    return 48u << 16;
}

uint16_t tud_audio_n_available(uint8_t function) {
    CHECK(function == 0);
    return mock.available;
}

uint16_t tud_audio_n_read(uint8_t function, void *buffer, uint16_t length) {
    CHECK(function == 0 && length <= mock.available);
    if (mock.short_read && length != 0) {
        --length;
    }
    memcpy(buffer, mock.fifo, length);
    mock.available -= length;
    memmove(mock.fifo, mock.fifo + length, mock.available);
    return length;
}

bool tud_audio_n_clear_ep_out_ff(uint8_t function) {
    CHECK(function == 0);
    mock.available = 0;
    return true;
}

bool tud_audio_n_fb_set(uint8_t function, uint32_t feedback) {
    CHECK(function == 0);
    mock.feedback = feedback;
    return true;
}

bool tud_audio_buffer_and_schedule_control_xfer(uint8_t port, const tusb_control_request_t *request, void *data, uint16_t length) {
    CHECK(port == 0 && request != NULL && length <= sizeof(mock.reply));
    memcpy(mock.reply, data, length);
    mock.reply_length = length;
    return true;
}

static bool storage_read(void *context, unsigned int slot, nxs_storage_record_t *record) {
    (void)context;
    CHECK(slot < NXS_STORAGE_SLOT_COUNT);
    memcpy(record->bytes, mock.storage[slot], sizeof(record->bytes));
    return true;
}

static bool storage_erase(void *context, unsigned int slot) {
    (void)context;
    CHECK(slot < NXS_STORAGE_SLOT_COUNT && mock.maintenance_requested && mock.maintenance_ready);
    ++mock.storage_erases;
    memset(mock.storage[slot], 0xff, sizeof(mock.storage[slot]));
    return true;
}

static bool storage_program(void *context, unsigned int slot, unsigned int page, const uint8_t bytes[NXS_STORAGE_PAGE_BYTES]) {
    (void)context;
    CHECK(slot < NXS_STORAGE_SLOT_COUNT && page <= NXS_STORAGE_COMMIT_PAGE);
    CHECK(mock.maintenance_requested && mock.maintenance_ready);
    ++mock.storage_programs;
    for (size_t index = 0; index < NXS_STORAGE_PAGE_BYTES; ++index) {
        mock.storage[slot][page * NXS_STORAGE_PAGE_BYTES + index] &= bytes[index];
    }
    return true;
}

static void enable_storage(const nxs_stored_state_t *restored) {
    static const nxs_storage_io_t io = {.read = storage_read, .erase = storage_erase, .program = storage_program};
    CHECK(nxs_usb_configure_storage(&io, NXS_FLASH_SUPPORTED_BYTES, restored));
}

static void initialize(void) {
    memset(&mock, 0, sizeof(mock));
    memset(mock.storage, 0xff, sizeof(mock.storage));
    mock.mounted = mock.allow_submit = mock.allow_host = true;
    CHECK(nxs_usb_init("TESTDEVICE", "test"));
    tud_mount_cb();
}

static void send(nxs_operation_t operation, uint32_t identifier, uint32_t generation, const nxs_snapshot_t *snapshot) {
    uint8_t report[NXS_REPORT_SIZE];
    nxs_test_request(operation, identifier, generation, snapshot, report);
    tud_hid_set_report_cb(0, NXS_REPORT_ID, HID_REPORT_TYPE_FEATURE, report + 1, NXS_REPORT_SIZE - 1u);
}

static nxs_message_t response(uint32_t identifier, nxs_result_t result) {
    uint8_t report[NXS_REPORT_SIZE] = {NXS_REPORT_ID};
    CHECK(tud_hid_get_report_cb(0, NXS_REPORT_ID, HID_REPORT_TYPE_FEATURE, report + 1, NXS_REPORT_SIZE - 1u) == NXS_REPORT_SIZE - 1u);
    return nxs_test_response(report, identifier, result);
}

static void send_name(uint32_t identifier, uint32_t generation, const char *name) {
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
    tud_hid_set_report_cb(0, NXS_REPORT_ID, HID_REPORT_TYPE_FEATURE, report + 1, NXS_REPORT_SIZE - 1u);
}

static void set_alternate(uint8_t alternate) {
    tusb_control_request_t request = {
        .bmRequestType = 0x01, .bRequest = TUSB_REQ_SET_INTERFACE, .wIndex = NXS_USB_AUDIO_STREAM_INTERFACE, .wValue = alternate};
    CHECK(tud_audio_set_itf_cb(0, &request));
}

static void test_hid_bridge_and_owner_acknowledgement(void) {
    initialize();
    uint8_t buffer[NXS_REPORT_SIZE - 1u];
    CHECK(tud_hid_get_report_cb(0, NXS_REPORT_ID, HID_REPORT_TYPE_FEATURE, buffer, sizeof(buffer)) == 0);
    send(NXS_OPERATION_CAPABILITIES, 1, 0, NULL);
    nxs_message_t reply = response(1, NXS_RESULT_OK);
    nxs_capabilities_t capabilities;
    CHECK(nxs_capabilities_decode(reply.payload, reply.payload_length, &capabilities) == NXS_RESULT_OK);
    CHECK(capabilities.feature_flags == 0 && capabilities.flash_size_bytes == 0);
    nxs_snapshot_t snapshot = nxs_default_snapshot();
    snapshot.attenuation_db = -12;
    uint8_t report[NXS_REPORT_SIZE];
    nxs_test_request(NXS_OPERATION_APPLY_STATE, 2, 1, &snapshot, report);
    tud_hid_set_report_cb(0, NXS_REPORT_ID, HID_REPORT_TYPE_FEATURE, report + 1, NXS_REPORT_SIZE - 2u);
    tud_hid_set_report_cb(0, 2, HID_REPORT_TYPE_FEATURE, report + 1, NXS_REPORT_SIZE - 1u);
    response(1, NXS_RESULT_OK);
    CHECK(mock.submitted == 0);
    send(NXS_OPERATION_APPLY_STATE, 2, 1, &snapshot);
    nxs_usb_task();
    CHECK(mock.submitted == 1 && mock.has_job);
    response(1, NXS_RESULT_OK);
    mock.result = mock.result_ready = true;
    reply = response(2, NXS_RESULT_OK);
    CHECK(reply.generation == 2);
    send(NXS_OPERATION_APPLY_STATE, 2, 1, &snapshot);
    response(2, NXS_RESULT_OK);
    CHECK(mock.submitted == 1);
    send(NXS_OPERATION_READ_STATE, 3, 0, NULL);
    reply = response(3, NXS_RESULT_OK);
    CHECK(nxs_snapshot_decode(reply.payload, reply.payload_length, &snapshot) == NXS_RESULT_OK);
    CHECK(snapshot.attenuation_db == -12 && snapshot.muted == 1);
    send(NXS_OPERATION_PERSIST_STATE, 4, 2, NULL);
    response(4, NXS_RESULT_STORAGE_UNAVAILABLE);
}

static tusb_control_request_t entity_request(uint8_t entity, uint8_t selector, uint8_t operation, uint16_t length) {
    return (tusb_control_request_t){.bmRequestType = 0xa1,
                                    .bRequest = operation,
                                    .wValue = (uint16_t)selector << 8,
                                    .wIndex = (uint16_t)entity << 8,
                                    .wLength = length};
}

static void test_clock_and_host_controls(void) {
    initialize();
    tusb_control_request_t request = entity_request(NXS_USB_CLOCK_ENTITY, AUDIO_CS_CTRL_SAM_FREQ, AUDIO_CS_REQ_CUR, 4);
    CHECK(tud_audio_get_req_entity_cb(0, &request));
    CHECK(mock.reply_length == 4 && mock.reply[0] == 0x80 && mock.reply[1] == 0xbb && mock.reply[2] == 0 && mock.reply[3] == 0);
    request.bRequest = AUDIO_CS_REQ_RANGE;
    request.wLength = 14;
    CHECK(tud_audio_get_req_entity_cb(0, &request));
    CHECK(mock.reply_length == 14 && mock.reply[0] == 1 && mock.reply[2] == 0x80 && mock.reply[6] == 0x80);
    request = entity_request(NXS_USB_CLOCK_ENTITY, AUDIO_CS_CTRL_CLK_VALID, AUDIO_CS_REQ_CUR, 1);
    CHECK(tud_audio_get_req_entity_cb(0, &request) && mock.reply[0] == 1);
    request = entity_request(NXS_USB_FEATURE_ENTITY, AUDIO_FU_CTRL_VOLUME, AUDIO_CS_REQ_CUR, 2);
    request.bmRequestType = 0x21;
    uint8_t volume[] = {0, 0xf4};
    CHECK(tud_audio_set_req_entity_cb(0, &request, volume));
    CHECK(mock.host_volume == -12 * 256);
    volume[1] = 1;
    CHECK(!tud_audio_set_req_entity_cb(0, &request, volume));
    CHECK(mock.host_volume == -12 * 256);
    mock.allow_host = false;
    volume[1] = 0xfa;
    CHECK(!tud_audio_set_req_entity_cb(0, &request, volume));
    mock.allow_host = true;
    request = entity_request(NXS_USB_FEATURE_ENTITY, AUDIO_FU_CTRL_VOLUME, AUDIO_CS_REQ_CUR, 2);
    CHECK(tud_audio_get_req_entity_cb(0, &request) && mock.reply[0] == 0 && mock.reply[1] == 0xf4);
    request = entity_request(NXS_USB_FEATURE_ENTITY, AUDIO_FU_CTRL_VOLUME, AUDIO_CS_REQ_RANGE, 8);
    CHECK(tud_audio_get_req_entity_cb(0, &request));
    CHECK(mock.reply_length == 8 && mock.reply[0] == 1 && mock.reply[2] == 0 && mock.reply[3] == 0xb0 && mock.reply[4] == 0 &&
          mock.reply[5] == 0 && mock.reply[6] == 0 && mock.reply[7] == 1);
    request = entity_request(NXS_USB_FEATURE_ENTITY, AUDIO_FU_CTRL_MUTE, AUDIO_CS_REQ_CUR, 1);
    request.bmRequestType = 0x21;
    uint8_t mute = 1;
    CHECK(tud_audio_set_req_entity_cb(0, &request, &mute) && mock.host_muted);
    mute = 2;
    CHECK(!tud_audio_set_req_entity_cb(0, &request, &mute) && mock.host_muted);
    request.wValue |= 1;
    mute = 0;
    CHECK(!tud_audio_set_req_entity_cb(0, &request, &mute));
}

static void test_packets_and_lifecycle(void) {
    initialize();
    set_alternate(1);
    mock.available = NXS_DSP_BLOCK_FRAMES * 4;
    CHECK(tud_audio_rx_done_post_read_cb(0, mock.available, 0, NXS_USB_AUDIO_OUT_ENDPOINT, 1));
    CHECK(mock.received_frames == NXS_DSP_BLOCK_FRAMES && mock.available == 0);
    set_alternate(2);
    mock.available = NXS_AUDIO_USB_MAX_FRAMES * 6;
    CHECK(tud_audio_rx_done_post_read_cb(0, mock.available, 0, NXS_USB_AUDIO_OUT_ENDPOINT, 2));
    CHECK(mock.received_frames == NXS_DSP_BLOCK_FRAMES + NXS_AUDIO_USB_MAX_FRAMES);
    nxs_usb_task();
    CHECK(mock.feedback == 48u << 16 && mock.streaming);
    uint32_t epoch = mock.epoch;
    tud_suspend_cb(false);
    CHECK(mock.suspended && mock.epoch != epoch);
    tud_resume_cb();
    CHECK(!mock.suspended && mock.streaming);
    set_alternate(0);
    CHECK(!mock.streaming);
}

static void test_new_configuration_resets_session(void) {
    initialize();
    send(NXS_OPERATION_READ_STATE, 1, 0, NULL);
    response(1, NXS_RESULT_OK);
    set_alternate(1);
    CHECK(mock.streaming);
    /* TinyUSB resets the class drivers on bus reset without calling tud_umount_cb. */
    tud_mount_cb();
    send(NXS_OPERATION_CAPABILITIES, 1, 0, NULL);
    response(1, NXS_RESULT_OK);
    CHECK(!mock.streaming);
}

static void test_oversized_packet_uses_active_format_limit(void) {
    initialize();
    set_alternate(1);
    mock.available = (NXS_AUDIO_USB_MAX_FRAMES + 1u) * 4;
    CHECK(tud_audio_rx_done_post_read_cb(0, mock.available, 0, NXS_USB_AUDIO_OUT_ENDPOINT, 1));
    CHECK(mock.rejected == 1 && mock.received_frames == 0 && mock.available == 0);
}

static void test_short_fifo_read_discards_partial_frame(void) {
    initialize();
    set_alternate(1);
    mock.available = NXS_DSP_BLOCK_FRAMES * 4;
    mock.short_read = true;
    CHECK(tud_audio_rx_done_post_read_cb(0, mock.available, 0, NXS_USB_AUDIO_OUT_ENDPOINT, 1));
    CHECK(mock.rejected == 1 && mock.received_frames == 0 && mock.available == 0);
}

static void test_new_session_can_reuse_an_inflight_request_id(void) {
    initialize();
    nxs_snapshot_t snapshot = nxs_default_snapshot();
    snapshot.attenuation_db = -9;
    send(NXS_OPERATION_APPLY_STATE, 1, 1, &snapshot);
    nxs_usb_task();
    CHECK(mock.submitted == 1 && mock.has_job);
    tud_mount_cb();
    send(NXS_OPERATION_CAPABILITIES, 1, 0, NULL);
    nxs_message_t reply = response(1, NXS_RESULT_OK);
    CHECK(reply.operation == NXS_OPERATION_CAPABILITIES && reply.generation == 1);
    mock.result = mock.result_ready = true;
    reply = response(1, NXS_RESULT_OK);
    CHECK(reply.operation == NXS_OPERATION_CAPABILITIES && reply.generation == 1);
    send(NXS_OPERATION_READ_STATE, 2, 0, NULL);
    reply = response(2, NXS_RESULT_OK);
    CHECK(reply.generation == 2 && mock.submitted == 1);
    CHECK(nxs_snapshot_decode(reply.payload, reply.payload_length, &snapshot) == NXS_RESULT_OK);
    CHECK(snapshot.attenuation_db == -9);
}

static void test_audio_telemetry_preserves_storage_status(void) {
    initialize();
    enable_storage(NULL);
    send(NXS_OPERATION_STATUS, 1, 0, NULL);
    nxs_message_t reply = response(1, NXS_RESULT_OK);
    nxs_runtime_status_t status;
    CHECK(nxs_runtime_status_decode(reply.payload, reply.payload_length, &status) == NXS_RESULT_OK);
    CHECK(status.storage_available == 1 && status.persisted_generation == 0);
}

static void test_persistence_waits_for_audio_and_drains_usb(void) {
    initialize();
    enable_storage(NULL);
    set_alternate(1);
    send(NXS_OPERATION_READ_STATE, 1, 0, NULL);
    response(1, NXS_RESULT_OK);
    send(NXS_OPERATION_PERSIST_STATE, 2, 1, NULL);
    nxs_usb_task();
    CHECK(mock.maintenance_requested && !mock.maintenance_ready && mock.storage_erases == 0);
    response(1, NXS_RESULT_OK);
    mock.available = NXS_DSP_BLOCK_FRAMES * 4;
    CHECK(tud_audio_rx_done_post_read_cb(0, mock.available, 0, NXS_USB_AUDIO_OUT_ENDPOINT, 1));
    CHECK(mock.received_frames == 0 && mock.available == 0 && mock.rejected == 1);
    mock.maintenance_ready = true;
    uint32_t previous_epoch = mock.epoch;
    nxs_usb_task();
    nxs_message_t reply = response(2, NXS_RESULT_OK);
    CHECK(reply.generation == 1 && mock.storage_erases == 1 && mock.storage_programs == 2);
    CHECK(mock.maintenance_requested);
    mock.available = NXS_DSP_BLOCK_FRAMES * 4;
    CHECK(tud_audio_rx_done_post_read_cb(0, mock.available, 0, NXS_USB_AUDIO_OUT_ENDPOINT, 1));
    CHECK(mock.received_frames == 0 && mock.available == 0 && mock.rejected == 2);
    nxs_usb_task();
    CHECK(!mock.maintenance_requested && mock.epoch != previous_epoch && mock.streaming);
    send(NXS_OPERATION_STATUS, 3, 0, NULL);
    reply = response(3, NXS_RESULT_OK);
    nxs_runtime_status_t status;
    CHECK(nxs_runtime_status_decode(reply.payload, reply.payload_length, &status) == NXS_RESULT_OK);
    CHECK(status.storage_available == 1 && status.persisted_generation == 1);
    send(NXS_OPERATION_PERSIST_STATE, 2, 1, NULL);
    response(2, NXS_RESULT_OK);
    nxs_usb_task();
    CHECK(mock.storage_erases == 1 && !mock.maintenance_requested);
    nxs_storage_record_t record;
    memcpy(record.bytes, mock.storage[0], sizeof(record.bytes));
    nxs_stored_state_t stored;
    CHECK(nxs_storage_record_decode(&record, &stored));
    CHECK(stored.generation == 1 && stored.snapshot.muted == 1);
}

static void test_persistence_completes_after_session_reset(void) {
    initialize();
    enable_storage(NULL);
    send(NXS_OPERATION_PERSIST_STATE, 1, 1, NULL);
    nxs_usb_task();
    CHECK(mock.maintenance_requested && mock.storage_erases == 0);
    tud_mount_cb();
    send(NXS_OPERATION_CAPABILITIES, 1, 0, NULL);
    nxs_message_t reply = response(1, NXS_RESULT_OK);
    CHECK(reply.operation == NXS_OPERATION_CAPABILITIES);
    mock.maintenance_ready = true;
    nxs_usb_task();
    reply = response(1, NXS_RESULT_OK);
    CHECK(reply.operation == NXS_OPERATION_CAPABILITIES && mock.storage_erases == 1);
    nxs_usb_task();
    send(NXS_OPERATION_STATUS, 2, 0, NULL);
    reply = response(2, NXS_RESULT_OK);
    nxs_runtime_status_t status;
    CHECK(nxs_runtime_status_decode(reply.payload, reply.payload_length, &status) == NXS_RESULT_OK);
    CHECK(status.persisted_generation == 1 && status.storage_available == 1);
}

static void test_reset_waits_for_audio_and_can_be_canceled(void) {
    initialize();
    set_alternate(1);
    mock.reset_request.action = NXS_USB_RESET_BOOTSEL;
    nxs_usb_task();
    CHECK(mock.maintenance_requested && !nxs_audio_engine_maintenance_ready());
    CHECK(mock.storage_erases == 0 && mock.storage_programs == 0);
    mock.maintenance_ready = true;
    nxs_usb_task();
    CHECK(nxs_audio_engine_maintenance_ready());
    uint32_t previous_epoch = mock.epoch;
    mock.reset_request.action = NXS_USB_RESET_NONE;
    nxs_usb_task();
    CHECK(mock.maintenance_requested);
    nxs_usb_task();
    CHECK(!mock.maintenance_requested && mock.epoch != previous_epoch && mock.streaming);
}

static void test_name_persistence_updates_product_string(void) {
    initialize();
    enable_storage(NULL);
    const uint16_t *default_product = tud_descriptor_string_cb(2, 0x0409);
    CHECK(default_product != NULL && (default_product[0] & 0xffu) == 2u * strlen("NeXTsound development") + 2u);
    send_name(1, 1, "Bedroom SoundBox");
    nxs_usb_task();
    CHECK(mock.maintenance_requested && !mock.maintenance_ready && mock.storage_erases == 0);
    const uint16_t *pending_product = tud_descriptor_string_cb(2, 0x0409);
    CHECK(pending_product != NULL && (pending_product[0] & 0xffu) == 2u * strlen("NeXTsound development") + 2u);
    mock.maintenance_ready = true;
    nxs_usb_task();
    nxs_message_t reply = response(1, NXS_RESULT_OK);
    CHECK(reply.generation == 2 && mock.storage_erases == 1);
    const uint16_t *custom_product = tud_descriptor_string_cb(2, 0x0409);
    CHECK(custom_product != NULL && (custom_product[0] & 0xffu) == 2u * strlen("Bedroom SoundBox") + 2u);
    CHECK(custom_product[1] == 'B');
    nxs_storage_record_t record;
    memcpy(record.bytes, mock.storage[0], sizeof(record.bytes));
    nxs_stored_state_t stored;
    CHECK(nxs_storage_record_decode(&record, &stored));
    CHECK(strcmp(stored.device_name, "Bedroom SoundBox") == 0);
}

static void test_storage_callbacks(void) {
    test_persistence_waits_for_audio_and_drains_usb();
    test_persistence_completes_after_session_reset();
    test_name_persistence_updates_product_string();
}

static void test_basic_callbacks(void) {
    test_hid_bridge_and_owner_acknowledgement();
    test_clock_and_host_controls();
    test_packets_and_lifecycle();
}

int main(int count, char **arguments) {
    CHECK(count == 1 || count == 2);
    const char *name = count > 1 ? arguments[1] : "all";
    const struct {
        const char *name;
        void (*run)(void);
    } cases[] = {{"basic", test_basic_callbacks},
                 {"mount", test_new_configuration_resets_session},
                 {"packet", test_oversized_packet_uses_active_format_limit},
                 {"short-read", test_short_fifo_read_discards_partial_frame},
                 {"inflight", test_new_session_can_reuse_an_inflight_request_id},
                 {"storage-status", test_audio_telemetry_preserves_storage_status},
                 {"storage-flow", test_storage_callbacks},
                 {"reset-flow", test_reset_waits_for_audio_and_can_be_canceled}};
    size_t matched = 0;
    for (size_t index = 0; index < sizeof(cases) / sizeof(cases[0]); ++index) {
        if (!strcmp(name, "all") || !strcmp(name, cases[index].name)) {
            cases[index].run();
            ++matched;
        }
    }
    CHECK(matched != 0);
    return nxs_test_finish("USB control callbacks");
}
