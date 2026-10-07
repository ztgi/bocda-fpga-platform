#include "tx_stage1_test.h"

#include <stdint.h>
#include <stdio.h>
#include "xil_io.h"
#include "xil_mmu.h"
#include "sleep.h"

/* Explicit addresses of the merged fixed-500M Stage1 BD, not BSP fallbacks. */
#define TX_BRAM_BASE       0x40000000U
#define TX_CTRL_BASE       0x41200000U
#define TX_GT_STATUS_BASE  0x40020000U
#define GPIO_DATA          0x00U
#define GPIO_TRI           0x04U
#define GPIO_DATA2         0x08U
#define CTRL_APPLY         (1U << 8)
#define CTRL_ENABLE        (1U << 9)
#define CTRL_SOFT_RESET    (1U << 10)
#define CFG_VALID         (1U << 0)
#define CFG_ERROR         (1U << 1)
#define CORE_PATTERN_VALID (1U << 2)
#define CORE_BUSY          (1U << 3)
#define CORE_SEQUENCE      (1U << 6)
#define GT_READY_BITS      0x07U /* PLL lock, TXRESETDONE, effective GT ready */
#define GT_CTRL_RESET      (1U << 3)
#define GT_RATE_ERROR      (1U << 11)
#define RATE_ID_500M       1U
#define RECORD_WORDS       16U

static uint32_t record_crc(const uint32_t *words)
{
    uint32_t crc = 0xFFFFFFFFU;
    unsigned int word, bit;

    /* Words 1..14, each little-endian/LSB-first; same as config_loader.v. */
    for (word = 1; word <= 14; ++word) {
        uint32_t value = words[word];
        for (bit = 0; bit < 32; ++bit) {
            uint32_t feedback = (crc ^ value) & 1U;
            crc >>= 1;
            if (feedback)
                crc ^= 0xEDB88320U;
            value >>= 1;
        }
    }
    return ~crc;
}

static uint32_t core_status(void)
{
    return Xil_In32(TX_CTRL_BASE + GPIO_DATA2);
}

static uint32_t gt_status(void)
{
    return Xil_In32(TX_GT_STATUS_BASE + GPIO_DATA);
}

static void print_status(const char *step)
{
    uint32_t core = core_status();
    uint32_t gt = gt_status();

    printf("TX_TEST %s ctrl=0x%08lx core=0x%08lx gt=0x%08lx\r\n",
           step, (unsigned long)Xil_In32(TX_CTRL_BASE),
           (unsigned long)core, (unsigned long)gt);
    printf("TX_TEST cfg_valid=%lu cfg_error=%lu pattern_valid=%lu "
           "busy=%lu sequence_active=%lu core_error=0x%02lx "
           "pll_lock=%lu txresetdone=%lu gt_ready=%lu ctrl_rst=%lu "
           "rate_id=%lu rate_error=%lu\r\n",
           (unsigned long)(core & 1U),
           (unsigned long)((core >> 1) & 1U),
           (unsigned long)((core >> 2) & 1U),
           (unsigned long)((core >> 3) & 1U),
           (unsigned long)((core >> 6) & 1U),
           (unsigned long)(core >> 24),
           (unsigned long)(gt & 1U),
           (unsigned long)((gt >> 1) & 1U),
           (unsigned long)((gt >> 2) & 1U),
           (unsigned long)((gt >> 3) & 1U),
           (unsigned long)((gt >> 4) & 15U),
           (unsigned long)((gt >> 11) & 1U));
}

int tx_stage1_test(void)
{
    uint32_t words[RECORD_WORDS] = {0};
    uint32_t control, core, gt;
    unsigned int i;
    const char *failure;

    printf("\r\nTX_TEST START fixed=500_Mbps refclk=125_MHz "
           "txusrclk2=7.8125_MHz no_udp eom_disabled\r\n");

    /* Device accesses, including the BRAM commit, must not be cached. */
    Xil_SetTlbAttributes(TX_BRAM_BASE, DEVICE_MEMORY);
    Xil_SetTlbAttributes(TX_CTRL_BASE, DEVICE_MEMORY);

    /* Preserve APPLY parity; all rate/refclk request bits remain zero. */
    control = Xil_In32(TX_CTRL_BASE) & CTRL_APPLY;
    Xil_Out32(TX_CTRL_BASE + GPIO_TRI, 0U);
    Xil_Out32(TX_CTRL_BASE, control | CTRL_SOFT_RESET);
    dmb();
    usleep(1000);
    /* Release soft reset BEFORE APPLY so the TX-domain snapshot is accepted. */
    Xil_Out32(TX_CTRL_BASE, control);
    dmb();
    usleep(1000);
    print_status("DISABLED");

    /* Record 0: 63-bit configured pattern, repeat=1, loop=1; HEAD/gaps=0.
     * Bits are sent LSB-first. The 63-bit 0x5555555555555555 period has
     * alternating bits except the adjacent 1s at its wrap; not infinite 0101.
     * Seed/order/source reserved fields, phase scan and EOM remain zero.
     */
    words[0] = 0x54582801U;   /* magic=5458, format=2, VALID=1, sequence=1 */
    words[2] = 1U | (1U << 14);
    words[9] = 0x55555555U;
    words[10] = 0x55555555U;
    words[13] = 0x08101001U;  /* gap_width=8, max_repeat=16, words=16, seq=1 */
    words[15] = record_crc(words);

    /* Atomic commit: invalid header, payload+CRC, then valid header last. */
    Xil_Out32(TX_BRAM_BASE, words[0] & ~(1U << 11));
    dmb();
    for (i = 1; i < RECORD_WORDS; ++i)
        Xil_Out32(TX_BRAM_BASE + 4U * i, words[i]);
    dmb();
    for (i = 1; i < RECORD_WORDS; ++i) {
        if (Xil_In32(TX_BRAM_BASE + 4U * i) != words[i]) {
            printf("TX_TEST BRAM_MISMATCH word=%u\r\n", i);
            failure = "BRAM_READBACK";
            goto fail;
        }
    }
    Xil_Out32(TX_BRAM_BASE, words[0]);
    dmb();
    if (Xil_In32(TX_BRAM_BASE) != words[0]) {
        failure = "HEADER_READBACK";
        goto fail;
    }
    printf("TX_TEST BRAM_OK index=0 words=16 crc=0x%08lx\r\n",
           (unsigned long)words[15]);

    control ^= CTRL_APPLY;
    Xil_Out32(TX_CTRL_BASE, control);
    dmb();
    /* Let the new load finish; do not mistake the previous CFG_VALID for ACK. */
    usleep(1000);
    for (i = 0; i < 100; ++i) {
        core = core_status();
        if (core & CFG_ERROR) {
            failure = "CONFIG_LOADER_ERROR";
            goto fail;
        }
        if (core & CFG_VALID)
            break;
        usleep(1000);
    }
    if (i == 100) {
        failure = "CONFIG_TIMEOUT";
        goto fail;
    }
    print_status("APPLIED");

    control |= CTRL_ENABLE;
    Xil_Out32(TX_CTRL_BASE, control);
    dmb();
    for (i = 0; i < 2000; ++i) {
        gt = gt_status();
        core = core_status();
        if ((gt & GT_RATE_ERROR) || (core & CFG_ERROR)) {
            failure = "GT_OR_CONFIG_ERROR";
            goto fail;
        }
        if (((gt & (GT_READY_BITS | GT_CTRL_RESET)) == GT_READY_BITS) &&
            (((gt >> 4) & 15U) == RATE_ID_500M) &&
            ((core & (CFG_VALID | CORE_PATTERN_VALID | CORE_BUSY |
                      CORE_SEQUENCE)) ==
             (CFG_VALID | CORE_PATTERN_VALID | CORE_BUSY | CORE_SEQUENCE)))
            break;
        usleep(1000);
    }
    if (i == 2000) {
        failure = "GT_OR_SEQUENCE_TIMEOUT";
        goto fail;
    }
    print_status("ENABLED");
    printf("TX_TEST READY fixed_63bit_loop_started; RX continues. "
           "This is status/readback only, not serial/optical validation.\r\n");
    return 0;

fail:
    Xil_Out32(TX_CTRL_BASE, control & ~CTRL_ENABLE);
    dmb();
    print_status("DISABLED_ON_ERROR");
    printf("TX_TEST FAIL reason=%s; optical TX disabled, RX continues.\r\n",
           failure);
    return -1;
}
