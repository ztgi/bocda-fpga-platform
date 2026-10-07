#ifndef TEST_XIL_MMU_H
#define TEST_XIL_MMU_H
#include <stdint.h>
#define DEVICE_MEMORY 0xC06U
void Xil_SetTlbAttributes(uintptr_t address, uint32_t attributes);
#endif
