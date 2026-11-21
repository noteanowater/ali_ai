//==============================================================================
// SCU_REG default value / read-write check pattern (flat version, one access per line)
//   - Reset values and writable bits derived from SCU_REG.v (RELEASE DATE 2026/11/20)
//   - Usage: include in the tb module that instantiates es_spi_master, then call chip_top_task;
//     (this file defines chip_top_task, remove/rename any other chip_top_task in the tb)
//   - ES_SPI_RD(addr, exp) : 2nd arg is the expected value (compared inside)
//
// Group switches (only STEP1/STEP2/STEP3 run by default):
//   `define SCU_RW_PHY  : STEP4, RW test of DDR IO test / DDR PHY JTAG / USB PHY config registers
//   `define SCU_RW_SYS  : STEP5, RW test of power/clock gate/reset/PLL/divider registers (affects system)
//   `define SCU_BYTE_WR : STEP6, byte-enable write test, uses es_spi_master.ES_SPI_WR_BE(addr, data, be)
//                         (STEP6 registers inside `ifdef SCU_RW_PHY / SCU_RW_SYS also need those switches)
//   0x030 (CPU_RESET/CHIP_RESET/SYS_RESET) and delay chain registers
//   (GMAC 0x1B8~0x1CC, 0x1E0~0x1E8 / EMMC 0x230~0x250) are never written, read in STEP1 only.
//
// RW check per register : write FFFF_FFFF / 0000_0000 / 5A5A_5A5A / A5A5_A5A5, read back each,
//                         expected = (wdata & rw_mask) | (default & ~rw_mask), then restore default
// Byte check per register: for be = 0001/0010/0100/1000/0011/1100/0101/1010 :
//                         write default -> byte write ~default with be -> read back,
//                         expected = default ^ (rw_mask & byte_mask(be)), then restore default
//
// Expected values of TB-driven RO fields: 0x028/0x050/0x054/0x058 from rsim readback,
// all other RO fields assume TB input = 0. Edit the expected value on the line directly.
//==============================================================================

task chip_top_task ;
begin
//==============================================================================
// STEP1 : read reset default value of all registers
//==============================================================================
$display("at %t , SCU STEP1 : read default value ---- Begin", $time);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h000 , 32'h0000_0000); // SYS_CHIP_ID_REG1 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h004 , 32'h0000_0000); // SYS_CHIP_ID_REG2 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h0000_0000); // POWER_CTRL
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0001_0005); // SYSTEM_MODE_SEL (xip_en[16] defaults to 1)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0003); // PLL_GATE
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF); // MAIN_IP_CLK_GATE0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_7FFF); // MAIN_IP_CLK_GATE1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0001_FFFF); // SUB_IP_CLK_GATE
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF); // AON_IP_CLK_GATE0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_01FF); // AON_IP_CLK_GATE1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h028 , 32'h0000_0007); // PLL_LOCK (RO, TB dependent)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h030 , 32'h0000_0033); // CPU/CHIP/SYS_RESET
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h03FD_07FF); // MAIN_IP_RESET
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0001_0103); // SUB_IP_RESET
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_00FF); // AON_IP_RESET
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_0000); // DDR_RESET
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3200_0701); // OSC_CTRL ([29:24] RO status)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'hA155_5555); // PLLSYS_CFG0 ([28:0] RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h0043_0053); // PLLSYS_CFG1 (mostly RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'h0169_0000); // PLLSYS_CFG2
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'h2100_0000); // PLL_MFP_CFG0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'h0052_307D); // PLL_MFP_CFG1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'h0169_0000); // PLL_MFP_CFG2
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'hA100_0000); // PLL_DDR_CFG0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'h0075_3064); // PLL_DDR_CFG1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'h0169_0000); // PLL_DDR_CFG2
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_000C); // PLL_CLK_SEL / DIV_DDR1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0000); // PLL_CONFIG_EN
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'h1818_273B); // DIV_CPU/MFP
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'h2121_2127); // DIV_DDR0/TX/TX_BP/RX
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'h1330_1010); // IP_CLK_DIV1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'h4001_1111); // IP_CLK_DIV2
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h0000_0002); // IP_CLK_DIV3
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h094 , 32'h0000_0000); // CPU_WFI (RO, TB dependent)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0000_0000); // DDR_PHY_JTAG ([8] RO TDO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'h0000_0000); // DDR_VER_PRJ
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'h0000_0000); // DDR_VER_DATE
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h0000_0000); // DDR_IO_TEST0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h0000_0000); // DDR_IO_TEST1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h0000_0000); // DDR_IO_TEST2
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h0000_0000); // DDR_IO_TEST3
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'h0000_0000); // A_DJ/A_ET
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'h0000_0000); // A_OJ/A_SJ
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'h0000_0000); // DQ_DJ / A_DT(RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'h0000_0000); // DQ_ET/DQ_OJ
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_0000); // DQ_SJ / DQ_DT(RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0200_0000); // DM/DTO/RET_EN
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'h1E13_4000); // U3DEV_CFG_0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'h0027_F71C); // U3DEV_CFG_1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'h3920_0000); // U3DEV_CFG_2
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h2101_8933); // U3DEV_CFG_3
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_0000); // U3DEV_CFG_4
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h4734_5508); // U3DEV_CFG_5
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F4 , 32'h0000_0000); // U3DEV_LA_TRACE0 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F8 , 32'h0000_0000); // U3DEV_LA_TRACE1 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'h1E13_4000); // U3HOST0_CFG_0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'h0027_F71C); // U3HOST0_CFG_1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'h3920_0000); // U3HOST0_CFG_2
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h2101_8933); // U3HOST0_CFG_3
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_0000); // U3HOST0_CFG_4
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h2134_5508); // U3HOST0_CFG_5 (clkdiv2=1, commononn=0)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h114 , 32'h0000_0000); // U3HOST0_LA_TRACE0 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h118 , 32'h0000_0000); // U3HOST0_LA_TRACE1 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h11C , 32'h0000_0000); // U3HOST1_LA_TRACE0 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h120 , 32'h0000_0000); // U3HOST1_LA_TRACE1 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h124 , 32'h0000_0000); // U3DEV_OBS_SIGNAL (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h128 , 32'h0000_0000); // U3DEV_OBS_CRDATA (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h12C , 32'h0000_0000); // U3DEV_OBS_CLK (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h0000_0000); // LVDS_TX0_MUX0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h0000_0000); // LVDS_TX0_MUX1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h0000_0000); // LVDS_TX0_MUX2
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h0000_0000); // LVDS_TX0_MUX3
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h0000_0000); // LVDS_TX0_MUX4
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h0000_0000); // LVDS_TX1_MUX0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h0000_0000); // LVDS_TX1_MUX1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h0000_0000); // LVDS_TX1_MUX2
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h0000_0000); // LVDS_TX1_MUX3
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h0000_0000); // LVDS_TX1_MUX4
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h0000_0000); // LVDS_RX0_MUX0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h0000_0000); // LVDS_RX0_MUX1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h0000_0000); // LVDS_RX0_MUX2
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h0000_0000); // LVDS_RX0_MUX3
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h0000_0000); // LVDS_RX0_MUX4
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h0000_0000); // LVDS_RX0_MUX5
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h0000_0000); // LVDS_RX0_MUX6
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h0000_0000); // LVDS_RX1_MUX0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h0000_0000); // LVDS_RX1_MUX1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h0000_0000); // LVDS_RX1_MUX2
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h0000_0000); // LVDS_RX1_MUX3
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h0000_0000); // LVDS_RX1_MUX4
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h0000_0000); // LVDS_RX1_MUX5
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h0000_0000); // LVDS_RX1_MUX6
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h0000_0000); // LVDS_TX0_CTRL ([25:24] RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h0000_0000); // LVDS_TX0_PRBS_SEED
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h0000_0000); // LVDS_TX1_CTRL ([27:26] RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h0000_0000); // LVDS_TX1_PRBS_SEED
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0000); // LVDS_RX_PRBS_CTRL
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_0000); // GMAC_PHY_CTRL ([13:8] RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B8 , 32'h0000_0000); // GMAC_DELAY_CHAIN_CTRL
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1BC , 32'h0000_0000); // TEN_S_TIME
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1C0 , 32'h0000_0000); // RGMII_DLY_DEFAULT0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1C4 , 32'h0000_0000); // RGMII_DLY_DEFAULT1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1C8 , 32'h0000_0000); // RGMII_TX_DLY_TARGET
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1CC , 32'h0000_0000); // RGMII_RX_DLY_TARGET
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1E0 , 32'h0000_0000); // DLY_CLK_CYCLE_RPT (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1E4 , 32'h0000_0000); // RGMII_CAL (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1E8 , 32'h0000_0000); // RGMII_DLY_ACTUAL (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h0208_0208); // GMAC_DPRAM_CFG
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h0000_0000); // BREATHE_REG
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'h1E13_4000); // U3HOST1_CFG_0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'h0027_F71C); // U3HOST1_CFG_1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'h3920_0000); // U3HOST1_CFG_2
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h2101_8933); // U3HOST1_CFG_3
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_0000); // U3HOST1_CFG_4
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h2134_5508); // U3HOST1_CFG_5
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h20C , 32'h0000_0000); // U3HOST0_OBS_SIGNAL (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h210 , 32'h0000_0000); // U3HOST0_OBS_CRDATA (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h214 , 32'h0000_0000); // U3HOST0_OBS_CLK (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h218 , 32'h0000_0000); // U3HOST1_OBS_SIGNAL (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h21C , 32'h0000_0000); // U3HOST1_OBS_CRDATA (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h220 , 32'h0000_0000); // U3HOST1_OBS_CLK (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h230 , 32'h0000_0102); // EMMC_DELAY_CHAIN_CTRL
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h234 , 32'h0000_0000); // EMMC_TEN_S_TIME
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h238 , 32'h0000_0000); // EMMC_DLY_DEFAULT0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h23C , 32'h0000_0000); // EMMC_DLY_DEFAULT1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h240 , 32'h0000_0000); // EMMC_CLK_OUT_DLY_TARGET
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h244 , 32'h0000_0000); // EMMC_STB_IN_DLY_TARGET
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h248 , 32'h0000_0000); // EMMC_DLY_CLK_CYCLE_RPT (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h24C , 32'h0000_0000); // EMMC_CAL_STAT (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h250 , 32'h0000_0000); // EMMC_DLY_ACTUAL (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h0000_0000); // AHB_MAIN_BUS_TIMEOUT_CTRL
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h258 , 32'h0000_0000); // AHB_MAIN_BUS_TIMEOUT_INT (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h25C , 32'h0000_0000); // AHB_MAIN_BUS_TIMEOUT_ADDR (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h0000_0000); // AHB_SUB_BUS_TIMEOUT_CTRL
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h264 , 32'h0000_0000); // AHB_SUB_BUS_TIMEOUT_INT (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h268 , 32'h0000_0000); // AHB_SUB_BUS_TIMEOUT_ADDR (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h0000_0000); // APB_MAIN_BUS_TIMEOUT_CTRL
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h270 , 32'h0000_0000); // APB_MAIN_BUS_TIMEOUT_INT (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h274 , 32'h0000_0000); // APB_MAIN_BUS_TIMEOUT_ADDR (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h0000_0000); // APB_AON_BUS_TIMEOUT_CTRL
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h27C , 32'h0000_0000); // APB_AON_BUS_TIMEOUT_INT (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h280 , 32'h0000_0000); // APB_AON_BUS_TIMEOUT_ADDR (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'h0000_0000); // SW_CFG_REG_0
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'h0000_0000); // SW_CFG_REG_1
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'h0000_0000); // SW_CFG_REG_2
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'h0000_0000); // SW_CFG_REG_3
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'h0000_0000); // SW_CFG_REG_4
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'h0000_0000); // SW_CFG_REG_5
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'h0000_0000); // SW_CFG_REG_6
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'h0000_0000); // SW_CFG_REG_7
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'h0000_0000); // SW_CFG_REG_8
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'h0000_0000); // SW_CFG_REG_9
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'h0000_0000); // SW_CFG_REG_10
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'h0000_0000); // SW_CFG_REG_11

//==============================================================================
// STEP2 : RO register write-protect check (write all 1s, read back unchanged)
//         undefined addresses (holes) must read back 0
//==============================================================================
$display("at %t , SCU STEP2 : RO register write-protect check ---- Begin", $time);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h000 , 32'hFFFF_FFFF); // SYS_CHIP_ID_REG1 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h000 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h004 , 32'hFFFF_FFFF); // SYS_CHIP_ID_REG2 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h004 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h028 , 32'hFFFF_FFFF); // PLL_LOCK (RO, TB dependent)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h028 , 32'h0000_0007);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h094 , 32'hFFFF_FFFF); // CPU_WFI (RO, TB dependent)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h094 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F4 , 32'hFFFF_FFFF); // U3DEV_LA_TRACE0 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F8 , 32'hFFFF_FFFF); // U3DEV_LA_TRACE1 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h114 , 32'hFFFF_FFFF); // U3HOST0_LA_TRACE0 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h114 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h118 , 32'hFFFF_FFFF); // U3HOST0_LA_TRACE1 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h118 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h11C , 32'hFFFF_FFFF); // U3HOST1_LA_TRACE0 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h11C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h120 , 32'hFFFF_FFFF); // U3HOST1_LA_TRACE1 (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h120 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h124 , 32'hFFFF_FFFF); // U3DEV_OBS_SIGNAL (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h124 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h128 , 32'hFFFF_FFFF); // U3DEV_OBS_CRDATA (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h128 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h12C , 32'hFFFF_FFFF); // U3DEV_OBS_CLK (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h12C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h20C , 32'hFFFF_FFFF); // U3HOST0_OBS_SIGNAL (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h20C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h210 , 32'hFFFF_FFFF); // U3HOST0_OBS_CRDATA (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h210 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h214 , 32'hFFFF_FFFF); // U3HOST0_OBS_CLK (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h214 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h218 , 32'hFFFF_FFFF); // U3HOST1_OBS_SIGNAL (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h218 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h21C , 32'hFFFF_FFFF); // U3HOST1_OBS_CRDATA (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h21C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h220 , 32'hFFFF_FFFF); // U3HOST1_OBS_CLK (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h220 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h258 , 32'hFFFF_FFFF); // AHB_MAIN_BUS_TIMEOUT_INT (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h258 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h25C , 32'hFFFF_FFFF); // AHB_MAIN_BUS_TIMEOUT_ADDR (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h25C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h264 , 32'hFFFF_FFFF); // AHB_SUB_BUS_TIMEOUT_INT (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h264 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h268 , 32'hFFFF_FFFF); // AHB_SUB_BUS_TIMEOUT_ADDR (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h268 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h270 , 32'hFFFF_FFFF); // APB_MAIN_BUS_TIMEOUT_INT (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h270 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h274 , 32'hFFFF_FFFF); // APB_MAIN_BUS_TIMEOUT_ADDR (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h274 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h27C , 32'hFFFF_FFFF); // APB_AON_BUS_TIMEOUT_INT (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h27C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h280 , 32'hFFFF_FFFF); // APB_AON_BUS_TIMEOUT_ADDR (RO)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h280 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h02C , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h02C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h044 , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h044 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h04C , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h04C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h09C , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h09C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D0 , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D4 , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0EC , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0EC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A4 , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B0 , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1D0 , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1DC , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1DC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h224 , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h224 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h22C , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h22C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h284 , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h284 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2BC , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2BC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2F0 , 32'hFFFF_FFFF); // undefined address (hole)
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2F0 , 32'h0000_0000);

//==============================================================================
// STEP3 : safe group RW check (no effect on system clock/reset/power)
//   bus timeout ctrl (0x254/0x260/0x26C/0x278): timeout_en/error_resp_en are set
//   for a short time, default restored afterwards
//==============================================================================
$display("at %t , SCU STEP3 : safe RW register check ---- Begin", $time);
// 0x0A0 DDR_VER_PRJ : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);

// 0x0A4 DDR_VER_DATE : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);

// 0x130 LVDS_TX0_MUX0 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h0000_0000);

// 0x134 LVDS_TX0_MUX1 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h0000_0000);

// 0x138 LVDS_TX0_MUX2 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h0000_0000);

// 0x13C LVDS_TX0_MUX3 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h0000_0000);

// 0x140 LVDS_TX0_MUX4 : default = 32'h0000_0000, rw_mask = 32'h000F_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h000F_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h000A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h0005_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h0000_0000);

// 0x144 LVDS_TX1_MUX0 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h0000_0000);

// 0x148 LVDS_TX1_MUX1 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h0000_0000);

// 0x14C LVDS_TX1_MUX2 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h0000_0000);

// 0x150 LVDS_TX1_MUX3 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h0000_0000);

// 0x154 LVDS_TX1_MUX4 : default = 32'h0000_0000, rw_mask = 32'h000F_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h000F_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h000A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h0005_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h0000_0000);

// 0x158 LVDS_RX0_MUX0 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h0000_0000);

// 0x15C LVDS_RX0_MUX1 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h0000_0000);

// 0x160 LVDS_RX0_MUX2 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h0000_0000);

// 0x164 LVDS_RX0_MUX3 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h0000_0000);

// 0x168 LVDS_RX0_MUX4 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h0000_0000);

// 0x16C LVDS_RX0_MUX5 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h0000_0000);

// 0x170 LVDS_RX0_MUX6 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h0000_0000);

// 0x174 LVDS_RX1_MUX0 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h0000_0000);

// 0x178 LVDS_RX1_MUX1 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h0000_0000);

// 0x17C LVDS_RX1_MUX2 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h0000_0000);

// 0x180 LVDS_RX1_MUX3 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h0000_0000);

// 0x184 LVDS_RX1_MUX4 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h0000_0000);

// 0x188 LVDS_RX1_MUX5 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h0000_0000);

// 0x18C LVDS_RX1_MUX6 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h3FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h1A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h0000_0000);

// 0x190 LVDS_TX0_CTRL : default = 32'h0000_0000, rw_mask = 32'h04FF_FFF3
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h04FF_FFF3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h005A_5A52);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h04A5_A5A1);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h0000_0000);

// 0x194 LVDS_TX0_PRBS_SEED : default = 32'h0000_0000, rw_mask = 32'h7F7F_7F7F
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h7F7F_7F7F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h2525_2525);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h0000_0000);

// 0x198 LVDS_TX1_CTRL : default = 32'h0000_0000, rw_mask = 32'h13FF_FFF3
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h13FF_FFF3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h125A_5A52);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h01A5_A5A1);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h0000_0000);

// 0x19C LVDS_TX1_PRBS_SEED : default = 32'h0000_0000, rw_mask = 32'h7F7F_7F7F
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h7F7F_7F7F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h2525_2525);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h0000_0000);

// 0x1A0 LVDS_RX_PRBS_CTRL : default = 32'h0000_0000, rw_mask = 32'h0000_0303
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0303);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0202);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0101);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);

// 0x1B4 GMAC_PHY_CTRL : default = 32'h0000_0000, rw_mask = 32'h0000_003F
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_003F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_001A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_0025);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);

// 0x1EC GMAC_DPRAM_CFG : default = 32'h0208_0208, rw_mask = 32'h1FFF_1FFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h1FFF_1FFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h1A5A_1A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h05A5_05A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'h0208_0208);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h0208_0208);

// 0x1F0 BREATHE_REG : default = 32'h0000_0000, rw_mask = 32'h0FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h0FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h0A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h05A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);

// 0x254 AHB_MAIN_BUS_TIMEOUT_CTRL : default = 32'h0000_0000, rw_mask = 32'h007F_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h007F_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h005A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h0025_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h0000_0000);

// 0x260 AHB_SUB_BUS_TIMEOUT_CTRL : default = 32'h0000_0000, rw_mask = 32'h000F_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h000F_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h000A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h0005_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h0000_0000);

// 0x26C APB_MAIN_BUS_TIMEOUT_CTRL : default = 32'h0000_0000, rw_mask = 32'h003F_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h003F_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h001A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h0025_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h0000_0000);

// 0x278 APB_AON_BUS_TIMEOUT_CTRL : default = 32'h0000_0000, rw_mask = 32'h003F_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h003F_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h001A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h0025_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h0000_0000);

// 0x2C0 SW_CFG_REG_0 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);

// 0x2C4 SW_CFG_REG_1 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);

// 0x2C8 SW_CFG_REG_2 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);

// 0x2CC SW_CFG_REG_3 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'h0000_0000);

// 0x2D0 SW_CFG_REG_4 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);

// 0x2D4 SW_CFG_REG_5 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);

// 0x2D8 SW_CFG_REG_6 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);

// 0x2DC SW_CFG_REG_7 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'h0000_0000);

// 0x2E0 SW_CFG_REG_8 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);

// 0x2E4 SW_CFG_REG_9 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);

// 0x2E8 SW_CFG_REG_10 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);

// 0x2EC SW_CFG_REG_11 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'h0000_0000);

`ifdef SCU_RW_PHY
//==============================================================================
// STEP4 : PHY related RW (DDR IO test / DDR PHY JTAG / USB PHY)
//==============================================================================
$display("at %t , SCU STEP4 : PHY RW register check ---- Begin", $time);
// 0x098 DDR_PHY_JTAG : default = 32'h0000_0000, rw_mask = 32'h0001_000F
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0001_000F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0000_000A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0001_0005);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0000_0000);

// 0x0A8 DDR_IO_TEST0 : default = 32'h0000_0000, rw_mask = 32'h1E7F_BDEF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h1E7F_BDEF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h1A5A_184A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h0425_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);

// 0x0AC DDR_IO_TEST1 : default = 32'h0000_0000, rw_mask = 32'h1EF3_FCFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h1EF3_FCFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h1A52_585A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h04A1_A4A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h0000_0000);

// 0x0B0 DDR_IO_TEST2 : default = 32'h0000_0000, rw_mask = 32'h3DEF_0FFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h3DEF_0FFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h184A_0A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h25A5_05A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);

// 0x0B4 DDR_IO_TEST3 : default = 32'h0000_0000, rw_mask = 32'h007F_9FEF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h007F_9FEF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h005A_1A4A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h0025_85A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);

// 0x0B8 A_DJ/A_ET : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);

// 0x0BC A_OJ/A_SJ : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'h0000_0000);

// 0x0C0 DQ_DJ : default = 32'h0000_0000, rw_mask = 32'hFFFF_0000
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'h5A5A_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'hA5A5_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);

// 0x0C4 DQ_ET/DQ_OJ : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);

// 0x0C8 DQ_SJ : default = 32'h0000_0000, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);

// 0x0CC DM/DTO/RET_EN : default = 32'h0200_0000, rw_mask = 32'h0303_FCFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0303_FCFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0202_585A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0101_A4A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'h0200_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0200_0000);

// 0x0D8 U3DEV_CFG_0 : default = 32'h1E13_4000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'h1E13_4000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'h1E13_4000);

// 0x0DC U3DEV_CFG_1 : default = 32'h0027_F71C, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'h0027_F71C);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'h0027_F71C);

// 0x0E0 U3DEV_CFG_2 : default = 32'h3920_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'h3920_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'h3920_0000);

// 0x0E4 U3DEV_CFG_3 : default = 32'h2101_8933, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h7FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'h2101_8933);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h2101_8933);

// 0x0E8 U3DEV_CFG_4 : default = 32'h0000_0000, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);

// 0x0F0 U3DEV_CFG_5 : default = 32'h4734_5508, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h7FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'h4734_5508);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h4734_5508);

// 0x0FC U3HOST0_CFG_0 : default = 32'h1E13_4000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'h1E13_4000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'h1E13_4000);

// 0x100 U3HOST0_CFG_1 : default = 32'h0027_F71C, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'h0027_F71C);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'h0027_F71C);

// 0x104 U3HOST0_CFG_2 : default = 32'h3920_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'h3920_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'h3920_0000);

// 0x108 U3HOST0_CFG_3 : default = 32'h2101_8933, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h7FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'h2101_8933);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h2101_8933);

// 0x10C U3HOST0_CFG_4 : default = 32'h0000_0000, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_0000);

// 0x110 U3HOST0_CFG_5 : default = 32'h2134_5508, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h7FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'h2134_5508);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h2134_5508);

// 0x1F4 U3HOST1_CFG_0 : default = 32'h1E13_4000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'h1E13_4000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'h1E13_4000);

// 0x1F8 U3HOST1_CFG_1 : default = 32'h0027_F71C, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'h0027_F71C);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'h0027_F71C);

// 0x1FC U3HOST1_CFG_2 : default = 32'h3920_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'h3920_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'h3920_0000);

// 0x200 U3HOST1_CFG_3 : default = 32'h2101_8933, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h7FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'h2101_8933);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h2101_8933);

// 0x204 U3HOST1_CFG_4 : default = 32'h0000_0000, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_0000);

// 0x208 U3HOST1_CFG_5 : default = 32'h2134_5508, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h7FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h25A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'h2134_5508);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h2134_5508);

`endif

`ifdef SCU_RW_SYS
//==============================================================================
// STEP5 : system level RW (power/clock gate/reset/PLL/divider) -- really changes chip behavior
//   enable only after confirming the SPI2APB -> SCU access path does not go through
//   a gated/reset clock domain. 0x050 OSC status bits must be stable during the test.
//==============================================================================
$display("at %t , SCU STEP5 : SYS RW register check ---- Begin", $time);
// 0x008 POWER_CTRL : default = 32'h0000_0000, rw_mask = 32'h01FF_01FF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h01FF_01FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h005A_005A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h01A5_01A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h0000_0000);

// 0x00C SYSTEM_MODE_SEL : default = 32'h0001_0005, rw_mask = 32'h0101_7305
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0101_7305);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0000_5200);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0101_2105);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'h0001_0005);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0001_0005);

// 0x010 PLL_GATE : default = 32'h0000_0003, rw_mask = 32'h0000_0003
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0002);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0001);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0003);

// 0x014 MAIN_IP_CLK_GATE0 : default = 32'hFFFF_FFFF, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);

// 0x018 MAIN_IP_CLK_GATE1 : default = 32'h0000_7FFF, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);

// 0x01C SUB_IP_CLK_GATE : default = 32'h0001_FFFF, rw_mask = 32'h0001_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0000_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0001_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);

// 0x020 AON_IP_CLK_GATE0 : default = 32'h0FFF_FFFF, rw_mask = 32'h0FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h0A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h05A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);

// 0x024 AON_IP_CLK_GATE1 : default = 32'h0000_01FF, rw_mask = 32'h0000_01FF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_005A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_01A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_01FF);

// 0x034 MAIN_IP_RESET : default = 32'h03FD_07FF, rw_mask = 32'h03FD_07FF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h0258_025A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h01A5_05A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);

// 0x038 SUB_IP_RESET : default = 32'h0001_0103, rw_mask = 32'h0001_0103
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0001_0103);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0000_0002);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0001_0101);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'h0001_0103);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0001_0103);

// 0x03C AON_IP_RESET : default = 32'h0000_00FF, rw_mask = 32'h0000_00FF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_005A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_00A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_00FF);

// 0x040 DDR_RESET : default = 32'h0000_0000, rw_mask = 32'h0000_03FF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_03FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_025A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_01A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_0000);

// 0x050 OSC_CTRL (RO status must be stable during test) : default = 32'h3200_0701, rw_mask = 32'h0001_0703
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3201_0703);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3200_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3200_0202);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3201_0501);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'h3200_0701);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3200_0701);

// 0x054 PLLSYS_CFG0 : default = 32'hA155_5555, rw_mask = 32'hE000_0000
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'hE155_5555);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'h0155_5555);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'h4155_5555);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'hA155_5555);

// 0x058 PLLSYS_CFG1 : default = 32'h0043_0053, rw_mask = 32'h8000_C000
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h8043_C053);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h0043_0053);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h0043_4053);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h8043_8053);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'h0043_0053);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h0043_0053);

// 0x05C PLLSYS_CFG2 : default = 32'h0169_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'h0169_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'h0169_0000);

// 0x060 PLL_MFP_CFG0 : default = 32'h2100_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'h2100_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'h2100_0000);

// 0x064 PLL_MFP_CFG1 : default = 32'h0052_307D, rw_mask = 32'hF777_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'hF777_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'h5252_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'hA525_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'h0052_307D);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'h0052_307D);

// 0x068 PLL_MFP_CFG2 : default = 32'h0169_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'h0169_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'h0169_0000);

// 0x06C PLL_DDR_CFG0 : default = 32'hA100_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'hA100_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'hA100_0000);

// 0x070 PLL_DDR_CFG1 : default = 32'h0075_3064, rw_mask = 32'hF777_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'hF777_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'h5252_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'hA525_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'h0075_3064);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'h0075_3064);

// 0x074 PLL_DDR_CFG2 : default = 32'h0169_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'h0169_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'h0169_0000);

// 0x078 PLL_CLK_SEL / DIV_DDR1 : default = 32'h0000_000C, rw_mask = 32'h0000_73FF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_73FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_525A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_21A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'h0000_000C);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_000C);

// 0x07C PLL_CONFIG_EN : default = 32'h0000_0000, rw_mask = 32'h0000_0007
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0007);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0002);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0005);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0000);

// 0x080 DIV_CPU/MFP : default = 32'h1818_273B, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'h1818_273B);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'h1818_273B);

// 0x084 DIV_DDR0/TX/TX_BP/RX : default = 32'h2121_2127, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'h2121_2127);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'h2121_2127);

// 0x088 IP_CLK_DIV1 : default = 32'h1330_1010, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'h1330_1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'h1330_1010);

// 0x08C IP_CLK_DIV2 : default = 32'h4001_1111, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'h4001_1111);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'h4001_1111);

// 0x090 IP_CLK_DIV3 : default = 32'h0000_0002, rw_mask = 32'h1F00_0FFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h1F00_0FFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'h5A5A_5A5A);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h1A00_0A5A);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'hA5A5_A5A5);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h0500_05A5);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'h0000_0002);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h0000_0002);

`endif

`ifdef SCU_BYTE_WR
//==============================================================================
// STEP6 : byte-enable write check
//==============================================================================
$display("at %t , SCU STEP6 : byte-enable write check ---- Begin", $time);
// 0x0A0 DDR_VER_PRJ : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A0 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A0 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A0 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A0 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A0 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A0 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A0 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A0 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);

// 0x0A4 DDR_VER_DATE : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A4 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A4 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A4 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A4 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A4 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A4 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A4 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A4 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);

// 0x130 LVDS_TX0_MUX0 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h130 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h130 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h130 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h130 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h130 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h130 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h130 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h130 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h0000_0000);

// 0x134 LVDS_TX0_MUX1 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h134 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h134 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h134 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h134 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h134 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h134 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h134 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h134 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h0000_0000);

// 0x138 LVDS_TX0_MUX2 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h138 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h138 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h138 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h138 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h138 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h138 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h138 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h138 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h0000_0000);

// 0x13C LVDS_TX0_MUX3 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h13C , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h13C , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h13C , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h13C , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h13C , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h13C , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h13C , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h13C , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h0000_0000);

// 0x140 LVDS_TX0_MUX4 : default = 32'h0000_0000, rw_mask = 32'h000F_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h140 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h140 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h140 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h000F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h140 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h140 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h140 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h000F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h140 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h000F_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h140 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h0000_0000);

// 0x144 LVDS_TX1_MUX0 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h144 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h144 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h144 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h144 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h144 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h144 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h144 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h144 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h0000_0000);

// 0x148 LVDS_TX1_MUX1 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h148 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h148 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h148 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h148 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h148 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h148 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h148 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h148 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h0000_0000);

// 0x14C LVDS_TX1_MUX2 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h14C , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h14C , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h14C , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h14C , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h14C , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h14C , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h14C , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h14C , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h0000_0000);

// 0x150 LVDS_TX1_MUX3 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h150 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h150 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h150 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h150 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h150 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h150 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h150 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h150 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h0000_0000);

// 0x154 LVDS_TX1_MUX4 : default = 32'h0000_0000, rw_mask = 32'h000F_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h154 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h154 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h154 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h000F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h154 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h154 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h154 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h000F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h154 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h000F_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h154 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h0000_0000);

// 0x158 LVDS_RX0_MUX0 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h158 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h158 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h158 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h158 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h158 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h158 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h158 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h158 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h0000_0000);

// 0x15C LVDS_RX0_MUX1 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h15C , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h15C , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h15C , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h15C , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h15C , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h15C , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h15C , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h15C , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h0000_0000);

// 0x160 LVDS_RX0_MUX2 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h160 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h160 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h160 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h160 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h160 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h160 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h160 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h160 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h0000_0000);

// 0x164 LVDS_RX0_MUX3 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h164 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h164 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h164 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h164 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h164 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h164 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h164 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h164 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h0000_0000);

// 0x168 LVDS_RX0_MUX4 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h168 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h168 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h168 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h168 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h168 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h168 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h168 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h168 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h0000_0000);

// 0x16C LVDS_RX0_MUX5 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h16C , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h16C , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h16C , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h16C , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h16C , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h16C , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h16C , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h16C , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h0000_0000);

// 0x170 LVDS_RX0_MUX6 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h170 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h170 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h170 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h170 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h170 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h170 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h170 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h170 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h0000_0000);

// 0x174 LVDS_RX1_MUX0 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h174 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h174 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h174 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h174 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h174 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h174 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h174 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h174 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h0000_0000);

// 0x178 LVDS_RX1_MUX1 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h178 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h178 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h178 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h178 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h178 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h178 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h178 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h178 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h0000_0000);

// 0x17C LVDS_RX1_MUX2 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h17C , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h17C , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h17C , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h17C , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h17C , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h17C , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h17C , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h17C , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h0000_0000);

// 0x180 LVDS_RX1_MUX3 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h180 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h180 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h180 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h180 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h180 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h180 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h180 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h180 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h0000_0000);

// 0x184 LVDS_RX1_MUX4 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h184 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h184 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h184 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h184 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h184 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h184 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h184 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h184 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h0000_0000);

// 0x188 LVDS_RX1_MUX5 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h188 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h188 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h188 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h188 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h188 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h188 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h188 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h188 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h0000_0000);

// 0x18C LVDS_RX1_MUX6 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h18C , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h18C , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h18C , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h18C , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h3F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h18C , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h18C , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h3FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h18C , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h18C , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h3F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h0000_0000);

// 0x190 LVDS_TX0_CTRL : default = 32'h0000_0000, rw_mask = 32'h04FF_FFF3
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h190 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h0000_00F3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h190 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h190 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h190 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h0400_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h190 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h0000_FFF3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h190 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h04FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h190 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h00FF_00F3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h190 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h0400_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h0000_0000);

// 0x194 LVDS_TX0_PRBS_SEED : default = 32'h0000_0000, rw_mask = 32'h7F7F_7F7F
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h194 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h0000_007F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h194 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h0000_7F00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h194 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h007F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h194 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h7F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h194 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h0000_7F7F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h194 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h7F7F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h194 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h007F_007F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h194 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h7F00_7F00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h0000_0000);

// 0x198 LVDS_TX1_CTRL : default = 32'h0000_0000, rw_mask = 32'h13FF_FFF3
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h198 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h0000_00F3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h198 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h198 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h198 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h1300_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h198 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h0000_FFF3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h198 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h13FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h198 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h00FF_00F3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h198 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h1300_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h0000_0000);

// 0x19C LVDS_TX1_PRBS_SEED : default = 32'h0000_0000, rw_mask = 32'h7F7F_7F7F
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h19C , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h0000_007F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h19C , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h0000_7F00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h19C , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h007F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h19C , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h7F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h19C , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h0000_7F7F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h19C , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h7F7F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h19C , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h007F_007F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h19C , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h7F00_7F00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h0000_0000);

// 0x1A0 LVDS_RX_PRBS_CTRL : default = 32'h0000_0000, rw_mask = 32'h0000_0303
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1A0 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1A0 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0300);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1A0 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1A0 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1A0 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0303);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1A0 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1A0 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1A0 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0300);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);

// 0x1B4 GMAC_PHY_CTRL : default = 32'h0000_0000, rw_mask = 32'h0000_003F
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1B4 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_003F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1B4 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1B4 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1B4 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1B4 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_003F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1B4 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1B4 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_003F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1B4 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);

// 0x1EC GMAC_DPRAM_CFG : default = 32'h0208_0208, rw_mask = 32'h1FFF_1FFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'h0208_0208);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1EC , 32'hFDF7_FDF7 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h0208_02F7);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'h0208_0208);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1EC , 32'hFDF7_FDF7 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h0208_1D08);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'h0208_0208);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1EC , 32'hFDF7_FDF7 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h02F7_0208);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'h0208_0208);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1EC , 32'hFDF7_FDF7 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h1D08_0208);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'h0208_0208);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1EC , 32'hFDF7_FDF7 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h0208_1DF7);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'h0208_0208);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1EC , 32'hFDF7_FDF7 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h1DF7_0208);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'h0208_0208);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1EC , 32'hFDF7_FDF7 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h02F7_02F7);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'h0208_0208);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1EC , 32'hFDF7_FDF7 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h1D08_1D08);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'h0208_0208);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h0208_0208);

// 0x1F0 BREATHE_REG : default = 32'h0000_0000, rw_mask = 32'h0FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F0 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F0 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F0 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F0 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h0F00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F0 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F0 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h0FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F0 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F0 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h0F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);

// 0x254 AHB_MAIN_BUS_TIMEOUT_CTRL : default = 32'h0000_0000, rw_mask = 32'h007F_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h254 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h254 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h254 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h007F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h254 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h254 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h254 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h007F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h254 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h007F_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h254 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h0000_0000);

// 0x260 AHB_SUB_BUS_TIMEOUT_CTRL : default = 32'h0000_0000, rw_mask = 32'h000F_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h260 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h260 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h260 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h000F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h260 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h260 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h260 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h000F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h260 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h000F_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h260 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h0000_0000);

// 0x26C APB_MAIN_BUS_TIMEOUT_CTRL : default = 32'h0000_0000, rw_mask = 32'h003F_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h26C , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h26C , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h26C , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h003F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h26C , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h26C , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h26C , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h003F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h26C , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h003F_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h26C , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h0000_0000);

// 0x278 APB_AON_BUS_TIMEOUT_CTRL : default = 32'h0000_0000, rw_mask = 32'h003F_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h278 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h278 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h278 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h003F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h278 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h278 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h278 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h003F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h278 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h003F_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h278 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h0000_0000);

// 0x2C0 SW_CFG_REG_0 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C0 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C0 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C0 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C0 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C0 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C0 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C0 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C0 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);

// 0x2C4 SW_CFG_REG_1 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C4 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C4 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C4 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C4 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C4 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C4 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C4 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C4 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);

// 0x2C8 SW_CFG_REG_2 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C8 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C8 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C8 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C8 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C8 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C8 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C8 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2C8 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);

// 0x2CC SW_CFG_REG_3 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2CC , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2CC , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2CC , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2CC , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2CC , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2CC , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2CC , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2CC , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'h0000_0000);

// 0x2D0 SW_CFG_REG_4 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D0 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D0 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D0 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D0 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D0 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D0 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D0 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D0 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);

// 0x2D4 SW_CFG_REG_5 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D4 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D4 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D4 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D4 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D4 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D4 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D4 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D4 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);

// 0x2D8 SW_CFG_REG_6 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D8 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D8 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D8 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D8 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D8 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D8 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D8 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2D8 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);

// 0x2DC SW_CFG_REG_7 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2DC , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2DC , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2DC , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2DC , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2DC , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2DC , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2DC , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2DC , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'h0000_0000);

// 0x2E0 SW_CFG_REG_8 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E0 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E0 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E0 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E0 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E0 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E0 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E0 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E0 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);

// 0x2E4 SW_CFG_REG_9 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E4 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E4 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E4 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E4 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E4 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E4 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E4 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E4 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);

// 0x2E8 SW_CFG_REG_10 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E8 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E8 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E8 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E8 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E8 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E8 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E8 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2E8 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);

// 0x2EC SW_CFG_REG_11 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2EC , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2EC , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2EC , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2EC , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2EC , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2EC , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2EC , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h2EC , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'h0000_0000);

`ifdef SCU_RW_PHY
// 0x098 DDR_PHY_JTAG : default = 32'h0000_0000, rw_mask = 32'h0001_000F
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h098 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0000_000F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h098 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h098 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0001_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h098 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h098 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0000_000F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h098 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0001_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h098 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0001_000F);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h098 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0000_0000);

// 0x0A8 DDR_IO_TEST0 : default = 32'h0000_0000, rw_mask = 32'h1E7F_BDEF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A8 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h0000_00EF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A8 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h0000_BD00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A8 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h007F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A8 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h1E00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A8 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h0000_BDEF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A8 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h1E7F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A8 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h007F_00EF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0A8 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h1E00_BD00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);

// 0x0AC DDR_IO_TEST1 : default = 32'h0000_0000, rw_mask = 32'h1EF3_FCFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0AC , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0AC , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h0000_FC00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0AC , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h00F3_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0AC , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h1E00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0AC , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h0000_FCFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0AC , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h1EF3_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0AC , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h00F3_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0AC , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h1E00_FC00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h0000_0000);

// 0x0B0 DDR_IO_TEST2 : default = 32'h0000_0000, rw_mask = 32'h3DEF_0FFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B0 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B0 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h0000_0F00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B0 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h00EF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B0 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h3D00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B0 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h0000_0FFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B0 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h3DEF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B0 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h00EF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B0 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h3D00_0F00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);

// 0x0B4 DDR_IO_TEST3 : default = 32'h0000_0000, rw_mask = 32'h007F_9FEF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B4 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h0000_00EF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B4 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h0000_9F00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B4 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h007F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B4 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B4 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h0000_9FEF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B4 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h007F_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B4 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h007F_00EF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B4 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h0000_9F00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);

// 0x0B8 A_DJ/A_ET : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B8 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B8 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B8 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B8 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B8 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B8 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B8 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0B8 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);

// 0x0BC A_OJ/A_SJ : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0BC , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0BC , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0BC , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0BC , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0BC , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0BC , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0BC , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0BC , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'h0000_0000);

// 0x0C0 DQ_DJ : default = 32'h0000_0000, rw_mask = 32'hFFFF_0000
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C0 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C0 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C0 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C0 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C0 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C0 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C0 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C0 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);

// 0x0C4 DQ_ET/DQ_OJ : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C4 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C4 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C4 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C4 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'hFF00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C4 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C4 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C4 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C4 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);

// 0x0C8 DQ_SJ : default = 32'h0000_0000, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C8 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C8 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C8 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C8 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C8 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C8 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C8 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0C8 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);

// 0x0CC DM/DTO/RET_EN : default = 32'h0200_0000, rw_mask = 32'h0303_FCFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'h0200_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0CC , 32'hFDFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0200_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'h0200_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0CC , 32'hFDFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0200_FC00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'h0200_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0CC , 32'hFDFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0203_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'h0200_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0CC , 32'hFDFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0100_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'h0200_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0CC , 32'hFDFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0200_FCFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'h0200_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0CC , 32'hFDFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0103_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'h0200_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0CC , 32'hFDFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0203_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'h0200_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0CC , 32'hFDFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0100_FC00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'h0200_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0200_0000);

// 0x0D8 U3DEV_CFG_0 : default = 32'h1E13_4000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0D8 , 32'hE1EC_BFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'h1E13_40FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0D8 , 32'hE1EC_BFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'h1E13_BF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0D8 , 32'hE1EC_BFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'h1EEC_4000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0D8 , 32'hE1EC_BFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'hE113_4000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0D8 , 32'hE1EC_BFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'h1E13_BFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0D8 , 32'hE1EC_BFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'hE1EC_4000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0D8 , 32'hE1EC_BFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'h1EEC_40FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0D8 , 32'hE1EC_BFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'hE113_BF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'h1E13_4000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'h1E13_4000);

// 0x0DC U3DEV_CFG_1 : default = 32'h0027_F71C, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0DC , 32'hFFD8_08E3 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'h0027_F7E3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0DC , 32'hFFD8_08E3 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'h0027_081C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0DC , 32'hFFD8_08E3 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'h00D8_F71C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0DC , 32'hFFD8_08E3 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'hFF27_F71C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0DC , 32'hFFD8_08E3 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'h0027_08E3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0DC , 32'hFFD8_08E3 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'hFFD8_F71C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0DC , 32'hFFD8_08E3 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'h00D8_F7E3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0DC , 32'hFFD8_08E3 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'hFF27_081C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'h0027_F71C);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'h0027_F71C);

// 0x0E0 U3DEV_CFG_2 : default = 32'h3920_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E0 , 32'hC6DF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'h3920_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E0 , 32'hC6DF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'h3920_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E0 , 32'hC6DF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'h39DF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E0 , 32'hC6DF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'hC620_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E0 , 32'hC6DF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'h3920_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E0 , 32'hC6DF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'hC6DF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E0 , 32'hC6DF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'h39DF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E0 , 32'hC6DF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'hC620_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'h3920_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'h3920_0000);

// 0x0E4 U3DEV_CFG_3 : default = 32'h2101_8933, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E4 , 32'hDEFE_76CC , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h2101_89CC);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E4 , 32'hDEFE_76CC , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h2101_7633);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E4 , 32'hDEFE_76CC , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h21FE_8933);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E4 , 32'hDEFE_76CC , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h5E01_8933);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E4 , 32'hDEFE_76CC , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h2101_76CC);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E4 , 32'hDEFE_76CC , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h5EFE_8933);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E4 , 32'hDEFE_76CC , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h21FE_89CC);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E4 , 32'hDEFE_76CC , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h5E01_7633);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'h2101_8933);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h2101_8933);

// 0x0E8 U3DEV_CFG_4 : default = 32'h0000_0000, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E8 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E8 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E8 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E8 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E8 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E8 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E8 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0E8 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);

// 0x0F0 U3DEV_CFG_5 : default = 32'h4734_5508, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'h4734_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0F0 , 32'hB8CB_AAF7 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h4734_55F7);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'h4734_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0F0 , 32'hB8CB_AAF7 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h4734_AA08);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'h4734_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0F0 , 32'hB8CB_AAF7 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h47CB_5508);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'h4734_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0F0 , 32'hB8CB_AAF7 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h3834_5508);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'h4734_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0F0 , 32'hB8CB_AAF7 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h4734_AAF7);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'h4734_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0F0 , 32'hB8CB_AAF7 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h38CB_5508);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'h4734_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0F0 , 32'hB8CB_AAF7 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h47CB_55F7);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'h4734_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0F0 , 32'hB8CB_AAF7 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h3834_AA08);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'h4734_5508);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h4734_5508);

// 0x0FC U3HOST0_CFG_0 : default = 32'h1E13_4000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0FC , 32'hE1EC_BFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'h1E13_40FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0FC , 32'hE1EC_BFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'h1E13_BF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0FC , 32'hE1EC_BFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'h1EEC_4000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0FC , 32'hE1EC_BFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'hE113_4000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0FC , 32'hE1EC_BFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'h1E13_BFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0FC , 32'hE1EC_BFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'hE1EC_4000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0FC , 32'hE1EC_BFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'h1EEC_40FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h0FC , 32'hE1EC_BFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'hE113_BF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'h1E13_4000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'h1E13_4000);

// 0x100 U3HOST0_CFG_1 : default = 32'h0027_F71C, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h100 , 32'hFFD8_08E3 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'h0027_F7E3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h100 , 32'hFFD8_08E3 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'h0027_081C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h100 , 32'hFFD8_08E3 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'h00D8_F71C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h100 , 32'hFFD8_08E3 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'hFF27_F71C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h100 , 32'hFFD8_08E3 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'h0027_08E3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h100 , 32'hFFD8_08E3 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'hFFD8_F71C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h100 , 32'hFFD8_08E3 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'h00D8_F7E3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h100 , 32'hFFD8_08E3 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'hFF27_081C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'h0027_F71C);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'h0027_F71C);

// 0x104 U3HOST0_CFG_2 : default = 32'h3920_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h104 , 32'hC6DF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'h3920_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h104 , 32'hC6DF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'h3920_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h104 , 32'hC6DF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'h39DF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h104 , 32'hC6DF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'hC620_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h104 , 32'hC6DF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'h3920_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h104 , 32'hC6DF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'hC6DF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h104 , 32'hC6DF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'h39DF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h104 , 32'hC6DF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'hC620_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'h3920_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'h3920_0000);

// 0x108 U3HOST0_CFG_3 : default = 32'h2101_8933, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h108 , 32'hDEFE_76CC , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h2101_89CC);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h108 , 32'hDEFE_76CC , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h2101_7633);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h108 , 32'hDEFE_76CC , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h21FE_8933);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h108 , 32'hDEFE_76CC , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h5E01_8933);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h108 , 32'hDEFE_76CC , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h2101_76CC);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h108 , 32'hDEFE_76CC , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h5EFE_8933);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h108 , 32'hDEFE_76CC , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h21FE_89CC);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h108 , 32'hDEFE_76CC , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h5E01_7633);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'h2101_8933);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h2101_8933);

// 0x10C U3HOST0_CFG_4 : default = 32'h0000_0000, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h10C , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h10C , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h10C , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h10C , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h10C , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h10C , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h10C , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h10C , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_0000);

// 0x110 U3HOST0_CFG_5 : default = 32'h2134_5508, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h110 , 32'hDECB_AAF7 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h2134_55F7);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h110 , 32'hDECB_AAF7 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h2134_AA08);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h110 , 32'hDECB_AAF7 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h21CB_5508);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h110 , 32'hDECB_AAF7 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h5E34_5508);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h110 , 32'hDECB_AAF7 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h2134_AAF7);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h110 , 32'hDECB_AAF7 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h5ECB_5508);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h110 , 32'hDECB_AAF7 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h21CB_55F7);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h110 , 32'hDECB_AAF7 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h5E34_AA08);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'h2134_5508);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h2134_5508);

// 0x1F4 U3HOST1_CFG_0 : default = 32'h1E13_4000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F4 , 32'hE1EC_BFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'h1E13_40FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F4 , 32'hE1EC_BFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'h1E13_BF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F4 , 32'hE1EC_BFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'h1EEC_4000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F4 , 32'hE1EC_BFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'hE113_4000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F4 , 32'hE1EC_BFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'h1E13_BFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F4 , 32'hE1EC_BFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'hE1EC_4000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F4 , 32'hE1EC_BFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'h1EEC_40FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F4 , 32'hE1EC_BFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'hE113_BF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'h1E13_4000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'h1E13_4000);

// 0x1F8 U3HOST1_CFG_1 : default = 32'h0027_F71C, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F8 , 32'hFFD8_08E3 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'h0027_F7E3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F8 , 32'hFFD8_08E3 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'h0027_081C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F8 , 32'hFFD8_08E3 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'h00D8_F71C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F8 , 32'hFFD8_08E3 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'hFF27_F71C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F8 , 32'hFFD8_08E3 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'h0027_08E3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F8 , 32'hFFD8_08E3 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'hFFD8_F71C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F8 , 32'hFFD8_08E3 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'h00D8_F7E3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1F8 , 32'hFFD8_08E3 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'hFF27_081C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'h0027_F71C);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'h0027_F71C);

// 0x1FC U3HOST1_CFG_2 : default = 32'h3920_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1FC , 32'hC6DF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'h3920_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1FC , 32'hC6DF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'h3920_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1FC , 32'hC6DF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'h39DF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1FC , 32'hC6DF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'hC620_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1FC , 32'hC6DF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'h3920_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1FC , 32'hC6DF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'hC6DF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1FC , 32'hC6DF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'h39DF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'h3920_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h1FC , 32'hC6DF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'hC620_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'h3920_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'h3920_0000);

// 0x200 U3HOST1_CFG_3 : default = 32'h2101_8933, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h200 , 32'hDEFE_76CC , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h2101_89CC);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h200 , 32'hDEFE_76CC , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h2101_7633);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h200 , 32'hDEFE_76CC , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h21FE_8933);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h200 , 32'hDEFE_76CC , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h5E01_8933);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h200 , 32'hDEFE_76CC , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h2101_76CC);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h200 , 32'hDEFE_76CC , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h5EFE_8933);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h200 , 32'hDEFE_76CC , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h21FE_89CC);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h200 , 32'hDEFE_76CC , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h5E01_7633);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'h2101_8933);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h2101_8933);

// 0x204 U3HOST1_CFG_4 : default = 32'h0000_0000, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h204 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h204 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h204 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h204 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h204 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h204 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h204 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h204 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_0000);

// 0x208 U3HOST1_CFG_5 : default = 32'h2134_5508, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h208 , 32'hDECB_AAF7 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h2134_55F7);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h208 , 32'hDECB_AAF7 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h2134_AA08);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h208 , 32'hDECB_AAF7 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h21CB_5508);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h208 , 32'hDECB_AAF7 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h5E34_5508);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h208 , 32'hDECB_AAF7 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h2134_AAF7);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h208 , 32'hDECB_AAF7 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h5ECB_5508);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h208 , 32'hDECB_AAF7 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h21CB_55F7);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h208 , 32'hDECB_AAF7 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h5E34_AA08);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'h2134_5508);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h2134_5508);

`endif
`ifdef SCU_RW_SYS
// 0x008 POWER_CTRL : default = 32'h0000_0000, rw_mask = 32'h01FF_01FF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h008 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h008 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h0000_0100);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h008 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h00FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h008 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h0100_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h008 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h0000_01FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h008 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h01FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h008 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h008 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h0100_0100);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h0000_0000);

// 0x00C SYSTEM_MODE_SEL : default = 32'h0001_0005, rw_mask = 32'h0101_7305
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'h0001_0005);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h00C , 32'hFFFE_FFFA , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0001_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'h0001_0005);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h00C , 32'hFFFE_FFFA , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0001_7305);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'h0001_0005);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h00C , 32'hFFFE_FFFA , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0000_0005);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'h0001_0005);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h00C , 32'hFFFE_FFFA , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0101_0005);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'h0001_0005);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h00C , 32'hFFFE_FFFA , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0001_7300);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'h0001_0005);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h00C , 32'hFFFE_FFFA , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0100_0005);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'h0001_0005);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h00C , 32'hFFFE_FFFA , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'h0001_0005);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h00C , 32'hFFFE_FFFA , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0101_7305);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'h0001_0005);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0001_0005);

// 0x010 PLL_GATE : default = 32'h0000_0003, rw_mask = 32'h0000_0003
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h010 , 32'hFFFF_FFFC , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h010 , 32'hFFFF_FFFC , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h010 , 32'hFFFF_FFFC , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h010 , 32'hFFFF_FFFC , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h010 , 32'hFFFF_FFFC , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h010 , 32'hFFFF_FFFC , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h010 , 32'hFFFF_FFFC , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h010 , 32'hFFFF_FFFC , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'h0000_0003);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0003);

// 0x014 MAIN_IP_CLK_GATE0 : default = 32'hFFFF_FFFF, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h014 , 32'h0000_0000 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'hFFFF_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h014 , 32'h0000_0000 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'hFFFF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h014 , 32'h0000_0000 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'hFF00_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h014 , 32'h0000_0000 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'h00FF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h014 , 32'h0000_0000 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'hFFFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h014 , 32'h0000_0000 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h014 , 32'h0000_0000 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'hFF00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h014 , 32'h0000_0000 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);

// 0x018 MAIN_IP_CLK_GATE1 : default = 32'h0000_7FFF, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h018 , 32'hFFFF_8000 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_7F00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h018 , 32'hFFFF_8000 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_80FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h018 , 32'hFFFF_8000 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h018 , 32'hFFFF_8000 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h018 , 32'hFFFF_8000 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_8000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h018 , 32'hFFFF_8000 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h018 , 32'hFFFF_8000 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_7F00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h018 , 32'hFFFF_8000 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_80FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);

// 0x01C SUB_IP_CLK_GATE : default = 32'h0001_FFFF, rw_mask = 32'h0001_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h01C , 32'hFFFE_0000 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0001_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h01C , 32'hFFFE_0000 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0001_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h01C , 32'hFFFE_0000 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h01C , 32'hFFFE_0000 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h01C , 32'hFFFE_0000 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0001_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h01C , 32'hFFFE_0000 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h01C , 32'hFFFE_0000 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0000_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h01C , 32'hFFFE_0000 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0001_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);

// 0x020 AON_IP_CLK_GATE0 : default = 32'h0FFF_FFFF, rw_mask = 32'h0FFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h020 , 32'hF000_0000 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h0FFF_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h020 , 32'hF000_0000 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h0FFF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h020 , 32'hF000_0000 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h0F00_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h020 , 32'hF000_0000 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h00FF_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h020 , 32'hF000_0000 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h0FFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h020 , 32'hF000_0000 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h0000_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h020 , 32'hF000_0000 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h0F00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h020 , 32'hF000_0000 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h00FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);

// 0x024 AON_IP_CLK_GATE1 : default = 32'h0000_01FF, rw_mask = 32'h0000_01FF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h024 , 32'hFFFF_FE00 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_0100);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h024 , 32'hFFFF_FE00 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h024 , 32'hFFFF_FE00 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h024 , 32'hFFFF_FE00 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h024 , 32'hFFFF_FE00 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h024 , 32'hFFFF_FE00 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h024 , 32'hFFFF_FE00 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_0100);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h024 , 32'hFFFF_FE00 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_01FF);

// 0x034 MAIN_IP_RESET : default = 32'h03FD_07FF, rw_mask = 32'h03FD_07FF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h034 , 32'hFC02_F800 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h03FD_0700);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h034 , 32'hFC02_F800 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h03FD_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h034 , 32'hFC02_F800 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h0300_07FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h034 , 32'hFC02_F800 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h00FD_07FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h034 , 32'hFC02_F800 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h03FD_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h034 , 32'hFC02_F800 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h0000_07FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h034 , 32'hFC02_F800 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h0300_0700);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h034 , 32'hFC02_F800 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h00FD_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);

// 0x038 SUB_IP_RESET : default = 32'h0001_0103, rw_mask = 32'h0001_0103
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'h0001_0103);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h038 , 32'hFFFE_FEFC , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0001_0100);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'h0001_0103);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h038 , 32'hFFFE_FEFC , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0001_0003);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'h0001_0103);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h038 , 32'hFFFE_FEFC , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0000_0103);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'h0001_0103);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h038 , 32'hFFFE_FEFC , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0001_0103);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'h0001_0103);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h038 , 32'hFFFE_FEFC , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0001_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'h0001_0103);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h038 , 32'hFFFE_FEFC , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0000_0103);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'h0001_0103);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h038 , 32'hFFFE_FEFC , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0000_0100);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'h0001_0103);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h038 , 32'hFFFE_FEFC , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0001_0003);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'h0001_0103);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0001_0103);

// 0x03C AON_IP_RESET : default = 32'h0000_00FF, rw_mask = 32'h0000_00FF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h03C , 32'hFFFF_FF00 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h03C , 32'hFFFF_FF00 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h03C , 32'hFFFF_FF00 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h03C , 32'hFFFF_FF00 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h03C , 32'hFFFF_FF00 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h03C , 32'hFFFF_FF00 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h03C , 32'hFFFF_FF00 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h03C , 32'hFFFF_FF00 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_00FF);

// 0x040 DDR_RESET : default = 32'h0000_0000, rw_mask = 32'h0000_03FF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h040 , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h040 , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_0300);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h040 , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h040 , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h040 , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_03FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h040 , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h040 , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h040 , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_0300);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_0000);

// 0x050 OSC_CTRL (RO status must be stable during test) : default = 32'h3200_0701, rw_mask = 32'h0001_0703
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'h3200_0701);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h050 , 32'hCDFF_F8FE , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3200_0702);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'h3200_0701);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h050 , 32'hCDFF_F8FE , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3200_0001);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'h3200_0701);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h050 , 32'hCDFF_F8FE , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3201_0701);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'h3200_0701);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h050 , 32'hCDFF_F8FE , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3200_0701);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'h3200_0701);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h050 , 32'hCDFF_F8FE , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3200_0002);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'h3200_0701);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h050 , 32'hCDFF_F8FE , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3201_0701);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'h3200_0701);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h050 , 32'hCDFF_F8FE , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3201_0702);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'h3200_0701);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h050 , 32'hCDFF_F8FE , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3200_0001);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'h3200_0701);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3200_0701);

// 0x054 PLLSYS_CFG0 : default = 32'hA155_5555, rw_mask = 32'hE000_0000
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h054 , 32'h5EAA_AAAA , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h054 , 32'h5EAA_AAAA , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h054 , 32'h5EAA_AAAA , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h054 , 32'h5EAA_AAAA , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'h4155_5555);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h054 , 32'h5EAA_AAAA , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h054 , 32'h5EAA_AAAA , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'h4155_5555);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h054 , 32'h5EAA_AAAA , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h054 , 32'h5EAA_AAAA , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'h4155_5555);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'hA155_5555);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'hA155_5555);

// 0x058 PLLSYS_CFG1 : default = 32'h0043_0053, rw_mask = 32'h8000_C000
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'h0043_0053);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h058 , 32'hFFBC_FFAC , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h0043_0053);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'h0043_0053);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h058 , 32'hFFBC_FFAC , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h0043_C053);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'h0043_0053);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h058 , 32'hFFBC_FFAC , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h0043_0053);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'h0043_0053);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h058 , 32'hFFBC_FFAC , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h8043_0053);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'h0043_0053);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h058 , 32'hFFBC_FFAC , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h0043_C053);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'h0043_0053);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h058 , 32'hFFBC_FFAC , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h8043_0053);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'h0043_0053);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h058 , 32'hFFBC_FFAC , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h0043_0053);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'h0043_0053);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h058 , 32'hFFBC_FFAC , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h8043_C053);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'h0043_0053);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h0043_0053);

// 0x05C PLLSYS_CFG2 : default = 32'h0169_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h05C , 32'hFE96_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'h0169_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h05C , 32'hFE96_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'h0169_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h05C , 32'hFE96_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'h0196_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h05C , 32'hFE96_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'hFE69_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h05C , 32'hFE96_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'h0169_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h05C , 32'hFE96_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'hFE96_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h05C , 32'hFE96_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'h0196_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h05C , 32'hFE96_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'hFE69_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'h0169_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'h0169_0000);

// 0x060 PLL_MFP_CFG0 : default = 32'h2100_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'h2100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h060 , 32'hDEFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'h2100_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'h2100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h060 , 32'hDEFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'h2100_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'h2100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h060 , 32'hDEFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'h21FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'h2100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h060 , 32'hDEFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'hDE00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'h2100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h060 , 32'hDEFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'h2100_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'h2100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h060 , 32'hDEFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'hDEFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'h2100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h060 , 32'hDEFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'h21FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'h2100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h060 , 32'hDEFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'hDE00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'h2100_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'h2100_0000);

// 0x064 PLL_MFP_CFG1 : default = 32'h0052_307D, rw_mask = 32'hF777_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'h0052_307D);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h064 , 32'hFFAD_CF82 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'h0052_3082);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'h0052_307D);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h064 , 32'hFFAD_CF82 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'h0052_CF7D);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'h0052_307D);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h064 , 32'hFFAD_CF82 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'h0025_307D);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'h0052_307D);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h064 , 32'hFFAD_CF82 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'hF752_307D);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'h0052_307D);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h064 , 32'hFFAD_CF82 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'h0052_CF82);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'h0052_307D);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h064 , 32'hFFAD_CF82 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'hF725_307D);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'h0052_307D);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h064 , 32'hFFAD_CF82 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'h0025_3082);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'h0052_307D);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h064 , 32'hFFAD_CF82 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'hF752_CF7D);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'h0052_307D);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'h0052_307D);

// 0x068 PLL_MFP_CFG2 : default = 32'h0169_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h068 , 32'hFE96_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'h0169_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h068 , 32'hFE96_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'h0169_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h068 , 32'hFE96_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'h0196_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h068 , 32'hFE96_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'hFE69_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h068 , 32'hFE96_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'h0169_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h068 , 32'hFE96_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'hFE96_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h068 , 32'hFE96_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'h0196_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h068 , 32'hFE96_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'hFE69_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'h0169_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'h0169_0000);

// 0x06C PLL_DDR_CFG0 : default = 32'hA100_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'hA100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h06C , 32'h5EFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'hA100_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'hA100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h06C , 32'h5EFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'hA100_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'hA100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h06C , 32'h5EFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'hA1FF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'hA100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h06C , 32'h5EFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'h5E00_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'hA100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h06C , 32'h5EFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'hA100_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'hA100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h06C , 32'h5EFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'h5EFF_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'hA100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h06C , 32'h5EFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'hA1FF_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'hA100_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h06C , 32'h5EFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'h5E00_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'hA100_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'hA100_0000);

// 0x070 PLL_DDR_CFG1 : default = 32'h0075_3064, rw_mask = 32'hF777_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'h0075_3064);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h070 , 32'hFF8A_CF9B , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'h0075_309B);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'h0075_3064);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h070 , 32'hFF8A_CF9B , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'h0075_CF64);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'h0075_3064);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h070 , 32'hFF8A_CF9B , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'h0002_3064);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'h0075_3064);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h070 , 32'hFF8A_CF9B , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'hF775_3064);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'h0075_3064);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h070 , 32'hFF8A_CF9B , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'h0075_CF9B);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'h0075_3064);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h070 , 32'hFF8A_CF9B , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'hF702_3064);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'h0075_3064);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h070 , 32'hFF8A_CF9B , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'h0002_309B);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'h0075_3064);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h070 , 32'hFF8A_CF9B , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'hF775_CF64);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'h0075_3064);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'h0075_3064);

// 0x074 PLL_DDR_CFG2 : default = 32'h0169_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h074 , 32'hFE96_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'h0169_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h074 , 32'hFE96_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'h0169_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h074 , 32'hFE96_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'h0196_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h074 , 32'hFE96_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'hFE69_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h074 , 32'hFE96_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'h0169_FFFF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h074 , 32'hFE96_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'hFE96_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h074 , 32'hFE96_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'h0196_00FF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'h0169_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h074 , 32'hFE96_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'hFE69_FF00);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'h0169_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'h0169_0000);

// 0x078 PLL_CLK_SEL / DIV_DDR1 : default = 32'h0000_000C, rw_mask = 32'h0000_73FF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'h0000_000C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h078 , 32'hFFFF_FFF3 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_00F3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'h0000_000C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h078 , 32'hFFFF_FFF3 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_730C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'h0000_000C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h078 , 32'hFFFF_FFF3 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_000C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'h0000_000C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h078 , 32'hFFFF_FFF3 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_000C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'h0000_000C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h078 , 32'hFFFF_FFF3 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_73F3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'h0000_000C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h078 , 32'hFFFF_FFF3 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_000C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'h0000_000C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h078 , 32'hFFFF_FFF3 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_00F3);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'h0000_000C);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h078 , 32'hFFFF_FFF3 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_730C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'h0000_000C);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_000C);

// 0x07C PLL_CONFIG_EN : default = 32'h0000_0000, rw_mask = 32'h0000_0007
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h07C , 32'hFFFF_FFFF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0007);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h07C , 32'hFFFF_FFFF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h07C , 32'hFFFF_FFFF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h07C , 32'hFFFF_FFFF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h07C , 32'hFFFF_FFFF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0007);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h07C , 32'hFFFF_FFFF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h07C , 32'hFFFF_FFFF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0007);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h07C , 32'hFFFF_FFFF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'h0000_0000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0000);

// 0x080 DIV_CPU/MFP : default = 32'h1818_273B, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'h1818_273B);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h080 , 32'hE7E7_D8C4 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'h1818_27C4);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'h1818_273B);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h080 , 32'hE7E7_D8C4 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'h1818_D83B);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'h1818_273B);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h080 , 32'hE7E7_D8C4 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'h18E7_273B);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'h1818_273B);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h080 , 32'hE7E7_D8C4 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'hE718_273B);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'h1818_273B);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h080 , 32'hE7E7_D8C4 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'h1818_D8C4);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'h1818_273B);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h080 , 32'hE7E7_D8C4 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'hE7E7_273B);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'h1818_273B);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h080 , 32'hE7E7_D8C4 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'h18E7_27C4);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'h1818_273B);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h080 , 32'hE7E7_D8C4 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'hE718_D83B);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'h1818_273B);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'h1818_273B);

// 0x084 DIV_DDR0/TX/TX_BP/RX : default = 32'h2121_2127, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'h2121_2127);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h084 , 32'hDEDE_DED8 , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'h2121_21D8);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'h2121_2127);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h084 , 32'hDEDE_DED8 , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'h2121_DE27);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'h2121_2127);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h084 , 32'hDEDE_DED8 , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'h21DE_2127);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'h2121_2127);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h084 , 32'hDEDE_DED8 , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'hDE21_2127);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'h2121_2127);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h084 , 32'hDEDE_DED8 , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'h2121_DED8);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'h2121_2127);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h084 , 32'hDEDE_DED8 , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'hDEDE_2127);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'h2121_2127);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h084 , 32'hDEDE_DED8 , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'h21DE_21D8);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'h2121_2127);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h084 , 32'hDEDE_DED8 , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'hDE21_DE27);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'h2121_2127);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'h2121_2127);

// 0x088 IP_CLK_DIV1 : default = 32'h1330_1010, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'h1330_1010);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h088 , 32'hECCF_EFEF , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'h1330_10EF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'h1330_1010);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h088 , 32'hECCF_EFEF , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'h1330_EF10);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'h1330_1010);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h088 , 32'hECCF_EFEF , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'h13CF_1010);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'h1330_1010);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h088 , 32'hECCF_EFEF , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'hEC30_1010);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'h1330_1010);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h088 , 32'hECCF_EFEF , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'h1330_EFEF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'h1330_1010);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h088 , 32'hECCF_EFEF , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'hECCF_1010);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'h1330_1010);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h088 , 32'hECCF_EFEF , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'h13CF_10EF);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'h1330_1010);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h088 , 32'hECCF_EFEF , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'hEC30_EF10);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'h1330_1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'h1330_1010);

// 0x08C IP_CLK_DIV2 : default = 32'h4001_1111, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'h4001_1111);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h08C , 32'hBFFE_EEEE , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'h4001_11EE);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'h4001_1111);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h08C , 32'hBFFE_EEEE , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'h4001_EE11);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'h4001_1111);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h08C , 32'hBFFE_EEEE , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'h40FE_1111);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'h4001_1111);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h08C , 32'hBFFE_EEEE , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'hBF01_1111);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'h4001_1111);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h08C , 32'hBFFE_EEEE , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'h4001_EEEE);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'h4001_1111);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h08C , 32'hBFFE_EEEE , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'hBFFE_1111);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'h4001_1111);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h08C , 32'hBFFE_EEEE , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'h40FE_11EE);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'h4001_1111);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h08C , 32'hBFFE_EEEE , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'hBF01_EE11);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'h4001_1111);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'h4001_1111);

// 0x090 IP_CLK_DIV3 : default = 32'h0000_0002, rw_mask = 32'h1F00_0FFF
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'h0000_0002);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h090 , 32'hFFFF_FFFD , 4'b0001);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h0000_00FD);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'h0000_0002);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h090 , 32'hFFFF_FFFD , 4'b0010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h0000_0F02);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'h0000_0002);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h090 , 32'hFFFF_FFFD , 4'b0100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h0000_0002);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'h0000_0002);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h090 , 32'hFFFF_FFFD , 4'b1000);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h1F00_0002);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'h0000_0002);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h090 , 32'hFFFF_FFFD , 4'b0011);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h0000_0FFD);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'h0000_0002);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h090 , 32'hFFFF_FFFD , 4'b1100);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h1F00_0002);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'h0000_0002);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h090 , 32'hFFFF_FFFD , 4'b0101);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h0000_00FD);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'h0000_0002);
        es_spi_master.ES_SPI_WR_BE(32'ha000_c000 + 32'h090 , 32'hFFFF_FFFD , 4'b1010);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h1F00_0F02);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'h0000_0002);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h0000_0002);

`endif
`endif

$display("at %t , SCU register default/RW check ---- End", $time);
end
endtask
