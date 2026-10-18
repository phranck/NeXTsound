/*
 * QMI transaction loop adapted from Pico SDK 2.2.0 hardware_flash/flash.c,
 * revision a1438dff1d38bd9c65dbd693f0e5db4b9ae91779, for RAM-only metadata reads.
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 * SPDX-License-Identifier: BSD-3-Clause
 * The complete notice is retained in Firmware/ThirdParty/Pico-SDK-LICENSE.txt.
 */
#include "nxs_protocol.h"

#include "hardware/clocks.h"
#include "hardware/flash.h"
#include "hardware/structs/qmi.h"
#include "hardware/sync.h"
#include "pico/stdio_usb.h"
#include "pico/stdlib.h"
#include "pico/unique_id.h"

#include <stdio.h>

#if !PICO_NO_FLASH || PICO_RP2040
#error "The flash metadata probe must be an RP2350 RAM-only image"
#endif

#define NXS_PROBE_SFDP_BYTES 256u
#define NXS_PROBE_COMMAND_TIMEOUT_US 10000u

static bool read_command(const uint8_t *transmit, uint8_t *receive, size_t count) {
    if (!((transmit[0] == 0x9f && count == 4) || (transmit[0] == 0x5a && count == NXS_PROBE_SFDP_BYTES + 5u))) {
        return false;
    }
    /* SDK flash_do_cmd is excluded from PICO_NO_FLASH builds. Start from generic 03h XIP before the bounded QMI read. */
    flash_start_xip();
    hw_set_bits(&qmi_hw->direct_csr, QMI_DIRECT_CSR_ASSERT_CS0N_BITS);
    hw_set_bits(&qmi_hw->direct_csr, QMI_DIRECT_CSR_EN_BITS);
    size_t to_send = count, to_receive = count;
    uint32_t started = time_us_32();
    while ((to_send || to_receive) && time_us_32() - started < NXS_PROBE_COMMAND_TIMEOUT_US) {
        uint32_t flags = qmi_hw->direct_csr;
        if (to_send && !(flags & QMI_DIRECT_CSR_TXFULL_BITS)) {
            qmi_hw->direct_tx = *transmit++;
            --to_send;
        }
        if (to_receive && !(flags & QMI_DIRECT_CSR_RXEMPTY_BITS)) {
            *receive++ = (uint8_t)qmi_hw->direct_rx;
            --to_receive;
        }
    }
    hw_clear_bits(&qmi_hw->direct_csr, QMI_DIRECT_CSR_EN_BITS);
    hw_clear_bits(&qmi_hw->direct_csr, QMI_DIRECT_CSR_ASSERT_CS0N_BITS);
    flash_flush_cache();
    return to_send == 0 && to_receive == 0;
}

static void print_hex(const uint8_t *bytes, size_t count) {
    for (size_t index = 0; index < count; ++index) {
        printf("%02x", bytes[index]);
    }
}

int main(void) {
    if (!set_sys_clock_khz(NXS_SYSTEM_CLOCK_HZ / 1000u, true)) {
        panic("The metadata probe requires 150 MHz");
    }
    static uint8_t jedec_tx[4] = {0x9f}, jedec_rx[4];
    static uint8_t sfdp_tx[NXS_PROBE_SFDP_BYTES + 5u] = {0x5a, 0, 0, 0, 0};
    static uint8_t sfdp_rx[NXS_PROBE_SFDP_BYTES + 5u];
    uint32_t interrupts = save_and_disable_interrupts();
    bool success = read_command(jedec_tx, jedec_rx, sizeof(jedec_tx)) && read_command(sfdp_tx, sfdp_rx, sizeof(sfdp_tx));
    restore_interrupts(interrupts);
    char serial[PICO_UNIQUE_BOARD_ID_SIZE_BYTES * 2 + 1];
    pico_get_unique_board_id_string(serial, sizeof(serial));
    stdio_init_all();
    for (;;) {
        if (stdio_usb_connected()) {
            printf("{\"schema\":1,\"ram_only\":true,\"ok\":%s,\"serial\":\"%s\",\"system_clock_hz\":%lu,\"jedec\":\"",
                   success ? "true" : "false", serial, (unsigned long)clock_get_hz(clk_sys));
            print_hex(jedec_rx + 1, sizeof(jedec_rx) - 1);
            printf("\",\"sfdp\":\"");
            print_hex(sfdp_rx + 5, NXS_PROBE_SFDP_BYTES);
            printf("\"}\n");
            stdio_flush();
        }
        sleep_ms(250);
    }
}
