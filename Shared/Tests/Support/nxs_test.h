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

static inline int nxs_test_finish(const char *suite) {
    printf("%s checks passed: %u assertions\n", suite, nxs_test_assertions);
    return EXIT_SUCCESS;
}

#endif
