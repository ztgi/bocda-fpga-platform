`timescale 1ns/1ps

// Passive observer of the existing four-converter, two-lane, F=4 RX stream.
// No ready/backpressure or reset is driven back into the production chain.
module generic_iq_observer #(
    // Number of PREVIOUS consecutive good edges required before publishing.
    // With 3, the first valid registered output is on the fourth good edge.
    parameter integer WARMUP_CYCLES = 3
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 rx_clk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rx_reset" *)
    input wire rx_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rx_reset RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input wire rx_reset,
    input wire [15:0] adc_data_0,
    input wire [15:0] adc_data_1,
    input wire [15:0] adc_data_2,
    input wire [15:0] adc_data_3,
    input wire [3:0] adc_enable,
    input wire jesd_data_valid,
    input wire [3:0] jesd_sof,
    input wire [1:0] jesd_ctrl_state,
    input wire [3:0] jesd_lane_cgs_state,
    input wire jesd_core_reset,
    output reg signed [15:0] rx1_i,
    output reg signed [15:0] rx1_q,
    output reg signed [15:0] rx2_i,
    output reg signed [15:0] rx2_q,
    output reg sample_valid,
    output reg link_ready,
    output reg [31:0] sample_index
);
    localparam integer CW = (WARMUP_CYCLES < 2) ? 1 : $clog2(WARMUP_CYCLES + 1);
    localparam [CW-1:0] WARMUP_LIMIT = WARMUP_CYCLES;
    reg [CW-1:0] good_edges;
    reg [31:0] next_sample_index;
    wire link_good = jesd_data_valid && (jesd_sof == 4'b0001) &&
                     (jesd_ctrl_state == 2'b11) &&
                     (jesd_lane_cgs_state == 4'b1010);

    // All inputs must already belong to rx_clk. Synchronous reset only;
    // the upstream reset synchronizer must provide safe reset release.
    // Mapping preserves the existing algorithm convention, not an on-board
    // verification of physical I/Q ordering or conjugation.
    always @(posedge rx_clk) begin
        if (rx_reset || jesd_core_reset) begin
            rx1_i <= 16'sd0;
            rx1_q <= 16'sd0;
            rx2_i <= 16'sd0;
            rx2_q <= 16'sd0;
            good_edges <= 0;
            next_sample_index <= 0;
            sample_index <= 0;
            sample_valid <= 1'b0;
            link_ready <= 1'b0;
        end else begin
            // One register boundary; invalid samples are explicitly don't-care.
            rx1_i <= adc_data_0;
            rx1_q <= adc_data_1;
            rx2_i <= adc_data_2;
            rx2_q <= adc_data_3;
            sample_valid <= 1'b0;
            link_ready <= 1'b0;
            sample_index <= 0;
            if (!link_good) begin
                good_edges <= 0;
                next_sample_index <= 0;
            end else begin
                if (good_edges < WARMUP_LIMIT)
                    good_edges <= good_edges + 1'b1;
                if (good_edges == WARMUP_LIMIT) begin
                    link_ready <= 1'b1;
                    if (&adc_enable) begin
                        sample_valid <= 1'b1;
                        sample_index <= next_sample_index;
                        next_sample_index <= next_sample_index + 1'b1;
                    end else begin
                        next_sample_index <= 0;
                    end
                end else begin
                    next_sample_index <= 0;
                end
            end
        end
    end
    // synthesis translate_off
    initial begin
        if (WARMUP_CYCLES < 1)
            $fatal(1, "WARMUP_CYCLES must be at least 1");
    end
    // synthesis translate_on
endmodule
