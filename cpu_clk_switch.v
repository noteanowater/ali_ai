//-----------------------------------------------------------------------------
// cpu_clk_switch
//
// A45 CPU clock source switch: switch controller + glitch-free mux.
//
//   a45_src_clk_sel = 0 : core_a45_div_clk
//   a45_src_clk_sel = 1 : pll_sys_a45_clk
//-----------------------------------------------------------------------------
module cpu_clk_switch #(
    parameter CNT_W = 8
) (
    input                   test_mode,
    input                   test_se,

    input                   clk,               // free running control clock
    input                   rst_n,

    input                   core_a45_div_clk,
    input                   pll_sys_a45_clk,

    input                   a45_src_clk_sel,   // requested clock select
    input                   core0_wfi,
    input                   core1_wfi,

    input      [CNT_W-1:0]  cfg_stable_cnt,
    input                   irq_en,
    input                   irq_clr,

    output                  a45_clk,           // glitch-free muxed CPU clock
    output                  a45_clk_sel_cur,   // select currently applied to the mux
    output                  switch_busy,
    output                  switch_done,
    output                  switch_done_irq
);

cpu_clk_switch_ctrl #(
    .CNT_W (CNT_W)
) u_cpu_clk_switch_ctrl (
    .clk             (clk             ),
    .rst_n           (rst_n           ),
    .clk_sel_req     (a45_src_clk_sel ),
    .core0_wfi       (core0_wfi       ),
    .core1_wfi       (core1_wfi       ),
    .cfg_stable_cnt  (cfg_stable_cnt  ),
    .irq_en          (irq_en          ),
    .irq_clr         (irq_clr         ),
    .clk_sel         (a45_clk_sel_cur ),
    .switch_busy     (switch_busy     ),
    .switch_done     (switch_done     ),
    .switch_done_irq (switch_done_irq )
);

clk_switch_2to1 u_clk_switch_2to1 (
    .test_mode (test_mode        ),
    .test_se   (test_se          ),
    .rst_n     (rst_n            ),
    .clka      (core_a45_div_clk ),
    .clkb      (pll_sys_a45_clk  ),
    .select    (a45_clk_sel_cur  ),
    .sel_clk   (clk              ),
    .clk_o     (a45_clk          )
);

endmodule
