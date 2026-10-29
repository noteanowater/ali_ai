`timescale 1ns/1ps
// 仿真用 ICG 行为模型 (综合使用工艺库 P1_CLK_GATE)
module P1_CLK_GATE (input CLK, input EN, input SE, output YGCLK);
reg en_l;
always @(*) if (!CLK) en_l = EN | SE;
assign YGCLK = CLK & en_l;
endmodule

module tb_pll_sys_dfs_ctrl;
reg clk_ref = 0, rst_n = 0;
reg pll_int_en = 0, pll_int_clr = 0;
integer err = 0, edges_during_gate = 0;
reg [1:0]  sel = 0;
reg [31:0] cfg = 0;
reg wfi0 = 0, wfi1 = 0;
reg pll_clk = 0, pll_lock = 0;
wire [1:0] sel_o; wire [31:0] cfg_o;
wire pll_pd, clk_g, busy, done, tmo, irq;

always #20.833 clk_ref = ~clk_ref;          // 24MHz

// PLL 模型: pd=1 时停振失锁; pd 释放后 2us 以 divider 对应频率锁定
real half = 5.0;                             // 100MHz
always #(half) if (!pll_pd) pll_clk = ~pll_clk;
realtime pd_rise, cfg_t;
always @(posedge pll_pd) begin pll_lock = 0; pd_rise = $realtime; end
always @(cfg_o) begin
    cfg_t = $realtime;
    if (rst_n && !pll_pd) begin err = err + 1; $display("ERR: divider changed while pd=0"); end
end
always @(negedge pll_pd) begin
    if (rst_n && $realtime - cfg_t < 1000.0) begin err = err + 1; $display("ERR: pd released < 1us after divider set"); end
    #2000;
    half = 1000.0 / (cfg_o[15:0]) / 2.0;     // cfg_o[15:0] = MHz
    if (!pll_pd) pll_lock = 1;
end

pll_sys_dfs_ctrl #(.CFG_W(32), .PLL_PD_CYC(32), .LOCK_TIMEOUT_CYC(1000)) dut (
    .clk_ref(clk_ref), .rst_n(rst_n), .test_mode(1'b0), .test_se(1'b0),
    .pll_sys_sel_i(sel), .pll_cfg_i(cfg),
    .pll_int_en(pll_int_en), .pll_int_clr(pll_int_clr),
    .core_wfi_mode_0(wfi0), .core_wfi_mode_1(wfi1),
    .pll_clk(pll_clk), .pll_lock(pll_lock),
    .pll_sys_sel_o(sel_o), .pll_cfg_o(cfg_o), .pll_pd(pll_pd), .pll_clk_gated(clk_g),
    .pll_dfs_busy(busy), .pll_dfs_done(done), .pll_lock_timeout(tmo), .pll_sys_lock_int(irq));

// 检查: gate 期间不得有时钟 / 配置变化必须发生在 gate 期间
always @(posedge clk_g) if (dut.state >= 3 && dut.state <= 5) edges_during_gate = edges_during_gate + 1;
always @(cfg_o) if (rst_n && dut.gate_en_pll) begin err = err + 1; $display("ERR: cfg changed while clk on"); end
always @(posedge clk_g) if (!dut.gate_en_pll) ; // ICG latch 保证无毛刺

// CPU 模型: 中断唤醒退出 WFI
always @(posedge irq) begin
    #50 wfi0 = 0; wfi1 = 0;
    $display("[%0t] IRQ, wake CPU. sel_o=%0d cfg_o=%0d done=%b tmo=%b", $time, sel_o, cfg_o, done, tmo);
end

task dfs(input [1:0] s, input [31:0] mhz);
begin
    @(posedge clk_ref); sel = s; cfg = mhz;   // step 2.1
    pll_int_en = 1;                           // step 2.2
    #500 wfi0 = 1; #300 wfi1 = 1;             // step 3
    wait (irq);
    #200 pll_int_clr = 1; pll_int_en = 0; #200 pll_int_clr = 0;
    #500;
    if (irq || busy || !done) begin err = err + 1; $display("ERR: state after dfs"); end
end
endtask

integer i; real t0, t1;
initial begin
    #200 rst_n = 1;
    #500;
    dfs(2'd1, 32'd200);
    @(posedge pll_clk) t0 = $realtime; @(posedge pll_clk) t1 = $realtime;
    $display("pll period = %0.2f ns", t1 - t0);
    if (t1 - t0 < 4.9 || t1 - t0 > 5.1) err = err + 1;
    dfs(2'd2, 32'd400);
    // 未置位 PLL_INT_EN 时进入 WFI 不触发调频
    wfi0 = 1; wfi1 = 1; #2000;
    if (busy) begin err = err + 1; $display("ERR: dfs without INT_EN"); end
    wfi0 = 0; wfi1 = 0;
    // 取消: WFI 前撤销 PLL_INT_EN
    pll_int_en = 1; #1000 pll_int_en = 0; #500;
    if (busy) begin err = err + 1; $display("ERR: cancel"); end
    // 超时: 锁死 lock=0
    force pll_lock = 0;
    dfs(2'd0, 32'd100);
    if (!tmo) begin err = err + 1; $display("ERR: timeout flag"); end
    release pll_lock;
    if (edges_during_gate) begin err = err + 1; $display("ERR: %0d clk edges while gated", edges_during_gate); end
    if (err == 0) $display("TEST PASSED"); else $display("TEST FAILED err=%0d", err);
    $finish;
end
initial begin $dumpfile("tb_pll_sys_dfs_ctrl.vcd"); $dumpvars(0, tb_pll_sys_dfs_ctrl); end
initial #2_000_000 begin $display("TIMEOUT"); $finish; end
endmodule
