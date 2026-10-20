#include "nxs_device.h"
#include "nxs_engine.h"
#include "nxs_usb.h"
#include "tusb.h"

#include <string.h>

static nxs_device_t device;
static bool job_in_flight;
static bool suspended;
static uint8_t alternate;
static uint32_t stream_epoch;
static int16_t host_volume;
static bool host_muted;
static const nxs_storage_io_t *storage_io;
static bool maintenance_active;
static bool maintenance_release_pending;

static void synchronize_audio_owner(void) {
    bool accepted;
    if (job_in_flight && nxs_audio_engine_take_result(&accepted)) {
        (void)nxs_device_complete_apply(&device, accepted ? NXS_RESULT_OK : NXS_RESULT_BUSY);
        job_in_flight = false;
    }
    const nxs_dsp_configuration_t *configuration = nxs_device_pending_configuration(&device);
    if (!job_in_flight && configuration && nxs_audio_engine_submit(configuration)) {
        job_in_flight = true;
    }
    nxs_runtime_status_t audio_status;
    nxs_audio_engine_status(&audio_status);
    (void)nxs_device_update_audio_status(&device, &audio_status);
}

static void update_transport(void) {
    nxs_audio_engine_transport(alternate != 0 && tud_mounted(), suspended, stream_epoch);
}

bool nxs_usb_init(const char *serial, const char *version) {
    if (!nxs_device_init(&device, serial, version)) {
        return false;
    }
    job_in_flight = false;
    storage_io = NULL;
    maintenance_active = false;
    maintenance_release_pending = false;
    suspended = false;
    alternate = 0;
    stream_epoch = 0;
    host_volume = 0;
    host_muted = false;
    nxs_usb_set_serial(serial);
    return nxs_audio_engine_host_controls(host_volume, host_muted);
}

bool nxs_usb_configure_storage(const nxs_storage_io_t *io, uint32_t flash_size_bytes, const nxs_stored_state_t *restored) {
    if ((io && (!io->read || !io->erase || !io->program)) ||
        !nxs_device_configure_storage(&device, flash_size_bytes, io != NULL, restored)) {
        return false;
    }
    storage_io = io;
    nxs_usb_set_product_name(device.capabilities.device_name);
    return true;
}

static void advance_maintenance(void) {
    nxs_stored_state_t state;
    bool persistence = nxs_device_pending_persistence(&device, &state);
    bool reset = nxs_usb_pending_reset().action != NXS_USB_RESET_NONE;
    if (persistence || reset) {
        if (!maintenance_active) {
            maintenance_active = true;
            nxs_audio_engine_request_maintenance(true);
        }
        maintenance_release_pending = false;
        if (persistence && nxs_audio_engine_maintenance_ready()) {
            nxs_result_t result = nxs_storage_save(storage_io, &state);
            (void)nxs_device_complete_persistence(&device, result);
            if (result == NXS_RESULT_OK) {
                nxs_usb_set_product_name(device.capabilities.device_name);
            }
            /* Keep the producer gated while the next tud_task drains transfers queued during flash access. */
            maintenance_release_pending = true;
        }
        return;
    }
    if (maintenance_active) {
        if (!maintenance_release_pending) {
            maintenance_release_pending = true;
            return;
        }
        (void)tud_audio_clear_ep_out_ff();
        ++stream_epoch;
        nxs_audio_engine_request_maintenance(false);
        maintenance_active = false;
        maintenance_release_pending = false;
    }
}

void nxs_usb_task(void) {
    synchronize_audio_owner();
    advance_maintenance();
    update_transport();
    if (alternate != 0 && !suspended && tud_mounted()) {
        uint32_t feedback = maintenance_active ? (NXS_SAMPLE_RATE_HZ / 1000u) << 16 : nxs_audio_engine_feedback();
        (void)tud_audio_n_fb_set(0, feedback);
    }
}

uint16_t tud_hid_get_report_cb(uint8_t instance, uint8_t report_id, hid_report_type_t type, uint8_t *buffer, uint16_t length) {
    if (instance != 0 || report_id != NXS_REPORT_ID || type != HID_REPORT_TYPE_FEATURE || length < NXS_REPORT_SIZE - 1u) {
        return 0;
    }
    synchronize_audio_owner();
    uint8_t report[NXS_REPORT_SIZE];
    if (!nxs_device_response(&device, report, sizeof(report))) {
        return 0;
    }
    memcpy(buffer, report + 1, NXS_REPORT_SIZE - 1u);
    return NXS_REPORT_SIZE - 1u;
}

void tud_hid_set_report_cb(uint8_t instance, uint8_t report_id, hid_report_type_t type, const uint8_t *buffer, uint16_t length) {
    if (instance != 0 || report_id != NXS_REPORT_ID || type != HID_REPORT_TYPE_FEATURE || length != NXS_REPORT_SIZE - 1u) {
        return;
    }
    synchronize_audio_owner();
    uint8_t report[NXS_REPORT_SIZE] = {NXS_REPORT_ID};
    memcpy(report + 1, buffer, length);
    (void)nxs_device_receive(&device, report, sizeof(report));
}

bool tud_audio_get_req_entity_cb(uint8_t rhport, const tusb_control_request_t *request) {
    uint8_t entity_id = TU_U16_HIGH(request->wIndex);
    uint8_t control_selector = TU_U16_HIGH(request->wValue);
    uint8_t channel_number = TU_U16_LOW(request->wValue);
    if (channel_number != 0) {
        return false;
    }
    if (entity_id == NXS_USB_CLOCK_ENTITY) {
        if (control_selector == AUDIO20_CS_CTRL_CLK_VALID && request->bRequest == AUDIO20_CS_REQ_CUR) {
            audio20_control_cur_1_t valid = {.bCur = 1};
            return tud_audio_buffer_and_schedule_control_xfer(rhport, request, &valid, sizeof(valid));
        }
        if (control_selector == AUDIO20_CS_CTRL_SAM_FREQ && request->bRequest == AUDIO20_CS_REQ_CUR) {
            audio20_control_cur_4_t frequency = {.bCur = tu_htole32(NXS_SAMPLE_RATE_HZ)};
            return tud_audio_buffer_and_schedule_control_xfer(rhport, request, &frequency, sizeof(frequency));
        }
        if (control_selector == AUDIO20_CS_CTRL_SAM_FREQ && request->bRequest == AUDIO20_CS_REQ_RANGE) {
            audio20_control_range_4_n_t(1)
                range = {.wNumSubRanges = tu_htole16(1),
                         .subrange[0] = {.bMin = tu_htole32(NXS_SAMPLE_RATE_HZ), .bMax = tu_htole32(NXS_SAMPLE_RATE_HZ), .bRes = 0}};
            return tud_audio_buffer_and_schedule_control_xfer(rhport, request, &range, sizeof(range));
        }
    }
    if (entity_id == NXS_USB_FEATURE_ENTITY) {
        if (control_selector == AUDIO20_FU_CTRL_MUTE && request->bRequest == AUDIO20_CS_REQ_CUR) {
            audio20_control_cur_1_t mute = {.bCur = host_muted ? 1u : 0u};
            return tud_audio_buffer_and_schedule_control_xfer(rhport, request, &mute, sizeof(mute));
        }
        if (control_selector == AUDIO20_FU_CTRL_VOLUME && request->bRequest == AUDIO20_CS_REQ_CUR) {
            audio20_control_cur_2_t volume = {.bCur = (int16_t)tu_htole16((uint16_t)host_volume)};
            return tud_audio_buffer_and_schedule_control_xfer(rhport, request, &volume, sizeof(volume));
        }
        if (control_selector == AUDIO20_FU_CTRL_VOLUME && request->bRequest == AUDIO20_CS_REQ_RANGE) {
            audio20_control_range_2_n_t(1) range = {.wNumSubRanges = tu_htole16(1),
                                                    .subrange[0] = {.bMin = (int16_t)tu_htole16((uint16_t)NXS_HOST_VOLUME_MIN_Q8_DB),
                                                                    .bMax = (int16_t)tu_htole16((uint16_t)NXS_HOST_VOLUME_MAX_Q8_DB),
                                                                    .bRes = tu_htole16(NXS_HOST_VOLUME_Q8_SCALE)}};
            return tud_audio_buffer_and_schedule_control_xfer(rhport, request, &range, sizeof(range));
        }
    }
    return false;
}

bool tud_audio_set_req_entity_cb(uint8_t rhport, const tusb_control_request_t *request, uint8_t *buffer) {
    (void)rhport;
    uint8_t entity_id = TU_U16_HIGH(request->wIndex);
    uint8_t control_selector = TU_U16_HIGH(request->wValue);
    uint8_t channel_number = TU_U16_LOW(request->wValue);
    if (entity_id != NXS_USB_FEATURE_ENTITY || channel_number != 0 || request->bRequest != AUDIO20_CS_REQ_CUR) {
        return false;
    }
    if (control_selector == AUDIO20_FU_CTRL_MUTE && request->wLength == 1 && buffer[0] <= 1) {
        bool mute = buffer[0] != 0;
        if (nxs_audio_engine_host_controls(host_volume, mute)) {
            host_muted = mute;
            return true;
        }
    }
    if (control_selector == AUDIO20_FU_CTRL_VOLUME && request->wLength == 2) {
        uint16_t raw = (uint16_t)(buffer[0] | ((uint16_t)buffer[1] << 8));
        int16_t volume = (int16_t)(raw < 0x8000u ? (int32_t)raw : (int32_t)raw - 65536);
        if (nxs_audio_engine_host_controls(volume, host_muted)) {
            host_volume = volume;
            return true;
        }
    }
    return false;
}

bool tud_audio_set_itf_close_EP_cb(uint8_t rhport, const tusb_control_request_t *request) {
    (void)rhport;
    if ((request->wIndex & 0xffu) == NXS_USB_AUDIO_STREAM_INTERFACE) {
        alternate = 0;
        ++stream_epoch;
        update_transport();
    }
    return true;
}

bool tud_audio_set_itf_cb(uint8_t rhport, const tusb_control_request_t *request) {
    (void)rhport;
    if ((request->wIndex & 0xffu) != NXS_USB_AUDIO_STREAM_INTERFACE) {
        return true;
    }
    if (request->wValue > 2) {
        return false;
    }
    alternate = (uint8_t)request->wValue;
    ++stream_epoch;
    update_transport();
    return true;
}

static void reject_audio_packet(void) {
    (void)tud_audio_clear_ep_out_ff();
    nxs_audio_engine_reject_packet();
    ++stream_epoch;
    update_transport();
}

bool tud_audio_rx_done_isr(uint8_t rhport, uint16_t received, uint8_t function, uint8_t endpoint, uint8_t current_alternate) {
    (void)rhport;
    if (function != 0 || endpoint != NXS_USB_AUDIO_OUT_ENDPOINT || current_alternate == 0 || current_alternate > 2) {
        return false;
    }
    if (maintenance_active) {
        (void)tud_audio_clear_ep_out_ff();
        nxs_audio_engine_reject_packet();
        return true;
    }
    uint8_t sample_bytes = current_alternate + 1u;
    uint16_t frame_bytes = sample_bytes * NXS_AUDIO_CHANNELS;
    uint16_t maximum = (uint16_t)(NXS_AUDIO_USB_MAX_FRAMES * frame_bytes);
    if (received > maximum || received % frame_bytes != 0) {
        reject_audio_packet();
        return true;
    }
    uint8_t packet[NXS_USB_MAX_AUDIO_PACKET];
    while (tud_audio_available() >= frame_bytes) {
        uint16_t length = (uint16_t)(tud_audio_available() / frame_bytes * frame_bytes);
        if (length > maximum) {
            length = maximum;
        }
        uint16_t actual = tud_audio_read(packet, length);
        if (actual != length) {
            reject_audio_packet();
            break;
        }
        (void)nxs_audio_engine_receive(packet, actual, sample_bytes);
    }
    return true;
}

void tud_mount_cb(void) {
    alternate = 0;
    suspended = false;
    ++stream_epoch;
    nxs_device_reset_session(&device);
    update_transport();
}

void tud_umount_cb(void) {
    alternate = 0;
    suspended = false;
    ++stream_epoch;
    nxs_device_reset_session(&device);
    update_transport();
}

void tud_suspend_cb(bool remote_wakeup_enabled) {
    (void)remote_wakeup_enabled;
    suspended = true;
    ++stream_epoch;
    update_transport();
}

void tud_resume_cb(void) {
    suspended = false;
    ++stream_epoch;
    update_transport();
}
