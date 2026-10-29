`timescale 1ns/1ps
//==============================================================================
// 仿真用行为模型 (综合使用工艺库 / IP)
//==============================================================================
module P_CLK_GATE (input CLK, input EN, input SE, output YGCLK);
reg en_l;
always @(*) if (!CLK) en_l = EN | SE;
assign YGCLK = CLK & en_l;
endmodule

module SRCKBUF (input I, output Z);
assign Z = I;
endmodule

module clk_div_256 (input clk, input rstn, input [7:0] div, output clk_o);
assign clk_o = 1'b0;
endmodule

// PLL 模型: Fvco = 24 * NI / M, clko0 = Fvco / (Q0_0+1), clko1 = Fvco / (Q0_1+1)
// pd=1 停振失锁; pd 释放后 LOCK_T 锁定
module INNO_PLL_TOP (
    output [7:0] tbladdr, output reg lock, output testout, output reg clko0, output reg clko1,
    input refclk, input pd, input [4:0] prediv, input [11:0] fbdiv, input [23:0] frac,
    input [2:0] postdiv0_0, postdiv0_1, postdiv1_0, postdiv1_1,
    input [1:0] gvco_bias, input [2:0] cpp_bias, cpi_bias, input dacpd, dsmpd, testen,
    input [1:0] testsel, input disable_sscg, input [3:0] divval, input downspread,
    input [7:0] ext_maxaddr, extwaveval, input sel_extwave, input [2:0] spread);
parameter real LOCK_T = 2000.0;
assign tbladdr = 8'd0; assign testout = 1'b0;
real fvco, h0 = 1.0, h1 = 1.0;
initial begin lock = 0; clko0 = 0; clko1 = 0; end
always @(posedge pd) lock = 0;
always @(negedge pd) begin
    fvco = 24.0 * fbdiv / prediv;
    h0 = 1000.0 / (fvco / (postdiv0_0 + 1)) / 2.0;
    h1 = 1000.0 / (fvco / (postdiv0_1 + 1)) / 2.0;
    #(LOCK_T) if (!pd) lock = 1;
end
always #(h0) if (!pd) clko0 = ~clko0; else clko0 = 0;
always #(h1) if (!pd) clko1 = ~clko1; else clko1 = 0;
endmodule

//==============================================================================
module tb_PLL_SYS_SHELL;
reg osc = 0, rstj = 0;
always #20.833 osc = ~osc;                   // 24MHz, 同时作为 PLL_SYS_CLK

reg  [31:0] cfg0; reg [28:0] cfg1; reg [31:0] cfg2;
reg  cfg_en = 0, int_en = 0, int_clr = 0, wfi0 = 0, wfi1 = 0, test_mode = 0;
reg  [1:0] sel = 0;
wire f600, f400, lock, irq, busy, done, tmo;
wire [1:0] sel_out;
integer err = 0;

PLL_SYS_SHELL #(.DFS_LOCK_TIMEOUT_CYC(2000)) dut (
    .PLL_SYS_F600_CLK(f600), .PLL_SYS_F400_CLK(f400), .PLL_SYS_LOCK(lock),
    .PLL_SYS_TESTOUT(), .PLL_SYS_TBLADDR(), .PLL_SYS_TEST_DIV1_CLK(), .PLL_SYS_TEST_DIV2_CLK(),
    .PLL_SYS_SCAN_DIV1_CLK(), .PLL_SYS_SCAN_DIV2_CLK(),
    .PLL_SYS_CLK_DIV1(8'h3b), .PLL_SYS_CLK_DIV2(8'h27),
    .PLL_SYS_CFG_0(cfg0), .PLL_SYS_CFG_1(cfg1), .PLL_SYS_CFG_2(cfg2), .PLL_SYS_CFG_EN(cfg_en),
    .PLL_SYS_SEL(sel), .PLL_SYS_SEL_OUT(sel_out),
    .PLL_SYS_INT_EN(int_en), .PLL_SYS_INT_CLR(int_clr),
    .CORE_WFI_MODE_0(wfi0), .CORE_WFI_MODE_1(wfi1),
    .PLL_SYS_LOCK_INT(irq), .PLL_SYS_DFS_BUSY(busy), .PLL_SYS_DFS_DONE(done), .PLL_SYS_LOCK_TIMEOUT(tmo),
    .DFT_CPU_SPEED_SEL(1'b0), .MBIST_MODE(1'b0), .TEST_MODE(test_mode),
    .OSC_24M_CLK(osc), .PLL_SYS_CLK(osc), .PLL_DFT_RSTJ(1'b1), .PLL_SYS_RSTJ(rstj));

// 配置 (与 shell 中 CFG 位分配一致): M=4, DIS_SSCG=1, DACPD=1, DSMPD=1(同 PD_REG)
task set_cfg(input [11:0] ni, input [2:0] q0, input [2:0] q1);
begin
    cfg0 = {1'b0, 1'b0, 1'b1, 5'd4, 24'd0};
    cfg1 = {1'b0, 3'd0, 3'd0, q1, q0, 2'd0, 1'b1, 1'b1, ni};
    cfg2 = {1'b0, 3'd0, 4'd1, 3'd3, 3'd2, 2'd1, 8'd0, 8'd0};
end
endtask

// ---------------- 检查 ----------------
// 1) divider 只能在 pd=1 时变化 (DFS 中); 2) pd 释放距 divider 变化 >= 1us
realtime cfg_t = 0;
always @(dut.PLL_SYS_FBDIV or dut.PLL_SYS_POSTDIV0_0 or dut.PLL_SYS_POSTDIV0_1) begin
    cfg_t = $realtime;
    if (rstj && busy && !dut.PLL_SYS_PD_ALL) begin err = err + 1; $display("ERR: divider changed while pd=0"); end
end
always @(negedge dut.PLL_SYS_PD_ALL)
    if (rstj && busy && $realtime - cfg_t < 1000.0) begin err = err + 1; $display("ERR: pd released < 1us after divider set"); end
// 3) DFS 中 PD..WAIT_LOCK 期间不得有 gated 时钟沿
integer edges = 0;
always @(posedge f600) if (dut.U_PLL_SYS_DFS_CTRL.state >= 3 && dut.U_PLL_SYS_DFS_CTRL.state <= 5) edges = edges + 1;
always @(posedge f400) if (dut.U_PLL_SYS_DFS_CTRL.state >= 3 && dut.U_PLL_SYS_DFS_CTRL.state <= 5) edges = edges + 1;

// CPU 模型: 中断唤醒退出 WFI
always @(posedge irq) begin
    #50 wfi0 = 0; wfi1 = 0;
    $display("[%0t] IRQ: NI=%0d Q0_0=%0d Q0_1=%0d sel_out=%0d done=%b tmo=%b",
             $time, dut.PLL_SYS_FBDIV, dut.PLL_SYS_POSTDIV0_0, dut.PLL_SYS_POSTDIV0_1, sel_out, done, tmo);
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

task dfs(input [11:0] ni, input [2:0] q0, input [2:0] q1, input [1:0] s);
begin
    set_cfg(ni, q0, q1); sel = s;            // SW 2: 写 CFG / SEL
    #100 int_en = 1;                         // SW 2: PLL_INT_EN
    #500 wfi0 = 1; #300 wfi1 = 1;            // core WFI
    wait (irq);
    #200 int_clr = 1; int_en = 0; #200 int_clr = 0;
    #300;
    if (irq || busy || !done) begin err = err + 1; $display("ERR: state after dfs"); end
end
endtask

initial begin
    set_cfg(12'd333, 3'd3, 3'd4);
    #300 rstj = 1;
    wait (lock); #500;
    $display("boot (reset cfg 500MHz):"); measure(499.5, 399.6);

    dfs(12'd399, 3'd3, 3'd5, 2'd1);          // -> 600 / 400
    measure(598.5, 399.0);
    if (sel_out != 2'd1) begin err = err + 1; $display("ERR: sel_out"); end

    dfs(12'd333, 3'd3, 3'd4, 2'd2);          // -> 500 / 400
    measure(499.5, 399.6);

    // 未置位 INT_EN 时 WFI 不触发
    set_cfg(12'd399, 3'd3, 3'd5);
    wfi0 = 1; wfi1 = 1; #5000;
    if (busy || dut.PLL_SYS_FBDIV != 333) begin err = err + 1; $display("ERR: dfs without INT_EN"); end
    wfi0 = 0; wfi1 = 0;

    // 原 CFG_EN 路径仍可用
    cfg_en = 1; #500 cfg_en = 0; #200;
    if (dut.PLL_SYS_FBDIV != 399) begin err = err + 1; $display("ERR: legacy CFG_EN"); end

    if (edges) begin err = err + 1; $display("ERR: %0d gated clk edges during pd/lock", edges); end
    if (err == 0) $display("TEST PASSED"); else $display("TEST FAILED err=%0d", err);
    $finish;
end
initial #3_000_000 begin $display("TIMEOUT"); $finish; end
endmodule
