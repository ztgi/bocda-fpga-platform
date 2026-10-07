`timescale 1ns/1ps
module tb_rx_baseline;
    reg clk=0;
    always #2 clk=~clk;
    reg sw_rst=1;
    wire rstn;
    rx_software_reset_sync reset_dut(clk, sw_rst, rstn);
    reg start=0;
    reg [23:0] samples=0;
    wire [28:0] threshold;
    wire threshold_valid;
    rx_capture_threshold threshold_dut(clk,rstn,start,samples,threshold,threshold_valid);
    reg output_en=0;
    reg [28:0] count_new=0, count_old=0;
    reg en_new=0, en_old=0;
    reg [23:0] frozen_samples;
    reg compare_enable=0;
    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin count_new<=0;count_old<=0;en_new<=0;en_old<=0;end
        else begin
            en_new <= output_en && threshold_valid && count_new<threshold;
            en_old <= output_en && count_old<((frozen_samples>>3)*255);
            if(output_en && threshold_valid && count_new<threshold) count_new<=count_new+1;
            if(output_en && count_old<((frozen_samples>>3)*255)) count_old<=count_old+1;
        end
    end
    always @(negedge clk) if(compare_enable &&
       (count_new!==count_old || en_new!==en_old)) $fatal(1,"counter/data_trans_en boundary differs");
    task tick; begin @(posedge clk); #0.2; end endtask
    task reset_release;
        integer k;
        begin
            compare_enable=0; output_en=0;start=0;
            @(negedge clk); #0.3;sw_rst=1;#0.1;
            if(rstn!==0) $fatal(1,"reset must assert without RX edge");
            @(negedge clk); sw_rst=0;
            for(k=1;k<=4;k=k+1) begin
                tick;
                if(rstn !== (k==4)) $fatal(1,"reset release must be fourth edge");
            end
            tick;
        end
    endtask
    task commit(input [23:0] n);
        reg [31:0] expected;
        begin
            @(negedge clk); start=0; tick;
            @(negedge clk); samples=n; frozen_samples=n;start=1;
            expected=(n>>3)*255;
            tick;if(threshold_valid) $fatal(1,"premature threshold");
            tick;if(threshold_valid) $fatal(1,"premature threshold 2");
            tick;if(!threshold_valid || threshold !== expected)
                $fatal(1,"threshold mismatch n=%h got=%h expected=%h",n,threshold,expected);
            // A parameter write during active capture must not change the snapshot.
            @(negedge clk); samples=~n;
            repeat(4) tick;
            if(threshold!==expected) $fatal(1,"active threshold contaminated");
        end
    endtask
    // State machine uses the original BRAM flag/data interface (no forced states).
    reg sc_resetn=0;
    reg [31:0] bram=0;
    reg add_done=0,dma_done=0,reset_done=0;
    wire [31:0] addr,din,rd_len,wr_len;
    wire rd,wr,start_add;
    state_change sc(.clk(clk),.rst_n(sc_resetn),.dout_in(bram),.start_gpio(1'b0),
      .end_add(add_done),.end_fdma(dma_done),.end_rst(reset_done),
      .addr(addr),.din_out(din),.start_rd(rd),.start_wr(wr),
      .rd_len(rd_len),.wr_len(wr_len),.start_add(start_add));
    integer i,k;
    initial begin
        #0.2;
        if(sc.flag_0!==0 || sc.clk_cnt!==0) $fatal(1,"missing FSM reset");
        sc_resetn=1;
        repeat(7) tick;
        if(sc.state!==1 || addr!==60) $fatal(1,"idle handshake");
        @(negedge clk);bram=1;
        wait(rd && addr==0 && rd_len==60);
        repeat(22) tick;
        if(sc.state!==2 || din!==2) $fatal(1,"parameter acknowledgment");
        @(negedge clk);bram=3;
        repeat(3) tick;
        if(!start_add || sc.state!==3) $fatal(1,"capture start handshake");
        @(negedge clk);add_done=1;tick;
        if(start_add || din!==4 || sc.state!==4) $fatal(1,"add acknowledgment");
        @(negedge clk);dma_done=1;tick;
        if(din!==5 || sc.state!==5) $fatal(1,"DMA acknowledgment");
        @(negedge clk);reset_done=1;tick;
        if(sc.state!==0) $fatal(1,"return idle");
        @(negedge clk);sc_resetn=0;#0.2;
        if(sc.flag_0!==0 || sc.clk_cnt!==0 || start_add!==0) $fatal(1,"runtime reset");
        reset_release;
        commit(0); commit(7); commit(8); commit(24'hffffff); commit(24'h800000);
        for(i=0;i<1000;i=i+1) commit($random);
        for(i=0;i<16;i=i+1) begin
            reset_release; commit(i*8+7);
            // Existing output_en_19 cannot arrive until 20 RX edges after output_en.
            repeat(20) tick;
            @(negedge clk);output_en=1;compare_enable=1;
            repeat(i*255+3) tick;
            if(count_new!==i*255 || en_new!==0) $fatal(1,"length boundary");
            @(negedge clk);output_en=0;tick;
        end
        $display("RX_BASELINE_RESET_THRESHOLD_HANDSHAKE_PASS");$finish;
    end
    initial begin #200000; $fatal(1,"timeout");end
endmodule
