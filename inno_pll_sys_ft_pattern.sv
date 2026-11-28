//==================================================
// HS100 INNO_PLL_SYS FT pattern
// Ref : HS100_INNO_PLL_SYS_FT_test_plan_20261127_2_1.doc
//   SYS_PLL_TEST_1 : SEL=00, CFG0=E155_5555, CFG1=0043_3053 / 0043_B053
//   SYS_PLL_TEST_2 : SEL=11, CFG0=E120_0000, CFG1=0076_3085 / 0076_B085
//   Each case: strap + PAD_RSTJ -> TESTSEL=00, wait 100us, XTG6 == 1 (lock)
//                              -> TESTSEL=10, XTG6 = 24MHz (23~25MHz)
//==================================================

//--------------------------------------------------
// Pad hierarchy paths -- adjust to your testbench
//--------------------------------------------------
`define PAD_WKUP_GPIO_4   test_chip_top.XWKUP_GPIO_4    // SEL[1]
`define PAD_WKUP_GPIO_3   test_chip_top.XWKUP_GPIO_3    // SEL[0]
`define PAD_SYSRESETN     test_chip_top.XSYSRESETN      // PAD_RSTJ
// ES_MODE4 (INNO_PLL_SYS test mode) strap pins
`define PAD_GPIO_5        test_chip_top.XGPIO_5         // TEST_MODE    = 0
`define PAD_UART0_TXD     test_chip_top.XUART0_TXD      // FUNC_MODE    = 0
`define PAD_IIC0_SCL      test_chip_top.XIIC0_SCL       // WORK_MODE[2] = 1
`define PAD_IIC1_SDA      test_chip_top.XIIC1_SDA       // WORK_MODE[1] = 0
`define PAD_IIC1_SCL      test_chip_top.XIIC1_SCL       // WORK_MODE[0] = 0

//--------------------------------------------------
// Register address
//--------------------------------------------------
localparam logic [31:0] PLL_SYS_CFG_0 = 32'ha000_c054;
localparam logic [31:0] PLL_SYS_CFG_1 = 32'ha000_c058;
localparam logic [31:0] PLL_CFG_EN    = 32'ha000_c07c;

//==================================================
// Clock frequency measurement
//==================================================
integer clk_err_cnt = 0;

task automatic clk_freq_meas(
    const ref logic   clk,              // clock to measure (must be a variable)
    input     real    f_exp,            // expected frequency, MHz
    input     string  name    = "CLK",  // name in log
    input     integer n       = 1000,   // number of cycles to measure
    input     real    tol_pct = 0.1     // allowed error, %
);
    real t0, t1, f_meas, err;
    begin
        repeat (8) @(posedge clk);
        t0 = $realtime;
        repeat (n) @(posedge clk);
        t1 = $realtime;

        if (t1 <= t0) begin
            clk_err_cnt = clk_err_cnt + 1;
            $display("[%0t] CLK_ERROR : %s period is zero", $realtime, name);
            return;
        end

        f_meas = n * 1000.0 / (t1 - t0);   // time unit ns -> MHz
        err    = (f_meas - f_exp) / f_exp * 100.0;
        if (err < 0.0) err = -err;

        if (err > tol_pct) begin
            clk_err_cnt = clk_err_cnt + 1;
            $display("[%0t] CLK_ERROR : %s = %f MHz , expect %f MHz +/- %f %% , err %f %%",
                     $realtime, name, f_meas, f_exp, tol_pct, err);
        end
        else
            $display("[%0t] CLK_PASS  : %s = %f MHz , expect %f MHz +/- %f %% , err %f %%",
                     $realtime, name, f_meas, f_exp, tol_pct, err);
    end
endtask

//==================================================
// Clock / status probes
//==================================================
logic pll_sys_cpu   ;
logic pll_sys_bus   ;
logic pll_ddr_ddr   ;
logic pll_ddr_bus   ;
logic pll_mfp_port0 ;
logic pll_mfp_port1 ;
logic XTAL_XC             ;
logic XTAL_32K_XC         ;
logic POR11C_MAI_POR_OUT  ;
logic POR33C_MAI_POR_OUT  ;
logic POR11C_SUB_POR_OUT  ;
logic POR33C_SUB_POR_OUT  ;
logic POR11C_AON_POR_OUT  ;
logic POR33C_AON_POR_OUT  ;
logic PLL_SYS_TESTOUT     ;
logic PLL_DDR_TESTOUT     ;
logic PLL_MFP_TESTOUT     ;
logic ES_MODE_RPT         ;

// clk_freq_meas uses a ref argument, so nets are copied into variables here
always @(*) pll_sys_cpu   = test_chip_top.chip_top.core_aon.U_PLL_SYS_CLK_TOP_SHELL.U_PLL_SYS_SHELL.PLL_SYS_F600_CLK;
always @(*) pll_sys_bus   = test_chip_top.chip_top.core_aon.U_PLL_SYS_CLK_TOP_SHELL.U_PLL_SYS_SHELL.PLL_SYS_F400_CLK;
always @(*) pll_ddr_ddr   = test_chip_top.chip_top.core_ddr_wrap.u_core_ddr.U_PLL_DDR_CLK_TOP_SHELL.U_PLL_DDR_SHELL.PLL_DDR_F400_CLK;
always @(*) pll_ddr_bus   = test_chip_top.chip_top.core_ddr_wrap.u_core_ddr.U_PLL_DDR_CLK_TOP_SHELL.U_PLL_DDR_SHELL.PLL_DDR_F300_CLK;
always @(*) pll_mfp_port0 = test_chip_top.chip_top.core_main.PLL_MFP.PLL_MFP_F1000_CLK;
always @(*) pll_mfp_port1 = test_chip_top.chip_top.core_main.PLL_MFP.PLL_MFP_F500_CLK;
always @(*) XTAL_XC       = test_chip_top.XTR0;
always @(*) XTAL_32K_XC   = test_chip_top.XTR1;

always @(*) POR11C_MAI_POR_OUT  = test_chip_top.XTR2 ;
always @(*) POR33C_MAI_POR_OUT  = test_chip_top.XTR3 ;
always @(*) POR11C_SUB_POR_OUT  = test_chip_top.XTR4 ;
always @(*) POR33C_SUB_POR_OUT  = test_chip_top.XTR5 ;
always @(*) POR11C_AON_POR_OUT  = test_chip_top.XTR6 ;
always @(*) POR33C_AON_POR_OUT  = test_chip_top.XTR7 ;
always @(*) PLL_SYS_TESTOUT     = test_chip_top.XTG6 ;
always @(*) PLL_DDR_TESTOUT     = test_chip_top.XTG7 ;
always @(*) PLL_MFP_TESTOUT     = test_chip_top.XTRPWM0 ;
always @(*) ES_MODE_RPT         = test_chip_top.XPWM12 ;

//==================================================
// Main
//==================================================
task chip_top_task ;
begin
    clk_err_cnt = 0;

    //==================================================
    // SYS_PLL_TEST_1
    //==================================================
    $display("[%0t] ==================== SYS_PLL_TEST_1 start ====================", $realtime);

    // ES_MODE4 strap
    force `PAD_GPIO_5      = 1'b0;   // TEST_MODE
    force `PAD_UART0_TXD   = 1'b0;   // FUNC_MODE
    force `PAD_IIC0_SCL    = 1'b1;   // WORK_MODE[2]
    force `PAD_IIC1_SDA    = 1'b0;   // WORK_MODE[1]
    force `PAD_IIC1_SCL    = 1'b0;   // WORK_MODE[0]
    // SEL[1:0] = 00
    force `PAD_WKUP_GPIO_4 = 1'b0;   // SEL[1]
    force `PAD_WKUP_GPIO_3 = 1'b0;   // SEL[0]
    // PAD_RSTJ 0 -> 1
    force `PAD_SYSRESETN   = 1'b0;
    #1us;
    force `PAD_SYSRESETN   = 1'b1;
    #10us;

    // TESTEN=1 , TESTSEL=00 (pll lock)
    test_chip_top.u_es_spi_master.ES_SPI_WR(PLL_SYS_CFG_0 , 32'he155_5555);
    test_chip_top.u_es_spi_master.ES_SPI_WR(PLL_SYS_CFG_1 , 32'h0043_3053);
    test_chip_top.u_es_spi_master.ES_SPI_WR(PLL_CFG_EN    , 32'h0000_0007);   // CFG_EN : load
    test_chip_top.u_es_spi_master.ES_SPI_WR(PLL_CFG_EN    , 32'h0000_0000);
    #100us;                                                                   // wait INNO_PLL stable
    if (PLL_SYS_TESTOUT === 1'b1)
        $display("[%0t] LOCK_PASS  : SYS_PLL_TEST_1 XTG6(lock) = 1", $realtime);
    else begin
        clk_err_cnt = clk_err_cnt + 1;
        $display("[%0t] LOCK_ERROR : SYS_PLL_TEST_1 XTG6(lock) = %b , expect 1", $realtime, PLL_SYS_TESTOUT);
    end

    // TESTSEL=10 (pfd clk) , XTG6 = 24MHz (23~25MHz)
    test_chip_top.u_es_spi_master.ES_SPI_WR(PLL_SYS_CFG_1 , 32'h0043_b053);
    test_chip_top.u_es_spi_master.ES_SPI_WR(PLL_CFG_EN    , 32'h0000_0007);   // CFG_EN : load
    test_chip_top.u_es_spi_master.ES_SPI_WR(PLL_CFG_EN    , 32'h0000_0000);
    clk_freq_meas(PLL_SYS_TESTOUT , 24.0 , "SYS_PLL_TEST_1_PFD" , 1000 , 100.0/24.0);

    //==================================================
    // SYS_PLL_TEST_2
    //==================================================
    $display("[%0t] ==================== SYS_PLL_TEST_2 start ====================", $realtime);

    // SEL[1:0] = 11
    force `PAD_WKUP_GPIO_4 = 1'b1;   // SEL[1]
    force `PAD_WKUP_GPIO_3 = 1'b1;   // SEL[0]
    // PAD_RSTJ 0 -> 1
    force `PAD_SYSRESETN   = 1'b0;
    #1us;
    force `PAD_SYSRESETN   = 1'b1;
    #10us;

    // TESTEN=1 , TESTSEL=00 (pll lock)
    test_chip_top.u_es_spi_master.ES_SPI_WR(PLL_SYS_CFG_0 , 32'he120_0000);
    test_chip_top.u_es_spi_master.ES_SPI_WR(PLL_SYS_CFG_1 , 32'h0076_3085);
    test_chip_top.u_es_spi_master.ES_SPI_WR(PLL_CFG_EN    , 32'h0000_0007);   // CFG_EN : load
    test_chip_top.u_es_spi_master.ES_SPI_WR(PLL_CFG_EN    , 32'h0000_0000);
    #100us;                                                                   // wait INNO_PLL stable
    if (PLL_SYS_TESTOUT === 1'b1)
        $display("[%0t] LOCK_PASS  : SYS_PLL_TEST_2 XTG6(lock) = 1", $realtime);
    else begin
        clk_err_cnt = clk_err_cnt + 1;
        $display("[%0t] LOCK_ERROR : SYS_PLL_TEST_2 XTG6(lock) = %b , expect 1", $realtime, PLL_SYS_TESTOUT);
    end

    // TESTSEL=10 (pfd clk) , XTG6 = 24MHz (23~25MHz)
    test_chip_top.u_es_spi_master.ES_SPI_WR(PLL_SYS_CFG_1 , 32'h0076_b085);
    test_chip_top.u_es_spi_master.ES_SPI_WR(PLL_CFG_EN    , 32'h0000_0007);   // CFG_EN : load
    test_chip_top.u_es_spi_master.ES_SPI_WR(PLL_CFG_EN    , 32'h0000_0000);
    clk_freq_meas(PLL_SYS_TESTOUT , 24.0 , "SYS_PLL_TEST_2_PFD" , 1000 , 100.0/24.0);

    //==================================================
    // release strap pins & summary
    //==================================================
    release `PAD_GPIO_5;
    release `PAD_UART0_TXD;
    release `PAD_IIC0_SCL;
    release `PAD_IIC1_SDA;
    release `PAD_IIC1_SCL;
    release `PAD_WKUP_GPIO_4;
    release `PAD_WKUP_GPIO_3;
    release `PAD_SYSRESETN;

    $display("==================================================");
    if (clk_err_cnt == 0)
        $display("[%0t] INNO_PLL_SYS FT : TEST PASS", $realtime);
    else
        $display("[%0t] INNO_PLL_SYS FT : TEST FAIL , error count = %0d", $realtime, clk_err_cnt);
    $display("==================================================");
end
endtask
