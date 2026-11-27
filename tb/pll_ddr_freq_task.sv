//==========================================================================
// File   : pll_ddr_freq_task.sv
// Task   : pll_ddr_set_freq(ddr_rate)
//   Reconfigure PLL_DDR through SCU (SPI) to run a different frequency.
//
//   SCU registers (base 32'ha000_c000)
//     0x6C : PLL_DDR_CFG_0  [31] PWRON (1 = PLL on, 0 = off) [29] DISABLE_SSCG
//                           [28:24] PREDIV(M)  [23:0] FRAC
//     0x70 : PLL_DDR_CFG_1  [11:0] FBDIV(NI) [12] DACPD [13] DSMPD [15:14] TESTSEL
//                           [18:16] POSTDIV0_0 [22:20] POSTDIV0_1
//                           [26:24] POSTDIV1_0 [30:28] POSTDIV1_1 [31] SEL_EXTWAVE
//     0x74 : PLL_DDR_CFG_2  loop / SSC parameters (keep default 0x0169_0000)
//     0x7C : PLL CFG_EN     rising edge loads the config into the PLL shell
//
//   Sequence (datasheet : dividers must be set while pd=1, release >= 1us later)
//     1. PWRON = 0 (PLL off) + new divider setting, pulse CFG_EN
//     2. wait >= 1us
//     3. PWRON = 1 (PLL on), pulse CFG_EN
//        -> PLL_PD_GEN releases the PLL pd pin after 100 cycles (~4.2us @24MHz)
//     4. wait PLL_DDR_LOCK = 1
//
//   ddr_rate : 1600 / 1500 / 1440 / 1400 / 1333 / 1050  (DDR data rate, MT/s)
//   +------+-----+---+-------+-----------------+-----------------+
//   | rate | NI  | M | Fvco  | clko0 (DDR)     | clko1 (IP)      |
//   +------+-----+---+-------+-----------------+-----------------+
//   | 1600 | 100 | 1 | 2400  | /6     400.000  | /8     300      |
//   | 1500 | 125 | 1 | 3000  | /8     375.000  | /5x/2  300      |
//   | 1440 |  75 | 1 | 1800  | /5     360.000  | /6     300      |
//   | 1400 | 175 | 2 | 2100  | /6     350.000  | /7     300      |
//   | 1333 | 125 | 1 | 3000  | /3x/3  333.333  | /5x/2  300      |
//   | 1050 | 175 | 2 | 2100  | /8     262.500  | /7     300      |
//   +------+-----+---+-------+-----------------+-----------------+
//   All settings are integer mode (FRAC = 0, DACPD = DSMPD = 1).
//==========================================================================

// CFG_EN bit of PLL_DDR in 0x7C (confirm with SCU : 3'b111 pulses all PLLs)
`ifndef PLL_DDR_CFG_EN_BIT
`define PLL_DDR_CFG_EN_BIT   32'h0000_0004
`endif
`ifndef PLL_DDR_LOCK_PATH
`define PLL_DDR_LOCK_PATH    test_chip_top.chip_top.core_ddr_wrap.u_core_ddr.U_PLL_DDR_CLK_TOP_SHELL.U_PLL_DDR_SHELL.PLL_DDR_LOCK
`endif

task pll_ddr_cfg_en_pulse;
begin
    ES_SPI_WR(32'ha000_c07C , `PLL_DDR_CFG_EN_BIT);
    ES_SPI_WR(32'ha000_c07C , 32'h0000_0000);
end
endtask

task pll_ddr_set_freq(input integer ddr_rate);
    reg [31:0] cfg0_off ;   // 0x6C with PWRON = 0 (PLL off)
    reg [31:0] cfg0_on  ;   // 0x6C with PWRON = 1 (PLL on)
    reg [31:0] cfg1     ;   // 0x70
    integer    t        ;
begin
    case (ddr_rate)
      1600 : begin cfg0_off = 32'h2100_0000; cfg0_on = 32'hA100_0000; cfg1 = 32'h0075_3064; end // 400.000 / 300
      1500 : begin cfg0_off = 32'h2100_0000; cfg0_on = 32'hA100_0000; cfg1 = 32'h1047_307D; end // 375.000 / 300
      1440 : begin cfg0_off = 32'h2100_0000; cfg0_on = 32'hA100_0000; cfg1 = 32'h0054_304B; end // 360.000 / 300
      1400 : begin cfg0_off = 32'h2200_0000; cfg0_on = 32'hA200_0000; cfg1 = 32'h0065_30AF; end // 350.000 / 300
      1333 : begin cfg0_off = 32'h2100_0000; cfg0_on = 32'hA100_0000; cfg1 = 32'h1242_307D; end // 333.333 / 300
      1050 : begin cfg0_off = 32'h2200_0000; cfg0_on = 32'hA200_0000; cfg1 = 32'h0067_30AF; end // 262.500 / 300
      default : begin
        $display("[PLL_DDR] ERROR : unsupported ddr_rate %0d", ddr_rate);
        $finish;
      end
    endcase

    $display("[PLL_DDR] @%0t switch to DDR-%0d : 0x6C=%h 0x70=%h", $time, ddr_rate, cfg0_on, cfg1);

    // 1. PLL off + new divider setting
    ES_SPI_WR(32'ha000_c06C , cfg0_off);
    ES_SPI_WR(32'ha000_c070 , cfg1);
    ES_SPI_WR(32'ha000_c074 , 32'h0169_0000);
    pll_ddr_cfg_en_pulse;

    // 2. keep PLL off >= 1us
    #2000;   // 2us (timescale 1ns)

    // 3. PLL on (PLL_PD_GEN releases pd after ~4.2us)
    ES_SPI_WR(32'ha000_c06C , cfg0_on);
    pll_ddr_cfg_en_pulse;

    // 4. wait lock (timeout 100us)
    t = 0;
    while ((`PLL_DDR_LOCK_PATH !== 1'b1) && (t < 100000)) begin
        #10; t = t + 10;
    end
    if (`PLL_DDR_LOCK_PATH === 1'b1)
        $display("[PLL_DDR] @%0t DDR-%0d locked", $time, ddr_rate);
    else
        $display("[PLL_DDR] @%0t ERROR : DDR-%0d lock timeout", $time, ddr_rate);
end
endtask

//--------------------------------------------------------------------------
// example
//--------------------------------------------------------------------------
// task chip_top_task ;
// begin
//     pll_ddr_set_freq(1600);
//     pll_ddr_set_freq(1333);
//     pll_ddr_set_freq(1500);
// end
// endtask
