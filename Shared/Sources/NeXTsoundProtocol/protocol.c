#include "nxs_protocol.h"

#include <float.h>
#include <math.h>
#include <string.h>

_Static_assert(sizeof(float) == 4 && FLT_RADIX == 2 && FLT_MANT_DIG == 24 && FLT_MAX_EXP == 128, "Protocol v1 requires IEEE-754 binary32");

static const nxs_parameter_range_t parameter_ranges[NXS_PARAMETER_COUNT] = {
    {20.0f, 5000.0f}, {20.0f, 20000.0f}, {-12.0f, 12.0f}, {0.2f, 10.0f}, {-80.0f, 0.0f}, {-36.0f, -1.0f}, {10.0f, 2000.0f}};
static const uint8_t protocol_magic[] = {'N', 'X', 'S', '1'};
static const uint16_t known_features =
    NXS_FEATURE_PERSISTENCE | NXS_FEATURE_FLASH_VERIFIED | NXS_FEATURE_DIAGNOSTICS | NXS_FEATURE_METADATA;

#define NXS_METADATA_SERIAL_OFFSET 4u
#define NXS_METADATA_SERIAL_BYTES 3u
#define NXS_METADATA_FLAGS_OFFSET (NXS_METADATA_SERIAL_OFFSET + NXS_METADATA_SERIAL_BYTES)
#define NXS_METADATA_OWNER_OFFSET (NXS_METADATA_FLAGS_OFFSET + 1u)
#define NXS_METADATA_NOTE_OFFSET (NXS_METADATA_OWNER_OFFSET + NXS_OWNER_NAME_LENGTH)
_Static_assert(NXS_METADATA_NOTE_OFFSET + NXS_OWNER_NOTE_LENGTH == NXS_METADATA_SIZE, "The metadata block holds every field");
_Static_assert(NXS_METADATA_PART_SIZE *NXS_METADATA_PART_COUNT == NXS_METADATA_SIZE, "The parts cover the metadata block");
_Static_assert(NXS_METADATA_WRITE_SIZE <= NXS_PAYLOAD_CAPACITY, "A metadata part fits one report");

static void write_u16(uint8_t *destination, uint16_t value) {
    destination[0] = (uint8_t)value;
    destination[1] = (uint8_t)(value >> 8);
}

static uint16_t read_u16(const uint8_t *source) {
    return (uint16_t)((uint16_t)source[0] | ((uint16_t)source[1] << 8));
}

static void write_u32(uint8_t *destination, uint32_t value) {
    for (size_t byte_index = 0; byte_index < 4; ++byte_index) {
        destination[byte_index] = (uint8_t)(value >> (byte_index * 8));
    }
}

static uint32_t read_u32(const uint8_t *source) {
    uint32_t value = 0;
    for (size_t byte_index = 0; byte_index < 4; ++byte_index) {
        value |= (uint32_t)source[byte_index] << (byte_index * 8);
    }
    return value;
}

static void write_float(uint8_t *destination, float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    write_u32(destination, bits);
}

static float read_float(const uint8_t *source) {
    uint32_t bits = read_u32(source);
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static bool all_zero(const uint8_t *bytes, size_t length) {
    for (size_t byte_index = 0; byte_index < length; ++byte_index) {
        if (bytes[byte_index] != 0) {
            return false;
        }
    }
    return true;
}

static bool within_range(float value, nxs_parameter_t parameter) {
    nxs_parameter_range_t range = parameter_ranges[parameter];
    return isfinite(value) && value >= range.minimum && value <= range.maximum;
}

static bool operation_is_valid(nxs_operation_t operation) {
    return operation >= NXS_OPERATION_CAPABILITIES && operation <= NXS_OPERATION_WRITE_METADATA;
}

/** Operations added in a later envelope revision require it, so a client of an earlier one never meets them. */
static uint8_t minimum_minor(nxs_operation_t operation) {
    switch (operation) {
    case NXS_OPERATION_DIAGNOSTICS:
        return NXS_DIAGNOSTICS_PROTOCOL_MINOR;
    case NXS_OPERATION_READ_METADATA:
    case NXS_OPERATION_WRITE_METADATA:
        return NXS_METADATA_PROTOCOL_MINOR;
    default:
        return NXS_PROTOCOL_LEGACY_MINOR;
    }
}

static nxs_result_t validate_message(const nxs_message_t *message) {
    if (!message || message->payload_length > NXS_PAYLOAD_CAPACITY || message->request_id == 0 ||
        (message->flags & ~NXS_FLAG_RESPONSE) != 0 || (unsigned int)message->result > NXS_RESULT_STORAGE_FAILED ||
        (!(message->flags & NXS_FLAG_RESPONSE) && message->result != NXS_RESULT_OK)) {
        return NXS_RESULT_INVALID_REPORT;
    }
    if (message->protocol_minor > NXS_PROTOCOL_MINOR || message->protocol_minor < minimum_minor(message->operation)) {
        return NXS_RESULT_UNSUPPORTED_VERSION;
    }
    return operation_is_valid(message->operation) ? NXS_RESULT_OK : NXS_RESULT_UNKNOWN_OPERATION;
}

static bool text_is_valid(const char text[17]) {
    if (text[0] == 0) {
        return false;
    }
    for (size_t character_index = 0; character_index < 17; ++character_index) {
        unsigned char character = (unsigned char)text[character_index];
        if (character == 0) {
            return true;
        }
        if (character_index == 16 || character < 0x21 || character > 0x7e) {
            return false;
        }
    }
    return false;
}

static bool decode_text(const uint8_t *source, char destination[17]) {
    bool terminated = false;
    memset(destination, 0, 17);
    for (size_t character_index = 0; character_index < 16; ++character_index) {
        if (source[character_index] == 0) {
            terminated = true;
        } else if (terminated || source[character_index] < 0x21 || source[character_index] > 0x7e) {
            return false;
        }
        destination[character_index] = (char)source[character_index];
    }
    return text_is_valid(destination);
}

static void encode_text(uint8_t *destination, const char source[17]) {
    for (size_t character_index = 0; character_index < 16 && source[character_index] != 0; ++character_index) {
        destination[character_index] = (uint8_t)source[character_index];
    }
}

/**
 * Unlike text_is_valid, an empty name is valid (no custom name stored yet), and a space is
 * allowed: this is a human-chosen label like "Bedroom SoundBox", not an identifier.
 */
static bool device_name_characters_valid(const char name[NXS_DEVICE_NAME_LENGTH]) {
    if (name[0] == 0) {
        return true;
    }
    for (size_t character_index = 0; character_index < NXS_DEVICE_NAME_LENGTH; ++character_index) {
        unsigned char character = (unsigned char)name[character_index];
        if (character == 0) {
            return true;
        }
        if (character_index == NXS_DEVICE_NAME_LENGTH - 1 || character < 0x20 || character > 0x7e) {
            return false;
        }
    }
    return false;
}

static bool decode_device_name(const uint8_t *source, char destination[NXS_DEVICE_NAME_LENGTH]) {
    bool terminated = false;
    memset(destination, 0, NXS_DEVICE_NAME_LENGTH);
    for (size_t character_index = 0; character_index < NXS_DEVICE_NAME_LENGTH - 1; ++character_index) {
        if (source[character_index] == 0) {
            terminated = true;
        } else if (terminated || source[character_index] < 0x20 || source[character_index] > 0x7e) {
            return false;
        }
        destination[character_index] = (char)source[character_index];
    }
    return device_name_characters_valid(destination);
}

static void encode_device_name(uint8_t *destination, const char source[NXS_DEVICE_NAME_LENGTH]) {
    for (size_t character_index = 0; character_index < NXS_DEVICE_NAME_LENGTH - 1 && source[character_index] != 0; ++character_index) {
        destination[character_index] = (uint8_t)source[character_index];
    }
}

static bool capabilities_are_valid(const nxs_capabilities_t *capabilities) {
    if (!capabilities || capabilities->sample_rate_hz != NXS_SAMPLE_RATE_HZ || capabilities->system_clock_hz != NXS_SYSTEM_CLOCK_HZ ||
        capabilities->eq_band_count != NXS_EQ_BAND_COUNT || capabilities->sample_format_mask == 0 ||
        (capabilities->sample_format_mask & ~(NXS_FORMAT_PCM16 | NXS_FORMAT_PCM24)) || (capabilities->feature_flags & ~known_features) ||
        !text_is_valid(capabilities->device_serial) || !text_is_valid(capabilities->firmware_version) ||
        !device_name_characters_valid(capabilities->device_name)) {
        return false;
    }
    if ((capabilities->feature_flags & NXS_FEATURE_FLASH_VERIFIED) && capabilities->flash_size_bytes == 0) {
        return false;
    }
    if ((capabilities->feature_flags & NXS_FEATURE_PERSISTENCE) && !(capabilities->feature_flags & NXS_FEATURE_FLASH_VERIFIED)) {
        return false;
    }
    if ((capabilities->feature_flags & NXS_FEATURE_METADATA) && !(capabilities->feature_flags & NXS_FEATURE_PERSISTENCE)) {
        return false;
    }
    for (size_t parameter_index = 0; parameter_index < NXS_PARAMETER_COUNT; ++parameter_index) {
        nxs_parameter_range_t range = capabilities->ranges[parameter_index];
        nxs_parameter_range_t supported = parameter_ranges[parameter_index];
        if (!isfinite(range.minimum) || !isfinite(range.maximum) || range.minimum > range.maximum || range.minimum < supported.minimum ||
            range.maximum > supported.maximum) {
            return false;
        }
    }
    return true;
}

bool nxs_host_volume_is_valid(float volume_db) {
    return isfinite(volume_db) && volume_db >= NXS_HOST_VOLUME_MIN_DB && volume_db <= NXS_HOST_VOLUME_MAX_DB;
}

static bool runtime_status_is_valid(const nxs_runtime_status_t *status) {
    return status && status->streaming <= 1 && status->host_muted <= 1 && status->storage_available <= 1 && isfinite(status->input_peak) &&
           status->input_peak >= 0.0f && status->input_peak <= 1.0f && isfinite(status->output_peak) && status->output_peak >= 0.0f &&
           status->output_peak <= 1.0f && nxs_host_volume_is_valid(status->host_volume_db);
}

nxs_parameter_range_t nxs_parameter_range(nxs_parameter_t parameter) {
    if ((unsigned int)parameter >= NXS_PARAMETER_COUNT) {
        return (nxs_parameter_range_t){0.0f, 0.0f};
    }
    return parameter_ranges[parameter];
}

nxs_snapshot_t nxs_default_snapshot(void) {
    nxs_snapshot_t snapshot = {0};
    snapshot.muted = 1;
    snapshot.high_pass_hz = 80.0f;
    snapshot.attenuation_db = -24.0f;
    snapshot.limiter_threshold_db = -3.0f;
    snapshot.limiter_release_ms = 120.0f;
    static const float center_frequencies[NXS_EQ_BAND_COUNT] = {100.0f, 300.0f, 1000.0f, 3000.0f, 10000.0f};
    for (size_t band_index = 0; band_index < NXS_EQ_BAND_COUNT; ++band_index) {
        snapshot.bands[band_index] = (nxs_eq_band_t){center_frequencies[band_index], 0.0f, 1.0f, 1};
    }
    return snapshot;
}

nxs_capabilities_t nxs_default_capabilities(void) {
    nxs_capabilities_t capabilities = {0};
    capabilities.sample_rate_hz = NXS_SAMPLE_RATE_HZ;
    capabilities.system_clock_hz = NXS_SYSTEM_CLOCK_HZ;
    capabilities.eq_band_count = NXS_EQ_BAND_COUNT;
    capabilities.sample_format_mask = NXS_FORMAT_PCM16 | NXS_FORMAT_PCM24;
    memcpy(capabilities.ranges, parameter_ranges, sizeof(parameter_ranges));
    return capabilities;
}

bool nxs_snapshot_is_valid(const nxs_snapshot_t *snapshot) {
    if (!snapshot || snapshot->muted > 1 || snapshot->high_pass_enabled > 1 ||
        !within_range(snapshot->high_pass_hz, NXS_PARAMETER_HIGH_PASS_HZ) ||
        !within_range(snapshot->attenuation_db, NXS_PARAMETER_ATTENUATION_DB) ||
        !within_range(snapshot->limiter_threshold_db, NXS_PARAMETER_LIMITER_THRESHOLD_DB) ||
        !within_range(snapshot->limiter_release_ms, NXS_PARAMETER_LIMITER_RELEASE_MS)) {
        return false;
    }
    for (size_t band_index = 0; band_index < NXS_EQ_BAND_COUNT; ++band_index) {
        nxs_eq_band_t band = snapshot->bands[band_index];
        if (band.enabled > 1 || !within_range(band.frequency_hz, NXS_PARAMETER_EQ_HZ) ||
            !within_range(band.gain_db, NXS_PARAMETER_EQ_GAIN_DB) || !within_range(band.quality, NXS_PARAMETER_EQ_QUALITY)) {
            return false;
        }
    }
    return true;
}

bool nxs_device_name_is_valid(const char name[NXS_DEVICE_NAME_LENGTH]) {
    return name && device_name_characters_valid(name);
}

static bool date_is_valid(uint32_t date) {
    static const uint8_t days_in_month[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    if (date == 0) {
        return true;
    }
    uint32_t year = date / 10000u;
    uint32_t month = date / 100u % 100u;
    uint32_t day = date % 100u;
    if (year == 0 || year > 9999u || month == 0 || month > 12u || day == 0) {
        return false;
    }
    bool leap_year = (year % 4u == 0 && year % 100u != 0) || year % 400u == 0;
    return day <= days_in_month[month - 1u] + (month == 2u && leap_year ? 1u : 0u);
}

/** Well-formed UTF-8 up to the first zero byte, without control characters except a permitted line feed, then zeros. */
static bool padded_text_is_valid(const uint8_t *text, size_t length, bool allows_line_feed) {
    size_t index = 0;
    while (index < length && text[index] != 0) {
        uint8_t lead = text[index];
        if (lead < 0x80) {
            if ((lead < 0x20 && !(allows_line_feed && lead == '\n')) || lead == 0x7f) {
                return false;
            }
            ++index;
            continue;
        }
        size_t continuation;
        uint8_t first_minimum = 0x80;
        uint8_t first_maximum = 0xbf;
        if (lead >= 0xc2 && lead <= 0xdf) {
            continuation = 1;
        } else if (lead >= 0xe0 && lead <= 0xef) {
            continuation = 2;
            first_minimum = lead == 0xe0 ? 0xa0 : 0x80;
            first_maximum = lead == 0xed ? 0x9f : 0xbf;
        } else if (lead >= 0xf0 && lead <= 0xf4) {
            continuation = 3;
            first_minimum = lead == 0xf0 ? 0x90 : 0x80;
            first_maximum = lead == 0xf4 ? 0x8f : 0xbf;
        } else {
            return false;
        }
        if (continuation >= length - index) {
            return false;
        }
        for (size_t offset = 1; offset <= continuation; ++offset) {
            uint8_t byte = text[index + offset];
            if (byte < (offset == 1 ? first_minimum : 0x80) || byte > (offset == 1 ? first_maximum : 0xbf)) {
                return false;
            }
        }
        index += continuation + 1;
    }
    return all_zero(text + index, length - index);
}

bool nxs_metadata_serial_number_is_set(uint8_t flags, uint32_t serial_number) {
    return (flags & NXS_METADATA_FLAG_SERIAL_NUMBER) != 0 || serial_number != 0;
}

bool nxs_owner_metadata_is_valid(const nxs_owner_metadata_t *metadata) {
    return metadata && date_is_valid(metadata->date) && metadata->serial_number <= NXS_SERIAL_NUMBER_MAX &&
           (metadata->has_serial_number || metadata->serial_number == 0) &&
           padded_text_is_valid(metadata->owner, NXS_OWNER_NAME_LENGTH, false) &&
           padded_text_is_valid(metadata->note, NXS_OWNER_NOTE_LENGTH, true);
}

const char *nxs_result_description(nxs_result_t result) {
    switch (result) {
    case NXS_RESULT_OK:
        return "Success";
    case NXS_RESULT_INVALID_REPORT:
        return "Invalid report";
    case NXS_RESULT_UNSUPPORTED_VERSION:
        return "Unsupported protocol version";
    case NXS_RESULT_UNKNOWN_OPERATION:
        return "Unknown operation";
    case NXS_RESULT_INVALID_PARAMETERS:
        return "Invalid parameters";
    case NXS_RESULT_STALE_GENERATION:
        return "Device state changed";
    case NXS_RESULT_BUSY:
        return "Device busy";
    case NXS_RESULT_STORAGE_UNAVAILABLE:
        return "Storage unavailable";
    case NXS_RESULT_STORAGE_FAILED:
        return "Storage verification failed";
    default:
        return "Unknown protocol result";
    }
}

nxs_result_t nxs_message_encode(const nxs_message_t *message, uint8_t *report, size_t length) {
    if (!report || length != NXS_REPORT_SIZE) {
        return NXS_RESULT_INVALID_REPORT;
    }
    nxs_result_t result = validate_message(message);
    if (result != NXS_RESULT_OK) {
        return result;
    }
    memset(report, 0, length);
    report[0] = NXS_REPORT_ID;
    report[1] = NXS_PROTOCOL_MAJOR;
    report[2] = message->protocol_minor;
    report[3] = (uint8_t)message->operation;
    memcpy(report + 4, protocol_magic, sizeof(protocol_magic));
    report[8] = message->flags;
    report[9] = (uint8_t)message->result;
    write_u16(report + 10, message->payload_length);
    write_u32(report + 12, message->request_id);
    write_u32(report + 16, message->generation);
    memcpy(report + NXS_HEADER_SIZE, message->payload, message->payload_length);
    return NXS_RESULT_OK;
}

nxs_result_t nxs_message_decode(const uint8_t *report, size_t length, nxs_message_t *message) {
    if (!report || !message || length != NXS_REPORT_SIZE || report[0] != NXS_REPORT_ID ||
        memcmp(report + 4, protocol_magic, sizeof(protocol_magic)) != 0) {
        return NXS_RESULT_INVALID_REPORT;
    }
    if (report[1] != NXS_PROTOCOL_MAJOR || report[2] > NXS_PROTOCOL_MINOR) {
        return NXS_RESULT_UNSUPPORTED_VERSION;
    }
    nxs_message_t candidate = {0};
    candidate.operation = (nxs_operation_t)report[3];
    candidate.protocol_minor = report[2];
    candidate.flags = report[8];
    candidate.result = (nxs_result_t)report[9];
    candidate.payload_length = read_u16(report + 10);
    candidate.request_id = read_u32(report + 12);
    candidate.generation = read_u32(report + 16);
    nxs_result_t result = validate_message(&candidate);
    if (result != NXS_RESULT_OK) {
        return result;
    }
    if (!all_zero(report + NXS_HEADER_SIZE + candidate.payload_length, NXS_PAYLOAD_CAPACITY - candidate.payload_length)) {
        return NXS_RESULT_INVALID_REPORT;
    }
    memcpy(candidate.payload, report + NXS_HEADER_SIZE, candidate.payload_length);
    *message = candidate;
    return NXS_RESULT_OK;
}

nxs_result_t nxs_snapshot_encode(const nxs_snapshot_t *snapshot, uint8_t *payload, size_t length) {
    if (!payload || length != NXS_SNAPSHOT_SIZE) {
        return NXS_RESULT_INVALID_REPORT;
    }
    if (!nxs_snapshot_is_valid(snapshot)) {
        return NXS_RESULT_INVALID_PARAMETERS;
    }
    memset(payload, 0, length);
    memcpy(payload, snapshot->profile_id, 16);
    write_u32(payload + 16, snapshot->profile_revision);
    payload[20] = snapshot->high_pass_enabled;
    payload[21] = snapshot->muted;
    write_float(payload + 24, snapshot->high_pass_hz);
    write_float(payload + 28, snapshot->attenuation_db);
    write_float(payload + 32, snapshot->limiter_threshold_db);
    write_float(payload + 36, snapshot->limiter_release_ms);
    for (size_t band_index = 0; band_index < NXS_EQ_BAND_COUNT; ++band_index) {
        size_t offset = 40 + band_index * 16;
        nxs_eq_band_t band = snapshot->bands[band_index];
        write_float(payload + offset, band.frequency_hz);
        write_float(payload + offset + 4, band.gain_db);
        write_float(payload + offset + 8, band.quality);
        payload[offset + 12] = band.enabled;
    }
    return NXS_RESULT_OK;
}

nxs_result_t nxs_snapshot_decode(const uint8_t *payload, size_t length, nxs_snapshot_t *snapshot) {
    if (!payload || !snapshot || length != NXS_SNAPSHOT_SIZE || !all_zero(payload + 22, 2)) {
        return NXS_RESULT_INVALID_REPORT;
    }
    nxs_snapshot_t candidate = {0};
    memcpy(candidate.profile_id, payload, 16);
    candidate.profile_revision = read_u32(payload + 16);
    candidate.high_pass_enabled = payload[20];
    candidate.muted = payload[21];
    candidate.high_pass_hz = read_float(payload + 24);
    candidate.attenuation_db = read_float(payload + 28);
    candidate.limiter_threshold_db = read_float(payload + 32);
    candidate.limiter_release_ms = read_float(payload + 36);
    for (size_t band_index = 0; band_index < NXS_EQ_BAND_COUNT; ++band_index) {
        size_t offset = 40 + band_index * 16;
        if (!all_zero(payload + offset + 13, 3)) {
            return NXS_RESULT_INVALID_REPORT;
        }
        candidate.bands[band_index] = (nxs_eq_band_t){read_float(payload + offset), read_float(payload + offset + 4),
                                                      read_float(payload + offset + 8), payload[offset + 12]};
    }
    if (!nxs_snapshot_is_valid(&candidate)) {
        return NXS_RESULT_INVALID_PARAMETERS;
    }
    *snapshot = candidate;
    return NXS_RESULT_OK;
}

nxs_result_t nxs_capabilities_encode(const nxs_capabilities_t *capabilities, uint8_t *payload, size_t length) {
    if (!payload || length != NXS_CAPABILITIES_SIZE) {
        return NXS_RESULT_INVALID_REPORT;
    }
    if (!capabilities_are_valid(capabilities)) {
        return NXS_RESULT_INVALID_PARAMETERS;
    }
    memset(payload, 0, length);
    write_u32(payload, capabilities->sample_rate_hz);
    write_u32(payload + 4, capabilities->system_clock_hz);
    write_u32(payload + 8, capabilities->flash_size_bytes);
    payload[12] = capabilities->eq_band_count;
    payload[13] = capabilities->sample_format_mask;
    write_u16(payload + 14, capabilities->feature_flags);
    encode_text(payload + 16, capabilities->device_serial);
    encode_text(payload + 32, capabilities->firmware_version);
    for (size_t parameter_index = 0; parameter_index < NXS_PARAMETER_COUNT; ++parameter_index) {
        size_t offset = 48 + parameter_index * 8;
        write_float(payload + offset, capabilities->ranges[parameter_index].minimum);
        write_float(payload + offset + 4, capabilities->ranges[parameter_index].maximum);
    }
    encode_device_name(payload + 104, capabilities->device_name);
    return NXS_RESULT_OK;
}

nxs_result_t nxs_capabilities_decode(const uint8_t *payload, size_t length, nxs_capabilities_t *capabilities) {
    if (!payload || !capabilities || length != NXS_CAPABILITIES_SIZE) {
        return NXS_RESULT_INVALID_REPORT;
    }
    nxs_capabilities_t candidate = {0};
    candidate.sample_rate_hz = read_u32(payload);
    candidate.system_clock_hz = read_u32(payload + 4);
    candidate.flash_size_bytes = read_u32(payload + 8);
    candidate.eq_band_count = payload[12];
    candidate.sample_format_mask = payload[13];
    /* Bits a later firmware adds are dropped rather than refused, so a newer board never locks out this app. */
    candidate.feature_flags = read_u16(payload + 14) & known_features;
    if (!decode_text(payload + 16, candidate.device_serial) || !decode_text(payload + 32, candidate.firmware_version)) {
        return NXS_RESULT_INVALID_PARAMETERS;
    }
    for (size_t parameter_index = 0; parameter_index < NXS_PARAMETER_COUNT; ++parameter_index) {
        size_t offset = 48 + parameter_index * 8;
        candidate.ranges[parameter_index] = (nxs_parameter_range_t){read_float(payload + offset), read_float(payload + offset + 4)};
    }
    if (!decode_device_name(payload + 104, candidate.device_name)) {
        return NXS_RESULT_INVALID_PARAMETERS;
    }
    if (!capabilities_are_valid(&candidate)) {
        return NXS_RESULT_INVALID_PARAMETERS;
    }
    *capabilities = candidate;
    return NXS_RESULT_OK;
}

nxs_result_t nxs_device_name_encode(const char name[NXS_DEVICE_NAME_LENGTH], uint8_t *payload, size_t length) {
    if (!payload || length != NXS_DEVICE_NAME_LENGTH) {
        return NXS_RESULT_INVALID_REPORT;
    }
    if (!device_name_characters_valid(name)) {
        return NXS_RESULT_INVALID_PARAMETERS;
    }
    memset(payload, 0, length);
    encode_device_name(payload, name);
    return NXS_RESULT_OK;
}

nxs_result_t nxs_device_name_decode(const uint8_t *payload, size_t length, char name[NXS_DEVICE_NAME_LENGTH]) {
    if (!payload || !name || length != NXS_DEVICE_NAME_LENGTH) {
        return NXS_RESULT_INVALID_REPORT;
    }
    char candidate[NXS_DEVICE_NAME_LENGTH];
    if (!decode_device_name(payload, candidate)) {
        return NXS_RESULT_INVALID_PARAMETERS;
    }
    memcpy(name, candidate, NXS_DEVICE_NAME_LENGTH);
    return NXS_RESULT_OK;
}

nxs_result_t nxs_owner_metadata_encode(const nxs_owner_metadata_t *metadata, uint8_t *block, size_t length) {
    if (!block || length != NXS_METADATA_SIZE) {
        return NXS_RESULT_INVALID_REPORT;
    }
    if (!nxs_owner_metadata_is_valid(metadata)) {
        return NXS_RESULT_INVALID_PARAMETERS;
    }
    write_u32(block, metadata->date);
    for (size_t byte_index = 0; byte_index < NXS_METADATA_SERIAL_BYTES; ++byte_index) {
        block[NXS_METADATA_SERIAL_OFFSET + byte_index] = (uint8_t)(metadata->serial_number >> (byte_index * 8));
    }
    block[NXS_METADATA_FLAGS_OFFSET] = metadata->has_serial_number ? NXS_METADATA_FLAG_SERIAL_NUMBER : 0u;
    memcpy(block + NXS_METADATA_OWNER_OFFSET, metadata->owner, NXS_OWNER_NAME_LENGTH);
    memcpy(block + NXS_METADATA_NOTE_OFFSET, metadata->note, NXS_OWNER_NOTE_LENGTH);
    return NXS_RESULT_OK;
}

nxs_result_t nxs_owner_metadata_decode(const uint8_t *block, size_t length, nxs_owner_metadata_t *metadata) {
    if (!block || !metadata || length != NXS_METADATA_SIZE || (block[NXS_METADATA_FLAGS_OFFSET] & ~NXS_METADATA_FLAG_SERIAL_NUMBER) != 0) {
        return NXS_RESULT_INVALID_REPORT;
    }
    nxs_owner_metadata_t candidate = {.date = read_u32(block)};
    for (size_t byte_index = 0; byte_index < NXS_METADATA_SERIAL_BYTES; ++byte_index) {
        candidate.serial_number |= (uint32_t)block[NXS_METADATA_SERIAL_OFFSET + byte_index] << (byte_index * 8);
    }
    candidate.has_serial_number = nxs_metadata_serial_number_is_set(block[NXS_METADATA_FLAGS_OFFSET], candidate.serial_number);
    memcpy(candidate.owner, block + NXS_METADATA_OWNER_OFFSET, NXS_OWNER_NAME_LENGTH);
    memcpy(candidate.note, block + NXS_METADATA_NOTE_OFFSET, NXS_OWNER_NOTE_LENGTH);
    if (!nxs_owner_metadata_is_valid(&candidate)) {
        return NXS_RESULT_INVALID_PARAMETERS;
    }
    *metadata = candidate;
    return NXS_RESULT_OK;
}

nxs_result_t nxs_runtime_status_encode(const nxs_runtime_status_t *status, uint8_t *payload, size_t length) {
    if (!payload || length != NXS_RUNTIME_STATUS_SIZE) {
        return NXS_RESULT_INVALID_REPORT;
    }
    if (!runtime_status_is_valid(status)) {
        return NXS_RESULT_INVALID_PARAMETERS;
    }
    memset(payload, 0, length);
    write_u32(payload, status->persisted_generation);
    write_u32(payload + 4, status->underrun_count);
    write_u32(payload + 8, status->overrun_count);
    write_u32(payload + 12, status->max_processing_us);
    write_u32(payload + 16, status->block_deadline_us);
    write_float(payload + 20, status->input_peak);
    write_float(payload + 24, status->output_peak);
    write_float(payload + 28, status->host_volume_db);
    payload[32] = status->streaming;
    payload[33] = status->host_muted;
    payload[34] = status->storage_available;
    return NXS_RESULT_OK;
}

nxs_result_t nxs_runtime_status_decode(const uint8_t *payload, size_t length, nxs_runtime_status_t *status) {
    if (!payload || !status || length != NXS_RUNTIME_STATUS_SIZE || !all_zero(payload + 35, 5)) {
        return NXS_RESULT_INVALID_REPORT;
    }
    nxs_runtime_status_t candidate = {0};
    candidate.persisted_generation = read_u32(payload);
    candidate.underrun_count = read_u32(payload + 4);
    candidate.overrun_count = read_u32(payload + 8);
    candidate.max_processing_us = read_u32(payload + 12);
    candidate.block_deadline_us = read_u32(payload + 16);
    candidate.input_peak = read_float(payload + 20);
    candidate.output_peak = read_float(payload + 24);
    candidate.host_volume_db = read_float(payload + 28);
    candidate.streaming = payload[32];
    candidate.host_muted = payload[33];
    candidate.storage_available = payload[34];
    if (!runtime_status_is_valid(&candidate)) {
        return NXS_RESULT_INVALID_PARAMETERS;
    }
    *status = candidate;
    return NXS_RESULT_OK;
}

nxs_result_t nxs_runtime_diagnostics_encode(const nxs_runtime_diagnostics_t *diagnostics, uint8_t *payload, size_t length) {
    if (!diagnostics || !payload || length != NXS_RUNTIME_DIAGNOSTICS_SIZE) {
        return NXS_RESULT_INVALID_REPORT;
    }
    write_u16(payload, NXS_DIAGNOSTICS_VERSION);
    write_u16(payload + 2, NXS_RUNTIME_DIAGNOSTICS_SIZE);
    write_u32(payload + 4, diagnostics->ring_underrun_count);
    write_u32(payload + 8, diagnostics->i2s_stall_count);
    write_u32(payload + 12, diagnostics->rejected_packet_count);
    write_u32(payload + 16, diagnostics->dsp_failure_count);
    write_u32(payload + 20, diagnostics->deadline_miss_count);
    write_u32(payload + 24, diagnostics->usb_suspend_count);
    write_u32(payload + 28, diagnostics->usb_resume_count);
    return NXS_RESULT_OK;
}

nxs_result_t nxs_runtime_diagnostics_decode(const uint8_t *payload, size_t length, nxs_runtime_diagnostics_t *diagnostics) {
    if (!payload || !diagnostics || length != NXS_RUNTIME_DIAGNOSTICS_SIZE || read_u16(payload + 2) != NXS_RUNTIME_DIAGNOSTICS_SIZE) {
        return NXS_RESULT_INVALID_REPORT;
    }
    if (read_u16(payload) != NXS_DIAGNOSTICS_VERSION) {
        return NXS_RESULT_UNSUPPORTED_VERSION;
    }
    nxs_runtime_diagnostics_t candidate = {.ring_underrun_count = read_u32(payload + 4),
                                           .i2s_stall_count = read_u32(payload + 8),
                                           .rejected_packet_count = read_u32(payload + 12),
                                           .dsp_failure_count = read_u32(payload + 16),
                                           .deadline_miss_count = read_u32(payload + 20),
                                           .usb_suspend_count = read_u32(payload + 24),
                                           .usb_resume_count = read_u32(payload + 28)};
    *diagnostics = candidate;
    return NXS_RESULT_OK;
}
