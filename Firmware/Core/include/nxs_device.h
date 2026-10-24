#ifndef NXS_DEVICE_H
#define NXS_DEVICE_H

#include "nxs_dsp.h"
#include "nxs_storage.h"

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
    /** Restored at boot. Every save writes it back, so saving a profile or a name never clears it. */
    nxs_owner_metadata_t metadata;
    nxs_runtime_status_t status;
    nxs_runtime_diagnostics_t diagnostics;
    uint32_t generation;
    nxs_cached_reply_t cache[NXS_DEVICE_REPLY_CACHE_COUNT];
    size_t cache_next;
    uint8_t response[NXS_REPORT_SIZE];
    bool response_available;
    bool apply_pending;
    bool persistence_pending;
    bool name_pending;
    bool pending_can_reply;
    uint8_t pending_report[NXS_REPORT_SIZE];
    nxs_message_t pending_request;
    nxs_snapshot_t pending_snapshot;
    nxs_dsp_configuration_t pending_configuration;
    char pending_name[NXS_DEVICE_NAME_LENGTH];
} nxs_device_t;

/** All calls belong to the USB/control owner, not the audio core. */
bool nxs_device_init(nxs_device_t *device, const char *serial, const char *firmware_version);
/** Boot-only configuration before requests, using platform-verified geometry and optional validated saved state. */
bool nxs_device_configure_storage(nxs_device_t *device, uint32_t flash_size_bytes, bool available, const nxs_stored_state_t *restored);
/** Audio telemetry cannot replace control-owned persistence fields. Invalid telemetry leaves state unchanged. */
bool nxs_device_update_audio_status(nxs_device_t *device, const nxs_runtime_status_t *status);
bool nxs_device_update_diagnostics(nxs_device_t *device, const nxs_runtime_diagnostics_t *diagnostics);
bool nxs_device_receive(nxs_device_t *device, const uint8_t *report, size_t length);
bool nxs_device_response(const nxs_device_t *device, uint8_t *report, size_t length);
/** Audio ownership transfer is supplied by the platform, after reading this immutable configuration. */
const nxs_dsp_configuration_t *nxs_device_pending_configuration(const nxs_device_t *device);
bool nxs_device_complete_apply(nxs_device_t *device, nxs_result_t result);
/** True while a PERSIST_STATE or SET_NAME request awaits its one shared flash write. */
bool nxs_device_pending_persistence(const nxs_device_t *device, nxs_stored_state_t *state);
bool nxs_device_complete_persistence(nxs_device_t *device, nxs_result_t result);
/** Accepted in-flight work survives disconnect; its old session's reply does not. */
void nxs_device_reset_session(nxs_device_t *device);

#endif
