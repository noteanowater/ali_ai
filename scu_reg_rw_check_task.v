//==============================================================================
// SCU_REG default value / read-write check pattern
//   - Reset values and writable bits derived from SCU_REG.v (RELEASE DATE 2026/11/20)
//   - Usage: put in the same tb file / module as chip_top_task, then call
//           scu_reg_check_task;
//   - Assumption: 2nd arg of es_spi_master.ES_SPI_RD(addr, exp) is the expected value (compared inside)
//
// Group switches (only the safe group runs by default):
//   `define SCU_RW_PHY  : RW test of DDR IO test / DDR PHY JTAG / USB PHY config registers
//   `define SCU_RW_SYS  : RW test of power/clock gate/reset/PLL/divider registers (affects system, use with care)
//   0x30 (CPU_RESET/CHIP_RESET/SYS_RESET) is read-only in all modes, never written
//   Delay chain registers are read-only in all modes, never written (default read in STEP1 only):
//     GMAC : 0x1B8 ~ 0x1CC (CTRL/TEN_S_TIME/DLY_DEFAULT/DLY_TARGET), 0x1E0 ~ 0x1E8 (status)
//     EMMC : 0x230 ~ 0x244 (CTRL/TEN_S_TIME/DLY_DEFAULT/DLY_TARGET), 0x248 ~ 0x250 (status)
//
// Note: expected values of RO fields assume all TB inputs are 0. If the TB ties them to other
//       values (e.g. CHIP_ID, PLL_LOCK, WFI), update the `SCU_RO_xxx macros or the expected values below.
//==============================================================================
`ifndef SCU_BASE
`define SCU_BASE        32'ha000_c000
`endif
`ifndef SCU_RO_CHIP_ID1
`define SCU_RO_CHIP_ID1 32'h0000_0000   // SYS_CHIP_ID_RPT1
`endif
`ifndef SCU_RO_CHIP_ID2
`define SCU_RO_CHIP_ID2 32'h0000_0000   // SYS_CHIP_ID_RPT2
`endif

//------------------------------------------------------------------------------
// Read default value
//------------------------------------------------------------------------------
task scu_rd_chk;
  input [31:0] ofs;
  input [31:0] exp;
begin
  es_spi_master.ES_SPI_RD(`SCU_BASE + ofs, exp);
end
endtask

//------------------------------------------------------------------------------
// RW check: write FFFF_FFFF / 0000_0000 / 5A5A_5A5A / A5A5_A5A5, read back after each write
//   expected = (wdata & msk) | (def & ~msk)   (msk = RW bits, other bits keep default/RO value)
//   finally write the default value back and read to confirm
//------------------------------------------------------------------------------
task scu_rw_chk;
  input [31:0] ofs;
  input [31:0] def;
  input [31:0] msk;
  reg   [31:0] pat;
  integer      i;
begin
  for (i = 0; i < 4; i = i + 1) begin
    case (i)
      0: pat = 32'hFFFF_FFFF;
      1: pat = 32'h0000_0000;
      2: pat = 32'h5A5A_5A5A;
      default: pat = 32'hA5A5_A5A5;
    endcase
    es_spi_master.ES_SPI_WR(`SCU_BASE + ofs, pat);
    es_spi_master.ES_SPI_RD(`SCU_BASE + ofs, (pat & msk) | (def & ~msk));
  end
  es_spi_master.ES_SPI_WR(`SCU_BASE + ofs, def);
  es_spi_master.ES_SPI_RD(`SCU_BASE + ofs, def);
end
endtask

//------------------------------------------------------------------------------
// RO check: write all 1s, read back, value must not change
//------------------------------------------------------------------------------
task scu_ro_chk;
  input [31:0] ofs;
  input [31:0] exp;
begin
  es_spi_master.ES_SPI_WR(`SCU_BASE + ofs, 32'hFFFF_FFFF);
  es_spi_master.ES_SPI_RD(`SCU_BASE + ofs, exp);
end
endtask

//==============================================================================
task scu_reg_check_task;
begin
  //============================================================================
  // STEP1 : read reset default value of all registers
  //============================================================================
  $display("at %t , SCU STEP1 : read default value ---- Begin", $time);
  scu_rd_chk(32'h000, `SCU_RO_CHIP_ID1); // SYS_CHIP_ID_REG1 (RO)
  scu_rd_chk(32'h004, `SCU_RO_CHIP_ID2); // SYS_CHIP_ID_REG2 (RO)
  scu_rd_chk(32'h008, 32'h0000_0000);    // POWER_CTRL
  scu_rd_chk(32'h00C, 32'h0001_0005);    // SYSTEM_MODE_SEL (xip_en[16] defaults to 1)
  scu_rd_chk(32'h010, 32'h0000_0003);    // PLL_GATE
  scu_rd_chk(32'h014, 32'hFFFF_FFFF);    // MAIN_IP_CLK_GATE0
  scu_rd_chk(32'h018, 32'h0000_7FFF);    // MAIN_IP_CLK_GATE1
  scu_rd_chk(32'h01C, 32'h0001_FFFF);    // SUB_IP_CLK_GATE
  scu_rd_chk(32'h020, 32'h0FFF_FFFF);    // AON_IP_CLK_GATE0
  scu_rd_chk(32'h024, 32'h0000_01FF);    // AON_IP_CLK_GATE1
  scu_rd_chk(32'h028, 32'h0000_0000);    // PLL_LOCK (RO, TB dependent)
  scu_rd_chk(32'h030, 32'h0000_0033);    // CPU/CHIP/SYS_RESET
  scu_rd_chk(32'h034, 32'h03FD_07FF);    // MAIN_IP_RESET
  scu_rd_chk(32'h038, 32'h0001_0103);    // SUB_IP_RESET
  scu_rd_chk(32'h03C, 32'h0000_00FF);    // AON_IP_RESET
  scu_rd_chk(32'h040, 32'h0000_0000);    // DDR_RESET
  scu_rd_chk(32'h050, 32'h0000_0701);    // OSC_CTRL ([29:24] RO status)
  scu_rd_chk(32'h054, 32'hA000_0000);    // PLLSYS_CFG0 ([28:0] RO)
  scu_rd_chk(32'h058, 32'h0000_0000);    // PLLSYS_CFG1 (mostly RO)
  scu_rd_chk(32'h05C, 32'h0169_0000);    // PLLSYS_CFG2
  scu_rd_chk(32'h060, 32'h2100_0000);    // PLL_MFP_CFG0
  scu_rd_chk(32'h064, 32'h0052_307D);    // PLL_MFP_CFG1
  scu_rd_chk(32'h068, 32'h0169_0000);    // PLL_MFP_CFG2
  scu_rd_chk(32'h06C, 32'hA100_0000);    // PLL_DDR_CFG0
  scu_rd_chk(32'h070, 32'h0075_3064);    // PLL_DDR_CFG1
  scu_rd_chk(32'h074, 32'h0169_0000);    // PLL_DDR_CFG2
  scu_rd_chk(32'h078, 32'h0000_000C);    // PLL_CLK_SEL / DIV_DDR1
  scu_rd_chk(32'h07C, 32'h0000_0000);    // PLL_CONFIG_EN
  scu_rd_chk(32'h080, 32'h1818_273B);    // DIV_CPU/MFP
  scu_rd_chk(32'h084, 32'h2121_2127);    // DIV_DDR0/TX/TX_BP/RX
  scu_rd_chk(32'h088, 32'h1330_1010);    // IP_CLK_DIV1
  scu_rd_chk(32'h08C, 32'h4001_1111);    // IP_CLK_DIV2
  scu_rd_chk(32'h090, 32'h0000_0002);    // IP_CLK_DIV3
  scu_rd_chk(32'h094, 32'h0000_0000);    // CPU_WFI (RO, TB dependent)
  scu_rd_chk(32'h098, 32'h0000_0000);    // DDR_PHY_JTAG ([8] RO TDO)
  scu_rd_chk(32'h0A0, 32'h0000_0000);    // DDR_VER_PRJ
  scu_rd_chk(32'h0A4, 32'h0000_0000);    // DDR_VER_DATE
  scu_rd_chk(32'h0A8, 32'h0000_0000);    // DDR_IO_TEST0
  scu_rd_chk(32'h0AC, 32'h0000_0000);    // DDR_IO_TEST1
  scu_rd_chk(32'h0B0, 32'h0000_0000);    // DDR_IO_TEST2
  scu_rd_chk(32'h0B4, 32'h0000_0000);    // DDR_IO_TEST3
  scu_rd_chk(32'h0B8, 32'h0000_0000);    // A_DJ/A_ET
  scu_rd_chk(32'h0BC, 32'h0000_0000);    // A_OJ/A_SJ
  scu_rd_chk(32'h0C0, 32'h0000_0000);    // DQ_DJ / A_DT(RO)
  scu_rd_chk(32'h0C4, 32'h0000_0000);    // DQ_ET/DQ_OJ
  scu_rd_chk(32'h0C8, 32'h0000_0000);    // DQ_SJ / DQ_DT(RO)
  scu_rd_chk(32'h0CC, 32'h0200_0000);    // DM/DTO/RET_EN
  scu_rd_chk(32'h0D8, 32'h1E13_4000);    // U3DEV_CFG_0
  scu_rd_chk(32'h0DC, 32'h0027_F71C);    // U3DEV_CFG_1
  scu_rd_chk(32'h0E0, 32'h3920_0000);    // U3DEV_CFG_2
  scu_rd_chk(32'h0E4, 32'h2101_8933);    // U3DEV_CFG_3
  scu_rd_chk(32'h0E8, 32'h0000_0000);    // U3DEV_CFG_4
  scu_rd_chk(32'h0F0, 32'h4734_5508);    // U3DEV_CFG_5
  scu_rd_chk(32'h0F4, 32'h0000_0000);    // U3DEV_LA_TRACE0 (RO)
  scu_rd_chk(32'h0F8, 32'h0000_0000);    // U3DEV_LA_TRACE1 (RO)
  scu_rd_chk(32'h0FC, 32'h1E13_4000);    // U3HOST0_CFG_0
  scu_rd_chk(32'h100, 32'h0027_F71C);    // U3HOST0_CFG_1
  scu_rd_chk(32'h104, 32'h3920_0000);    // U3HOST0_CFG_2
  scu_rd_chk(32'h108, 32'h2101_8933);    // U3HOST0_CFG_3
  scu_rd_chk(32'h10C, 32'h0000_0000);    // U3HOST0_CFG_4
  scu_rd_chk(32'h110, 32'h2134_5508);    // U3HOST0_CFG_5 (clkdiv2=1, commononn=0)
  scu_rd_chk(32'h114, 32'h0000_0000);    // U3HOST0_LA_TRACE0 (RO)
  scu_rd_chk(32'h118, 32'h0000_0000);    // U3HOST0_LA_TRACE1 (RO)
  scu_rd_chk(32'h11C, 32'h0000_0000);    // U3HOST1_LA_TRACE0 (RO)
  scu_rd_chk(32'h120, 32'h0000_0000);    // U3HOST1_LA_TRACE1 (RO)
  scu_rd_chk(32'h124, 32'h0000_0000);    // U3DEV_OBS_SIGNAL (RO)
  scu_rd_chk(32'h128, 32'h0000_0000);    // U3DEV_OBS_CRDATA (RO)
  scu_rd_chk(32'h12C, 32'h0000_0000);    // U3DEV_OBS_CLK (RO)
  scu_rd_chk(32'h130, 32'h0000_0000);    // LVDS_TX0_MUX0
  scu_rd_chk(32'h134, 32'h0000_0000);    // LVDS_TX0_MUX1
  scu_rd_chk(32'h138, 32'h0000_0000);    // LVDS_TX0_MUX2
  scu_rd_chk(32'h13C, 32'h0000_0000);    // LVDS_TX0_MUX3
  scu_rd_chk(32'h140, 32'h0000_0000);    // LVDS_TX0_MUX4
  scu_rd_chk(32'h144, 32'h0000_0000);    // LVDS_TX1_MUX0
  scu_rd_chk(32'h148, 32'h0000_0000);    // LVDS_TX1_MUX1
  scu_rd_chk(32'h14C, 32'h0000_0000);    // LVDS_TX1_MUX2
  scu_rd_chk(32'h150, 32'h0000_0000);    // LVDS_TX1_MUX3
  scu_rd_chk(32'h154, 32'h0000_0000);    // LVDS_TX1_MUX4
  scu_rd_chk(32'h158, 32'h0000_0000);    // LVDS_RX0_MUX0
  scu_rd_chk(32'h15C, 32'h0000_0000);    // LVDS_RX0_MUX1
  scu_rd_chk(32'h160, 32'h0000_0000);    // LVDS_RX0_MUX2
  scu_rd_chk(32'h164, 32'h0000_0000);    // LVDS_RX0_MUX3
  scu_rd_chk(32'h168, 32'h0000_0000);    // LVDS_RX0_MUX4
  scu_rd_chk(32'h16C, 32'h0000_0000);    // LVDS_RX0_MUX5
  scu_rd_chk(32'h170, 32'h0000_0000);    // LVDS_RX0_MUX6
  scu_rd_chk(32'h174, 32'h0000_0000);    // LVDS_RX1_MUX0
  scu_rd_chk(32'h178, 32'h0000_0000);    // LVDS_RX1_MUX1
  scu_rd_chk(32'h17C, 32'h0000_0000);    // LVDS_RX1_MUX2
  scu_rd_chk(32'h180, 32'h0000_0000);    // LVDS_RX1_MUX3
  scu_rd_chk(32'h184, 32'h0000_0000);    // LVDS_RX1_MUX4
  scu_rd_chk(32'h188, 32'h0000_0000);    // LVDS_RX1_MUX5
  scu_rd_chk(32'h18C, 32'h0000_0000);    // LVDS_RX1_MUX6
  scu_rd_chk(32'h190, 32'h0000_0000);    // LVDS_TX0_CTRL ([25:24] RO)
  scu_rd_chk(32'h194, 32'h0000_0000);    // LVDS_TX0_PRBS_SEED
  scu_rd_chk(32'h198, 32'h0000_0000);    // LVDS_TX1_CTRL ([27:26] RO)
  scu_rd_chk(32'h19C, 32'h0000_0000);    // LVDS_TX1_PRBS_SEED
  scu_rd_chk(32'h1A0, 32'h0000_0000);    // LVDS_RX_PRBS_CTRL
  scu_rd_chk(32'h1B4, 32'h0000_0000);    // GMAC_PHY_CTRL ([13:8] RO)
  scu_rd_chk(32'h1B8, 32'h0000_0000);    // GMAC_DELAY_CHAIN_CTRL
  scu_rd_chk(32'h1BC, 32'h0000_0000);    // TEN_S_TIME
  scu_rd_chk(32'h1C0, 32'h0000_0000);    // RGMII_DLY_DEFAULT0
  scu_rd_chk(32'h1C4, 32'h0000_0000);    // RGMII_DLY_DEFAULT1
  scu_rd_chk(32'h1C8, 32'h0000_0000);    // RGMII_TX_DLY_TARGET
  scu_rd_chk(32'h1CC, 32'h0000_0000);    // RGMII_RX_DLY_TARGET
  scu_rd_chk(32'h1E0, 32'h0000_0000);    // DLY_CLK_CYCLE_RPT (RO)
  scu_rd_chk(32'h1E4, 32'h0000_0000);    // RGMII_CAL (RO)
  scu_rd_chk(32'h1E8, 32'h0000_0000);    // RGMII_DLY_ACTUAL (RO)
  scu_rd_chk(32'h1EC, 32'h0208_0208);    // GMAC_DPRAM_CFG
  scu_rd_chk(32'h1F0, 32'h0000_0000);    // BREATHE_REG
  scu_rd_chk(32'h1F4, 32'h1E13_4000);    // U3HOST1_CFG_0
  scu_rd_chk(32'h1F8, 32'h0027_F71C);    // U3HOST1_CFG_1
  scu_rd_chk(32'h1FC, 32'h3920_0000);    // U3HOST1_CFG_2
  scu_rd_chk(32'h200, 32'h2101_8933);    // U3HOST1_CFG_3
  scu_rd_chk(32'h204, 32'h0000_0000);    // U3HOST1_CFG_4
  scu_rd_chk(32'h208, 32'h2134_5508);    // U3HOST1_CFG_5
  scu_rd_chk(32'h20C, 32'h0000_0000);    // U3HOST0_OBS_SIGNAL (RO)
  scu_rd_chk(32'h210, 32'h0000_0000);    // U3HOST0_OBS_CRDATA (RO)
  scu_rd_chk(32'h214, 32'h0000_0000);    // U3HOST0_OBS_CLK (RO)
  scu_rd_chk(32'h218, 32'h0000_0000);    // U3HOST1_OBS_SIGNAL (RO)
  scu_rd_chk(32'h21C, 32'h0000_0000);    // U3HOST1_OBS_CRDATA (RO)
  scu_rd_chk(32'h220, 32'h0000_0000);    // U3HOST1_OBS_CLK (RO)
  scu_rd_chk(32'h230, 32'h0000_0102);    // EMMC_DELAY_CHAIN_CTRL
  scu_rd_chk(32'h234, 32'h0000_0000);    // EMMC_TEN_S_TIME
  scu_rd_chk(32'h238, 32'h0000_0000);    // EMMC_DLY_DEFAULT0
  scu_rd_chk(32'h23C, 32'h0000_0000);    // EMMC_DLY_DEFAULT1
  scu_rd_chk(32'h240, 32'h0000_0000);    // EMMC_CLK_OUT_DLY_TARGET
  scu_rd_chk(32'h244, 32'h0000_0000);    // EMMC_STB_IN_DLY_TARGET
  scu_rd_chk(32'h248, 32'h0000_0000);    // EMMC_DLY_CLK_CYCLE_RPT (RO)
  scu_rd_chk(32'h24C, 32'h0000_0000);    // EMMC_CAL_STAT (RO)
  scu_rd_chk(32'h250, 32'h0000_0000);    // EMMC_DLY_ACTUAL (RO)
  scu_rd_chk(32'h254, 32'h0000_0000);    // AHB_MAIN_BUS_TIMEOUT_CTRL
  scu_rd_chk(32'h258, 32'h0000_0000);    // AHB_MAIN_BUS_TIMEOUT_INT (RO)
  scu_rd_chk(32'h25C, 32'h0000_0000);    // AHB_MAIN_BUS_TIMEOUT_ADDR (RO)
  scu_rd_chk(32'h260, 32'h0000_0000);    // AHB_SUB_BUS_TIMEOUT_CTRL
  scu_rd_chk(32'h264, 32'h0000_0000);    // AHB_SUB_BUS_TIMEOUT_INT (RO)
  scu_rd_chk(32'h268, 32'h0000_0000);    // AHB_SUB_BUS_TIMEOUT_ADDR (RO)
  scu_rd_chk(32'h26C, 32'h0000_0000);    // APB_MAIN_BUS_TIMEOUT_CTRL
  scu_rd_chk(32'h270, 32'h0000_0000);    // APB_MAIN_BUS_TIMEOUT_INT (RO)
  scu_rd_chk(32'h274, 32'h0000_0000);    // APB_MAIN_BUS_TIMEOUT_ADDR (RO)
  scu_rd_chk(32'h278, 32'h0000_0000);    // APB_AON_BUS_TIMEOUT_CTRL
  scu_rd_chk(32'h27C, 32'h0000_0000);    // APB_AON_BUS_TIMEOUT_INT (RO)
  scu_rd_chk(32'h280, 32'h0000_0000);    // APB_AON_BUS_TIMEOUT_ADDR (RO)
  scu_rd_chk(32'h2C0, 32'h0000_0000);    // SW_CFG_REG_0
  scu_rd_chk(32'h2C4, 32'h0000_0000);    // SW_CFG_REG_1
  scu_rd_chk(32'h2C8, 32'h0000_0000);    // SW_CFG_REG_2
  scu_rd_chk(32'h2CC, 32'h0000_0000);    // SW_CFG_REG_3
  scu_rd_chk(32'h2D0, 32'h0000_0000);    // SW_CFG_REG_4
  scu_rd_chk(32'h2D4, 32'h0000_0000);    // SW_CFG_REG_5
  scu_rd_chk(32'h2D8, 32'h0000_0000);    // SW_CFG_REG_6
  scu_rd_chk(32'h2DC, 32'h0000_0000);    // SW_CFG_REG_7
  scu_rd_chk(32'h2E0, 32'h0000_0000);    // SW_CFG_REG_8
  scu_rd_chk(32'h2E4, 32'h0000_0000);    // SW_CFG_REG_9
  scu_rd_chk(32'h2E8, 32'h0000_0000);    // SW_CFG_REG_10
  scu_rd_chk(32'h2EC, 32'h0000_0000);    // SW_CFG_REG_11

  //============================================================================
  // STEP2 : RO register write-protect check (write all 1s, read back unchanged)
  //============================================================================
  $display("at %t , SCU STEP2 : RO register write-protect check ---- Begin", $time);
  scu_ro_chk(32'h000, `SCU_RO_CHIP_ID1);
  scu_ro_chk(32'h004, `SCU_RO_CHIP_ID2);
  scu_ro_chk(32'h028, 32'h0);
  scu_ro_chk(32'h094, 32'h0);
  scu_ro_chk(32'h0F4, 32'h0);
  scu_ro_chk(32'h0F8, 32'h0);
  scu_ro_chk(32'h114, 32'h0);
  scu_ro_chk(32'h118, 32'h0);
  scu_ro_chk(32'h11C, 32'h0);
  scu_ro_chk(32'h120, 32'h0);
  scu_ro_chk(32'h124, 32'h0);
  scu_ro_chk(32'h128, 32'h0);
  scu_ro_chk(32'h12C, 32'h0);
  scu_ro_chk(32'h20C, 32'h0);
  scu_ro_chk(32'h210, 32'h0);
  scu_ro_chk(32'h214, 32'h0);
  scu_ro_chk(32'h218, 32'h0);
  scu_ro_chk(32'h21C, 32'h0);
  scu_ro_chk(32'h220, 32'h0);
  scu_ro_chk(32'h258, 32'h0);
  scu_ro_chk(32'h25C, 32'h0);
  scu_ro_chk(32'h264, 32'h0);
  scu_ro_chk(32'h268, 32'h0);
  scu_ro_chk(32'h270, 32'h0);
  scu_ro_chk(32'h274, 32'h0);
  scu_ro_chk(32'h27C, 32'h0);
  scu_ro_chk(32'h280, 32'h0);

  // Undefined addresses (holes) : write all 1s, read back must be 0
  scu_ro_chk(32'h02C, 32'h0);
  scu_ro_chk(32'h044, 32'h0);
  scu_ro_chk(32'h04C, 32'h0);
  scu_ro_chk(32'h09C, 32'h0);
  scu_ro_chk(32'h0D0, 32'h0);
  scu_ro_chk(32'h0D4, 32'h0);
  scu_ro_chk(32'h0EC, 32'h0);
  scu_ro_chk(32'h1A4, 32'h0);
  scu_ro_chk(32'h1B0, 32'h0);
  scu_ro_chk(32'h1D0, 32'h0);
  scu_ro_chk(32'h1DC, 32'h0);
  scu_ro_chk(32'h224, 32'h0);
  scu_ro_chk(32'h22C, 32'h0);
  scu_ro_chk(32'h284, 32'h0);
  scu_ro_chk(32'h2BC, 32'h0);
  scu_ro_chk(32'h2F0, 32'h0);

  //============================================================================
  // STEP3 : safe group RW check (no effect on system clock/reset/power)
  //           scu_rw_chk(offset, default, rw_mask)
  //============================================================================
  $display("at %t , SCU STEP3 : safe RW register check ---- Begin", $time);
  scu_rw_chk(32'h0A0, 32'h0000_0000, 32'hFFFF_FFFF); // DDR_VER_PRJ
  scu_rw_chk(32'h0A4, 32'h0000_0000, 32'hFFFF_FFFF); // DDR_VER_DATE

  scu_rw_chk(32'h130, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_TX0_MUX0
  scu_rw_chk(32'h134, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_TX0_MUX1
  scu_rw_chk(32'h138, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_TX0_MUX2
  scu_rw_chk(32'h13C, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_TX0_MUX3
  scu_rw_chk(32'h140, 32'h0000_0000, 32'h000F_FFFF); // LVDS_TX0_MUX4
  scu_rw_chk(32'h144, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_TX1_MUX0
  scu_rw_chk(32'h148, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_TX1_MUX1
  scu_rw_chk(32'h14C, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_TX1_MUX2
  scu_rw_chk(32'h150, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_TX1_MUX3
  scu_rw_chk(32'h154, 32'h0000_0000, 32'h000F_FFFF); // LVDS_TX1_MUX4
  scu_rw_chk(32'h158, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_RX0_MUX0
  scu_rw_chk(32'h15C, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_RX0_MUX1
  scu_rw_chk(32'h160, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_RX0_MUX2
  scu_rw_chk(32'h164, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_RX0_MUX3
  scu_rw_chk(32'h168, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_RX0_MUX4
  scu_rw_chk(32'h16C, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_RX0_MUX5
  scu_rw_chk(32'h170, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_RX0_MUX6
  scu_rw_chk(32'h174, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_RX1_MUX0
  scu_rw_chk(32'h178, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_RX1_MUX1
  scu_rw_chk(32'h17C, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_RX1_MUX2
  scu_rw_chk(32'h180, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_RX1_MUX3
  scu_rw_chk(32'h184, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_RX1_MUX4
  scu_rw_chk(32'h188, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_RX1_MUX5
  scu_rw_chk(32'h18C, 32'h0000_0000, 32'h3FFF_FFFF); // LVDS_RX1_MUX6
  scu_rw_chk(32'h190, 32'h0000_0000, 32'h04FF_FFF3); // LVDS_TX0_CTRL
  scu_rw_chk(32'h194, 32'h0000_0000, 32'h7F7F_7F7F); // LVDS_TX0_PRBS_SEED
  scu_rw_chk(32'h198, 32'h0000_0000, 32'h13FF_FFF3); // LVDS_TX1_CTRL
  scu_rw_chk(32'h19C, 32'h0000_0000, 32'h7F7F_7F7F); // LVDS_TX1_PRBS_SEED
  scu_rw_chk(32'h1A0, 32'h0000_0000, 32'h0000_0303); // LVDS_RX_PRBS_CTRL

  scu_rw_chk(32'h1B4, 32'h0000_0000, 32'h0000_003F); // GMAC_PHY_CTRL
  scu_rw_chk(32'h1EC, 32'h0208_0208, 32'h1FFF_1FFF); // GMAC_DPRAM_CFG
  scu_rw_chk(32'h1F0, 32'h0000_0000, 32'h0FFF_FFFF); // BREATHE_REG

  // Bus timeout ctrl: while timeout_en/error_resp_en are set, any other bus access timeout reports an error; default restored afterwards
  scu_rw_chk(32'h254, 32'h0000_0000, 32'h007F_FFFF); // AHB_MAIN_BUS_TIMEOUT_CTRL
  scu_rw_chk(32'h260, 32'h0000_0000, 32'h000F_FFFF); // AHB_SUB_BUS_TIMEOUT_CTRL
  scu_rw_chk(32'h26C, 32'h0000_0000, 32'h003F_FFFF); // APB_MAIN_BUS_TIMEOUT_CTRL
  scu_rw_chk(32'h278, 32'h0000_0000, 32'h003F_FFFF); // APB_AON_BUS_TIMEOUT_CTRL

  scu_rw_chk(32'h2C0, 32'h0000_0000, 32'hFFFF_FFFF); // SW_CFG_REG_0
  scu_rw_chk(32'h2C4, 32'h0000_0000, 32'hFFFF_FFFF); // SW_CFG_REG_1
  scu_rw_chk(32'h2C8, 32'h0000_0000, 32'hFFFF_FFFF); // SW_CFG_REG_2
  scu_rw_chk(32'h2CC, 32'h0000_0000, 32'hFFFF_FFFF); // SW_CFG_REG_3
  scu_rw_chk(32'h2D0, 32'h0000_0000, 32'hFFFF_FFFF); // SW_CFG_REG_4
  scu_rw_chk(32'h2D4, 32'h0000_0000, 32'hFFFF_FFFF); // SW_CFG_REG_5
  scu_rw_chk(32'h2D8, 32'h0000_0000, 32'hFFFF_FFFF); // SW_CFG_REG_6
  scu_rw_chk(32'h2DC, 32'h0000_0000, 32'hFFFF_FFFF); // SW_CFG_REG_7
  scu_rw_chk(32'h2E0, 32'h0000_0000, 32'hFFFF_FFFF); // SW_CFG_REG_8
  scu_rw_chk(32'h2E4, 32'h0000_0000, 32'hFFFF_FFFF); // SW_CFG_REG_9
  scu_rw_chk(32'h2E8, 32'h0000_0000, 32'hFFFF_FFFF); // SW_CFG_REG_10
  scu_rw_chk(32'h2EC, 32'h0000_0000, 32'hFFFF_FFFF); // SW_CFG_REG_11

`ifdef SCU_RW_PHY
  //============================================================================
  // STEP4 : PHY related RW (DDR IO test / DDR PHY JTAG / USB PHY)
  //============================================================================
  $display("at %t , SCU STEP4 : PHY RW register check ---- Begin", $time);
  scu_rw_chk(32'h098, 32'h0000_0000, 32'h0001_000F); // DDR_PHY_JTAG
  scu_rw_chk(32'h0A8, 32'h0000_0000, 32'h1E7F_BDEF); // DDR_IO_TEST0
  scu_rw_chk(32'h0AC, 32'h0000_0000, 32'h1EF3_FCFF); // DDR_IO_TEST1
  scu_rw_chk(32'h0B0, 32'h0000_0000, 32'h3DEF_0FFF); // DDR_IO_TEST2
  scu_rw_chk(32'h0B4, 32'h0000_0000, 32'h007F_9FEF); // DDR_IO_TEST3
  scu_rw_chk(32'h0B8, 32'h0000_0000, 32'hFFFF_FFFF); // A_DJ/A_ET
  scu_rw_chk(32'h0BC, 32'h0000_0000, 32'hFFFF_FFFF); // A_OJ/A_SJ
  scu_rw_chk(32'h0C0, 32'h0000_0000, 32'hFFFF_0000); // DQ_DJ
  scu_rw_chk(32'h0C4, 32'h0000_0000, 32'hFFFF_FFFF); // DQ_ET/DQ_OJ
  scu_rw_chk(32'h0C8, 32'h0000_0000, 32'h0000_FFFF); // DQ_SJ
  scu_rw_chk(32'h0CC, 32'h0200_0000, 32'h0303_FCFF); // DM/DTO/RET_EN

  scu_rw_chk(32'h0D8, 32'h1E13_4000, 32'hFFFF_FFFF); // U3DEV_CFG_0
  scu_rw_chk(32'h0DC, 32'h0027_F71C, 32'hFFFF_FFFF); // U3DEV_CFG_1
  scu_rw_chk(32'h0E0, 32'h3920_0000, 32'hFFFF_FFFF); // U3DEV_CFG_2
  scu_rw_chk(32'h0E4, 32'h2101_8933, 32'h7FFF_FFFF); // U3DEV_CFG_3
  scu_rw_chk(32'h0E8, 32'h0000_0000, 32'h0000_FFFF); // U3DEV_CFG_4
  scu_rw_chk(32'h0F0, 32'h4734_5508, 32'h7FFF_FFFF); // U3DEV_CFG_5
  scu_rw_chk(32'h0FC, 32'h1E13_4000, 32'hFFFF_FFFF); // U3HOST0_CFG_0
  scu_rw_chk(32'h100, 32'h0027_F71C, 32'hFFFF_FFFF); // U3HOST0_CFG_1
  scu_rw_chk(32'h104, 32'h3920_0000, 32'hFFFF_FFFF); // U3HOST0_CFG_2
  scu_rw_chk(32'h108, 32'h2101_8933, 32'h7FFF_FFFF); // U3HOST0_CFG_3
  scu_rw_chk(32'h10C, 32'h0000_0000, 32'h0000_FFFF); // U3HOST0_CFG_4
  scu_rw_chk(32'h110, 32'h2134_5508, 32'h7FFF_FFFF); // U3HOST0_CFG_5
  scu_rw_chk(32'h1F4, 32'h1E13_4000, 32'hFFFF_FFFF); // U3HOST1_CFG_0
  scu_rw_chk(32'h1F8, 32'h0027_F71C, 32'hFFFF_FFFF); // U3HOST1_CFG_1
  scu_rw_chk(32'h1FC, 32'h3920_0000, 32'hFFFF_FFFF); // U3HOST1_CFG_2
  scu_rw_chk(32'h200, 32'h2101_8933, 32'h7FFF_FFFF); // U3HOST1_CFG_3
  scu_rw_chk(32'h204, 32'h0000_0000, 32'h0000_FFFF); // U3HOST1_CFG_4
  scu_rw_chk(32'h208, 32'h2134_5508, 32'h7FFF_FFFF); // U3HOST1_CFG_5
`endif

`ifdef SCU_RW_SYS
  //============================================================================
  // STEP5 : system level RW (power/clock gate/reset/PLL/divider) -- really changes chip behavior
  //   enable only after confirming the SPI2APB -> SCU access path does not go through a gated/reset clock domain
  //   0x30 CPU_RESET/CHIP_RESET/SYS_RESET is not write-tested
  //============================================================================
  $display("at %t , SCU STEP5 : SYS RW register check ---- Begin", $time);
  scu_rw_chk(32'h008, 32'h0000_0000, 32'h01FF_01FF); // POWER_CTRL
  scu_rw_chk(32'h00C, 32'h0001_0005, 32'h0101_7305); // SYSTEM_MODE_SEL
  scu_rw_chk(32'h010, 32'h0000_0003, 32'h0000_0003); // PLL_GATE
  scu_rw_chk(32'h014, 32'hFFFF_FFFF, 32'hFFFF_FFFF); // MAIN_IP_CLK_GATE0
  scu_rw_chk(32'h018, 32'h0000_7FFF, 32'h0000_FFFF); // MAIN_IP_CLK_GATE1
  scu_rw_chk(32'h01C, 32'h0001_FFFF, 32'h0001_FFFF); // SUB_IP_CLK_GATE
  scu_rw_chk(32'h020, 32'h0FFF_FFFF, 32'h0FFF_FFFF); // AON_IP_CLK_GATE0
  scu_rw_chk(32'h024, 32'h0000_01FF, 32'h0000_01FF); // AON_IP_CLK_GATE1
  scu_rw_chk(32'h034, 32'h03FD_07FF, 32'h03FD_07FF); // MAIN_IP_RESET
  scu_rw_chk(32'h038, 32'h0001_0103, 32'h0001_0103); // SUB_IP_RESET
  scu_rw_chk(32'h03C, 32'h0000_00FF, 32'h0000_00FF); // AON_IP_RESET
  scu_rw_chk(32'h040, 32'h0000_0000, 32'h0000_03FF); // DDR_RESET
  scu_rw_chk(32'h050, 32'h0000_0701, 32'h0001_0703); // OSC_CTRL
  scu_rw_chk(32'h054, 32'hA000_0000, 32'hE000_0000); // PLLSYS_CFG0
  scu_rw_chk(32'h058, 32'h0000_0000, 32'h8000_C000); // PLLSYS_CFG1
  scu_rw_chk(32'h05C, 32'h0169_0000, 32'hFFFF_FFFF); // PLLSYS_CFG2
  scu_rw_chk(32'h060, 32'h2100_0000, 32'hFFFF_FFFF); // PLL_MFP_CFG0
  scu_rw_chk(32'h064, 32'h0052_307D, 32'hF777_FFFF); // PLL_MFP_CFG1
  scu_rw_chk(32'h068, 32'h0169_0000, 32'hFFFF_FFFF); // PLL_MFP_CFG2
  scu_rw_chk(32'h06C, 32'hA100_0000, 32'hFFFF_FFFF); // PLL_DDR_CFG0
  scu_rw_chk(32'h070, 32'h0075_3064, 32'hF777_FFFF); // PLL_DDR_CFG1
  scu_rw_chk(32'h074, 32'h0169_0000, 32'hFFFF_FFFF); // PLL_DDR_CFG2
  scu_rw_chk(32'h078, 32'h0000_000C, 32'h0000_73FF); // PLL_CLK_SEL / DIV_DDR1
  scu_rw_chk(32'h07C, 32'h0000_0000, 32'h0000_0007); // PLL_CONFIG_EN
  scu_rw_chk(32'h080, 32'h1818_273B, 32'hFFFF_FFFF); // DIV_CPU/MFP
  scu_rw_chk(32'h084, 32'h2121_2127, 32'hFFFF_FFFF); // DIV_DDR0/TX/TX_BP/RX
  scu_rw_chk(32'h088, 32'h1330_1010, 32'hFFFF_FFFF); // IP_CLK_DIV1
  scu_rw_chk(32'h08C, 32'h4001_1111, 32'hFFFF_FFFF); // IP_CLK_DIV2
  scu_rw_chk(32'h090, 32'h0000_0002, 32'h1F00_0FFF); // IP_CLK_DIV3
`endif

  $display("at %t , SCU register default/RW check ---- End", $time);
end
endtask
