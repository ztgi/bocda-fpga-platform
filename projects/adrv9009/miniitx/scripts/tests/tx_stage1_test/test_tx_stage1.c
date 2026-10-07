/* Execute the actual production test with mocked MMIO, never on hardware. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "../../../Workspace/adrv9009_test/src/app/tx_stage1_test.c"

enum fault_kind { NONE, BAD_PAYLOAD, BAD_HEADER, CONFIG_ERROR,
                  NO_CONFIG, GT_ERROR, NO_GT, WRONG_RATE };
static enum fault_kind fault;
static uint32_t bram[16], ctrl, status, gt;
static unsigned int apply_count, enable_count, writes, barriers;
static int committed;

static uint32_t independent_crc(void)
{
    uint32_t crc = 0xFFFFFFFFU;
    unsigned int word, byte, bit;
    for (word = 1; word <= 14; ++word) {
        for (byte = 0; byte < 4; ++byte) {
            crc ^= (bram[word] >> (8 * byte)) & 0xFFU;
            for (bit = 0; bit < 8; ++bit)
                crc = (crc & 1U) ? (crc >> 1) ^ 0xEDB88320U : crc >> 1;
        }
    }
    return ~crc;
}

uint32_t Xil_In32(uintptr_t address)
{
    if (address >= TX_BRAM_BASE && address < TX_BRAM_BASE + 64U) {
        unsigned int i = (unsigned int)(address - TX_BRAM_BASE) / 4;
        if ((fault == BAD_PAYLOAD && i == 9) ||
            (fault == BAD_HEADER && i == 0 && committed))
            return bram[i] ^ 1U;
        return bram[i];
    }
    if (address == TX_CTRL_BASE) return ctrl;
    if (address == TX_CTRL_BASE + GPIO_DATA2) return status;
    if (address == TX_GT_STATUS_BASE) return gt;
    assert(!"Unexpected MMIO read (must not touch RX/AD9528)");
    return 0;
}

void Xil_Out32(uintptr_t address, uint32_t value)
{
    if (address >= TX_BRAM_BASE && address < TX_BRAM_BASE + 64U) {
        unsigned int i = (unsigned int)(address - TX_BRAM_BASE) / 4;
        if (i == 0 && !(value & (1U << 11))) {
            writes = 0;
            committed = 0;
        } else if (i == 0) {
            assert(writes == 15 && barriers > 0);
            committed = 1;
        } else {
            assert(!committed);
            ++writes;
        }
        bram[i] = value;
        return;
    }
    if (address == TX_CTRL_BASE + GPIO_TRI) { assert(value == 0); return; }
    assert(address == TX_CTRL_BASE);
    assert(!(value & ~0x700U)); /* index 0; never requests a rate/refclk change */
    if ((ctrl ^ value) & CTRL_APPLY) {
        assert(committed && !(value & (CTRL_ENABLE | CTRL_SOFT_RESET)));
        assert(bram[0] == 0x54582801U && bram[13] == 0x08101001U);
        assert(bram[15] == independent_crc());
        assert(bram[2] == 0x4001U);
        assert(bram[9] == 0x55555555U && bram[10] == 0x55555555U);
        assert(!bram[1] && !bram[3] && !bram[4] && !bram[5] && !bram[6]);
        assert(!bram[7] && !bram[8] && !bram[11] && !bram[12] && !bram[14]);
        ++apply_count;
        status = fault == CONFIG_ERROR ? CFG_ERROR :
                 fault == NO_CONFIG ? 0U : CFG_VALID;
    }
    if ((value & CTRL_ENABLE) && !(ctrl & CTRL_ENABLE)) {
        assert(apply_count && status == CFG_VALID);
        ++enable_count;
        gt = fault == GT_ERROR ? GT_RATE_ERROR :
             fault == NO_GT ? 0U : fault == WRONG_RATE ? 0x27U : 0x17U;
        status |= CORE_PATTERN_VALID | CORE_BUSY | CORE_SEQUENCE;
    }
    ctrl = value;
}

void Xil_SetTlbAttributes(uintptr_t address, uint32_t attributes)
{
    assert(address == TX_BRAM_BASE || address == TX_CTRL_BASE);
    assert(attributes == DEVICE_MEMORY);
}
void test_dmb(void) { ++barriers; }
int usleep(unsigned long usec) { assert(usec == 1000); return 0; }

static void setup(enum fault_kind f, uint32_t initial_apply)
{
    fault = f;
    memset(bram, 0, sizeof(bram));
    ctrl = initial_apply;
    status = gt = apply_count = enable_count = writes = barriers = 0;
    committed = 0;
}

int main(void)
{
    unsigned int f;
    setup(NONE, 0);
    assert(tx_stage1_test() == 0);
    assert(ctrl == 0x300U && apply_count == 1 && enable_count == 1);
    setup(NONE, CTRL_APPLY);
    assert(tx_stage1_test() == 0);
    assert(ctrl == 0x200U && apply_count == 1 && enable_count == 1);
    for (f = BAD_PAYLOAD; f <= WRONG_RATE; ++f) {
        setup((enum fault_kind)f, 0);
        assert(tx_stage1_test() == -1);
        assert(!(ctrl & CTRL_ENABLE));
    }
    puts("TX_STAGE1_PS_MMIO_TEST_PASS: record/CRC/commit/APPLY/ENABLE/timeouts");
    return 0;
}
