#ifndef NXS_DEVICE_H
#define NXS_DEVICE_H

#include "nxs_dsp.h"

#define NXS_DEVICE_REPLY_CACHE_COUNT 4u

typedef struct {
    uint8_t request[NXS_REPORT_SIZE];
    uint8_t response[NXS_REPORT_SIZE];
    uint32_t request_id;
    bool valid;
} nxs_cached_reply_t;

typedef struct {
    nxs_capabilities_t capabilities;
    nxs_snapshot_t active;
    nxs_runtime_status_t status;
    uint32_t generation;
    nxs_cached_reply_t cache[NXS_DEVICE_REPLY_CACHE_COUNT];
    size_t cache_next;
    uint8_t response[NXS_REPORT_SIZE];
    bool response_available;
    bool apply_pending;
    bool pending_can_reply;
    uint8_t pending_report[NXS_REPORT_SIZE];
    nxs_message_t pending_request;
    nxs_snapshot_t pending_snapshot;
    nxs_dsp_configuration_t pending_configuration;
} nxs_device_t;

/** All calls belong to the USB/control owner, not the audio core. */
bool nxs_device_init(nxs_device_t *device, const char *serial, const char *firmware_version);
bool nxs_device_receive(nxs_device_t *device, const uint8_t *report, size_t length);
bool nxs_device_response(const nxs_device_t *device, uint8_t *report, size_t length);
/** Audio ownership transfer is supplied by the platform, after reading this immutable configuration. */
const nxs_dsp_configuration_t *nxs_device_pending_configuration(const nxs_device_t *device);
bool nxs_device_complete_apply(nxs_device_t *device, nxs_result_t result);
/** An accepted in-flight apply survives disconnect; its old session's reply does not. */
void nxs_device_reset_session(nxs_device_t *device);

#endif
