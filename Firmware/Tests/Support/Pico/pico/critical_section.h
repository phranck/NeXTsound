#ifndef NXS_TEST_CRITICAL_SECTION_H
#define NXS_TEST_CRITICAL_SECTION_H

/* The host tests run on one thread without interrupts, so a critical section has nothing to exclude. */
typedef struct {
    int unused;
} critical_section_t;

static inline void critical_section_init(critical_section_t *section) {
    (void)section;
}

static inline void critical_section_enter_blocking(critical_section_t *section) {
    (void)section;
}

static inline void critical_section_exit(critical_section_t *section) {
    (void)section;
}

#endif
