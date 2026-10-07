`timescale 1ns/1ps
// Freeze the parameter on the rising start_add handshake (parameters already
// accepted by state_change). Two preparation edges precede the existing
// 20-cycle output_en delay. No pipeline is added to the sample/data path.
module rx_capture_threshold (
    input wire rx_clk,
    input wire resetn,
    input wire start_add,
    input wire [23:0] sampling_num,
    output reg [28:0] threshold_reg,
    output reg threshold_valid
);
    reg start_add_d;
    reg [20:0] groups_snapshot;
    reg [28:0] threshold_next;
    reg prepare_valid, commit_valid;
    always @(posedge rx_clk or negedge resetn) begin
        if (!resetn) begin
            start_add_d <= 1'b0;
            groups_snapshot <= 21'd0;
            threshold_next <= 29'd0;
            threshold_reg <= 29'd0;
            threshold_valid <= 1'b0;
            prepare_valid <= 1'b0;
            commit_valid <= 1'b0;
        end else begin
            start_add_d <= start_add;
            prepare_valid <= start_add && !start_add_d;
            commit_valid <= prepare_valid;
            if (start_add && !start_add_d) begin
                groups_snapshot <= sampling_num[23:3];
                threshold_valid <= 1'b0;
            end
            if (prepare_valid)
                threshold_next <= {groups_snapshot, 8'd0} - {8'd0, groups_snapshot};
            if (commit_valid) begin
                threshold_reg <= threshold_next;
                threshold_valid <= 1'b1;
            end
        end
    end
    // Full range: (2^21-1)*255 = 534773505 < 2^29. No overflow/truncation
    // differs from the original unsigned 32-bit multiplication/comparison.
endmodule
