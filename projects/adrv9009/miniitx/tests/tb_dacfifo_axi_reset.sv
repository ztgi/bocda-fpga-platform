`timescale 1ns/1ps
// Exercise the generated IP, not a handwritten substitute reset model.
module tb_dacfifo_axi_reset;
    reg clk = 0;
    always #2 clk = ~clk;
    reg ext_reset_n = 0;
    wire peripheral_aresetn;
    system_dacfifo_axi_rstgen_0 dut (
        .slowest_sync_clk(clk),
        .ext_reset_in(ext_reset_n),
        .aux_reset_in(1'b1), // C_AUX_RESET_HIGH=0: inactive
        .mb_debug_sys_rst(1'b0),
        .dcm_locked(1'b1),
        .peripheral_aresetn(peripheral_aresetn)
    );
    task wait_edges(input integer count);
        repeat (count) @(posedge clk);
        #1;
    endtask
    initial begin
        wait_edges(100);
        if (peripheral_aresetn !== 1'b0) $fatal(1, "External reset not asserted");
        @(negedge clk); ext_reset_n = 1;
        wait_edges(100);
        if (peripheral_aresetn !== 1'b1) $fatal(1, "Reset stuck: auxiliary polarity/constant mismatch");
        @(negedge clk); ext_reset_n = 0;
        wait_edges(100);
        if (peripheral_aresetn !== 1'b0) $fatal(1, "Reset cannot reassert");
        @(negedge clk); ext_reset_n = 1;
        wait_edges(100);
        if (peripheral_aresetn !== 1'b1) $fatal(1, "Reset cannot release again");
        $display("DACFIFO_AXI_RESET_REGRESSION_PASS");
        $finish;
    end
endmodule
