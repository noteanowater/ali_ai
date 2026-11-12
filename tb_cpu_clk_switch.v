`timescale 1ns/1ps

//----------------- behavioural models of the library cells (simulation only) -----------------
module P1_CLK_GATE (input CLK, input EN, input SE, output YGCLK);
reg en_lat;
always @ (CLK or EN or SE)
    if (!CLK)
        en_lat = EN | SE;
assign YGCLK = CLK & en_lat;
endmodule

module OR2_X6B_A7PP140ZTL_C35 (input A, input B, output Y);
assign Y = A | B;
endmodule

//----------------- testbench -----------------
module tb_cpu_clk_switch;

// Note: clk_switch_2to1 keeps the old clock running for one more cycle after
// its sel_*_dly3 feedback falls, while the new clock is enabled 5 new-clock
// cycles after that feedback. With a latch based clock gate the old clock
// high phase must therefore end within ~4 cycles of the new clock, i.e. the
// new clock may be at most ~8x faster than the old one. Override DIV_HALF
// (e.g. -P tb_cpu_clk_switch.DIV_HALF=20.0) to see the mux glitch otherwise.
parameter real DIV_HALF = 5.0;    // core_a45_div_clk : 100MHz
parameter real PLL_HALF = 1.3;    // pll_sys_a45_clk  : ~385MHz
parameter real CLK_HALF = 3.5;    // control clock    : ~143MHz

reg        clk, rst_n;
reg        div_clk, pll_clk;
reg        sel, wfi0, wfi1;
reg  [7:0] stable_cnt;
reg        irq_en, irq_clr;
wire       a45_clk, sel_cur, busy, done, irq;

integer    errors = 0;

cpu_clk_switch #(.CNT_W(8)) dut (
    .test_mode        (1'b0      ),
    .test_se          (1'b0      ),
    .clk              (clk       ),
    .rst_n            (rst_n     ),
    .core_a45_div_clk (div_clk   ),
    .pll_sys_a45_clk  (pll_clk   ),
    .a45_src_clk_sel  (sel       ),
    .core0_wfi        (wfi0      ),
    .core1_wfi        (wfi1      ),
    .cfg_stable_cnt   (stable_cnt),
    .irq_en           (irq_en    ),
    .irq_clr          (irq_clr   ),
    .a45_clk          (a45_clk   ),
    .a45_clk_sel_cur  (sel_cur   ),
    .switch_busy      (busy      ),
    .switch_done      (done      ),
    .switch_done_irq  (irq       )
);

initial clk     = 0; always #CLK_HALF clk     = ~clk;
initial div_clk = 0; always #DIV_HALF div_clk = ~div_clk;
initial pll_clk = 0; always #PLL_HALF pll_clk = ~pll_clk;

//----------------- checkers -----------------
// glitch check: no pulse (high or low) shorter than the fastest clock half period
realtime last_edge;
initial last_edge = 0;
always @ (a45_clk) begin
    if (rst_n && ($realtime - last_edge) < (PLL_HALF - 0.01)) begin
        $display("ERROR %0t: glitch on a45_clk, pulse width %0f ns", $time, $realtime - last_edge);
        errors = errors + 1;
    end
    last_edge = $realtime;
end

// the select to the mux may only change while both cores are in WFI
always @ (sel_cur)
    if (rst_n && !(wfi0 && wfi1)) begin
        $display("ERROR %0t: clock switched while a core is not in WFI", $time);
        errors = errors + 1;
    end

task check;
    input        cond;
    input [319:0] msg;
    begin
        if (!cond) begin
            $display("ERROR %0t: %0s", $time, msg);
            errors = errors + 1;
        end
    end
endtask

// measure the period of a45_clk
function is_period;
    input real period;
    input real half;
    is_period = (period > 2*half - 0.01) && (period < 2*half + 0.01);
endfunction

task measure_period;
    output real period;
    realtime t0;
    begin
        @ (posedge a45_clk); t0 = $realtime;
        @ (posedge a45_clk); period = $realtime - t0;
    end
endtask

task clear_irq;
    begin
        @ (posedge clk); irq_clr <= 1'b1;
        @ (posedge clk); irq_clr <= 1'b0;
        repeat (2) @ (posedge clk);
        check(!irq, "irq not cleared");
    end
endtask

real period;

initial begin
    rst_n = 0; sel = 0; wfi0 = 0; wfi1 = 0;
    stable_cnt = 8'd40; irq_en = 1; irq_clr = 0;
    #103 rst_n = 1;
    repeat (20) @ (posedge clk);

    measure_period(period);
    check(is_period(period, DIV_HALF), "reset: a45_clk is not div clk");

    // ---- case 1: div -> pll, cores enter WFI one after the other ----
    @ (posedge clk); sel <= 1'b1;
    repeat (10) @ (posedge clk);
    check(busy && !sel_cur, "case1: must wait for WFI");
    wfi0 = 1;
    repeat (10) @ (posedge clk);
    check(busy && !sel_cur, "case1: must wait for both cores");
    wfi1 = 1;
    @ (posedge irq);
    check(sel_cur && !busy, "case1: irq without switch");
    measure_period(period);
    check(is_period(period, PLL_HALF), "case1: a45_clk is not pll clk at irq");
    wfi0 = 0; wfi1 = 0;                       // irq wakes the cores up
    clear_irq;

    // ---- case 2: pll -> div ----
    @ (posedge clk); sel <= 1'b0;
    #37 wfi1 = 1;
    #91 wfi0 = 1;
    @ (posedge irq);
    check(!sel_cur && !busy, "case2: irq without switch");
    measure_period(period);
    check(is_period(period, DIV_HALF), "case2: a45_clk is not div clk at irq");
    wfi0 = 0; wfi1 = 0;
    clear_irq;

    // ---- case 3: request withdrawn before WFI -> no switch, no irq ----
    @ (posedge clk); sel <= 1'b1;
    repeat (10) @ (posedge clk);
    sel <= 1'b0;
    repeat (10) @ (posedge clk);
    check(!busy && !sel_cur && !irq, "case3: request not dropped");
    wfi0 = 1; wfi1 = 1;
    repeat (80) @ (posedge clk);
    check(!busy && !sel_cur && !irq, "case3: unexpected switch");
    wfi0 = 0; wfi1 = 0;

    // ---- case 4: irq masked, status still set after enabling ----
    irq_en = 0;
    @ (posedge clk); sel <= 1'b1;
    wfi0 = 1; wfi1 = 1;
    @ (posedge done);
    repeat (2) @ (posedge clk);
    check(!irq && sel_cur, "case4: irq not masked");
    irq_en = 1;
    #1 check(irq, "case4: irq status lost");
    wfi0 = 0; wfi1 = 0;
    clear_irq;

    repeat (20) @ (posedge clk);
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d errors", errors);
    $finish;
end

initial begin
    #200000;
    $display("TEST FAILED: timeout");
    $finish;
end

endmodule
