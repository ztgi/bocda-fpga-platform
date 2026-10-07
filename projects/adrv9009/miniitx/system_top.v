// ***************************************************************************
// ***************************************************************************
// Copyright 2014 - 2017 (c) Analog Devices, Inc. All rights reserved.
//
// 这是一个由Analog Devices开发的基于Zynq SoC和ADRV9009射频收发器的系统顶层模块。
// 主要功能包括：射频信号收发、数字信号处理（FFT、加窗）、DMA数据传输到DDR3内存，
// 以及通过PS（处理器系统）进行控制和数据处理。

`timescale 1ns/100ps

/*
 * FMC连接器接口映射表：
 * 系统信号名称       板卡标签          FMC引脚        FPGA引脚
 * --------------------------------------------------------------------
 * ref_clk1_p/n      FPGA_REF_CLK+/-   B20/B21        AA8/AA7   (参考时钟)
 * rx_data_p/n[0:3]  SERDOUT0-3        A2/A3等        AJ8/AJ7等 (接收数据)
 * tx_data_p/n[0:3]  SERDIN0-3         A22/A23等      AK6/AK5等 (发送数据)
 * rx_sync_p/n       SYNCINB0+/-       G9/G10         AH19/AJ19 (接收同步)
 * 等等...
 * 详细映射关系请参考Analog Devices官方文档
 */

module system_top (
  // PS DDR3内存接口
  inout       [14:0]      ddr_addr,      // DDR3地址总线
  inout       [ 2:0]      ddr_ba,        // Bank地址
  inout                   ddr_cas_n,      // 列地址选通
  inout                   ddr_ck_n,       // 差分时钟负端
  inout                   ddr_ck_p,       // 差分时钟正端
  inout                   ddr_cke,        // 时钟使能
  inout                   ddr_cs_n,       // 片选
  inout       [ 3:0]      ddr_dm,        // 数据掩码
  inout       [31:0]      ddr_dq,        // 数据总线
  inout       [ 3:0]      ddr_dqs_n,     // 差分数据选通负端
  inout       [ 3:0]      ddr_dqs_p,     // 差分数据选通正端
  inout                   ddr_odt,        // 片内终结
  inout                   ddr_ras_n,      // 行地址选通
  inout                   ddr_reset_n,    // 复位
  inout                   ddr_we_n,       // 写使能

  // PS固定接口
  inout                   fixed_io_ddr_vrn,   // DDR终端参考电压
  inout                   fixed_io_ddr_vrp,   // DDR终端参考电压
  inout       [53:0]      fixed_io_mio,       // 多功能IO
  inout                   fixed_io_ps_clk,    // PS时钟
  inout                   fixed_io_ps_porb,   // PS上电复位
  inout                   fixed_io_ps_srstb,  // PS软复位

  // PL DDR3时钟（未使用）
  input                   sys_clk_p,
  input                   sys_clk_n,

  // 音频输出
  output                  spdif,          // S/PDIF音频输出

  // I2C接口
  inout                   iic_scl,        // I2C时钟
  inout                   iic_sda,        // I2C数据

  // ADRV9009参考时钟
  input                   ref_clk0_p,     // 参考时钟0正端（未使用）
  input                   ref_clk0_n,     // 参考时钟0负端（未使用）
  input                   ref_clk1_p,     // 参考时钟1正端（主要时钟）
  input                   ref_clk1_n,     // 参考时钟1负端

  // ADRV9009数据接口
  input       [ 3:0]      rx_data_p,      // 4通道接收数据正端
  input       [ 3:0]      rx_data_n,      // 4通道接收数据负端
  output      [ 3:0]      tx_data_p,      // 4通道发送数据正端
  output      [ 3:0]      tx_data_n,      // 4通道发送数据负端

  // 同步信号
  output                  rx_sync_p,      // 接收同步正端
  output                  rx_sync_n,      // 接收同步负端
  output                  rx_os_sync_p,   // 接收过采样同步正端
  output                  rx_os_sync_n,   // 接收过采样同步负端
  input                   tx_sync_p,      // 发送同步正端
  input                   tx_sync_n,      // 发送同步负端
  input                   tx_sync_1_p,    // 发送同步1正端
  input                   tx_sync_1_n,    // 发送同步1负端
  input                   sysref_p,       // 系统参考时钟正端
  input                   sysref_n,       // 系统参考时钟负端

  output                  sysref_out_p,   // 系统参考时钟输出正端
  output                  sysref_out_n,   // 系统参考时钟输出负端

  // SPI配置接口
  output                  spi_csn_ad9528,    // AD9528时钟芯片片选
  output                  spi_csn_adrv9009,  // ADRV9009片选
  output                  spi_clk,           // SPI时钟
  output                  spi_mosi,          // SPI主出从入
  input                   spi_miso,          // SPI主入从出

  // 控制和状态引脚
  inout                   ad9528_reset_b,     // AD9528复位（低有效）
  inout                   ad9528_sysref_req,  // AD9528系统参考请求
  inout                   adrv9009_tx1_enable, // 发射通道1使能
  inout                   adrv9009_tx2_enable, // 发射通道2使能
  inout                   adrv9009_rx1_enable, // 接收通道1使能
  inout                   adrv9009_rx2_enable, // 接收通道2使能
  inout                   adrv9009_test,       // 测试模式
  inout                   adrv9009_reset_b,    // ADRV9009复位（低有效）
  inout                   adrv9009_gpint,      // 通用中断

  // ADRV9009 GPIO引脚
  inout                   adrv9009_gpio_00,
  inout                   adrv9009_gpio_01,
  inout                   adrv9009_gpio_02,
  inout                   adrv9009_gpio_03,
  inout                   adrv9009_gpio_04,
  inout                   adrv9009_gpio_05,
  inout                   adrv9009_gpio_06,
  inout                   adrv9009_gpio_07,
  inout                   adrv9009_gpio_08,
  inout                   adrv9009_gpio_09,
  inout                   adrv9009_gpio_10,
  inout                   adrv9009_gpio_11,
  inout                   adrv9009_gpio_12,
  inout                   adrv9009_gpio_13,
  inout                   adrv9009_gpio_14,
  inout                   adrv9009_gpio_15,
  inout                   adrv9009_gpio_16,
  inout                   adrv9009_gpio_17,
  inout                   adrv9009_gpio_18,

  // 调试输出：2分频时钟
  (*mark_debug="true"*) output reg clk_2_out,

  // Stage 1 optical TX: independent local 125 MHz reference, fixed 500M.
  input gt_refclk125_p,
  input gt_refclk125_n,
  output gtx_txp_out,
  output gtx_txn_out,
  output eom_out,
  output soa_gate_out,
  output acq_trig_out,
  output acq_gate_out,
  output gt_sequence_sync_out,
  output txusrclk2_monitor_out
);

  // ============================================================================
  // 内部信号声明
  // ============================================================================

  // GPIO总线
  wire    [63:0]  gpio_i;    // GPIO输入
  wire    [63:0]  gpio_o;    // GPIO输出
  wire    [63:0]  gpio_t;    // GPIO三态控制

  // 差分时钟信号（转换为单端）
  wire            ref_clk0;   // 参考时钟0（单端）
  wire            ref_clk1;   // 参考时钟1（单端）
  wire            rx_sync;    // 接收同步（单端）
  wire            rx_os_sync; // 接收过采样同步（单端）
  wire            tx_sync;    // 发送同步（单端）
  wire            tx_sync_1;  // 发送同步1（单端）
  wire            sysref;     // 系统参考时钟（单端）
  wire            sysref_out; // 系统参考时钟输出（单端）

  // 系统参考时钟输出固定为0
  assign sysref_out = 0;

  // 部分GPIO引脚回环连接
  assign gpio_i[63:60] = gpio_o[63:60];  // 位63-60输出直接反馈到输入
  assign gpio_i[31:15] = gpio_o[31:15];  // 位31-15输出直接反馈到输入

  // ============================================================================
  // 差分信号缓冲器实例化
  // ============================================================================

  // 参考时钟输入缓冲器（GTE2专用缓冲器，用于高速时钟）
  IBUFDS_GTE2 i_ibufds_rx_ref_clk (
    .CEB (1'd0),              // 时钟使能（低有效），0表示使能
    .I   (ref_clk0_p),        // 差分正端输入
    .IB  (ref_clk0_n),        // 差分负端输入
    .O   (ref_clk0),          // 单端时钟输出
    .ODIV2 ()                 // 2分频输出（未使用）
  );

  IBUFDS_GTE2 i_ibufds_ref_clk1 (
    .CEB (1'd0),
    .I   (ref_clk1_p),
    .IB  (ref_clk1_n),
    .O   (ref_clk1),
    .ODIV2 ()
  );

  // 同步信号输出缓冲器（差分输出）
  OBUFDS i_obufds_rx_sync (
    .I (rx_sync),           // 单端输入
    .O (rx_sync_p),         // 差分正端输出
    .OB(rx_sync_n)          // 差分负端输出
  );

  OBUFDS i_obufds_rx_os_sync (
    .I (rx_os_sync),
    .O (rx_os_sync_p),
    .OB(rx_os_sync_n)
  );

  OBUFDS i_obufds_sysref_out (
    .I (sysref_out),
    .O (sysref_out_p),
    .OB(sysref_out_n)
  );

  // 同步信号输入缓冲器（差分输入）
  IBUFDS i_ibufds_tx_sync (
    .I  (tx_sync_p),
    .IB (tx_sync_n),
    .O  (tx_sync)
  );

  IBUFDS i_ibufds_tx_sync_1 (
    .I  (tx_sync_1_p),
    .IB (tx_sync_1_n),
    .O  (tx_sync_1)
  );

  IBUFDS i_ibufds_sysref (
    .I  (sysref_p),
    .IB (sysref_n),
    .O  (sysref)
  );

  // GPIO缓冲器（28位双向IO）
  ad_iobuf #(.DATA_WIDTH(28)) i_iobuf (
    .dio_t ({gpio_t[59:32]}),   // 三态控制信号
    .dio_i ({gpio_o[59:32]}),   // 输出数据
    .dio_o ({gpio_i[59:32]}),   // 输入数据
    .dio_p ({ ad9528_reset_b,       // 59
              ad9528_sysref_req,    // 58
              adrv9009_tx1_enable,  // 57
              adrv9009_tx2_enable,  // 56
              adrv9009_rx1_enable,  // 55
              adrv9009_rx2_enable,  // 54
              adrv9009_test,        // 53
              adrv9009_reset_b,     // 52
              adrv9009_gpint,       // 51
              adrv9009_gpio_00,     // 50
              adrv9009_gpio_01,     // 49
              adrv9009_gpio_02,     // 48
              adrv9009_gpio_03,     // 47
              adrv9009_gpio_04,     // 46
              adrv9009_gpio_05,     // 45
              adrv9009_gpio_06,     // 44
              adrv9009_gpio_07,     // 43
              adrv9009_gpio_15,     // 42
              adrv9009_gpio_08,     // 41
              adrv9009_gpio_09,     // 40
              adrv9009_gpio_10,     // 39
              adrv9009_gpio_11,     // 38
              adrv9009_gpio_12,     // 37
              adrv9009_gpio_14,     // 36
              adrv9009_gpio_13,     // 35
              adrv9009_gpio_17,     // 34
              adrv9009_gpio_16,     // 33
              adrv9009_gpio_18})
  );

  // ============================================================================
  // 内部信号声明（续）
  // ============================================================================

  // DMA接口信号
  wire [31:0]  FDMA_S_fdma_waddr;   // DMA写地址
  wire         FDMA_S_fdma_wareq;    // DMA写请求
  wire         FDMA_S_fdma_wbusy;    // DMA写忙标志
  wire         FDMA_S_fdma_wready;   // DMA写就绪
  wire [15:0]  FDMA_S_fdma_wsize;    // DMA传输大小
  wire         FDMA_S_fdma_wvalid;   // DMA写有效

  // 系统控制信号
  (*mark_debug="true"*) wire rst_in;          // RX-domain software reset release
  (*mark_debug="true"*) reg  rst_clkwiz;       // 时钟模块复位
  (*mark_debug="true"*) reg  valid;            // 数据有效标志
  (*mark_debug="true"*) reg  valid_fft;        // FFT有效标志
  (*mark_debug="true"*) reg  output_end;       // 输出结束标志
  (*mark_debug="true"*) wire [31:0] bfs;       // FFT结果（幅度）
  (*mark_debug="true"*) reg  [31:0] bfs_out;   // FFT结果输出
  (*mark_debug="true"*) wire bfs_valid;        // FFT结果有效
  (*mark_debug="true"*) wire output_en;        // 输出使能
  (*mark_debug="true"*) reg  output_end_signal; // 输出结束信号

  // 时钟和配置信号
  wire         clk_fs_half;          // 半采样率时钟
  wire         locked;               // 时钟锁定标志
  wire [23:0]  sampling_num;         // 采样点数
  wire         spi_rst;              // SPI复位
  (*mark_debug="true"*) wire [127:0] dout_fft; // FFT输出数据（128位）

  // 数据流信号
  (*mark_debug="true"*) wire data_out_valid;    // FFT输出有效
  wire         clk_160;              // 160MHz时钟
  (*mark_debug="true"*) wire delay_end;         // 延迟结束标志
  (*mark_debug="true"*) wire fft_valid0;        // FFT通道0有效
  (*mark_debug="true"*) wire fft_valid1;        // FFT通道1有效
  wire [15:0]  frame_num;            // 帧数
  (*mark_debug="true"*) wire [15:0] adc_data_0; // ADC通道0数据
  (*mark_debug="true"*) wire [15:0] adc_data_1; // ADC通道1数据
  wire [0:0]   adc_enable_0;         // ADC通道0使能
  wire [0:0]   adc_enable_1;         // ADC通道1使能
  wire [0:0]   adc_valid_0;          // ADC通道0有效
  wire [0:0]   adc_valid_1;          // ADC通道1有效

  // 计数器和状态信号
  (*mark_debug="true"*) reg [23:0] cnt_valid;      // 采样点计数器
  (*mark_debug="true"*) reg [15:0] cnt_g_valid;    // 帧计数器
  wire         sign;                 // 下降沿检测信号
  reg          d0, d1;               // 下降沿检测寄存器
  reg          sign_cnt;             // 下降沿计数
  (*mark_debug="true"*) reg valid_temp;           // 有效信号临时存储
  reg          valid_temp0, valid_temp1; // 有效信号临时存储（备份）
  reg [63:0]   data_in_temp0, data_in_temp1; // 数据临时存储

  // DDS和FFT控制信号
  (*mark_debug="true"*) wire dds_ready;           // DDS就绪信号
  (*mark_debug="true"*) wire [15:0] out_sin;      // DDS正弦输出
  (*mark_debug="true"*) wire fft_valid_out;       // FFT输出有效

  // 时钟和延迟控制
  wire         clk_2_temp;           // 2分频时钟临时信号
  reg          delay_10_begin;       // 10秒延迟开始标志
  reg          delay_10_end;         // 10秒延迟结束标志
  reg [35:0]   delay_10;             // 10秒延迟计数器（36位）

  // 状态标志
  (*mark_debug="true"*) reg end_add;      // 累加结束标志
  (*mark_debug="true"*) reg end_fdma;     // DMA结束标志

  // 数据处理信号
  (*mark_debug="true"*) reg [19:0] shift_output_en;  // 输出使能移位寄存器
  (*mark_debug="true"*) reg data_trans_en;           // 数据传输使能
  (*mark_debug="true"*) reg [28:0] data_fir_cnt;     // FIR数据计数
  (*mark_debug="true"*) reg [20:0] bfs_cnt;          // FFT结果计数

  // 时钟分频信号
  reg clk_2_0, clk_2_1;              // 2分频时钟寄存器
  wire clk_pos;                      // 时钟上升沿检测
  assign clk_pos = !clk_2_0 & clk_2_1; // 检测时钟上升沿

  // 控制寄存器
  reg [16:0] clk_pos_cnt;            // 上升沿计数
  (*mark_debug="true"*) wire [31:0] gpio_out;        // GPIO输出数据

  // DDS控制
  (*mark_debug="true"*) reg [3:0] dds_ready_cnt;     // DDS就绪计数器
  (*mark_debug="true"*) reg dds_ready_8;             // 8倍速DDS就绪

  // 窗函数存储器
  reg [14:0] win [0:15];             // 16点窗函数系数存储器

  // 加窗处理信号
  (*mark_debug="true"*) wire signed [30:0] datai;    // I路加窗后数据
  (*mark_debug="true"*) wire signed [30:0] dataq;    // Q路加窗后数据
  (*mark_debug="true"*) wire signed [15:0] datai_15; // 移位后I路数据
  (*mark_debug="true"*) wire signed [15:0] dataq_15; // 移位后Q路数据
  reg [15:0] data_win;               // 当前窗系数
  reg [15:0] data_win_8;             // 8倍速窗系数

  // 测试信号
  (*mark_debug="true"*) reg signed [15:0] data_in_test_0; // 测试数据I路
  (*mark_debug="true"*) reg signed [15:0] data_in_test_1; // 测试数据Q路
  (*mark_debug="true"*) wire [31:0] sin_wave;         // 正弦波输出（正常速率）
  (*mark_debug="true"*) wire [31:0] sin_wave_8;       // 正弦波输出（8倍速）

  // 复位控制
  (*mark_debug="true"*) reg [7:0] rst_cnt;            // 复位计数器
  (*mark_debug="true"*) reg end_rst;                  // 复位结束标志

  // 采样点数寄存器（多级流水线）
  (* EQUIVALENT_REGISTER_REMOVAL="NO" *) reg [23:0] sampling_num_0;
  (* EQUIVALENT_REGISTER_REMOVAL="NO" *) reg [23:0] sampling_num_1;
  (* EQUIVALENT_REGISTER_REMOVAL="NO" *) reg [23:0] sampling_num_2;
  (* EQUIVALENT_REGISTER_REMOVAL="NO" *) reg [23:0] sampling_num_3;
  (* EQUIVALENT_REGISTER_REMOVAL="NO" *) reg [23:0] sampling_num_4;
  (* EQUIVALENT_REGISTER_REMOVAL="NO" *) reg [23:0] sampling_num_5;
  (* EQUIVALENT_REGISTER_REMOVAL="NO" *) reg [23:0] sampling_num_6;
  (* EQUIVALENT_REGISTER_REMOVAL="NO" *) reg [23:0] sampling_num_7;
  (* EQUIVALENT_REGISTER_REMOVAL="NO" *) reg [23:0] sampling_num_8;

  // 循环索引
  (*mark_debug="true"*) reg [31:0] i;                // 主循环索引
  (*mark_debug="true"*) reg [3:0] j = 0;             // 窗系数索引（正常速率）
  (*mark_debug="true"*) reg [3:0] h = 0;             // 窗系数索引（8倍速）

  // ============================================================================
  // 连续赋值
  // ============================================================================

  // DDS就绪信号：FFT通道0或通道1有效
  assign dds_ready = fft_valid0 || fft_valid1;

  // 数据移位（15位右移，相当于除以32768）
  assign datai_15 = datai >>> 15;
  assign dataq_15 = dataq >>> 15;
  assign datai_8_15 = datai_8 >>> 15;
  assign dataq_8_15 = dataq_8 >>> 15;

  // 合成正弦波数据：{Q路数据, I路数据}
  assign sin_wave = {dataq_15, datai_15};
  assign sin_wave_8 = {dataq_8_15, datai_8_15};

  // 时钟上升沿检测：clk_2_temp的上升沿
  assign clk_pos = !clk_2_0 & clk_2_1;

  // ============================================================================
  // 主要逻辑块
  // ============================================================================

  // ----------------------------------------------------------------------------
  // 1. 窗系数初始化（16点汉宁窗近似值）
  // ----------------------------------------------------------------------------
  always @(posedge clk_160) begin
    // 窗函数系数（对称结构）
    win[0]  <= 15'd2621;  // 0.08 * 32768 ≈ 2621
    win[1]  <= 15'd3925;  // 0.12 * 32768 ≈ 3925
    win[2]  <= 15'd7609;  // 0.23 * 32768 ≈ 7609
    win[3]  <= 15'd13037; // 0.40 * 32768 ≈ 13037
    win[4]  <= 15'd19270; // 0.59 * 32768 ≈ 19270
    win[5]  <= 15'd25231; // 0.77 * 32768 ≈ 25231
    win[6]  <= 15'd29889; // 0.91 * 32768 ≈ 29889
    win[7]  <= 15'd32439; // 0.99 * 32768 ≈ 32439
    win[8]  <= 15'd32439; // 对称点
    win[9]  <= 15'd29889;
    win[10] <= 15'd25231;
    win[11] <= 15'd19270;
    win[12] <= 15'd13037;
    win[13] <= 15'd7609;
    win[14] <= 15'd3925;
    win[15] <= 15'd2621;
  end

  // ----------------------------------------------------------------------------
  // 2. 采样点数流水线寄存器（减少关键路径）
  // ----------------------------------------------------------------------------
  always @(posedge clk_160 or negedge rst_in) begin
    if (!rst_in) begin
      // 复位时清零
      sampling_num_0 <= 24'd0;
      sampling_num_1 <= 24'd0;
      sampling_num_2 <= 24'd0;
      sampling_num_3 <= 24'd0;
      sampling_num_4 <= 24'd0;
      sampling_num_5 <= 24'd0;
      sampling_num_6 <= 24'd0;
      sampling_num_7 <= 24'd0;
      sampling_num_8 <= 24'd0;
    end else begin
      // 多级流水线传递采样点数
      sampling_num_0 <= sampling_num;
      sampling_num_1 <= sampling_num;
      sampling_num_2 <= sampling_num;
      sampling_num_3 <= sampling_num;
      sampling_num_4 <= sampling_num;
      sampling_num_5 <= sampling_num;
      sampling_num_6 <= sampling_num;
      sampling_num_7 <= sampling_num;
      sampling_num_8 <= sampling_num;
    end
  end

  // ----------------------------------------------------------------------------
  // 3. DDS就绪计数器
  // ----------------------------------------------------------------------------
  always @(posedge clk_160 or negedge rst_in) begin
    if (!rst_in) begin
      dds_ready_cnt <= 0;
    end else if (dds_ready && dds_ready_cnt < 8) begin
      dds_ready_cnt <= dds_ready_cnt + 1;  // 计数到8
    end
  end

  // 8倍速DDS就绪标志
  always @(posedge clk_160 or negedge rst_in) begin
    if (!rst_in) begin
      dds_ready_8 <= 0;
    end else if (dds_ready && dds_ready_cnt >= 7) begin
      dds_ready_8 <= 1;  // 当计数器>=7时使能8倍速处理
    end else begin
      dds_ready_8 <= 0;
    end
  end

  // ----------------------------------------------------------------------------
  // 4. 窗系数索引控制
  // ----------------------------------------------------------------------------
  // 正常速率窗系数索引（0-15循环）
  always @(posedge clk_160 or negedge rst_in) begin
    if (!rst_in) begin
      j <= 0;
    end else if (dds_ready) begin
      j <= j + 1;  // 每个有效数据递增
    end
  end

  // 8倍速窗系数索引
  always @(posedge clk_160 or negedge rst_in) begin
    if (!rst_in) begin
      h <= 0;
    end else if (dds_ready_8) begin
      h <= h + 1;  // 8倍速处理时递增
    end
  end

  // ----------------------------------------------------------------------------
  // 5. 数据索引控制（最大10560个点）
  // ----------------------------------------------------------------------------
  always @(posedge clk_160 or negedge rst_in) begin
    if (!rst_in) begin
      i <= 0;
    end else if (dds_ready && i < 10560 - 1) begin
      i <= i + 1;  // 递增数据索引
    end else begin
      i <= 0;      // 达到最大值后复位
    end
  end

  // ----------------------------------------------------------------------------
  // 6. 窗系数选择
  // ----------------------------------------------------------------------------
  always @(posedge clk_160 or negedge rst_in) begin
    if (!rst_in) begin
      data_win <= 16'd0;
    end else begin
      data_win <= {1'b0, win[j]};  // 正常速率窗系数（添加符号位）
    end
  end

  always @(posedge clk_160 or negedge rst_in) begin
    if (!rst_in) begin
      data_win_8 <= 16'd0;
    end else begin
      data_win_8 <= {1'b0, win[h]};  // 8倍速窗系数
    end
  end

  // ----------------------------------------------------------------------------
  // 7. 测试数据选择（ADC数据或预存数据）
  // ----------------------------------------------------------------------------
  always @(posedge clk_160 or negedge rst_in) begin
    if (!rst_in) begin
      data_in_test_0 <= 16'd0;
    end else begin
      // 可选择使用预存数据或实时ADC数据
      // data_in_test_0 <= data_i[i];        // 预存数据模式
      data_in_test_0 <= adc_data_0;          // 实时ADC数据模式
    end
  end

  always @(posedge clk_160 or negedge rst_in) begin
    if (!rst_in) begin
      data_in_test_1 <= 16'd0;
    end else begin
      // data_in_test_1 <= data_q[i];        // 预存数据模式
      data_in_test_1 <= adc_data_1;          // 实时ADC数据模式
    end
  end

  // ----------------------------------------------------------------------------
  // 8. 复位控制逻辑
  // ----------------------------------------------------------------------------
  // 时钟模块复位（固定为1）
  always @(posedge clk_160) begin
    rst_clkwiz <= 1'b1;
  end

  // clk_160 and clk_fs_half are the same adrv9009_rx_device_clk BD net.
  rx_software_reset_sync u_rx_software_reset (
    .rx_clk(clk_160), .software_reset(gpio_out[1]), .resetn(rst_in)
  );

  // 复位计数器（40个周期）
  always @(posedge clk_160) begin
    if (!rst_in && rst_cnt < 8'd40) begin
      rst_cnt <= rst_cnt + 1;  // 复位期间计数
    end else if (rst_in) begin
      rst_cnt <= 8'd0;         // 复位释放时清零
    end
  end

  // 复位结束标志（计数器大于20时置位）
  always @(posedge clk_160) begin
    if (rst_cnt > 8'd20) begin
      end_rst <= 1'd1;
    end else begin
      end_rst <= 1'd0;
    end
  end

  // ----------------------------------------------------------------------------
  // 9. 累加和DMA结束标志控制
  // ----------------------------------------------------------------------------
  // 连接end_add和end_fdma信号
  always @(posedge clk_160) begin
    if (!rst_in) begin
      end_add  <= 1'd0;
      end_fdma <= 1'd0;
    end else begin
      if (output_end_signal == 1) begin
        // 输出结束时，关闭累加，开启DMA
        end_add  <= 1'd0;
        end_fdma <= 1'd1;
      end else if (output_en == 1) begin
        // 输出使能时，开启累加，关闭DMA
        end_add  <= 1'd1;
        end_fdma <= 1'd0;
      end
    end
  end

  // 输出结束信号锁存
  always @(posedge clk_160) begin
    if (!rst_in) begin
      output_end_signal <= 1'b0;
    end else if (output_end == 1) begin
      output_end_signal <= 1'b1;  // 锁存输出结束标志
    end
  end

  // ----------------------------------------------------------------------------
  // 10. 10秒延迟控制（用于系统启动延时）
  // ----------------------------------------------------------------------------
  // 延迟开始标志
  always @(posedge clk_160) begin
    if (!rst_in) begin
      delay_10_begin <= 1'b1;  // 复位后开始延迟
    end
  end

  // 延迟计数器（614,400,000个周期 ≈ 5秒 @ 122.88MHz）
  always @(posedge clk_160) begin
    if (delay_10_begin && !delay_10_end) begin
      delay_10 <= delay_10 + 1'b1;  // 计数直到达到设定值
    end
  end

  // 延迟结束判断
  always @(posedge clk_160) begin
    if (delay_10 >= 36'd614400000) begin
      delay_10_end <= 1'b1;  // 达到延迟时间
    end else begin
      delay_10_end <= 1'b0;
    end
  end

  // ----------------------------------------------------------------------------
  // 11. 采样点计数器（用于控制每帧数据处理）
  // ----------------------------------------------------------------------------
  always @(posedge clk_fs_half) begin
    if (!rst_in) begin
      cnt_valid <= 24'd0;
    end else begin
      if (start_add && (cnt_valid < (sampling_num_1 - 1))) begin
        cnt_valid <= cnt_valid + 1;  // 计数采样点
      end else if (!start_add && cnt_valid > 0) begin
        cnt_valid <= cnt_valid;      // 保持当前值
      end else begin
        cnt_valid <= 24'd0;          // 清零
      end
    end
  end

  // ----------------------------------------------------------------------------
  // 12. 帧计数器（用于控制多帧数据处理）
  // ----------------------------------------------------------------------------
  always @(posedge clk_fs_half) begin
    if (!rst_in) begin
      cnt_g_valid <= 16'd0;
    end else begin
      if (start_add && (cnt_valid == (sampling_num_2 - 1)) &&
          (cnt_g_valid < (frame_num - 1))) begin
        cnt_g_valid <= cnt_g_valid + 1;  // 完成一帧后递增
      end else if (!start_add && cnt_g_valid > 0) begin
        cnt_g_valid <= cnt_g_valid;      // 保持
      end else begin
        cnt_g_valid <= 24'd0;           // 清零
      end
    end
  end

  // ----------------------------------------------------------------------------
  // 13. 有效信号延迟
  // ----------------------------------------------------------------------------
  always @(posedge clk_fs_half) begin
    if (!rst_in) begin
      valid_temp <= 1'b0;
    end else begin
      valid_temp <= valid;  // 延迟一个周期
    end
  end

  // ----------------------------------------------------------------------------
  // 14. 输出使能移位寄存器（20级流水线）
  // ----------------------------------------------------------------------------
  always @(posedge clk_fs_half or negedge rst_in) begin
    if (!rst_in) begin
      shift_output_en <= 20'd0;
    end else begin
      // 移位寄存器，用于延迟输出使能信号
      shift_output_en <= {shift_output_en[18:0], output_en};
    end
  end

  // 提取第19级延迟信号
  wire output_en_19;
  assign output_en_19 = shift_output_en[19];

  wire [28:0] threshold_reg;
  wire threshold_valid;
  rx_capture_threshold u_rx_capture_threshold (
    .rx_clk(clk_fs_half), .resetn(rst_in), .start_add(start_add),
    .sampling_num(sampling_num), .threshold_reg(threshold_reg),
    .threshold_valid(threshold_valid)
  );

  // ----------------------------------------------------------------------------
  // 15. FIR数据计数器
  // ----------------------------------------------------------------------------
  always @(posedge clk_fs_half or negedge rst_in) begin
    if (!rst_in) begin
      data_fir_cnt <= 29'd0;
    end else if (output_en_19 && threshold_valid && data_fir_cnt < threshold_reg) begin
      data_fir_cnt <= data_fir_cnt + 1;  // 计数直到达到设定值
    end else begin
      data_fir_cnt <= data_fir_cnt;      // 保持
    end
  end

  // ----------------------------------------------------------------------------
  // 16. 数据传输使能
  // ----------------------------------------------------------------------------
  always @(posedge clk_fs_half or negedge rst_in) begin
    if (!rst_in) begin
      data_trans_en <= 1'd0;
    end else if (output_en_19 && threshold_valid && data_fir_cnt < threshold_reg) begin
      data_trans_en <= 1;   // 在计数范围内使能传输
    end else begin
      data_trans_en <= 0;   // 否则关闭
    end
  end

  // ----------------------------------------------------------------------------
  // 17. FFT结果计数器
  // ----------------------------------------------------------------------------
  always @(posedge clk_fs_half or negedge rst_in) begin
    if (!rst_in) begin
      bfs_cnt <= 21'd0;
    end else if (FDMA_S_fdma_wvalid) begin
      if (bfs_cnt <= (sampling_num_5 >> 3)) begin
        bfs_cnt <= bfs_cnt + 1;  // 计数DMA传输
      end else begin
        bfs_cnt <= 22'd0;        // 达到最大值后清零
      end
    end else begin
      bfs_cnt <= bfs_cnt;        // 保持
    end
  end

  // ----------------------------------------------------------------------------
  // 18. FFT结果输出寄存器
  // ----------------------------------------------------------------------------
  always @(posedge clk_fs_half or negedge rst_in) begin
    if (!rst_in) begin
      bfs_out <= 32'd0;
    end else begin
      bfs_out <= bfs;  // 锁存FFT结果
    end
  end

  // ----------------------------------------------------------------------------
  // 19. 输出结束判断
  // ----------------------------------------------------------------------------
  always @(posedge clk_fs_half or negedge rst_in) begin
    if (!rst_in) begin
      output_end <= 1'd0;
    end else if ((bfs_cnt >= 3) && (bfs_cnt == (sampling_num_6 >> 3) + 1)) begin
      output_end <= 1'd1;  // 达到预定计数值时结束输出
    end else begin
      output_end <= 1'd0;
    end
  end

  // ----------------------------------------------------------------------------
  // 20. SPI复位下降沿检测
  // ----------------------------------------------------------------------------
  // 下降沿检测寄存器
  always @(posedge clk_fs_half or negedge locked) begin
    if (!locked) begin
      d0 <= 1'b0;
      d1 <= 1'b0;
    end else begin
      d0 <= spi_rst;  // 当前值
      d1 <= d0;       // 前一个值
    end
  end

  // 下降沿检测（d1=1且d0=0）
  assign sign = d1 & (~d0);

  // 下降沿计数器（只计数一次）
  always @(posedge clk_fs_half or negedge locked) begin
    if (!locked) begin
      sign_cnt <= 1'b0;
    end else if (sign && sign_cnt <= 1'd0) begin
      sign_cnt <= sign_cnt + 1'b1;  // 检测到下降沿时计数
    end else if (sign_cnt == 1'd1) begin
      sign_cnt <= sign_cnt;         // 保持计数值
    end
  end

  // ----------------------------------------------------------------------------
  // 21. 2分频时钟生成和边沿检测
  // ----------------------------------------------------------------------------
  // 2分频时钟寄存器
  always @(posedge clk_fs_half or negedge rst_in) begin
    if (!rst_in) begin
      clk_2_0 <= 0;
      clk_2_1 <= 0;
    end else begin
      clk_2_0 <= clk_2_temp;  // 当前值
      clk_2_1 <= clk_2_0;     // 前一个值（用于边沿检测）
    end
  end

  // 上升沿计数器
  always @(posedge clk_fs_half or negedge rst_in) begin
    if (!rst_in) begin
      clk_pos_cnt <= 17'd0;
    end else if (start_add && clk_pos && clk_pos_cnt < frame_num) begin
      clk_pos_cnt <= clk_pos_cnt + 1;  // 检测到上升沿时计数
    end else begin
      clk_pos_cnt <= clk_pos_cnt;      // 保持
    end
  end

  // 有效信号生成（在指定帧数内有效）
  always @(posedge clk_fs_half or negedge rst_in) begin
    if (!rst_in) begin
      valid <= 0;
    end else begin
      if (start_add && clk_pos_cnt < frame_num) begin
        valid <= 1;   // 启动且未达到帧数上限时有效
      end else begin
        valid <= 0;   // 否则无效
      end
    end
  end

  // ----------------------------------------------------------------------------
  // 22. 时钟输出控制
  // ----------------------------------------------------------------------------
  // 调试时钟输出（2分频时钟）
  always @(posedge clk_160) begin
    if (!rst_in) begin
      clk_2_out <= 1'b0;
    end else begin
      if (valid) begin
        clk_2_out <= clk_2_temp;  // 有效时输出2分频时钟
      end
    end
  end

  // FFT有效信号
  always @(posedge clk_160) begin
    if (!rst_in) begin
      valid_fft <= 1'b0;
    end else begin
      if (valid) begin
        valid_fft <= clk_2_temp;  // 有效时传递时钟
      end
    end
  end

  // ============================================================================
  // DMA数据打包和组号控制
  // ============================================================================

  // 累加结束上升沿检测
  (*mark_debug="true"*) reg end_add_0;
  (*mark_debug="true"*) wire end_add_pos;
  assign end_add_pos = end_add && !end_add_0;  // 检测end_add的上升沿

  // end_add延迟寄存器
  always @(posedge clk_160 or negedge rst_in) begin
    if (!rst_in) begin
      end_add_0 <= 0;
    end else begin
      end_add_0 <= end_add;  // 延迟一个周期
    end
  end

  // 数据选择标志（选择发送FFT结果或组号）
  (*mark_debug="true"*) reg data_choose;
  always @(posedge clk_160 or negedge rst_in) begin
    if (!rst_in) begin
      data_choose <= 0;
    end else if (FDMA_S_fdma_wvalid) begin
      data_choose <= 1;  // DMA写有效时选择FFT数据
    end
  end

  // 数据选择移位寄存器（8级流水线）
  reg [7:0] shift_data_choose;
  wire data_choose_7 = shift_data_choose[7];  // 第7级输出

  always @(posedge clk_160 or negedge rst_in) begin
    if (!rst_in) begin
      shift_data_choose <= 8'd0;
    end else if (FDMA_S_fdma_wvalid) begin
      shift_data_choose <= {shift_data_choose[6:0], data_choose};
    end
  end

  // 组号计数器（每次累加结束时递增）
  (*mark_debug="true"*) reg [31:0] group_number;
  always @(posedge clk_160) begin
    if (end_add_pos) begin
      group_number <= group_number + 1;  // 组号递增
    end
  end

  // DMA数据选择：data_choose=1时发送FFT结果，否则发送组号
  (*mark_debug="true"*) wire [31:0] fdma_data_in;
  assign fdma_data_in = data_choose ? bfs_out : group_number;

  // 地址偏移：发送FFT数据时偏移4字节，发送组号时偏移0字节
  (*mark_debug="true"*) wire [31:0] addr_offset_4;
  assign addr_offset_4 = data_choose ? 4 : 0;

  // DMA使能：发送FFT数据时用bfs_valid，发送组号时用end_add_pos
  (*mark_debug="true"*) wire fdma_data_en;
  assign fdma_data_en = data_choose ? bfs_valid : end_add_pos;

  // ============================================================================
  // 主要模块实例化
  // ============================================================================

  // ----------------------------------------------------------------------------
  // 1. 系统包装模块（包含Zynq PS和PL主要逻辑）
  // ----------------------------------------------------------------------------
  wire tx_ctrl_clk, tx_ctrl_resetn;
  wire [31:0] tx_gpio_ctrl, tx_gpio_status, tx_gt_status;
  // Only config index/apply/enable/soft-reset are exposed in Stage 1.
  // Rate ID/request bits and all dynamic executor entries are disabled.
  wire [31:0] tx_gpio_ctrl_fixed = {21'd0, tx_gpio_ctrl[10:0]};
  wire [63:0] optical_txdata, optical_valid_mask;
  wire optical_txusrclk2, optical_eom_clk, optical_eom_safe;
  wire [2:0] optical_eom_subdiv_log2;
  wire optical_tx_rst, optical_gt_ready, optical_apply_blocked;
  wire tx_cfg_bram_clk, tx_cfg_bram_rst, tx_cfg_bram_en;
  wire [3:0] tx_cfg_bram_we;
  wire [31:0] tx_cfg_bram_addr, tx_cfg_bram_din, tx_cfg_bram_dout;

  laser_gt_tx_profile0 u_laser_gt_tx_profile0 (
    .ctrl_clk(tx_ctrl_clk), .ctrl_rst(~tx_ctrl_resetn),
    .gt_refclk125_p(gt_refclk125_p), .gt_refclk125_n(gt_refclk125_n),
    .ad9528_gtnorthrefclk0(1'b0),
    .gpio_ctrl_axi(tx_gpio_ctrl_fixed), .gpio_status_axi(tx_gpio_status),
    .dynamic_start(1'b0), .dynamic_descriptor_valid(1'b0),
    .dynamic_words(2048'd0), .dynamic_refclk_ready(1'b0),
    .dynamic_abort(1'b0), .dynamic_rollback_ready(1'b0),
    .txdata_in(optical_txdata), .valid_mask_in(optical_valid_mask),
    .txusrclk2_out(optical_txusrclk2), .eom_clk_out(optical_eom_clk),
    .eom_subdiv_log2_out(optical_eom_subdiv_log2),
    .eom_clock_safe_out(optical_eom_safe),
    .tx_rst_out(optical_tx_rst), .gt_ready_out(optical_gt_ready),
    .gt_status_out(tx_gt_status),
    .dbg_apply_enable_blocked(optical_apply_blocked),
    .gtx_txp_out(gtx_txp_out), .gtx_txn_out(gtx_txn_out)
  );

  laser_tx_core #(.CURRENT_STATIC_RATE_MBPS(500)) u_laser_tx_core (
    .axi_clk(tx_ctrl_clk), .axi_rstn(tx_ctrl_resetn),
    .txusrclk2(optical_txusrclk2), .eom_clk(optical_eom_clk),
    .eom_subdiv_log2(optical_eom_subdiv_log2),
    .eom_clock_safe(optical_eom_safe), .tx_rst(optical_tx_rst),
    .gt_ready(optical_gt_ready), .gpio_ctrl(tx_gpio_ctrl_fixed),
    .rate_apply_enable_blocked(optical_apply_blocked),
    .gpio_status(tx_gpio_status),
    .bram_clk(tx_cfg_bram_clk), .bram_rst(tx_cfg_bram_rst),
    .bram_en(tx_cfg_bram_en), .bram_we(tx_cfg_bram_we),
    .bram_addr(tx_cfg_bram_addr), .bram_din(tx_cfg_bram_din),
    .bram_dout(tx_cfg_bram_dout),
    .txdata(optical_txdata), .valid_mask(optical_valid_mask),
    .eom_out(eom_out), .soa_gate_out(soa_gate_out),
    .acq_trig_out(acq_trig_out), .acq_gate_out(acq_gate_out),
    .gt_sequence_sync_out(gt_sequence_sync_out),
    .txusrclk2_monitor_out(txusrclk2_monitor_out)
  );

  system_wrapper i_system_wrapper (
    .tx_ctrl_clk(tx_ctrl_clk), .tx_ctrl_resetn(tx_ctrl_resetn),
    .tx_gpio_ctrl(tx_gpio_ctrl), .tx_gpio_status(tx_gpio_status),
    .tx_gt_status(tx_gt_status),
    .TX_CONFIG_BRAM_addr(tx_cfg_bram_addr),
    .TX_CONFIG_BRAM_clk(tx_cfg_bram_clk),
    .TX_CONFIG_BRAM_din(tx_cfg_bram_din),
    .TX_CONFIG_BRAM_dout(tx_cfg_bram_dout),
    .TX_CONFIG_BRAM_en(tx_cfg_bram_en),
    .TX_CONFIG_BRAM_rst(tx_cfg_bram_rst),
    .TX_CONFIG_BRAM_we(tx_cfg_bram_we),
    // 系统配置
    .dac_fifo_bypass        (gpio_o[60]),        // DAC FIFO旁路
    .adc_fir_filter_active  (gpio_o[61]),        // ADC FIR滤波器使能
    .dac_fir_filter_active  (gpio_o[62]),        // DAC FIR滤波器使能

    // DDR3接口
    .ddr_addr               (ddr_addr),
    .ddr_ba                 (ddr_ba),
    .ddr_cas_n              (ddr_cas_n),
    .ddr_ck_n               (ddr_ck_n),
    .ddr_ck_p               (ddr_ck_p),
    .ddr_cke                (ddr_cke),
    .ddr_cs_n               (ddr_cs_n),
    .ddr_dm                 (ddr_dm),
    .ddr_dq                 (ddr_dq),
    .ddr_dqs_n              (ddr_dqs_n),
    .ddr_dqs_p              (ddr_dqs_p),
    .ddr_odt                (ddr_odt),
    .ddr_ras_n              (ddr_ras_n),
    .ddr_reset_n            (ddr_reset_n),
    .ddr_we_n               (ddr_we_n),

    // PS固定接口
    .fixed_io_ddr_vrn       (fixed_io_ddr_vrn),
    .fixed_io_ddr_vrp       (fixed_io_ddr_vrp),
    .fixed_io_mio           (fixed_io_mio),
    .fixed_io_ps_clk        (fixed_io_ps_clk),
    .fixed_io_ps_porb       (fixed_io_ps_porb),
    .fixed_io_ps_srstb      (fixed_io_ps_srstb),

    // GPIO接口
    .gpio_i                 (gpio_i),
    .gpio_o                 (gpio_o),
    .gpio_t                 (gpio_t),

    // I2C接口
    .iic_main_scl_io        (iic_scl),
    .iic_main_sda_io        (iic_sda),

    // ADRV9009接收数据接口
    .rx_data_0_n            (rx_data_n[0]),
    .rx_data_0_p            (rx_data_p[0]),
    .rx_data_1_n            (rx_data_n[1]),
    .rx_data_1_p            (rx_data_p[1]),
    .rx_data_2_n            (rx_data_n[2]),
    .rx_data_2_p            (rx_data_p[2]),
    .rx_data_3_n            (rx_data_n[3]),
    .rx_data_3_p            (rx_data_p[3]),

    // 参考时钟和同步
    .rx_ref_clk_0           (ref_clk1),          // 接收参考时钟
    .rx_ref_clk_2           (ref_clk1),          // 接收过采样参考时钟
    .rx_sync_0              (rx_sync),           // 接收同步
    .rx_sync_2              (rx_os_sync),        // 接收过采样同步
    .rx_sysref_0            (sysref),            // 接收系统参考
    .rx_sysref_2            (sysref),            // 接收过采样系统参考

    // 音频输出
    .spdif                  (spdif),

    // SPI0接口（连接AD9528和ADRV9009）
    .spi0_clk_i             (spi_clk),
    .spi0_clk_o             (spi_clk),
    .spi0_csn_0_o           (spi_csn_ad9528),
    .spi0_csn_1_o           (spi_csn_adrv9009),
    .spi0_csn_2_o           (),                  // 未使用
    .spi0_csn_i             (1'b1),              // 片选输入（未使用）
    .spi0_sdi_i             (spi_miso),          // 从设备输入
    .spi0_sdo_i             (spi_mosi),          // 主设备输出（输入）
    .spi0_sdo_o             (spi_mosi),          // 主设备输出

    // SPI1接口（未使用）
    .spi1_clk_i             (1'd0),
    .spi1_clk_o             (),
    .spi1_csn_0_o           (),
    .spi1_csn_1_o           (),
    .spi1_csn_2_o           (),
    .spi1_csn_i             (1'b1),
    .spi1_sdi_i             (1'd0),
    .spi1_sdo_i             (1'd0),
    .spi1_sdo_o             (),

    // ADRV9009发送数据接口
    .tx_data_0_n            (tx_data_n[0]),
    .tx_data_0_p            (tx_data_p[0]),
    .tx_data_1_n            (tx_data_n[1]),
    .tx_data_1_p            (tx_data_p[1]),
    .tx_data_2_n            (tx_data_n[2]),
    .tx_data_2_p            (tx_data_p[2]),
    .tx_data_3_n            (tx_data_n[3]),
    .tx_data_3_p            (tx_data_p[3]),

    // 发送时钟和同步
    .tx_ref_clk_0           (ref_clk1),          // 发送参考时钟
    .tx_sync_0              (tx_sync),           // 发送同步
    .tx_sysref_0            (sysref),            // 发送系统参考

    // DMA接口
    .FDMA_S_fdma_waddr      (FDMA_S_fdma_waddr),
    .FDMA_S_fdma_wareq      (FDMA_S_fdma_wareq),
    .FDMA_S_fdma_wbusy      (FDMA_S_fdma_wbusy),
    .FDMA_S_fdma_wdata      (fdma_data_in),      // DMA写入数据
    .FDMA_S_fdma_wready     (FDMA_S_fdma_wready),
    .FDMA_S_fdma_wsize      (FDMA_S_fdma_wsize),
    .FDMA_S_fdma_wvalid     (FDMA_S_fdma_wvalid),

    // 状态和控制信号
    .end_add                (end_add),           // 累加结束
    .end_fdma               (end_fdma),          // DMA结束
    .end_rst                (end_rst),           // 复位结束
    .rst_in                 (rst_in),            // 复位输入
    .din_add                (dout_fft),          // FFT输出数据
    .valid_add              (data_out_valid),    // FFT输出有效
    .fnum                   (sampling_num_7 >> 4), // FFT点数（采样点数/16/2）
    .sin_wave               (sin_wave),          // 正弦波输出（正常速率）
    .sin_wave_8             (sin_wave_8),        // 正弦波输出（8倍速）
    .valid_fft              (valid_fft),         // FFT有效
    .data_trans_en          (data_trans_en),     // 数据传输使能
    .start_gpio             (gpio_out[0]),       // 启动GPIO
    .sampling_num_in        (sampling_num_8),    // 采样点数输入

    // 时钟信号
    .clk_fs_half            (clk_fs_half),       // 半采样率时钟
    .locked                 (locked),            // 时钟锁定
    .clk_160                (clk_160),           // 160MHz时钟

    // 配置参数
    .frame_num              (frame_num),         // 帧数
    .bfs                    (bfs),               // FFT幅度结果
    .bfs_valid              (bfs_valid),         // FFT结果有效
    .output_en              (output_en),         // 输出使能
    .sampling_num           (sampling_num),      // 采样点数
    .dout_fft               (dout_fft),          // FFT输出
    .data_out_valid         (data_out_valid),    // 数据输出有效
    .fft_valid0             (fft_valid0),        // FFT通道0有效
    .fft_valid1             (fft_valid1),        // FFT通道1有效

    // 控制信号
    .start_add              (start_add),         // 启动累加
    .spi_rst                (spi_rst),           // SPI复位

    // 时钟和数据
    .clk_2                  (clk_2_temp),        // 2分频时钟
    .adc_data_0             (adc_data_0),        // ADC通道0数据
    .adc_enable_0           (adc_enable_0),      // ADC通道0使能
    .adc_valid_0            (adc_valid_0),       // ADC通道0有效
    .adc_data_1             (adc_data_1),        // ADC通道1数据
    .adc_enable_1           (adc_enable_1),      // ADC通道1使能
    .adc_valid_1            (adc_valid_1),       // ADC通道1有效

    // 复位和GPIO
    .rst_clkwiz             (rst_clkwiz),        // 时钟模块复位
    .gpio_out               (gpio_out)           // GPIO输出
  );

  // ----------------------------------------------------------------------------
  // 2. DMA控制器模块
  // ----------------------------------------------------------------------------
  control_fdma control_fdma(
    .ui_clk           (clk_fs_half),       // 用户接口时钟
    .fdma_rstn        (rst_in),            // DMA复位（低有效）
    .fdma_waddr       (FDMA_S_fdma_waddr), // 写地址
    .fdma_wareq       (FDMA_S_fdma_wareq), // 写请求
    .fdma_wsize       (FDMA_S_fdma_wsize), // 写大小
    .fdma_wbusy       (FDMA_S_fdma_wbusy), // 写忙标志
    .fdma_wvalid      (FDMA_S_fdma_wvalid),// 写有效
    .fdma_wready      (FDMA_S_fdma_wready),// 写就绪
    .res_output_en    (fdma_data_en),      // 结果输出使能
    .output_end       (output_end),        // 输出结束
    .addr_offset_4    (addr_offset_4)      // 地址偏移
  );

  // ----------------------------------------------------------------------------
  // 3. 乘法器模块实例化（用于加窗处理）
  // ----------------------------------------------------------------------------

  // 正常速率I路乘法器（数据 × 窗系数）
  mult_gen_top mult_gen_top_0 (
    .CLK (clk_160),              // 160MHz时钟
    .A   (data_in_test_0),       // I路输入数据
    .B   (data_win),             // 窗系数
    .CE  (dds_ready),            // 时钟使能（DDS就绪时有效）
    .P   (datai)                 // 乘法结果输出
  );

  // 正常速率Q路乘法器
  mult_gen_top mult_gen_top_1 (
    .CLK (clk_160),
    .A   (data_in_test_1),       // Q路输入数据
    .B   (data_win),             // 窗系数
    .CE  (dds_ready),
    .P   (dataq)                 // 乘法结果输出
  );

  // 8倍速I路乘法器
  mult_gen_top mult_gen_top_2 (
    .CLK (clk_160),
    .A   (data_in_test_0),       // I路输入数据
    .B   (data_win_8),           // 8倍速窗系数
    .CE  (dds_ready_8),          // 8倍速使能
    .P   (datai_8)               // 乘法结果输出
  );

  // 8倍速Q路乘法器
  mult_gen_top mult_gen_top_3 (
    .CLK (clk_160),
    .A   (data_in_test_1),       // Q路输入数据
    .B   (data_win_8),           // 8倍速窗系数
    .CE  (dds_ready_8),          // 8倍速使能
    .P   (dataq_8)               // 乘法结果输出
  );

  // ----------------------------------------------------------------------------
  // 4. FFT有效输入模块
  // ----------------------------------------------------------------------------
  fft_valid_in fft_valid_in(
    .aclk      (clk_160),       // 时钟
    .aresetn   (rst_in),        // 复位（低有效）
    .delay_end (delay_end),     // 延迟结束
    .valid     (fft_valid_out)  // FFT有效输出
  );

endmodule

// ***************************************************************************
// ***************************************************************************
