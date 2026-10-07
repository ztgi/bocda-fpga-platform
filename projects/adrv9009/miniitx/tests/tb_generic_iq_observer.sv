`timescale 1ns/1ps
module tb_generic_iq_observer;
    reg clk=0;
    always #2 clk=~clk;
    reg rst=1, core_reset=0, valid=0;
    reg [3:0] sof=1, cgs=4'ha, en=4'hf;
    reg [1:0] ctrl=3;
    reg [63:0] data=0;
    wire [63:0] q;
    wire sv, ready;
    wire [31:0] idx;
    generic_iq_observer dut (
        .rx_clk(clk), .rx_reset(rst), .jesd_core_reset(core_reset),
        .adc_data_0(data[15:0]), .adc_data_1(data[31:16]),
        .adc_data_2(data[47:32]), .adc_data_3(data[63:48]),
        .adc_enable(en), .jesd_data_valid(valid), .jesd_sof(sof),
        .jesd_ctrl_state(ctrl), .jesd_lane_cgs_state(cgs),
        .rx1_i(q[15:0]), .rx1_q(q[31:16]),
        .rx2_i(q[47:32]), .rx2_q(q[63:48]),
        .sample_valid(sv), .link_ready(ready), .sample_index(idx)
    );
    integer good_count=0, cycles=0;
    reg [31:0] expected_next=0, expected_index;
    reg expected_ready, expected_valid;
    reg [63:0] expected_data;
    always @(posedge clk) begin
        cycles=cycles+1;
        expected_ready=0; expected_valid=0; expected_index=0;
        expected_data=data;
        if (rst || core_reset) begin
            expected_data=0; good_count=0; expected_next=0;
        end else if (!(valid && sof==1 && ctrl==3 && cgs==4'ha)) begin
            good_count=0; expected_next=0;
        end else begin
            expected_ready=(good_count >= 3);
            expected_valid=expected_ready && en==4'hf;
            if (expected_valid) begin
                expected_index=expected_next;
                expected_next=expected_next+1;
            end else expected_next=0;
            if(good_count<3) good_count=good_count+1;
        end
        #0.1;
        if ({q,sv,ready,idx} !== {expected_data,expected_valid,expected_ready,expected_index})
            $fatal(1,"Mismatch cycle=%0d valid=%b ready=%b index=%h expected=%b/%b/%h",
                cycles,sv,ready,idx,expected_valid,expected_ready,expected_index);
    end
    task tick(input integer n);
        repeat(n) begin
            @(negedge clk);
            data={data[47:0],data[63:48]}+64'h80010003ffff0001;
        end
    endtask
    integer i;
    initial begin
        tick(3); rst=0; tick(3); valid=1;
        tick(20);
        valid=0; tick(1); valid=1; tick(9);
        sof=2; tick(2); sof=1; tick(9);
        ctrl=2; tick(1); ctrl=3; tick(9);
        cgs=9; tick(2); cgs=4'ha; tick(9);
        cgs=6; tick(2); cgs=4'ha; tick(9);
        core_reset=1; tick(2); core_reset=0; tick(9);
        en=7; tick(3); en=4'hf; tick(9);
        rst=1; tick(2); rst=0; tick(9);
        // White-box acceleration of the defined 32-bit wrap boundary.
        dut.next_sample_index=32'hfffffffe;
        expected_next=32'hfffffffe;
        tick(4);
        for(i=0;i<300;i=i+1) begin
            valid=($urandom_range(0,9)!=0);
            sof=($urandom_range(0,19)==0)?4'b0100:4'b0001;
            en=($urandom_range(0,19)==0)?4'h3:4'hf;
            tick(1);
        end
        $display("GENERIC_IQ_OBSERVER_REGRESSION_PASS cycles=%0d",cycles);
        $finish;
    end
    initial begin #20000; $fatal(1,"Timeout"); end
endmodule
