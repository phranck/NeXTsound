#ifndef NXS_PROTOCOL_TEST_H
#define NXS_PROTOCOL_TEST_H

#include "nxs_protocol.h"
#include "nxs_test.h"

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

static inline nxs_message_t nxs_test_response(const uint8_t report[NXS_REPORT_SIZE], uint32_t identifier, nxs_result_t result) {
    nxs_message_t reply;
    CHECK(nxs_message_decode(report, NXS_REPORT_SIZE, &reply) == NXS_RESULT_OK);
    CHECK(reply.request_id == identifier && reply.flags == NXS_FLAG_RESPONSE && reply.result == result);
    return reply;
}

#endif
