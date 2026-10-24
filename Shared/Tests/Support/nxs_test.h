#ifndef NXS_TEST_H
#define NXS_TEST_H

#include <stdio.h>
#include <stdlib.h>

static unsigned int nxs_test_assertions;

#define CHECK(condition)                                                                                                                   \
    do {                                                                                                                                   \
        ++nxs_test_assertions;                                                                                                             \
        if (!(condition)) {                                                                                                                \
            fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition);                                                                \
            exit(EXIT_FAILURE);                                                                                                            \
        }                                                                                                                                  \
    } while (0)

/** Reads exactly `count` hex byte values from a fixture file, separated by whitespace, and fails on any surplus. */
static inline void nxs_test_read_hex(const char *path, unsigned char *bytes, size_t count) {
    FILE *fixture = fopen(path, "r");
    CHECK(fixture != NULL);
    for (size_t byte_index = 0; byte_index < count; ++byte_index) {
        unsigned int value;
        CHECK(fscanf(fixture, "%2x", &value) == 1);
        bytes[byte_index] = (unsigned char)value;
    }
    unsigned int extra;
    CHECK(fscanf(fixture, "%2x", &extra) == EOF);
    CHECK(fclose(fixture) == 0);
}

static inline int nxs_test_finish(const char *suite) {
    printf("%s checks passed: %u assertions\n", suite, nxs_test_assertions);
    return EXIT_SUCCESS;
}

#endif
