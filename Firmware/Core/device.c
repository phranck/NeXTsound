#include "nxs_device.h"

#include <string.h>

static bool copy_text(char destination[17], const char *text) {
    if (!text || strlen(text) > 16) {
        return false;
    }
    memcpy(destination, text, strlen(text) + 1);
    return true;
}

bool nxs_device_init(nxs_device_t *device, const char *serial, const char *firmware_version) {
    if (!device) {
        return false;
    }
    nxs_capabilities_t capabilities = nxs_default_capabilities();
    uint8_t payload[NXS_CAPABILITIES_SIZE];
    if (!copy_text(capabilities.device_serial, serial) || !copy_text(capabilities.firmware_version, firmware_version) ||
        nxs_capabilities_encode(&capabilities, payload, sizeof(payload)) != NXS_RESULT_OK) {
        return false;
    }
    memset(device, 0, sizeof(*device));
    device->capabilities = capabilities;
    device->active = nxs_default_snapshot();
    device->generation = 1;
    device->status.block_deadline_us = NXS_DSP_BLOCK_DEADLINE_US;
    return true;
}

bool nxs_device_configure_storage(nxs_device_t *device, uint32_t flash_size_bytes, bool available, const nxs_stored_state_t *restored) {
    if (!device || device->generation != 1 || device->response_available || device->apply_pending || device->persistence_pending ||
        device->name_pending || (flash_size_bytes != 0 && flash_size_bytes != NXS_FLASH_SUPPORTED_BYTES) ||
        ((available || restored) && flash_size_bytes == 0)) {
        return false;
    }
    nxs_dsp_configuration_t configuration;
    if (restored && (restored->generation == 0 || !nxs_dsp_prepare(&restored->snapshot, &configuration) ||
                     !nxs_device_name_is_valid(restored->device_name))) {
        return false;
    }
    device->capabilities.flash_size_bytes = flash_size_bytes;
    device->capabilities.feature_flags = (flash_size_bytes ? NXS_FEATURE_FLASH_VERIFIED : 0u) | (available ? NXS_FEATURE_PERSISTENCE : 0u);
    device->status.storage_available = available ? 1u : 0u;
    if (restored) {
        device->active = restored->snapshot;
        device->generation = restored->generation;
        device->status.persisted_generation = restored->generation;
        memcpy(device->capabilities.device_name, restored->device_name, sizeof(device->capabilities.device_name));
    }
    return true;
}

bool nxs_device_update_audio_status(nxs_device_t *device, const nxs_runtime_status_t *status) {
    if (!device || !status) {
        return false;
    }
    nxs_runtime_status_t candidate = *status;
    candidate.persisted_generation = device->status.persisted_generation;
    candidate.storage_available = device->status.storage_available;
    uint8_t payload[NXS_RUNTIME_STATUS_SIZE];
    if (nxs_runtime_status_encode(&candidate, payload, sizeof(payload)) != NXS_RESULT_OK) {
        return false;
    }
    device->status = candidate;
    return true;
}

static nxs_message_t response_for(const nxs_device_t *device, const nxs_message_t *request, nxs_result_t result) {
    nxs_message_t response = {0};
    response.operation = request->operation;
    response.request_id = request->request_id;
    response.flags = NXS_FLAG_RESPONSE;
    response.result = result;
    response.generation = device->generation;
    return response;
}

static bool publish(nxs_device_t *device, const nxs_message_t *response, const uint8_t *request, bool cache) {
    if (nxs_message_encode(response, device->response, sizeof(device->response)) != NXS_RESULT_OK) {
        return false;
    }
    device->response_available = true;
    if (cache) {
        nxs_cached_reply_t *entry = &device->cache[device->cache_next];
        memcpy(entry->request, request, NXS_REPORT_SIZE);
        memcpy(entry->response, device->response, NXS_REPORT_SIZE);
        entry->request_id = response->request_id;
        entry->valid = true;
        device->cache_next = (device->cache_next + 1u) % NXS_DEVICE_REPLY_CACHE_COUNT;
    }
    return true;
}

static bool duplicate_request(nxs_device_t *device, const nxs_message_t *request, const uint8_t *report) {
    for (size_t index = 0; index < NXS_DEVICE_REPLY_CACHE_COUNT; ++index) {
        nxs_cached_reply_t *entry = &device->cache[index];
        if (!entry->valid || entry->request_id != request->request_id) {
            continue;
        }
        if (memcmp(report, entry->request, NXS_REPORT_SIZE) == 0) {
            memcpy(device->response, entry->response, NXS_REPORT_SIZE);
            device->response_available = true;
        } else {
            nxs_message_t response = response_for(device, request, NXS_RESULT_INVALID_REPORT);
            publish(device, &response, report, false);
        }
        return true;
    }
    return false;
}

static void begin_pending(nxs_device_t *device, const nxs_message_t *request, const uint8_t *report) {
    device->pending_can_reply = true;
    device->pending_request = *request;
    memcpy(device->pending_report, report, NXS_REPORT_SIZE);
}

bool nxs_device_receive(nxs_device_t *device, const uint8_t *report, size_t length) {
    nxs_message_t request;
    if (!device || nxs_message_decode(report, length, &request) != NXS_RESULT_OK || (request.flags & NXS_FLAG_RESPONSE)) {
        return false;
    }
    if ((device->apply_pending || device->persistence_pending || device->name_pending) && device->pending_can_reply &&
        request.request_id == device->pending_request.request_id) {
        if (memcmp(report, device->pending_report, NXS_REPORT_SIZE) == 0) {
            device->pending_can_reply = true;
            return true;
        }
        nxs_message_t response = response_for(device, &request, NXS_RESULT_INVALID_REPORT);
        return publish(device, &response, report, false);
    }
    if (duplicate_request(device, &request, report)) {
        return true;
    }
    nxs_message_t response = response_for(device, &request, NXS_RESULT_OK);
    if (request.operation != NXS_OPERATION_APPLY_STATE && request.operation != NXS_OPERATION_SET_NAME && request.payload_length != 0) {
        response.result = NXS_RESULT_INVALID_PARAMETERS;
    } else {
        switch (request.operation) {
        case NXS_OPERATION_CAPABILITIES:
            response.payload_length = NXS_CAPABILITIES_SIZE;
            response.result = nxs_capabilities_encode(&device->capabilities, response.payload, response.payload_length);
            break;
        case NXS_OPERATION_READ_STATE:
            response.payload_length = NXS_SNAPSHOT_SIZE;
            response.result = nxs_snapshot_encode(&device->active, response.payload, response.payload_length);
            break;
        case NXS_OPERATION_STATUS:
            response.payload_length = NXS_RUNTIME_STATUS_SIZE;
            response.result = nxs_runtime_status_encode(&device->status, response.payload, response.payload_length);
            break;
        case NXS_OPERATION_PERSIST_STATE:
            if (!device->status.storage_available) {
                response.result = NXS_RESULT_STORAGE_UNAVAILABLE;
            } else if (device->apply_pending || device->persistence_pending || device->name_pending) {
                response.result = NXS_RESULT_BUSY;
            } else if (request.generation != device->generation) {
                response.result = NXS_RESULT_STALE_GENERATION;
            } else {
                device->persistence_pending = true;
                device->pending_snapshot = device->active;
                begin_pending(device, &request, report);
                return true;
            }
            break;
        case NXS_OPERATION_APPLY_STATE:
            if (device->apply_pending || device->persistence_pending || device->name_pending || device->generation == UINT32_MAX) {
                response.result = NXS_RESULT_BUSY;
            } else if (request.generation != device->generation) {
                response.result = NXS_RESULT_STALE_GENERATION;
            } else if (nxs_snapshot_decode(request.payload, request.payload_length, &device->pending_snapshot) != NXS_RESULT_OK ||
                       !nxs_dsp_prepare(&device->pending_snapshot, &device->pending_configuration)) {
                response.result = NXS_RESULT_INVALID_PARAMETERS;
            } else {
                device->apply_pending = true;
                begin_pending(device, &request, report);
                return true;
            }
            break;
        case NXS_OPERATION_SET_NAME:
            if (!device->status.storage_available) {
                response.result = NXS_RESULT_STORAGE_UNAVAILABLE;
            } else if (device->apply_pending || device->persistence_pending || device->name_pending || device->generation == UINT32_MAX) {
                response.result = NXS_RESULT_BUSY;
            } else if (request.generation != device->generation) {
                response.result = NXS_RESULT_STALE_GENERATION;
            } else if (nxs_device_name_decode(request.payload, request.payload_length, device->pending_name) != NXS_RESULT_OK) {
                response.result = NXS_RESULT_INVALID_PARAMETERS;
            } else {
                device->name_pending = true;
                begin_pending(device, &request, report);
                return true;
            }
            break;
        }
    }
    if (response.result != NXS_RESULT_OK) {
        response.payload_length = 0;
    }
    return publish(device, &response, report, true);
}

bool nxs_device_response(const nxs_device_t *device, uint8_t *report, size_t length) {
    if (!device || !report || length != NXS_REPORT_SIZE || !device->response_available) {
        return false;
    }
    memcpy(report, device->response, NXS_REPORT_SIZE);
    return true;
}

const nxs_dsp_configuration_t *nxs_device_pending_configuration(const nxs_device_t *device) {
    return device && device->apply_pending ? &device->pending_configuration : NULL;
}

static void complete_pending(nxs_device_t *device, nxs_result_t result) {
    nxs_message_t response = response_for(device, &device->pending_request, result);
    if (device->pending_can_reply) {
        publish(device, &response, device->pending_report, true);
    }
    device->apply_pending = false;
    device->persistence_pending = false;
    device->name_pending = false;
}

bool nxs_device_complete_apply(nxs_device_t *device, nxs_result_t result) {
    if (!device || !device->apply_pending || (unsigned int)result > NXS_RESULT_STORAGE_FAILED) {
        return false;
    }
    if (result == NXS_RESULT_OK) {
        device->active = device->pending_snapshot;
        ++device->generation;
    }
    complete_pending(device, result);
    return true;
}

bool nxs_device_pending_persistence(const nxs_device_t *device, nxs_stored_state_t *state) {
    if (!device || !state || !(device->persistence_pending || device->name_pending)) {
        return false;
    }
    nxs_stored_state_t candidate = {0};
    candidate.snapshot = device->persistence_pending ? device->pending_snapshot : device->active;
    candidate.generation = device->persistence_pending ? device->pending_request.generation : device->generation + 1u;
    const char *name = device->name_pending ? device->pending_name : device->capabilities.device_name;
    memcpy(candidate.device_name, name, sizeof(candidate.device_name));
    *state = candidate;
    return true;
}

bool nxs_device_complete_persistence(nxs_device_t *device, nxs_result_t result) {
    if (!device || (!device->persistence_pending && !device->name_pending) || (unsigned int)result > NXS_RESULT_STORAGE_FAILED) {
        return false;
    }
    if (result == NXS_RESULT_OK) {
        if (device->persistence_pending) {
            device->status.persisted_generation = device->pending_request.generation;
        } else {
            memcpy(device->capabilities.device_name, device->pending_name, sizeof(device->capabilities.device_name));
            ++device->generation;
            device->status.persisted_generation = device->generation;
        }
    }
    complete_pending(device, result);
    return true;
}

void nxs_device_reset_session(nxs_device_t *device) {
    if (!device) {
        return;
    }
    memset(device->cache, 0, sizeof(device->cache));
    device->cache_next = 0;
    device->response_available = false;
    device->pending_can_reply = false;
}
