# Stage1 fixed-500M / no_udp 冻结基线

冻结是复制已有交付文件，不是重新构建或重新验证；原文件和旧目录均未覆盖。
冻结副本在 `releases/stage1-fixed500-no-udp/`，副本设置只读。

| 文件 | 用途 |
|---|---|
| system_top_tx_rx_stage1_fixed500_ce_repaired.bit | CE route6 修复后的 Stage1 FPGA |
| system_top_tx_rx_stage1_fixed500_ce_repaired.ltx | 同一次修复设计的匹配探针 |
| adrv9009_rx_tx_fixed500_test.elf | 唯一 ADRV9009 application + 最小 TX_TEST |

UART 应打印：`TX_TEST START fixed=500_Mbps refclk=125_MHz txusrclk2=7.8125_MHz no_udp eom_disabled`。
三个 TX 地址：config BRAM `0x40000000`、control GPIO `0x41200000`、
GT status GPIO `0x40020000`。16-word record、CRC、header 最后提交不变。

TX_TEST 写入 63-bit 周期 `0x5555555555555555`、repeat=1、loop=1，HEAD/gap/EOM=0。
LSB-first；63-bit 周期的 wrap 处有相邻两个 1，不是无限长 0101。
调用顺序：原 RX 初始化 → TX_TEST 写配置 → APPLY → ENABLE → 状态检查 → 原 RX 主循环。

现有报告结果（非本轮新跑）：全局 WNS=-0.457 ns、TNS=-24.094 ns，
保留 inherited RX/BFS/FIR setup/recovery 问题；CE[5..8] 修复后约 +0.008 ns。
Stage1 acceptance 不等于 full RX timing signoff，必须保留 `NON_SIGNOFF_STAGE1` 边界。
本轮未运行新的综合/实现，未上板，不能声称光链路/RX/TX 已通过硬件验证。

原始中文报告、软件构建日志的完整本地副本也在该冻结目录。Git 不跟踪二进制、
原始日志或带机器路径的历史报告；软件受限依赖和公司源码仍在本地。
