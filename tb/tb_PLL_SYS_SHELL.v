`timescale 1ns/1ps
//==============================================================================
// 仿真用行为模型 (综合使用工艺库 / IP)
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

// PLL 模型: Fvco = 24 * NI / M, clko0 = Fvco / (Q0_0+1), clko1 = Fvco / (Q0_1+1)
// pd=1 停振失锁; pd 释放后 LOCK_T 锁定 (lock_block=1 时永不锁定)
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
always #20.833 osc = ~osc;                   // 24MHz, 同时作为 PLL_SYS_CLK

reg  [31:0] cfg0; reg [28:0] cfg1; reg [31:0] cfg2;
reg  cfg_en = 0, int_en = 0, wfi0 = 0, wfi1 = 0;
reg  [1:0] mode = 0;
wire f600, f400, lock, irq, busy, done, tmo;
integer err = 0;

PLL_SYS_SHELL #(.DFS_LOCK_TIMEOUT_CYC(2000)) dut (
    .PLL_SYS_F600_CLK(f600), .PLL_SYS_F400_CLK(f400), .PLL_SYS_LOCK(lock),
    .PLL_SYS_TESTOUT(), .PLL_SYS_TBLADDR(), .PLL_SYS_TEST_DIV1_CLK(), .PLL_SYS_TEST_DIV2_CLK(),
    .PLL_SYS_SCAN_DIV1_CLK(), .PLL_SYS_SCAN_DIV2_CLK(),
    .PLL_SYS_CLK_DIV1(8'h3b), .PLL_SYS_CLK_DIV2(8'h27),
    .PLL_SYS_CFG_0(cfg0), .PLL_SYS_CFG_1(cfg1), .PLL_SYS_CFG_2(cfg2), .PLL_SYS_CFG_EN(cfg_en),
    .PLL_SYS_DFS_MODE(mode), .PLL_SYS_INT_EN(int_en),
    .CORE_WFI_MODE_0(wfi0), .CORE_WFI_MODE_1(wfi1),
    .PLL_SYS_LOCK_INT(irq), .PLL_SYS_DFS_BUSY(busy), .PLL_SYS_DFS_DONE(done), .PLL_SYS_LOCK_TIMEOUT(tmo),
    .DFT_CPU_SPEED_SEL(2'b00), .MBIST_ES_MODE(1'b0), .TEST_MODE(1'b0),
    .OSC_24M_CLK(osc), .PLL_SYS_CLK(osc), .PLL_DFT_RSTJ(1'b1), .PLL_SYS_RSTJ(rstj));

// 配置 (与 shell 中 CFG 位分配一致): DIS_SSCG=1, DACPD=1, DSMPD=1(同 PD_REG)
task set_cfg(input [11:0] ni, input [4:0] m, input [2:0] q0, input [2:0] q1);
begin
    cfg0 = {1'b0, 1'b0, 1'b1, m, 24'd0};
    cfg1 = {1'b0, 3'd0, 3'd0, q1, q0, 2'd0, 1'b1, 1'b1, ni};
    cfg2 = {1'b0, 3'd0, 4'd1, 3'd3, 3'd2, 2'd1, 8'd0, 8'd0};
end
endtask

// ---------------- 检查 ----------------
wire [2:0] st = dut.U_PLL_SYS_DFS_CTRL.state;
wire [1:0] ml = dut.U_PLL_SYS_DFS_CTRL.mode_l;
// 1) divider 只在 pd=1 时变化 (DFS 中); 2) pd 释放距 divider 变化 >= 1us
realtime cfg_t = 0;
always @(dut.PLL_SYS_FBDIV_REG or dut.PLL_SYS_PREDIV_REG or dut.PLL_SYS_POSTDIV0_0_REG or dut.PLL_SYS_POSTDIV0_1_REG) begin
    cfg_t = $realtime;
    if (rstj && busy && !dut.PLL_SYS_PD_ALL) begin err = err + 1; $display("ERR: divider changed while pd=0"); end
end
always @(negedge dut.PLL_SYS_PD_ALL)
    if (rstj && busy && $realtime - cfg_t < 1000.0) begin err = err + 1; $display("ERR: pd released < 1us after divider set"); end
// 3) pd 期间: gate 的 port 无时钟沿, 切 24M 的 port 只有 24M 时钟
// 4) 输出无毛刺: 任何高/低电平宽度 >= 0.75ns (最快 PLL 时钟半周期约 0.835ns)
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
// 5) 切 24M 的 port 在 pd 期间必须持续有 24M 时钟
always @(posedge dut.U_PLL_SYS_DFS_CTRL.CLK) if (st == 4 && dut.U_PLL_SYS_DFS_CTRL.state_nxt == 5) begin
    if (ml[0] && l600 == 0) begin err = err + 1; $display("ERR: F600 no 24M clock during pd"); end
    if (ml[1] && l400 == 0) begin err = err + 1; $display("ERR: F400 no 24M clock during pd"); end
end
always @(f600) begin if (rstj && e600 != 0 && $realtime - e600 < 0.75) begin err = err + 1; $display("ERR: F600 glitch @%0t", $time); end e600 = $realtime; end
always @(f400) begin if (rstj && e400 != 0 && $realtime - e400 < 0.75) begin err = err + 1; $display("ERR: F400 glitch @%0t", $time); end e400 = $realtime; end

// CPU 模型: 中断唤醒退出 WFI, ISR 清 PLL_INT_EN
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

task dfs(input [1:0] md, input [11:0] ni, input [4:0] m, input [2:0] q0, input [2:0] q1);
begin
    set_cfg(ni, m, q0, q1); mode = md;       // SW 1.1 / 1.2
    #100 int_en = 1;                         // SW 1.3
    #500 wfi0 = 1; #300 wfi1 = 1;            // SW 2: WFI
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

    dfs(2'b00, 12'd399, 5'd4, 3'd3, 3'd5);   // 两 port gate,  -> 598.5 / 399
    measure(598.5, 399.0);
    dfs(2'b11, 12'd333, 5'd4, 3'd3, 3'd4);   // 两 port 切 24M -> 499.5 / 399.6
    measure(499.5, 399.6);
    dfs(2'b01, 12'd399, 5'd4, 3'd3, 3'd5);   // port0 24M, port1 gate
    measure(598.5, 399.0);
    dfs(2'b10, 12'd333, 5'd4, 3'd3, 3'd4);   // port0 gate, port1 24M
    measure(499.5, 399.6);

    // LOCK 超时: port0 (24M 模式) 停留在 24M
    dut.U_PLL_SYS.lock_block = 1;
    dfs(2'b01, 12'd399, 5'd4, 3'd3, 3'd5);
    if (!tmo) begin err = err + 1; $display("ERR: timeout flag"); end
    $display("timeout:"); measure(24.0, 399.0);
    dut.U_PLL_SYS.lock_block = 0;
    dfs(2'b01, 12'd333, 5'd4, 3'd3, 3'd4);   // 再次调频恢复
    measure(499.5, 399.6);

    // 未置位 INT_EN 时 WFI 不触发
    set_cfg(12'd399, 5'd4, 3'd3, 3'd5);
    wfi0 = 1; wfi1 = 1; #5000;
    if (busy || dut.PLL_SYS_FBDIV_REG != 333) begin err = err + 1; $display("ERR: dfs without INT_EN"); end
    wfi0 = 0; wfi1 = 0;

    // 原 CFG_EN 路径仍可用
    cfg_en = 1; #500 cfg_en = 0; #200;
    if (dut.PLL_SYS_FBDIV_REG != 399) begin err = err + 1; $display("ERR: legacy CFG_EN"); end

    if (err == 0) $display("TEST PASSED"); else $display("TEST FAILED err=%0d", err);
    $finish;
end
initial #5_000_000 begin $display("TIMEOUT"); $finish; end
endmodule
