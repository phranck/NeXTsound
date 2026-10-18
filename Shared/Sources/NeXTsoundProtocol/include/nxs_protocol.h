#ifndef NXS_PROTOCOL_H
#define NXS_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NXS_PROTOCOL_MAJOR 1u
#define NXS_PROTOCOL_MINOR 1u
#define NXS_PROTOCOL_LEGACY_MINOR 0u
#define NXS_DIAGNOSTICS_PROTOCOL_MINOR 1u
#define NXS_SNAPSHOT_PROTOCOL_MAJOR 1u
#define NXS_SNAPSHOT_PROTOCOL_MINOR 0u
#define NXS_DIAGNOSTICS_VERSION 1u
/** TinyUSB example identity for private bench builds, not an allocated release VID/PID. */
#define NXS_USB_VENDOR_ID 0xcafeu
#define NXS_USB_PRODUCT_ID 0x4014u
#define NXS_HID_USAGE_PAGE 0xff4eu
#define NXS_HID_USAGE 1u
#define NXS_REPORT_ID 1u
#define NXS_REPORT_SIZE 256u
#define NXS_HEADER_SIZE 20u
#define NXS_PAYLOAD_CAPACITY (NXS_REPORT_SIZE - NXS_HEADER_SIZE)
#define NXS_SNAPSHOT_SIZE 120u
#define NXS_CAPABILITIES_SIZE 112u
#define NXS_RUNTIME_STATUS_SIZE 40u
#define NXS_RUNTIME_DIAGNOSTICS_SIZE 32u
#define NXS_EQ_BAND_COUNT 5u
#define NXS_SAMPLE_RATE_HZ 48000u
#define NXS_SYSTEM_CLOCK_HZ 150000000u
#define NXS_HOST_VOLUME_MIN_DB (-80.0f)
#define NXS_HOST_VOLUME_MAX_DB 0.0f
#define NXS_FLAG_RESPONSE 1u
#define NXS_FORMAT_PCM16 1u
#define NXS_FORMAT_PCM24 2u
#define NXS_FEATURE_PERSISTENCE 1u
#define NXS_FEATURE_FLASH_VERIFIED 2u
#define NXS_FEATURE_DIAGNOSTICS 4u

/** Native structs are never wire images. Use the explicit codecs below. */
typedef enum {
    NXS_OPERATION_CAPABILITIES = 1,
    NXS_OPERATION_READ_STATE = 2,
    NXS_OPERATION_APPLY_STATE = 3,
    NXS_OPERATION_PERSIST_STATE = 4,
    NXS_OPERATION_STATUS = 5,
    NXS_OPERATION_DIAGNOSTICS = 6
} nxs_operation_t;

typedef enum {
    NXS_RESULT_OK = 0,
    NXS_RESULT_INVALID_REPORT = 1,
    NXS_RESULT_UNSUPPORTED_VERSION = 2,
    NXS_RESULT_UNKNOWN_OPERATION = 3,
    NXS_RESULT_INVALID_PARAMETERS = 4,
    NXS_RESULT_STALE_GENERATION = 5,
    NXS_RESULT_BUSY = 6,
    NXS_RESULT_STORAGE_UNAVAILABLE = 7,
    NXS_RESULT_STORAGE_FAILED = 8
} nxs_result_t;

typedef enum {
    NXS_PARAMETER_HIGH_PASS_HZ = 0,
    NXS_PARAMETER_EQ_HZ,
    NXS_PARAMETER_EQ_GAIN_DB,
    NXS_PARAMETER_EQ_QUALITY,
    NXS_PARAMETER_ATTENUATION_DB,
    NXS_PARAMETER_LIMITER_THRESHOLD_DB,
    NXS_PARAMETER_LIMITER_RELEASE_MS,
    NXS_PARAMETER_COUNT
} nxs_parameter_t;

typedef struct {
    float minimum;
    float maximum;
} nxs_parameter_range_t;

typedef struct {
    float frequency_hz;
    float gain_db;
    float quality;
    uint8_t enabled;
} nxs_eq_band_t;

typedef struct {
    uint8_t profile_id[16];
    uint32_t profile_revision;
    uint8_t high_pass_enabled;
    uint8_t muted;
    float high_pass_hz;
    float attenuation_db;
    float limiter_threshold_db;
    float limiter_release_ms;
    nxs_eq_band_t bands[NXS_EQ_BAND_COUNT];
} nxs_snapshot_t;

typedef struct {
    uint32_t sample_rate_hz;
    uint32_t system_clock_hz;
    uint32_t flash_size_bytes;
    uint8_t eq_band_count;
    uint8_t sample_format_mask;
    uint16_t feature_flags;
    char device_serial[17];
    char firmware_version[17];
    nxs_parameter_range_t ranges[NXS_PARAMETER_COUNT];
} nxs_capabilities_t;

typedef struct {
    uint32_t persisted_generation;
    uint32_t underrun_count;
    uint32_t overrun_count;
    uint32_t max_processing_us;
    uint32_t block_deadline_us;
    float input_peak;
    float output_peak;
    float host_volume_db;
    uint8_t streaming;
    uint8_t host_muted;
    uint8_t storage_available;
} nxs_runtime_status_t;

/** Boot-session counters wrap modulo 2^32. USB fields count callback notifications. */
typedef struct {
    uint32_t ring_underrun_count;
    uint32_t i2s_stall_count;
    uint32_t rejected_packet_count;
    uint32_t dsp_failure_count;
    uint32_t deadline_miss_count;
    uint32_t usb_suspend_count;
    uint32_t usb_resume_count;
} nxs_runtime_diagnostics_t;

typedef struct {
    nxs_operation_t operation;
    uint8_t protocol_minor;
    uint8_t flags;
    nxs_result_t result;
    uint32_t request_id;
    uint32_t generation;
    uint16_t payload_length;
    uint8_t payload[NXS_PAYLOAD_CAPACITY];
} nxs_message_t;

nxs_parameter_range_t nxs_parameter_range(nxs_parameter_t parameter);
nxs_snapshot_t nxs_default_snapshot(void);
nxs_capabilities_t nxs_default_capabilities(void);
bool nxs_snapshot_is_valid(const nxs_snapshot_t *snapshot);
bool nxs_host_volume_is_valid(float volume_db);
const char *nxs_result_description(nxs_result_t result);

/** Failure leaves the caller's destination unchanged. Padding must be zero. */
nxs_result_t nxs_message_encode(const nxs_message_t *message, uint8_t *report, size_t length);
nxs_result_t nxs_message_decode(const uint8_t *report, size_t length, nxs_message_t *message);
nxs_result_t nxs_snapshot_encode(const nxs_snapshot_t *snapshot, uint8_t *payload, size_t length);
nxs_result_t nxs_snapshot_decode(const uint8_t *payload, size_t length, nxs_snapshot_t *snapshot);
nxs_result_t nxs_capabilities_encode(const nxs_capabilities_t *capabilities, uint8_t *payload, size_t length);
nxs_result_t nxs_capabilities_decode(const uint8_t *payload, size_t length, nxs_capabilities_t *capabilities);
nxs_result_t nxs_runtime_status_encode(const nxs_runtime_status_t *status, uint8_t *payload, size_t length);
nxs_result_t nxs_runtime_status_decode(const uint8_t *payload, size_t length, nxs_runtime_status_t *status);
nxs_result_t nxs_runtime_diagnostics_encode(const nxs_runtime_diagnostics_t *diagnostics, uint8_t *payload, size_t length);
nxs_result_t nxs_runtime_diagnostics_decode(const uint8_t *payload, size_t length, nxs_runtime_diagnostics_t *diagnostics);

#ifdef __cplusplus
}
#endif
#endif
