//==========================================================================
// File   : pll_cfg_conn_check.sv
// Task   : pll_cfg_conn_check
//   Check SCU PLL config registers -> PLL shell connection.
//   (static task : force RHS may not use automatic variables)
//   Each SCU field is forced with all-0, all-1 and walking-1 patterns,
//   the decoded field inside the PLL shell must follow (pd is inverted
//   for *_PWRON_TEMP). Original register values are restored afterwards.
//
// Usage  : `include "pll_cfg_conn_check.sv" inside a TB module, then
//            initial begin
//              wait (reset released);
//              pll_cfg_conn_check(err_cnt);
//            end
//          Run with TEST_MODE = 0 and MBIST_ES_MODE = 0.
//
// Shell version
//   PLL_SYS_SHELL : *_TEMP field names (current version)
//   PLL_MFP/DDR   : define PLL_CONN_NEW_SHELL for the new shells (*_TEMP),
//                   otherwise the old shells (*_DFT) are checked.
//==========================================================================

`define PLL_CONN_SCU  test_chip_top.chip_top.core_aon.apb_subsystem_aon.u_scu
`define PLL_CONN_SYS  test_chip_top.chip_top.core_aon.U_PLL_SYS_CLK_TOP_SHELL.U_PLL_SYS_SHELL
`define PLL_CONN_MFP  test_chip_top.chip_top.core_main.PLL_MFP
`define PLL_CONN_DDR  test_chip_top.chip_top.core_ddr_wrap.u_core_ddr.U_PLL_DDR_CLK_TOP_SHELL.U_PLL_DDR_SHELL

`ifdef PLL_CONN_NEW_SHELL
  `define PLL_CONN_MFP_F(n)   `PLL_CONN_MFP.PLL_MFP_``n``_TEMP
  `define PLL_CONN_DDR_F(n)   `PLL_CONN_DDR.PLL_DDR_``n``_TEMP
  `define PLL_CONN_MFP_PD     `PLL_CONN_MFP.PLL_MFP_PWRON_TEMP
  `define PLL_CONN_DDR_PD     `PLL_CONN_DDR.PLL_DDR_PWRON_TEMP
  `define PLL_CONN_MD_PD_INV  1
`else
  `define PLL_CONN_MFP_F(n)   `PLL_CONN_MFP.PLL_MFP_``n``_DFT
  `define PLL_CONN_DDR_F(n)   `PLL_CONN_DDR.PLL_DDR_``n``_DFT
  `define PLL_CONN_MFP_PD     `PLL_CONN_MFP.PLL_MFP_PD_DFT
  `define PLL_CONN_DDR_PD     `PLL_CONN_DDR.PLL_DDR_PD_DFT
  `define PLL_CONN_MD_PD_INV  0
`endif

// TAG : print name, SRC : SCU register, DST : signal in PLL shell
// W   : width,      INV : 1 = DST is inverted SRC
`define PLL_CONN_CHK(TAG, SRC, DST, W, INV) \
  begin : chk_``TAG \
    logic [W-1:0] saved, pat, exp; \
    int           b; \
    saved = SRC; \
    for (b = -2; b < W; b++) begin \
      if      (b == -2) pat = {W{1'b0}}; \
      else if (b == -1) pat = {W{1'b1}}; \
      else              pat = {{(W-1){1'b0}},1'b1} << b; \
      exp = INV ? ~pat : pat; \
      force SRC = pat; \
      #1; \
      if (DST !== exp) begin \
        err_cnt++; \
        $display("[PLL_CONN][FAIL] %-24s SCU=%h expect=%h got=%h  (%s)", \
                 `"TAG`", pat, exp, DST, `"DST`"); \
      end \
    end \
    force SRC = saved; \
    #1; \
    release SRC; \
    chk_cnt++; \
  end

task pll_cfg_conn_check(output int err_cnt);
  int chk_cnt;
  err_cnt = 0;
  chk_cnt = 0;

  $display("[PLL_CONN] ===== PLL config connection check start @%0t =====", $time);

  //------------------------------------------------------------------------
  // PLL_SYS : 0x54 / 0x58 / 0x5C
  //   divider fields (frac/prediv/fbdiv/dacpd/dsmpd/postdiv) are not used
  //   by PLL_SYS_SHELL (strap), so they are checked at the shell port.
  //------------------------------------------------------------------------
  `PLL_CONN_CHK(SYS_FRAC        , `PLL_CONN_SCU.pllsys_frac_reg        , `PLL_CONN_SYS.PLL_SYS_CFG_0[23:0]       , 24, 0)
  `PLL_CONN_CHK(SYS_PREDIV      , `PLL_CONN_SCU.pllsys_prediv_reg      , `PLL_CONN_SYS.PLL_SYS_CFG_0[28:24]      ,  5, 0)
  `PLL_CONN_CHK(SYS_DIS_SSCG    , `PLL_CONN_SCU.pllsys_disable_sscg_reg, `PLL_CONN_SYS.PLL_SYS_DIS_SSCG_TEMP     ,  1, 0)
  `PLL_CONN_CHK(SYS_TESTEN      , `PLL_CONN_SCU.pllsys_testen_reg      , `PLL_CONN_SYS.PLL_SYS_TESTEN_TEMP       ,  1, 0)
  `PLL_CONN_CHK(SYS_PD          , `PLL_CONN_SCU.pllsys_pd_reg          , `PLL_CONN_SYS.PLL_SYS_PWRON_TEMP        ,  1, 1)
  `PLL_CONN_CHK(SYS_FBDIV       , `PLL_CONN_SCU.pllsys_fbdiv_reg       , `PLL_CONN_SYS.PLL_SYS_CFG_1[11:0]       , 12, 0)
  `PLL_CONN_CHK(SYS_DACPD       , `PLL_CONN_SCU.pllsys_dacpd_reg       , `PLL_CONN_SYS.PLL_SYS_CFG_1[12]         ,  1, 0)
  `PLL_CONN_CHK(SYS_DSMPD       , `PLL_CONN_SCU.pllsys_dsmpd_reg       , `PLL_CONN_SYS.PLL_SYS_CFG_1[13]         ,  1, 0)
  `PLL_CONN_CHK(SYS_TESTSEL     , `PLL_CONN_SCU.pllsys_testsel_reg     , `PLL_CONN_SYS.PLL_SYS_TESTSEL_TEMP      ,  2, 0)
  `PLL_CONN_CHK(SYS_POSTDIV0_0  , `PLL_CONN_SCU.pllsys_postdiv0_0_reg  , `PLL_CONN_SYS.PLL_SYS_CFG_1[18:16]      ,  3, 0)
  `PLL_CONN_CHK(SYS_POSTDIV0_1  , `PLL_CONN_SCU.pllsys_postdiv0_1_reg  , `PLL_CONN_SYS.PLL_SYS_CFG_1[21:19]      ,  3, 0)
  `PLL_CONN_CHK(SYS_POSTDIV1_0  , `PLL_CONN_SCU.pllsys_postdiv1_0_reg  , `PLL_CONN_SYS.PLL_SYS_CFG_1[24:22]      ,  3, 0)
  `PLL_CONN_CHK(SYS_POSTDIV1_1  , `PLL_CONN_SCU.pllsys_postdiv1_1_reg  , `PLL_CONN_SYS.PLL_SYS_CFG_1[27:25]      ,  3, 0)
  `PLL_CONN_CHK(SYS_SEL_EXTWAVE , `PLL_CONN_SCU.pllsys_sel_extwave_reg , `PLL_CONN_SYS.PLL_SYS_SEL_EXTWAVE_TEMP  ,  1, 0)
  `PLL_CONN_CHK(SYS_EXT_MAXADDR , `PLL_CONN_SCU.pllsys_ext_maxaddr_reg , `PLL_CONN_SYS.PLL_SYS_EXT_MAXADDR_TEMP  ,  8, 0)
  `PLL_CONN_CHK(SYS_EXTWAVEVAL  , `PLL_CONN_SCU.pllsys_extwaveval_reg  , `PLL_CONN_SYS.PLL_SYS_EXT_WAVEVAL_TEMP  ,  8, 0)
  `PLL_CONN_CHK(SYS_GVCO_BIAS   , `PLL_CONN_SCU.pllsys_gvco_bias_reg   , `PLL_CONN_SYS.PLL_SYS_GVCO_BIAS_TEMP    ,  2, 0)
  `PLL_CONN_CHK(SYS_CPP_BIAS    , `PLL_CONN_SCU.pllsys_cpp_bias_reg    , `PLL_CONN_SYS.PLL_SYS_CPP_BIAS_TEMP     ,  3, 0)
  `PLL_CONN_CHK(SYS_CPI_BIAS    , `PLL_CONN_SCU.pllsys_cpi_bias_reg    , `PLL_CONN_SYS.PLL_SYS_CPI_BIAS_TEMP     ,  3, 0)
  `PLL_CONN_CHK(SYS_DIVVAL      , `PLL_CONN_SCU.pllsys_divval_reg      , `PLL_CONN_SYS.PLL_SYS_DIVVAL_TEMP       ,  4, 0)
  `PLL_CONN_CHK(SYS_SPREAD      , `PLL_CONN_SCU.pllsys_spread_reg      , `PLL_CONN_SYS.PLL_SYS_SPREAD_TEMP       ,  3, 0)
  `PLL_CONN_CHK(SYS_DOWNSPREAD  , `PLL_CONN_SCU.pllsys_downspread_reg  , `PLL_CONN_SYS.PLL_SYS_DOWNSPREAD_TEMP   ,  1, 0)

  //------------------------------------------------------------------------
  // PLL_MFP : 0x60 / 0x64 / 0x68
  //------------------------------------------------------------------------
  `PLL_CONN_CHK(MFP_FRAC        , `PLL_CONN_SCU.pllmfp_frac_reg        , `PLL_CONN_MFP_F(FRAC)        , 24, 0)
  `PLL_CONN_CHK(MFP_PREDIV      , `PLL_CONN_SCU.pllmfp_prediv_reg      , `PLL_CONN_MFP_F(PREDIV)      ,  5, 0)
  `PLL_CONN_CHK(MFP_DIS_SSCG    , `PLL_CONN_SCU.pllmfp_disable_sscg_reg, `PLL_CONN_MFP_F(DIS_SSCG)    ,  1, 0)
  `PLL_CONN_CHK(MFP_TESTEN      , `PLL_CONN_SCU.pllmfp_testen_reg      , `PLL_CONN_MFP_F(TESTEN)      ,  1, 0)
  `PLL_CONN_CHK(MFP_PD          , `PLL_CONN_SCU.pllmfp_pd_reg          , `PLL_CONN_MFP_PD             ,  1, `PLL_CONN_MD_PD_INV)
  `PLL_CONN_CHK(MFP_FBDIV       , `PLL_CONN_SCU.pllmfp_fbdiv_reg       , `PLL_CONN_MFP_F(FBDIV)       , 12, 0)
  `PLL_CONN_CHK(MFP_DACPD       , `PLL_CONN_SCU.pllmfp_dacpd_reg       , `PLL_CONN_MFP_F(DACPD)       ,  1, 0)
  `PLL_CONN_CHK(MFP_DSMPD       , `PLL_CONN_SCU.pllmfp_dsmpd_reg       , `PLL_CONN_MFP_F(DSMPD)       ,  1, 0)
  `PLL_CONN_CHK(MFP_TESTSEL     , `PLL_CONN_SCU.pllmfp_testsel_reg     , `PLL_CONN_MFP_F(TESTSEL)     ,  2, 0)
  `PLL_CONN_CHK(MFP_POSTDIV0_0  , `PLL_CONN_SCU.pllmfp_postdiv0_0_reg  , `PLL_CONN_MFP_F(POSTDIV0_0)  ,  3, 0)
  `PLL_CONN_CHK(MFP_POSTDIV0_1  , `PLL_CONN_SCU.pllmfp_postdiv0_1_reg  , `PLL_CONN_MFP_F(POSTDIV0_1)  ,  3, 0)
  `PLL_CONN_CHK(MFP_POSTDIV1_0  , `PLL_CONN_SCU.pllmfp_postdiv1_0_reg  , `PLL_CONN_MFP_F(POSTDIV1_0)  ,  3, 0)
  `PLL_CONN_CHK(MFP_POSTDIV1_1  , `PLL_CONN_SCU.pllmfp_postdiv1_1_reg  , `PLL_CONN_MFP_F(POSTDIV1_1)  ,  3, 0)
  `PLL_CONN_CHK(MFP_SEL_EXTWAVE , `PLL_CONN_SCU.pllmfp_sel_extwave_reg , `PLL_CONN_MFP_F(SEL_EXTWAVE) ,  1, 0)
  `PLL_CONN_CHK(MFP_EXT_MAXADDR , `PLL_CONN_SCU.pllmfp_ext_maxaddr_reg , `PLL_CONN_MFP_F(EXT_MAXADDR) ,  8, 0)
  `PLL_CONN_CHK(MFP_EXTWAVEVAL  , `PLL_CONN_SCU.pllmfp_extwaveval_reg  , `PLL_CONN_MFP_F(EXT_WAVEVAL) ,  8, 0)
  `PLL_CONN_CHK(MFP_GVCO_BIAS   , `PLL_CONN_SCU.pllmfp_gvco_bias_reg   , `PLL_CONN_MFP_F(GVCO_BIAS)   ,  2, 0)
  `PLL_CONN_CHK(MFP_CPP_BIAS    , `PLL_CONN_SCU.pllmfp_cpp_bias_reg    , `PLL_CONN_MFP_F(CPP_BIAS)    ,  3, 0)
  `PLL_CONN_CHK(MFP_CPI_BIAS    , `PLL_CONN_SCU.pllmfp_cpi_bias_reg    , `PLL_CONN_MFP_F(CPI_BIAS)    ,  3, 0)
  `PLL_CONN_CHK(MFP_DIVVAL      , `PLL_CONN_SCU.pllmfp_divval_reg      , `PLL_CONN_MFP_F(DIVVAL)      ,  4, 0)
  `PLL_CONN_CHK(MFP_SPREAD      , `PLL_CONN_SCU.pllmfp_spread_reg      , `PLL_CONN_MFP_F(SPREAD)      ,  3, 0)
  `PLL_CONN_CHK(MFP_DOWNSPREAD  , `PLL_CONN_SCU.pllmfp_downspread_reg  , `PLL_CONN_MFP_F(DOWNSPREAD)  ,  1, 0)

  //------------------------------------------------------------------------
  // PLL_DDR : 0x6C / 0x70 / 0x74
  //------------------------------------------------------------------------
  `PLL_CONN_CHK(DDR_FRAC        , `PLL_CONN_SCU.pllddr_frac_reg        , `PLL_CONN_DDR_F(FRAC)        , 24, 0)
  `PLL_CONN_CHK(DDR_PREDIV      , `PLL_CONN_SCU.pllddr_prediv_reg      , `PLL_CONN_DDR_F(PREDIV)      ,  5, 0)
  `PLL_CONN_CHK(DDR_DIS_SSCG    , `PLL_CONN_SCU.pllddr_disable_sscg_reg, `PLL_CONN_DDR_F(DIS_SSCG)    ,  1, 0)
  `PLL_CONN_CHK(DDR_TESTEN      , `PLL_CONN_SCU.pllddr_testen_reg      , `PLL_CONN_DDR_F(TESTEN)      ,  1, 0)
  `PLL_CONN_CHK(DDR_PD          , `PLL_CONN_SCU.pllddr_pd_reg          , `PLL_CONN_DDR_PD             ,  1, `PLL_CONN_MD_PD_INV)
  `PLL_CONN_CHK(DDR_FBDIV       , `PLL_CONN_SCU.pllddr_fbdiv_reg       , `PLL_CONN_DDR_F(FBDIV)       , 12, 0)
  `PLL_CONN_CHK(DDR_DACPD       , `PLL_CONN_SCU.pllddr_dacpd_reg       , `PLL_CONN_DDR_F(DACPD)       ,  1, 0)
  `PLL_CONN_CHK(DDR_DSMPD       , `PLL_CONN_SCU.pllddr_dsmpd_reg       , `PLL_CONN_DDR_F(DSMPD)       ,  1, 0)
  `PLL_CONN_CHK(DDR_TESTSEL     , `PLL_CONN_SCU.pllddr_testsel_reg     , `PLL_CONN_DDR_F(TESTSEL)     ,  2, 0)
  `PLL_CONN_CHK(DDR_POSTDIV0_0  , `PLL_CONN_SCU.pllddr_postdiv0_0_reg  , `PLL_CONN_DDR_F(POSTDIV0_0)  ,  3, 0)
  `PLL_CONN_CHK(DDR_POSTDIV0_1  , `PLL_CONN_SCU.pllddr_postdiv0_1_reg  , `PLL_CONN_DDR_F(POSTDIV0_1)  ,  3, 0)
  `PLL_CONN_CHK(DDR_POSTDIV1_0  , `PLL_CONN_SCU.pllddr_postdiv1_0_reg  , `PLL_CONN_DDR_F(POSTDIV1_0)  ,  3, 0)
  `PLL_CONN_CHK(DDR_POSTDIV1_1  , `PLL_CONN_SCU.pllddr_postdiv1_1_reg  , `PLL_CONN_DDR_F(POSTDIV1_1)  ,  3, 0)
  `PLL_CONN_CHK(DDR_SEL_EXTWAVE , `PLL_CONN_SCU.pllddr_sel_extwave_reg , `PLL_CONN_DDR_F(SEL_EXTWAVE) ,  1, 0)
  `PLL_CONN_CHK(DDR_EXT_MAXADDR , `PLL_CONN_SCU.pllddr_ext_maxaddr_reg , `PLL_CONN_DDR_F(EXT_MAXADDR) ,  8, 0)
  `PLL_CONN_CHK(DDR_EXTWAVEVAL  , `PLL_CONN_SCU.pllddr_extwaveval_reg  , `PLL_CONN_DDR_F(EXT_WAVEVAL) ,  8, 0)
  `PLL_CONN_CHK(DDR_GVCO_BIAS   , `PLL_CONN_SCU.pllddr_gvco_bias_reg   , `PLL_CONN_DDR_F(GVCO_BIAS)   ,  2, 0)
  `PLL_CONN_CHK(DDR_CPP_BIAS    , `PLL_CONN_SCU.pllddr_cpp_bias_reg    , `PLL_CONN_DDR_F(CPP_BIAS)    ,  3, 0)
  `PLL_CONN_CHK(DDR_CPI_BIAS    , `PLL_CONN_SCU.pllddr_cpi_bias_reg    , `PLL_CONN_DDR_F(CPI_BIAS)    ,  3, 0)
  `PLL_CONN_CHK(DDR_DIVVAL      , `PLL_CONN_SCU.pllddr_divval_reg      , `PLL_CONN_DDR_F(DIVVAL)      ,  4, 0)
  `PLL_CONN_CHK(DDR_SPREAD      , `PLL_CONN_SCU.pllddr_spread_reg      , `PLL_CONN_DDR_F(SPREAD)      ,  3, 0)
  `PLL_CONN_CHK(DDR_DOWNSPREAD  , `PLL_CONN_SCU.pllddr_downspread_reg  , `PLL_CONN_DDR_F(DOWNSPREAD)  ,  1, 0)

  if (err_cnt == 0)
    $display("[PLL_CONN] ===== PASS : %0d fields checked, 0 error =====", chk_cnt);
  else
    $display("[PLL_CONN] ===== FAIL : %0d fields checked, %0d error(s) =====", chk_cnt, err_cnt);
endtask
