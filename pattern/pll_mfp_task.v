//==========================================================================
// FILE    : pll_mfp_task.v
// PURPOSE : PLL_MFP pattern
//           PLL_MFP has a single setting (1000MHz / 500MHz) in PLL_Config_Calculator.
//           1) default : PLL is on after reset but output gate CLK_EN_REG resets to 0,
//              so enable output clock via SCU, then measure.
//           2) re-lock : power down -> reload same setting -> power on -> lock -> measure,
//              to exercise the SCU -> CFG_EN -> PLL config path.
// USAGE   : `include "pll_mfp_task.v" inside test_chip_top, then call chip_top_task;
//           (frequency is calculated assuming 1ns time unit)
//
// SCU base 32'ha000_c400
//   0x10 [0] mfp_clk_on (PLL_MFP_CLK_EN) , [1] ddr_clk_on keep 1
//   0x28 [0] MFP_PLL_LOCK (RO)
//   0x60 PLL_MFP_CFG_0 : [31]pd(1=on) [30]testen [29]disable_sscg [28:24]M [23:0]frac
//                        NOTE: SCU reset value of pd is 0 (power down) while SHELL resets
//                        to power on. Any CFG_EN pulse must write pd=1 first, otherwise
//                        the PLL is powered down.
//   0x64 PLL_MFP_CFG_1 : [30:28]postdiv1_1 [26:24]postdiv1_0 [22:20]postdiv0_1
//                        [18:16]postdiv0_0 [13]dsmpd [12]dacpd [11:0]fbdiv
//   0x68 PLL_MFP_CFG_2 : fixed 32'h0169_0000 (divval=1 cpi=3 cpp=2 gvco=1, SSC off)
//   0x7C [1] PLL_MFP_CONFIG1_EN : rising edge loads all fields above (incl. CLK_EN)
//
// Frequency table (Fref=24MHz)
//   PLL_MFP : NI=125 M=1 Fvco=3000 clko0 /3 =1000 (MFP1)  clko1 /6 =500 (MFP2)
//             0x60=A100_0000  0x64=0052_307D  0x68=0169_0000
//==========================================================================

`define PLLMFP  test_chip_top.chip_top.core_main.PLL_MFP      // PLL_MFP_SHELL instance

integer pll_mfp_err_cnt;
initial pll_mfp_err_cnt = 0;

//------------------------------------------------------------------
// Frequency measure : measure n cycles of F1000 / F500, compare with expected (tolerance 0.1%)
//------------------------------------------------------------------
task pll_mfp_freq_meas;
    input real f1000_exp;    // MHz
    input real f500_exp;     // MHz
    real    t0, t1, f1000, f500, err;
    integer n;
    begin
        n = 1000;

        // F1000
        repeat (8) @(posedge `PLLMFP.PLL_MFP_F1000_CLK);
        t0 = $realtime;
        repeat (n) @(posedge `PLLMFP.PLL_MFP_F1000_CLK);
        t1 = $realtime;
        f1000 = n * 1000.0 / (t1 - t0);
        err   = (f1000 - f1000_exp) / f1000_exp * 100.0;
        if (err < 0.0) err = -err;
        if (err > 0.1) begin
            pll_mfp_err_cnt = pll_mfp_err_cnt + 1;
            $display("[%0t] PLL_MFP_ERROR : F1000 = %f MHz , expect %f MHz , err %f %%", $realtime, f1000, f1000_exp, err);
        end
        else
            $display("[%0t] PLL_MFP_PASS  : F1000 = %f MHz , expect %f MHz , err %f %%", $realtime, f1000, f1000_exp, err);

        // F500
        repeat (8) @(posedge `PLLMFP.PLL_MFP_F500_CLK);
        t0 = $realtime;
        repeat (n) @(posedge `PLLMFP.PLL_MFP_F500_CLK);
        t1 = $realtime;
        f500 = n * 1000.0 / (t1 - t0);
        err  = (f500 - f500_exp) / f500_exp * 100.0;
        if (err < 0.0) err = -err;
        if (err > 0.1) begin
            pll_mfp_err_cnt = pll_mfp_err_cnt + 1;
            $display("[%0t] PLL_MFP_ERROR : F500 = %f MHz , expect %f MHz , err %f %%", $realtime, f500, f500_exp, err);
        end
        else
            $display("[%0t] PLL_MFP_PASS  : F500 = %f MHz , expect %f MHz , err %f %%", $realtime, f500, f500_exp, err);
    end
endtask

//------------------------------------------------------------------
// pattern
//------------------------------------------------------------------
task chip_top_task;
begin
    //==============================================================
    // PLL_MFP default : wait lock, enable output clock, measure
    //==============================================================
    $display("[%0t] ===== PLL_MFP default (1000 / 500) =====", $realtime);
    a45_io_wait32b (32'ha000_c400, 32'h28 , 32'h0000_0001 , 32'h0000_0001 );   // wait SCU 0x28[0] MFP_PLL_LOCK = 1
    // keep default setting, pd=1 (SCU reset pd=0 must be overwritten), CLK_EN=1
    a45_io_write32b(32'ha000_c400, 32'h68 , 32'h0169_0000 );
    a45_io_write32b(32'ha000_c400, 32'h64 , 32'h0052_307D );
    a45_io_write32b(32'ha000_c400, 32'h60 , 32'hA100_0000 );   // pd=1
    a45_io_write32b(32'ha000_c400, 32'h10 , 32'h0000_0003 );   // MFP CLK_EN=1 , DDR keep 1
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0002 );   // CFG_EN 0->1
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );   // CFG_EN 1->0
    a45_io_wait32b (32'ha000_c400, 32'h28 , 32'h0000_0001 , 32'h0000_0001 );   // still locked
    pll_mfp_freq_meas(1000.0, 500.0);

    //==============================================================
    // PLL_MFP re-lock : NI=125 M=1 , clko0 /3 =1000 , clko1 /6 =500
    //==============================================================
    $display("[%0t] ===== PLL_MFP re-lock (1000 / 500) =====", $realtime);
    // gate off output + PLL power down + write settings
    a45_io_write32b(32'ha000_c400, 32'h10 , 32'h0000_0002 );   // MFP CLK_EN=0 , DDR keep 1
    a45_io_write32b(32'ha000_c400, 32'h68 , 32'h0169_0000 );
    a45_io_write32b(32'ha000_c400, 32'h64 , 32'h0052_307D );
    a45_io_write32b(32'ha000_c400, 32'h60 , 32'h2100_0000 );   // pd=0
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0002 );   // CFG_EN 0->1
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );   // CFG_EN 1->0
    a45_io_wait32b (32'ha000_c400, 32'h28 , 32'h0000_0001 , 32'h0000_0000 );   // wait SCU 0x28[0] MFP_PLL_LOCK = 0
    // PLL power on, wait LOCK
    a45_io_write32b(32'ha000_c400, 32'h60 , 32'hA100_0000 );   // pd=1
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0002 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    a45_io_wait32b (32'ha000_c400, 32'h28 , 32'h0000_0001 , 32'h0000_0001 );   // wait SCU 0x28[0] MFP_PLL_LOCK = 1
    // gate on output
    a45_io_write32b(32'ha000_c400, 32'h10 , 32'h0000_0003 );   // MFP CLK_EN=1
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0002 );
    #1000;
    a45_io_write32b(32'ha000_c400, 32'h7C , 32'h0000_0000 );
    pll_mfp_freq_meas(1000.0, 500.0);

    //==============================================================
    // result
    //==============================================================
    if (pll_mfp_err_cnt == 0) $display("===== PLL_MFP TEST PASS =====");
    else                      $display("===== PLL_MFP TEST FAIL : %0d error(s) =====", pll_mfp_err_cnt);
#2000;
end
endtask
