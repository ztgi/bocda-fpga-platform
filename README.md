# BOCDA FPGA platform

XC7Z100 + ADRV9009 RX / optical GTX TX 的独立源码仓库。原 laser_tx
工作区、旧分支及其未提交文件保持原样。

## Stage1 冻结

`stage1-fixed500-no-udp`：本地 125 MHz GT REFCLK、fixed 500 Mbps，
TXUSRCLK2 7.8125 MHz；`no_udp`、`eom_disabled`。现有 ADRV9009
application 是唯一 `main`，RX 初始化完成后调用 `tx_stage1_test()`。

明天第一轮上板仍使用本地 `releases/stage1-fixed500-no-udp/` 中冻结的
BIT、matching LTX 和 ELF，见 [Stage1说明](docs/stage1_baseline_cn.md)。
这些二进制和原始报告只在本地保留，不进入 Git/source commit。

## 源码/许可边界

用户要求暂不上传公司定制 BFS/FIR/FFT、state_change、bram_rd_wr、wave_spi_new
等源码。Talise API、固件及包含 AD9378-AD9379 API 许可的 application 文件也不上传。
它们仍保留在本地，并由 `.gitignore` 排除；**本仓库不是无依赖的完整 RX
分发包**，新克隆必须先自行取得授权依赖。BD 引用不会用假的 IP/tie-off 替代。

本地 ADI 公共 HDL 保留原版权和许可头，首笔精选提交不重新分发整套 library。
对用户自有 TX RTL/软件，本仓库未授予
公开再分发许可。GitHub repository 为 PRIVATE。

## 构建入口

见 [可复现构建说明](docs/build_cn.md)。Vivado/Vitis 2022.2。
Stage2 为独立 `stage2-udp` 分支，只接入八个固定档 TX 命令，
不变更 RX/JESD/DMA/AD9528 初始化，不提供 dynamic rate/refclk。
Stage2 的软件编译不代表 UDP/板级测试通过，不替换 Stage1 上板基线。
