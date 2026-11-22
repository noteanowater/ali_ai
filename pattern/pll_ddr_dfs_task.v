//==========================================================================
// FILE    : pll_ddr_dfs_task.v
// PURPOSE : PLL_DDR 调频 pattern
//           默认 DDR-1600 (F400=400MHz / F300=300MHz) 只测量不配置，
//           其余频点通过 SCU 配置后测量。
// USAGE   : 在 test_chip_top 内 `include "pll_ddr_dfs_task.v"，调用 chip_top_task;
//           (时间单位按 1ns 计算频率)
//
// SCU base 32'ha000_c400
//   0x10 [1] ddr_clk_on (PLL_DDR_CLK_EN) , [0] mfp_clk_on 保持 1
//   0x28 [2] DDR_PLL_LOCK (RO)
//   0x6C PLL_DDR_CFG_0 : [31]pd(1=on) [30]testen [29]disable_sscg [28:24]M [23:0]frac
//   0x70 PLL_DDR_CFG_1 : [30:28]postdiv1_1 [26:24]postdiv1_0 [22:20]postdiv0_1
//                        [18:16]postdiv0_0 [13]dsmpd [12]dacpd [11:0]fbdiv
//   0x74 PLL_DDR_CFG_2 : 固定 32'h0169_0000 (divval=1 cpi=3 cpp=2 gvco=1, SSC off)
//   0x7C [2] PLL_DDR_CONFIG2_EN : 上升沿载入以上全部字段 (含 CLK_EN)
//
// 频点表 (Fref=24MHz)
//   DDR-1600 : NI=100 M=1 Fvco=2400 clko0 /6   =400   clko1 /8   =300  0x70=0075_3064 (默认)
//   DDR-1500 : NI=125 M=1 Fvco=3000 clko0 /8   =375   clko1 /5x2 =300  0x70=1047_307D
//   DDR-1440 : NI=75  M=1 Fvco=1800 clko0 /5   =360   clko1 /6   =300  0x70=0054_304B
//   DDR-1400 : NI=175 M=2 Fvco=2100 clko0 /6   =350   clko1 /7   =300  0x70=0065_30AF
//   DDR-1333 : NI=125 M=1 Fvco=3000 clko0 /3x3 =333.3 clko1 /5x2 =300  0x70=1242_307D
//   DDR-1050 : NI=175 M=2 Fvco=2100 clko0 /8   =262.5 clko1 /7   =300  0x70=0067_30AF
//==========================================================================

`define PLLDDR  test_chip_top.chip_top.core_ddr_wrap.u_core_ddr.U_PLL_DDR_CLK_TOP_SHELL.U_PLL_DDR_SHELL

integer pll_ddr_err_cnt;
initial pll_ddr_err_cnt = 0;

//------------------------------------------------------------------
// 频率测量 : 测 F400 / F300 各 n 个周期，与期望值比对 (容差 0.1%)
//------------------------------------------------------------------
task pll_ddr_freq_meas;
    input real f400_exp;     // MHz
    input real f300_exp;     // MHz
    real    t0, t1, f400, f300, err;
    integer n;
    begin
        n = 400;

        // F400
        repeat (8) @(posedge `PLLDDR.PLL_DDR_F400_CLK);
        t0 = $realtime;
        repeat (n) @(posedge `PLLDDR.PLL_DDR_F400_CLK);
        t1 = $realtime;
        f400 = n * 1000.0 / (t1 - t0);
        err  = (f400 - f400_exp) / f400_exp * 100.0;
        if (err < 0.0) err = -err;
        if (err > 0.1) begin
            pll_ddr_err_cnt = pll_ddr_err_cnt + 1;
            $display("[%0t] PLL_DDR_ERROR : F400 = %f MHz , expect %f MHz , err %f %%", $realtime, f400, f400_exp, err);
        end
        else
            $display("[%0t] PLL_DDR_PASS  : F400 = %f MHz , expect %f MHz , err %f %%", $realtime, f400, f400_exp, err);

        // F300
        repeat (8) @(posedge `PLLDDR.PLL_DDR_F300_CLK);
        t0 = $realtime;
        repeat (n) @(posedge `PLLDDR.PLL_DDR_F300_CLK);
        t1 = $realtime;
        f300 = n * 1000.0 / (t1 - t0);
        err  = (f300 - f300_exp) / f300_exp * 100.0;
        if (err < 0.0) err = -err;
        if (err > 0.1) begin
            pll_ddr_err_cnt = pll_ddr_err_cnt + 1;
            $display("[%0t] PLL_DDR_ERROR : F300 = %f MHz , expect %f MHz , err %f %%", $realtime, f300, f300_exp, err);
        end
        else
            $display("[%0t] PLL_DDR_PASS  : F300 = %f MHz , expect %f MHz , err %f %%", $realtime, f300, f300_exp, err);
    end
endtask

//------------------------------------------------------------------
// pattern
//------------------------------------------------------------------
task chip_top_task;
begin
    //==============================================================
    // DDR-1600 默认值 : 只测量
    //==============================================================
    $display("[%0t] ===== DDR-1600 (default) =====", $realtime);
    wait (`PLLDDR.PLL_DDR_LOCK == 1'b1);
    a45_io_read32b (32'ha000_c400, 32'h28 , 32'h0000_0004 , 32'h0000_0004 );   // LOCK
    pll_ddr_freq_meas(400.0, 300.0);

    //==============================================================
    // DDR-1500 : NI=125 M=1 , clko0 /8 =375 , clko1 /5x2 =300
    //==============================================================
    $display("[%0t] ===== DDR-1500 =====", $realtime);
    // 关输出 + PLL 掉电 + 写新参数
    a45_io_write32b(32'ha000_c400, 32'h10 , 32'h0000_0001 );   // CLK_EN=0
    a45_io_write32b(32'ha000_c400, 32'h74 , 32'h0169_0000 );
    a45_io_write32b(32'ha000_c400, 32'h70 , 32'h1047_307D );
    a45_io_write32b(32'ha000_c400, 32'h6C , 32'h2100_0000 );   // pd=0
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );   // CFG_EN 0->1
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );   // CFG_EN 1->0
    #2000;
    // PLL 上电，等 LOCK
    a45_io_write32b(32'ha000_c400, 32'h6C , 32'hA100_0000 );   // pd=1
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    wait (`PLLDDR.PLL_DDR_LOCK == 1'b1);
    a45_io_read32b (32'ha000_c400, 32'h28 , 32'h0000_0004 , 32'h0000_0004 );
    // 打开输出
    a45_io_write32b(32'ha000_c400, 32'h10 , 32'h0000_0003 );   // CLK_EN=1
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    #1000;
    pll_ddr_freq_meas(375.0, 300.0);

    //==============================================================
    // DDR-1440 : NI=75 M=1 , clko0 /5 =360 , clko1 /6 =300
    //==============================================================
    $display("[%0t] ===== DDR-1440 =====", $realtime);
    a45_io_write32b(32'ha000_c400, 32'h10 , 32'h0000_0001 );
    a45_io_write32b(32'ha000_c400, 32'h74 , 32'h0169_0000 );
    a45_io_write32b(32'ha000_c400, 32'h70 , 32'h0054_304B );
    a45_io_write32b(32'ha000_c400, 32'h6C , 32'h2100_0000 );
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    #2000;
    a45_io_write32b(32'ha000_c400, 32'h6C , 32'hA100_0000 );
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    wait (`PLLDDR.PLL_DDR_LOCK == 1'b1);
    a45_io_read32b (32'ha000_c400, 32'h28 , 32'h0000_0004 , 32'h0000_0004 );
    a45_io_write32b(32'ha000_c400, 32'h10 , 32'h0000_0003 );
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    #1000;
    pll_ddr_freq_meas(360.0, 300.0);

    //==============================================================
    // DDR-1400 : NI=175 M=2 , clko0 /6 =350 , clko1 /7 =300
    //==============================================================
    $display("[%0t] ===== DDR-1400 =====", $realtime);
    a45_io_write32b(32'ha000_c400, 32'h10 , 32'h0000_0001 );
    a45_io_write32b(32'ha000_c400, 32'h74 , 32'h0169_0000 );
    a45_io_write32b(32'ha000_c400, 32'h70 , 32'h0065_30AF );
    a45_io_write32b(32'ha000_c400, 32'h6C , 32'h2200_0000 );   // M=2
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    #2000;
    a45_io_write32b(32'ha000_c400, 32'h6C , 32'hA200_0000 );
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    wait (`PLLDDR.PLL_DDR_LOCK == 1'b1);
    a45_io_read32b (32'ha000_c400, 32'h28 , 32'h0000_0004 , 32'h0000_0004 );
    a45_io_write32b(32'ha000_c400, 32'h10 , 32'h0000_0003 );
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    #1000;
    pll_ddr_freq_meas(350.0, 300.0);

    //==============================================================
    // DDR-1333 : NI=125 M=1 , clko0 /3x3 =333.333 , clko1 /5x2 =300
    //==============================================================
    $display("[%0t] ===== DDR-1333 =====", $realtime);
    a45_io_write32b(32'ha000_c400, 32'h10 , 32'h0000_0001 );
    a45_io_write32b(32'ha000_c400, 32'h74 , 32'h0169_0000 );
    a45_io_write32b(32'ha000_c400, 32'h70 , 32'h1242_307D );
    a45_io_write32b(32'ha000_c400, 32'h6C , 32'h2100_0000 );
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    #2000;
    a45_io_write32b(32'ha000_c400, 32'h6C , 32'hA100_0000 );
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    wait (`PLLDDR.PLL_DDR_LOCK == 1'b1);
    a45_io_read32b (32'ha000_c400, 32'h28 , 32'h0000_0004 , 32'h0000_0004 );
    a45_io_write32b(32'ha000_c400, 32'h10 , 32'h0000_0003 );
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    #1000;
    pll_ddr_freq_meas(333.333333, 300.0);

    //==============================================================
    // DDR-1050 : NI=175 M=2 , clko0 /8 =262.5 , clko1 /7 =300
    //==============================================================
    $display("[%0t] ===== DDR-1050 =====", $realtime);
    a45_io_write32b(32'ha000_c400, 32'h10 , 32'h0000_0001 );
    a45_io_write32b(32'ha000_c400, 32'h74 , 32'h0169_0000 );
    a45_io_write32b(32'ha000_c400, 32'h70 , 32'h0067_30AF );
    a45_io_write32b(32'ha000_c400, 32'h6C , 32'h2200_0000 );
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    #2000;
    a45_io_write32b(32'ha000_c400, 32'h6C , 32'hA200_0000 );
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    wait (`PLLDDR.PLL_DDR_LOCK == 1'b1);
    a45_io_read32b (32'ha000_c400, 32'h28 , 32'h0000_0004 , 32'h0000_0004 );
    a45_io_write32b(32'ha000_c400, 32'h10 , 32'h0000_0003 );
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0004 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    #1000;
    pll_ddr_freq_meas(262.5, 300.0);

    //==============================================================
    // 结果
    //==============================================================
    if (pll_ddr_err_cnt == 0) $display("===== PLL_DDR DFS TEST PASS =====");
    else                      $display("===== PLL_DDR DFS TEST FAIL : %0d error(s) =====", pll_ddr_err_cnt);
#2000;
end
endtask
