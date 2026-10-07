# 构建与授权依赖

## 必须先准备的本地输入

1. 获取许可允许使用的 ADRV9009/Talise application、API、固件。
   本地路径为 `projects/adrv9009/miniitx/Workspace/adrv9009_test/src/`。
2. 获取公司授权的 RX BFS/FIR/FFT IP，以及 state_change/bram_rd_wr/
   wave_spi_new/pulse_gen_in 源码与 IP packaging 文件。
3. 获取现有板级 DDR MIG 的合法 `.prj` 输入；不要使用原 XPR 中的旧参考工程绝对路径。
4. 完整 Stage1 物理复现还需要本地 MERGE_BASELINE routed DCP、原 RX
   clock LOC 清单及 CE route6 repair 记录。这些不是源码仓库内交付文件。

缺少任一依赖必须停止，不允许假 IP/tie-off、改时钟周期或伪称可自包含 clean rebuild。

## 硬件

`system.bd`、`system_top.v`、`rtl/`、`constraints/` 和必要 XCI 是输入。
保持 fixed-500M hook，local GT XCI + adapter + GT generated child 管理方式不变。
使用原流程 Refresh Module → Validate BD → Generate Output Products/Wrapper →
受影响 OOC → top synthesis → fixed-500M incremental implementation。
独立新构建不能覆盖冻结目录；不得简单从旧 impl run 导出丢失 CE repair 的 BIT。
只有完成 Stage1 gate 并保存新的 repaired routed DCP 后才生成匹配 BIT/LTX。

当前仓库仅提供可授权源码、接口快照和受限输入说明，不声称另一台机器仅凭 clone
即可恢复公司 RX 算法和 CE 修复后的逐 net 布线。原生成目录、XPR、BSP cache 不提交。

## 软件

现有 ADRV9009 application 为唯一 main/ELF。Stage1 `tx_stage1_test()` 在原初始化后调用。
Stage2 在同一处调用 `tx_stage2_udp_init()`，在原 while 循环中轮询
`tx_stage2_udp_poll()`；不加入另一个 main 或旧 laser main/BSP。
Stage2 build Tcl 在新仓库本地 `build/` 生成 platform/BSP（standalone、lwip211），
从该 application 源码创建 managed application 后 clean/build。
不手工添加对象参与最终链接。API/公司源码缺失时构建必须失败。

UDP 命令/软件验证结果在 Stage2 分支报告中记录。Stage2 不替代明天 Stage1 ELF。
