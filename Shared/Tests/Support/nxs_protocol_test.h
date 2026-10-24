#ifndef NXS_PROTOCOL_TEST_H
#define NXS_PROTOCOL_TEST_H

#include "nxs_protocol.h"
#include "nxs_test.h"

#include <string.h>

static inline void nxs_test_request(nxs_operation_t operation, uint32_t identifier, uint32_t generation, const nxs_snapshot_t *snapshot,
                                    uint8_t report[NXS_REPORT_SIZE]) {
    nxs_message_t request = {0};
    request.operation = operation;
    request.request_id = identifier;
    request.generation = generation;
    if (snapshot) {
        request.payload_length = NXS_SNAPSHOT_SIZE;
        CHECK(nxs_snapshot_encode(snapshot, request.payload, request.payload_length) == NXS_RESULT_OK);
    }
    CHECK(nxs_message_encode(&request, report, NXS_REPORT_SIZE) == NXS_RESULT_OK);
}

/** Compares field by field, because the struct has padding that a byte comparison would read. */
static inline bool nxs_test_metadata_equal(const nxs_owner_metadata_t *first, const nxs_owner_metadata_t *second) {
    return first->date == second->date && first->has_serial_number == second->has_serial_number &&
           first->serial_number == second->serial_number && memcmp(first->owner, second->owner, sizeof(first->owner)) == 0 &&
           memcmp(first->note, second->note, sizeof(first->note)) == 0;
}

static inline nxs_message_t nxs_test_response(const uint8_t report[NXS_REPORT_SIZE], uint32_t identifier, nxs_result_t result) {
    nxs_message_t reply;
    CHECK(nxs_message_decode(report, NXS_REPORT_SIZE, &reply) == NXS_RESULT_OK);
    CHECK(reply.request_id == identifier && reply.flags == NXS_FLAG_RESPONSE && reply.result == result);
    return reply;
}

#endif
