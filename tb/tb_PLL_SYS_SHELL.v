`timescale 1ns/1ps
//==============================================================================
// Behavioral models for simulation only (library cells / IP used in synthesis)
//==============================================================================
module P_CLK_GATE (input CLK, input EN, input SE, output YGCLK);
reg en_l;
always @(*) if (!CLK) en_l = EN | SE;
assign YGCLK = CLK & en_l;
endmodule

module P1_CLK_GATE (input CLK, input EN, input SE, output YGCLK);
reg en_l;
always @(*) if (!CLK) en_l = EN | SE;
assign YGCLK = CLK & en_l;
endmodule

module OR2_X6B_A7PP140ZTL_C35 (input A, input B, output Y);
assign Y = A | B;
endmodule

module SRCKBUF (input I, output Z);
assign Z = I;
endmodule

module clk_div_256 (input clk, input rstn, input [7:0] div, output clk_o);
assign clk_o = 1'b0;
endmodule

// PLL model: Fvco = 24 * NI / M, clko0 = Fvco / (Q0_0+1), clko1 = Fvco / (Q0_1+1)
// pd=1 stops output and drops lock; locks LOCK_T after pd release (never locks when lock_block=1)
module INNO_PLL_TOP (
    output [7:0] tbladdr, output reg lock, output testout, output reg clko0, output reg clko1,
    input refclk, input pd, input [4:0] prediv, input [11:0] fbdiv, input [23:0] frac,
    input [2:0] postdiv0_0, postdiv0_1, postdiv1_0, postdiv1_1,
    input [1:0] gvco_bias, input [2:0] cpp_bias, cpi_bias, input dacpd, dsmpd, testen,
    input [1:0] testsel, input disable_sscg, input [3:0] divval, input downspread,
    input [7:0] ext_maxaddr, extwaveval, input sel_extwave, input [2:0] spread);
parameter real LOCK_T = 2000.0;
reg lock_block = 0;
assign tbladdr = 8'd0; assign testout = 1'b0;
real fvco, h0 = 1.0, h1 = 1.0;
initial begin lock = 0; clko0 = 0; clko1 = 0; end
always @(posedge pd) lock = 0;
always @(negedge pd) begin
    fvco = 24.0 * fbdiv / prediv;
    h0 = 1000.0 / (fvco / (postdiv0_0 + 1)) / 2.0;
    h1 = 1000.0 / (fvco / (postdiv0_1 + 1)) / 2.0;
    #(LOCK_T) if (!pd && !lock_block) lock = 1;
end
always #(h0) if (!pd) clko0 = ~clko0; else clko0 = 0;
always #(h1) if (!pd) clko1 = ~clko1; else clko1 = 0;
endmodule

//==============================================================================
module tb_PLL_SYS_SHELL;
reg osc = 0, rstj = 0;
always #20.833 osc = ~osc;                   // 24MHz, also used as PLL_SYS_CLK

reg  [31:0] cfg0; reg [28:0] cfg1; reg [31:0] cfg2;
reg  cfg_en = 0, int_en = 0, wfi0 = 0, wfi1 = 0;
reg  [1:0] mode = 0;
reg        upd = 1;
reg  [1:0] div2 = 0;
wire f600, f400, lock, irq, busy, done, tmo;
integer err = 0;

`ifdef WFI_LEVEL
localparam WFI_PULSE = 0;
`else
localparam WFI_PULSE = 1;
`endif

PLL_SYS_SHELL #(.DFS_LOCK_TIMEOUT_CYC(2000), .DFS_WFI_PULSE(WFI_PULSE)) dut (
    .PLL_SYS_F600_CLK(f600), .PLL_SYS_F400_CLK(f400), .PLL_SYS_LOCK(lock),
    .PLL_SYS_TESTOUT(), .PLL_SYS_TBLADDR(), .PLL_SYS_TEST_DIV1_CLK(), .PLL_SYS_TEST_DIV2_CLK(),
    .PLL_SYS_SCAN_DIV1_CLK(), .PLL_SYS_SCAN_DIV2_CLK(),
    .PLL_SYS_CLK_DIV1(8'h3b), .PLL_SYS_CLK_DIV2(8'h27),
    .PLL_SYS_CFG_0(cfg0), .PLL_SYS_CFG_1(cfg1), .PLL_SYS_CFG_2(cfg2), .PLL_SYS_CFG_EN(cfg_en),
    .PLL_SYS_DFS_MODE(mode), .PLL_SYS_DFS_PLL_UPD(upd), .PLL_SYS_DFS_DIV2(div2), .PLL_SYS_INT_EN(int_en),
    .CORE_WFI_MODE_0(wfi0), .CORE_WFI_MODE_1(wfi1), .CORE_CLK(f600),
    .PLL_SYS_LOCK_INT(irq), .PLL_SYS_DFS_BUSY(busy), .PLL_SYS_DFS_DONE(done), .PLL_SYS_LOCK_TIMEOUT(tmo),
    .DFT_CPU_SPEED_SEL(2'b00), .MBIST_ES_MODE(1'b0), .TEST_MODE(1'b0),
    .OSC_24M_CLK(osc), .PLL_SYS_CLK(osc), .PLL_DFT_RSTJ(1'b1), .PLL_SYS_RSTJ(rstj));

// Config (same CFG bit mapping as the shell): DIS_SSCG=1, DACPD=1, DSMPD=1 (shared with PD_REG)
task set_cfg(input [11:0] ni, input [4:0] m, input [2:0] q0, input [2:0] q1);
begin
    cfg0 = {1'b0, 1'b0, 1'b1, m, 24'd0};
    cfg1 = {1'b0, 3'd0, 3'd0, q1, q0, 2'd0, 1'b1, 1'b1, ni};
    cfg2 = {1'b0, 3'd0, 4'd1, 3'd3, 3'd2, 2'd1, 8'd0, 8'd0};
end
endtask

// ---------------- checks ----------------
wire [2:0] st = dut.U_PLL_SYS_DFS_CTRL.STATE;
wire [1:0] ml = dut.U_PLL_SYS_DFS_CTRL.MODE_L;
// 1) divider changes only while pd=1 (during DFS); 2) pd released >= 1us after divider change
realtime cfg_t = 0;
always @(dut.PLL_SYS_FBDIV_REG or dut.PLL_SYS_PREDIV_REG or dut.PLL_SYS_POSTDIV0_0_REG or dut.PLL_SYS_POSTDIV0_1_REG) begin
    cfg_t = $realtime;
    if (rstj && busy && !dut.PLL_SYS_PD_ALL) begin err = err + 1; $display("ERR: divider changed while pd=0"); end
end
always @(negedge dut.PLL_SYS_PD_ALL)
    if (rstj && busy && $realtime - cfg_t < 1000.0) begin err = err + 1; $display("ERR: pd released < 1us after divider set"); end
// 3) during pd: no edges on gated ports, only 24M clock on 24M-mode ports
// 4) glitch-free outputs: every high/low phase >= 0.75ns (fastest PLL half period ~0.835ns)
realtime l600 = 0, l400 = 0, e600 = 0, e400 = 0;
always @(posedge f600) if (st >= 3 && st <= 5) begin
    if (!ml[0]) begin err = err + 1; $display("ERR: F600 edge while gated"); end
    else if (l600 != 0 && $realtime - l600 < 40.0) begin err = err + 1; $display("ERR: F600 not 24M during pd"); end
    l600 = $realtime;
end else l600 = 0;
always @(posedge f400) if (st >= 3 && st <= 5) begin
    if (!ml[1]) begin err = err + 1; $display("ERR: F400 edge while gated"); end
    else if (l400 != 0 && $realtime - l400 < 40.0) begin err = err + 1; $display("ERR: F400 not 24M during pd"); end
    l400 = $realtime;
end else l400 = 0;
// 5) 24M-mode ports must keep running at 24M during pd
always @(posedge dut.U_PLL_SYS_DFS_CTRL.CLK) if (st == 4 && dut.U_PLL_SYS_DFS_CTRL.STATE_NXT == 5 && dut.U_PLL_SYS_DFS_CTRL.PLL_UPD_L) begin
    if (ml[0] && l600 == 0) begin err = err + 1; $display("ERR: F600 no 24M clock during pd"); end
    if (ml[1] && l400 == 0) begin err = err + 1; $display("ERR: F400 no 24M clock during pd"); end
end
always @(f600) begin if (rstj && e600 != 0 && $realtime - e600 < 0.75) begin err = err + 1; $display("ERR: F600 glitch @%0t", $time); end e600 = $realtime; end
always @(f400) begin if (rstj && e400 != 0 && $realtime - e400 < 0.75) begin err = err + 1; $display("ERR: F400 glitch @%0t", $time); end e400 = $realtime; end

// 6) PLL_UPD = 0: PLL must not be powered down and its config must not change
always @(posedge dut.PLL_SYS_PD_ALL) if (rstj && busy && !dut.U_PLL_SYS_DFS_CTRL.PLL_UPD_L) begin err = err + 1; $display("ERR: pd asserted with PLL_UPD=0"); end
always @(dut.PLL_SYS_FBDIV_REG or dut.PLL_SYS_POSTDIV0_0_REG) if (rstj && busy && !dut.U_PLL_SYS_DFS_CTRL.PLL_UPD_L) begin err = err + 1; $display("ERR: PLL config changed with PLL_UPD=0"); end

// 7) when the interrupt fires, both glitch-free muxes have finished switching to the target clock
always @(posedge irq) begin
    if (dut.U_A45_SRC_CLK_MUX.sel_clkb_dly3 !== dut.PLL_SYS_DFS_DIV2_SEL[0] ||
        dut.U_PLL_SYS_F400_SRC_CLK_MUX.sel_clkb_dly3 !== dut.PLL_SYS_DFS_DIV2_SEL[1]) begin err = err + 1; $display("ERR: divider mux not settled at IRQ"); end
    if (dut.U_A45_PLL_OSC_CLK_MUX.sel_clkb_dly3 !== dut.PLL_SYS_DFS_SEL_24M[0] ||
        dut.U_PLL_SYS_F400_PLL_OSC_CLK_MUX.sel_clkb_dly3 !== dut.PLL_SYS_DFS_SEL_24M[1]) begin err = err + 1; $display("ERR: 24M mux not settled at IRQ"); end
end

// CPU model: interrupt wakes it from WFI, ISR clears PLL_INT_EN
always @(posedge irq) begin
    #50 wfi0 = 0; wfi1 = 0;
    $display("[%0t] IRQ: mode=%b NI=%0d M=%0d done=%b tmo=%b", $time, ml,
             dut.PLL_SYS_FBDIV_REG, dut.PLL_SYS_PREDIV_REG, done, tmo);
    #200 int_en = 0;
end

task measure(input real exp600, input real exp400);
real a, b, c, d;
begin
    @(posedge f600) a = $realtime; @(posedge f600) b = $realtime;
    @(posedge f400) c = $realtime; @(posedge f400) d = $realtime;
    $display("  F600 = %0.1f MHz, F400 = %0.1f MHz", 1000.0/(b-a), 1000.0/(d-c));
    if (1000.0/(b-a) < exp600-2 || 1000.0/(b-a) > exp600+2 ||
        1000.0/(d-c) < exp400-2 || 1000.0/(d-c) > exp400+2) begin err = err + 1; $display("ERR: freq"); end
end
endtask

// WFI as a 1-cycle pulse in the CPU clock (F600) domain
task wfi_pulse(input integer core);
begin
    @(posedge f600) #0.1; if (core == 0) wfi0 = 1; else wfi1 = 1;
    @(posedge f600) #0.1; if (core == 0) wfi0 = 0; else wfi1 = 0;
end
endtask

reg pulse_mode = 0;
task dfs(input [1:0] md, input [11:0] ni, input [4:0] m, input [2:0] q0, input [2:0] q1);
begin
    set_cfg(ni, m, q0, q1); mode = md;       // SW 1.1 / 1.2
    #100 int_en = 1;                         // SW 1.3
    if (pulse_mode) begin                    // SW 2: WFI
        #500 wfi_pulse(0); #300 wfi_pulse(1);
    end else begin
        #500 wfi0 = 1; #300 wfi1 = 1;
    end
    wait (irq); wait (!irq);
    #500;
    if (busy || !done) begin err = err + 1; $display("ERR: state after dfs"); end
end
endtask

initial begin
    set_cfg(12'd250, 5'd3, 3'd3, 3'd4);
    #300 rstj = 1;
    wait (lock); #500;
    $display("boot (reset cfg):"); measure(500.0, 400.0);

    // divider only, PLL kept at 500MHz (PLL_UPD = 0)
    upd = 0;
    div2 = 2'b01; dfs(2'b00, 12'd250, 5'd3, 3'd3, 3'd4);   // port0 /2, both gated    -> 250 / 400
    measure(250.0, 400.0);
    div2 = 2'b11; dfs(2'b11, 12'd250, 5'd3, 3'd3, 3'd4);   // both /2, both on 24M    -> 250 / 200
    measure(250.0, 200.0);
    div2 = 2'b00; dfs(2'b01, 12'd250, 5'd3, 3'd3, 3'd4);   // back to /1              -> 500 / 400
    measure(500.0, 400.0);
    upd = 1;

    dfs(2'b00, 12'd399, 5'd4, 3'd3, 3'd5);   // both ports gated,   -> 598.5 / 399
    measure(598.5, 399.0);
    dfs(2'b11, 12'd333, 5'd4, 3'd3, 3'd4);   // both ports on 24M,  -> 499.5 / 399.6
    measure(499.5, 399.6);
    dfs(2'b01, 12'd399, 5'd4, 3'd3, 3'd5);   // port0 24M, port1 gate
    measure(598.5, 399.0);
    dfs(2'b10, 12'd333, 5'd4, 3'd3, 3'd4);   // port0 gate, port1 24M
    measure(499.5, 399.6);

    // LOCK timeout: port0 (24M mode) stays on 24M
    dut.U_PLL_SYS.lock_block = 1;
    dfs(2'b01, 12'd399, 5'd4, 3'd3, 3'd5);
    if (!tmo) begin err = err + 1; $display("ERR: timeout flag"); end
    $display("timeout:"); measure(24.0, 399.0);
    dut.U_PLL_SYS.lock_block = 0;
    dfs(2'b01, 12'd333, 5'd4, 3'd3, 3'd4);   // recover with another DFS
    measure(499.5, 399.6);

    if (WFI_PULSE) begin
        // WFI as 1-cycle pulses (fast -> slow CDC)
        pulse_mode = 1;
        dfs(2'b00, 12'd399, 5'd4, 3'd3, 3'd5);
        measure(598.5, 399.0);
        // a WFI pulse before INT_EN must be ignored: only core1 pulses after arming -> no DFS
        set_cfg(12'd333, 5'd4, 3'd3, 3'd4);
        wfi_pulse(0); #500 int_en = 1; #500 wfi_pulse(1); #5000;
        if (dut.U_PLL_SYS_DFS_CTRL.STATE > 1 || dut.PLL_SYS_FBDIV_REG != 399) begin err = err + 1; $display("ERR: pre-arm WFI pulse not ignored"); end
        wfi_pulse(0); wait (irq); wait (!irq); #500;   // core0 WFI after arming completes it
        if (dut.PLL_SYS_FBDIV_REG != 333) begin err = err + 1; $display("ERR: dfs after pre-arm test"); end
        measure(499.5, 399.6);
        pulse_mode = 0;
    end

    // WFI without INT_EN does not trigger DFS
    set_cfg(12'd399, 5'd4, 3'd3, 3'd5);
    wfi0 = 1; wfi1 = 1; #5000;
    if (busy || dut.PLL_SYS_FBDIV_REG != 333) begin err = err + 1; $display("ERR: dfs without INT_EN"); end
    wfi0 = 0; wfi1 = 0;

    // legacy CFG_EN path still works
    cfg_en = 1; #500 cfg_en = 0; #200;
    if (dut.PLL_SYS_FBDIV_REG != 399) begin err = err + 1; $display("ERR: legacy CFG_EN"); end

    if (err == 0) $display("TEST PASSED"); else $display("TEST FAILED err=%0d", err);
    $finish;
end
initial #5_000_000 begin $display("TIMEOUT"); $finish; end
endmodule
