`timescale 1ns/1ps
// gpio_out[1] is an active-high software RESET, not a data/enable CDC.
// Assert immediately; release only after four edges of the target RX clock.
module rx_software_reset_sync (
    input wire rx_clk,
    input wire software_reset,
    output wire resetn
);
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg rst_in_0 = 1'b0;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg rst_in_1 = 1'b0;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg rst_in_2 = 1'b0;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg rst_in = 1'b0;
    always @(posedge rx_clk or posedge software_reset) begin
        if (software_reset) begin
            rst_in_0 <= 1'b0;
            rst_in_1 <= 1'b0;
            rst_in_2 <= 1'b0;
            rst_in <= 1'b0;
        end else begin
            rst_in_0 <= 1'b1;
            rst_in_1 <= rst_in_0;
            rst_in_2 <= rst_in_1;
            rst_in <= rst_in_2;
        end
    end
    assign resetn = rst_in;
endmodule
