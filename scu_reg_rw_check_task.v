//==============================================================================
// SCU_REG register check : read default -> write all 1s -> read expected
//   - Reset values / writable bits derived from SCU_REG.v (RELEASE DATE 2026/11/20)
//   - ES_SPI_RD(addr, exp) : 2nd arg is the expected value (compared inside)
//   - Expected value after writing 32'hFFFF_FFFF = default | rw_mask
//     (RW bits read 1, reserved / RO bits keep their value)
//   - Never written (read default only):
//       0x030 CPU_RESET/CHIP_RESET/SYS_RESET
//       delay chain : GMAC 0x1B8~0x1CC, 0x1E0~0x1E8 / EMMC 0x230~0x250
//   - `define SCU_RW_SYS : also write power / clock gate / reset / OSC / PLL / divider
//       registers (0x008~0x090). Off by default, these really change chip behavior.
//   - RO fields driven by TB: 0x028/0x050/0x054/0x058 use rsim readback values,
//     other RO fields assume TB input = 0. Edit the expected value on the line directly.
//   - Registers are left with all RW bits = 1 after the test (default not restored).
//==============================================================================

task chip_top_task ;
begin
$display("at %t , SCU register check ---- Begin", $time);

// 0x000 SYS_CHIP_ID_REG1 (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h000 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h000 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h000 , 32'h0000_0000);

// 0x004 SYS_CHIP_ID_REG2 (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h004 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h004 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h004 , 32'h0000_0000);

// 0x008 POWER_CTRL : default = 32'h0000_0000, rw_mask = 32'h01FF_01FF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h0000_0000);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h008 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h008 , 32'h01FF_01FF);
`endif

// 0x00C SYSTEM_MODE_SEL (xip_en[16] defaults to 1) : default = 32'h0001_0005, rw_mask = 32'h0101_7305
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0001_0005);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h00C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h00C , 32'h0101_7305);
`endif

// 0x010 PLL_GATE : default = 32'h0000_0003, rw_mask = 32'h0000_0003
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0003);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h010 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h010 , 32'h0000_0003);
`endif

// 0x014 MAIN_IP_CLK_GATE0 : default = 32'hFFFF_FFFF, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h014 , 32'hFFFF_FFFF);
`endif

// 0x018 MAIN_IP_CLK_GATE1 : default = 32'h0000_7FFF, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_7FFF);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h018 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h018 , 32'h0000_FFFF);
`endif

// 0x01C SUB_IP_CLK_GATE : default = 32'h0001_FFFF, rw_mask = 32'h0001_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h01C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h01C , 32'h0001_FFFF);
`endif

// 0x020 AON_IP_CLK_GATE0 : default = 32'h0FFF_FFFF, rw_mask = 32'h0FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h020 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h020 , 32'h0FFF_FFFF);
`endif

// 0x024 AON_IP_CLK_GATE1 : default = 32'h0000_01FF, rw_mask = 32'h0000_01FF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h024 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h024 , 32'h0000_01FF);
`endif

// 0x028 PLL_LOCK (RO, TB dependent) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h028 , 32'h0000_0007);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h028 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h028 , 32'h0000_0007);

// 0x030 CPU/CHIP/SYS_RESET : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h030 , 32'h0000_0033);

// 0x034 MAIN_IP_RESET : default = 32'h03FD_07FF, rw_mask = 32'h03FD_07FF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h034 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h034 , 32'h03FD_07FF);
`endif

// 0x038 SUB_IP_RESET : default = 32'h0001_0103, rw_mask = 32'h0001_0103
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0001_0103);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h038 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h038 , 32'h0001_0103);
`endif

// 0x03C AON_IP_RESET : default = 32'h0000_00FF, rw_mask = 32'h0000_00FF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h03C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h03C , 32'h0000_00FF);
`endif

// 0x040 DDR_RESET : default = 32'h0000_0000, rw_mask = 32'h0000_03FF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_0000);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h040 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h040 , 32'h0000_03FF);
`endif

// 0x050 OSC_CTRL ([29:24] RO status) : default = 32'h3200_0701, rw_mask = 32'h0001_0703
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3200_0701);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h050 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h050 , 32'h3201_0703);
`endif

// 0x054 PLLSYS_CFG0 ([28:0] RO) : default = 32'hA155_5555, rw_mask = 32'hE000_0000
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'hA155_5555);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h054 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h054 , 32'hE155_5555);
`endif

// 0x058 PLLSYS_CFG1 (mostly RO) : default = 32'h0043_0053, rw_mask = 32'h8000_C000
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h0043_0053);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h058 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h058 , 32'h8043_C053);
`endif

// 0x05C PLLSYS_CFG2 : default = 32'h0169_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'h0169_0000);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h05C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h05C , 32'hFFFF_FFFF);
`endif

// 0x060 PLL_MFP_CFG0 : default = 32'h2100_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'h2100_0000);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h060 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h060 , 32'hFFFF_FFFF);
`endif

// 0x064 PLL_MFP_CFG1 : default = 32'h0052_307D, rw_mask = 32'hF777_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'h0052_307D);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h064 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h064 , 32'hF777_FFFF);
`endif

// 0x068 PLL_MFP_CFG2 : default = 32'h0169_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'h0169_0000);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h068 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h068 , 32'hFFFF_FFFF);
`endif

// 0x06C PLL_DDR_CFG0 : default = 32'hA100_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'hA100_0000);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h06C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h06C , 32'hFFFF_FFFF);
`endif

// 0x070 PLL_DDR_CFG1 : default = 32'h0075_3064, rw_mask = 32'hF777_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'h0075_3064);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h070 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h070 , 32'hF777_FFFF);
`endif

// 0x074 PLL_DDR_CFG2 : default = 32'h0169_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'h0169_0000);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h074 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h074 , 32'hFFFF_FFFF);
`endif

// 0x078 PLL_CLK_SEL / DIV_DDR1 : default = 32'h0000_000C, rw_mask = 32'h0000_73FF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_000C);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h078 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h078 , 32'h0000_73FF);
`endif

// 0x07C PLL_CONFIG_EN : default = 32'h0000_0000, rw_mask = 32'h0000_0007
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0000);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h07C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h07C , 32'h0000_0007);
`endif

// 0x080 DIV_CPU/MFP : default = 32'h1818_273B, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'h1818_273B);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h080 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h080 , 32'hFFFF_FFFF);
`endif

// 0x084 DIV_DDR0/TX/TX_BP/RX : default = 32'h2121_2127, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'h2121_2127);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h084 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h084 , 32'hFFFF_FFFF);
`endif

// 0x088 IP_CLK_DIV1 : default = 32'h1330_1010, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'h1330_1010);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h088 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h088 , 32'hFFFF_FFFF);
`endif

// 0x08C IP_CLK_DIV2 : default = 32'h4001_1111, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'h4001_1111);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h08C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h08C , 32'hFFFF_FFFF);
`endif

// 0x090 IP_CLK_DIV3 : default = 32'h0000_0002, rw_mask = 32'h1F00_0FFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h0000_0002);
`ifdef SCU_RW_SYS
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h090 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h090 , 32'h1F00_0FFF);
`endif

// 0x094 CPU_WFI (RO, TB dependent) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h094 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h094 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h094 , 32'h0000_0000);

// 0x098 DDR_PHY_JTAG ([8] RO TDO) : default = 32'h0000_0000, rw_mask = 32'h0001_000F
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h098 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h098 , 32'h0001_000F);

// 0x0A0 DDR_VER_PRJ : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A0 , 32'hFFFF_FFFF);

// 0x0A4 DDR_VER_DATE : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A4 , 32'hFFFF_FFFF);

// 0x0A8 DDR_IO_TEST0 : default = 32'h0000_0000, rw_mask = 32'h1E7F_BDEF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0A8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0A8 , 32'h1E7F_BDEF);

// 0x0AC DDR_IO_TEST1 : default = 32'h0000_0000, rw_mask = 32'h1EF3_FCFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0AC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0AC , 32'h1EF3_FCFF);

// 0x0B0 DDR_IO_TEST2 : default = 32'h0000_0000, rw_mask = 32'h3DEF_0FFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B0 , 32'h3DEF_0FFF);

// 0x0B4 DDR_IO_TEST3 : default = 32'h0000_0000, rw_mask = 32'h007F_9FEF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B4 , 32'h007F_9FEF);

// 0x0B8 A_DJ/A_ET : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0B8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0B8 , 32'hFFFF_FFFF);

// 0x0BC A_OJ/A_SJ : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0BC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0BC , 32'hFFFF_FFFF);

// 0x0C0 DQ_DJ / A_DT(RO) : default = 32'h0000_0000, rw_mask = 32'hFFFF_0000
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C0 , 32'hFFFF_0000);

// 0x0C4 DQ_ET/DQ_OJ : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C4 , 32'hFFFF_FFFF);

// 0x0C8 DQ_SJ / DQ_DT(RO) : default = 32'h0000_0000, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0C8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0C8 , 32'h0000_FFFF);

// 0x0CC DM/DTO/RET_EN : default = 32'h0200_0000, rw_mask = 32'h0303_FCFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0200_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0CC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0CC , 32'h0303_FCFF);

// 0x0D8 U3DEV_CFG_0 : default = 32'h1E13_4000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D8 , 32'hFFFF_FFFF);

// 0x0DC U3DEV_CFG_1 : default = 32'h0027_F71C, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0DC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0DC , 32'hFFFF_FFFF);

// 0x0E0 U3DEV_CFG_2 : default = 32'h3920_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E0 , 32'hFFFF_FFFF);

// 0x0E4 U3DEV_CFG_3 : default = 32'h2101_8933, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E4 , 32'h7FFF_FFFF);

// 0x0E8 U3DEV_CFG_4 : default = 32'h0000_0000, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0E8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0E8 , 32'h0000_FFFF);

// 0x0F0 U3DEV_CFG_5 : default = 32'h4734_5508, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h4734_5508);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F0 , 32'h7FFF_FFFF);

// 0x0F4 U3DEV_LA_TRACE0 (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F4 , 32'h0000_0000);

// 0x0F8 U3DEV_LA_TRACE1 (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0F8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0F8 , 32'h0000_0000);

// 0x0FC U3HOST0_CFG_0 : default = 32'h1E13_4000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0FC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0FC , 32'hFFFF_FFFF);

// 0x100 U3HOST0_CFG_1 : default = 32'h0027_F71C, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h100 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h100 , 32'hFFFF_FFFF);

// 0x104 U3HOST0_CFG_2 : default = 32'h3920_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'h3920_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h104 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h104 , 32'hFFFF_FFFF);

// 0x108 U3HOST0_CFG_3 : default = 32'h2101_8933, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h108 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h108 , 32'h7FFF_FFFF);

// 0x10C U3HOST0_CFG_4 : default = 32'h0000_0000, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h10C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h10C , 32'h0000_FFFF);

// 0x110 U3HOST0_CFG_5 (clkdiv2=1, commononn=0) : default = 32'h2134_5508, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h110 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h110 , 32'h7FFF_FFFF);

// 0x114 U3HOST0_LA_TRACE0 (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h114 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h114 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h114 , 32'h0000_0000);

// 0x118 U3HOST0_LA_TRACE1 (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h118 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h118 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h118 , 32'h0000_0000);

// 0x11C U3HOST1_LA_TRACE0 (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h11C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h11C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h11C , 32'h0000_0000);

// 0x120 U3HOST1_LA_TRACE1 (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h120 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h120 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h120 , 32'h0000_0000);

// 0x124 U3DEV_OBS_SIGNAL (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h124 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h124 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h124 , 32'h0000_0000);

// 0x128 U3DEV_OBS_CRDATA (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h128 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h128 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h128 , 32'h0000_0000);

// 0x12C U3DEV_OBS_CLK (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h12C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h12C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h12C , 32'h0000_0000);

// 0x130 LVDS_TX0_MUX0 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h130 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h130 , 32'h3FFF_FFFF);

// 0x134 LVDS_TX0_MUX1 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h134 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h134 , 32'h3FFF_FFFF);

// 0x138 LVDS_TX0_MUX2 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h138 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h138 , 32'h3FFF_FFFF);

// 0x13C LVDS_TX0_MUX3 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h13C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h13C , 32'h3FFF_FFFF);

// 0x140 LVDS_TX0_MUX4 : default = 32'h0000_0000, rw_mask = 32'h000F_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h140 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h140 , 32'h000F_FFFF);

// 0x144 LVDS_TX1_MUX0 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h144 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h144 , 32'h3FFF_FFFF);

// 0x148 LVDS_TX1_MUX1 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h148 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h148 , 32'h3FFF_FFFF);

// 0x14C LVDS_TX1_MUX2 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h14C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h14C , 32'h3FFF_FFFF);

// 0x150 LVDS_TX1_MUX3 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h150 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h150 , 32'h3FFF_FFFF);

// 0x154 LVDS_TX1_MUX4 : default = 32'h0000_0000, rw_mask = 32'h000F_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h154 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h154 , 32'h000F_FFFF);

// 0x158 LVDS_RX0_MUX0 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h158 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h158 , 32'h3FFF_FFFF);

// 0x15C LVDS_RX0_MUX1 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h15C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h15C , 32'h3FFF_FFFF);

// 0x160 LVDS_RX0_MUX2 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h160 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h160 , 32'h3FFF_FFFF);

// 0x164 LVDS_RX0_MUX3 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h164 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h164 , 32'h3FFF_FFFF);

// 0x168 LVDS_RX0_MUX4 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h168 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h168 , 32'h3FFF_FFFF);

// 0x16C LVDS_RX0_MUX5 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h16C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h16C , 32'h3FFF_FFFF);

// 0x170 LVDS_RX0_MUX6 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h170 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h170 , 32'h3FFF_FFFF);

// 0x174 LVDS_RX1_MUX0 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h174 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h174 , 32'h3FFF_FFFF);

// 0x178 LVDS_RX1_MUX1 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h178 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h178 , 32'h3FFF_FFFF);

// 0x17C LVDS_RX1_MUX2 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h17C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h17C , 32'h3FFF_FFFF);

// 0x180 LVDS_RX1_MUX3 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h180 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h180 , 32'h3FFF_FFFF);

// 0x184 LVDS_RX1_MUX4 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h184 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h184 , 32'h3FFF_FFFF);

// 0x188 LVDS_RX1_MUX5 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h188 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h188 , 32'h3FFF_FFFF);

// 0x18C LVDS_RX1_MUX6 : default = 32'h0000_0000, rw_mask = 32'h3FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h18C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h18C , 32'h3FFF_FFFF);

// 0x190 LVDS_TX0_CTRL ([25:24] RO) : default = 32'h0000_0000, rw_mask = 32'h04FF_FFF3
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h190 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h190 , 32'h04FF_FFF3);

// 0x194 LVDS_TX0_PRBS_SEED : default = 32'h0000_0000, rw_mask = 32'h7F7F_7F7F
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h194 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h194 , 32'h7F7F_7F7F);

// 0x198 LVDS_TX1_CTRL ([27:26] RO) : default = 32'h0000_0000, rw_mask = 32'h13FF_FFF3
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h198 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h198 , 32'h13FF_FFF3);

// 0x19C LVDS_TX1_PRBS_SEED : default = 32'h0000_0000, rw_mask = 32'h7F7F_7F7F
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h19C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h19C , 32'h7F7F_7F7F);

// 0x1A0 LVDS_RX_PRBS_CTRL : default = 32'h0000_0000, rw_mask = 32'h0000_0303
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A0 , 32'h0000_0303);

// 0x1B4 GMAC_PHY_CTRL ([13:8] RO) : default = 32'h0000_0000, rw_mask = 32'h0000_003F
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B4 , 32'h0000_003F);

// 0x1B8 GMAC_DELAY_CHAIN_CTRL : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B8 , 32'h0000_0000);

// 0x1BC TEN_S_TIME : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1BC , 32'h0000_0000);

// 0x1C0 RGMII_DLY_DEFAULT0 : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1C0 , 32'h0000_0000);

// 0x1C4 RGMII_DLY_DEFAULT1 : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1C4 , 32'h0000_0000);

// 0x1C8 RGMII_TX_DLY_TARGET : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1C8 , 32'h0000_0000);

// 0x1CC RGMII_RX_DLY_TARGET : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1CC , 32'h0000_0000);

// 0x1E0 DLY_CLK_CYCLE_RPT (RO) : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1E0 , 32'h0000_0000);

// 0x1E4 RGMII_CAL (RO) : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1E4 , 32'h0000_0000);

// 0x1E8 RGMII_DLY_ACTUAL (RO) : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1E8 , 32'h0000_0000);

// 0x1EC GMAC_DPRAM_CFG : default = 32'h0208_0208, rw_mask = 32'h1FFF_1FFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h0208_0208);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1EC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1EC , 32'h1FFF_1FFF);

// 0x1F0 BREATHE_REG : default = 32'h0000_0000, rw_mask = 32'h0FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F0 , 32'h0FFF_FFFF);

// 0x1F4 U3HOST1_CFG_0 : default = 32'h1E13_4000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'h1E13_4000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F4 , 32'hFFFF_FFFF);

// 0x1F8 U3HOST1_CFG_1 : default = 32'h0027_F71C, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'h0027_F71C);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1F8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1F8 , 32'hFFFF_FFFF);

// 0x1FC U3HOST1_CFG_2 : default = 32'h3920_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'h3920_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1FC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1FC , 32'hFFFF_FFFF);

// 0x200 U3HOST1_CFG_3 : default = 32'h2101_8933, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h2101_8933);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h200 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h200 , 32'h7FFF_FFFF);

// 0x204 U3HOST1_CFG_4 : default = 32'h0000_0000, rw_mask = 32'h0000_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h204 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h204 , 32'h0000_FFFF);

// 0x208 U3HOST1_CFG_5 : default = 32'h2134_5508, rw_mask = 32'h7FFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h2134_5508);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h208 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h208 , 32'h7FFF_FFFF);

// 0x20C U3HOST0_OBS_SIGNAL (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h20C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h20C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h20C , 32'h0000_0000);

// 0x210 U3HOST0_OBS_CRDATA (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h210 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h210 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h210 , 32'h0000_0000);

// 0x214 U3HOST0_OBS_CLK (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h214 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h214 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h214 , 32'h0000_0000);

// 0x218 U3HOST1_OBS_SIGNAL (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h218 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h218 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h218 , 32'h0000_0000);

// 0x21C U3HOST1_OBS_CRDATA (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h21C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h21C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h21C , 32'h0000_0000);

// 0x220 U3HOST1_OBS_CLK (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h220 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h220 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h220 , 32'h0000_0000);

// 0x230 EMMC_DELAY_CHAIN_CTRL : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h230 , 32'h0000_0102);

// 0x234 EMMC_TEN_S_TIME : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h234 , 32'h0000_0000);

// 0x238 EMMC_DLY_DEFAULT0 : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h238 , 32'h0000_0000);

// 0x23C EMMC_DLY_DEFAULT1 : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h23C , 32'h0000_0000);

// 0x240 EMMC_CLK_OUT_DLY_TARGET : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h240 , 32'h0000_0000);

// 0x244 EMMC_STB_IN_DLY_TARGET : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h244 , 32'h0000_0000);

// 0x248 EMMC_DLY_CLK_CYCLE_RPT (RO) : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h248 , 32'h0000_0000);

// 0x24C EMMC_CAL_STAT (RO) : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h24C , 32'h0000_0000);

// 0x250 EMMC_DLY_ACTUAL (RO) : read default only, never written
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h250 , 32'h0000_0000);

// 0x254 AHB_MAIN_BUS_TIMEOUT_CTRL : default = 32'h0000_0000, rw_mask = 32'h007F_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h254 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h254 , 32'h007F_FFFF);

// 0x258 AHB_MAIN_BUS_TIMEOUT_INT (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h258 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h258 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h258 , 32'h0000_0000);

// 0x25C AHB_MAIN_BUS_TIMEOUT_ADDR (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h25C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h25C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h25C , 32'h0000_0000);

// 0x260 AHB_SUB_BUS_TIMEOUT_CTRL : default = 32'h0000_0000, rw_mask = 32'h000F_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h260 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h260 , 32'h000F_FFFF);

// 0x264 AHB_SUB_BUS_TIMEOUT_INT (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h264 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h264 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h264 , 32'h0000_0000);

// 0x268 AHB_SUB_BUS_TIMEOUT_ADDR (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h268 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h268 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h268 , 32'h0000_0000);

// 0x26C APB_MAIN_BUS_TIMEOUT_CTRL : default = 32'h0000_0000, rw_mask = 32'h003F_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h26C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h26C , 32'h003F_FFFF);

// 0x270 APB_MAIN_BUS_TIMEOUT_INT (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h270 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h270 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h270 , 32'h0000_0000);

// 0x274 APB_MAIN_BUS_TIMEOUT_ADDR (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h274 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h274 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h274 , 32'h0000_0000);

// 0x278 APB_AON_BUS_TIMEOUT_CTRL : default = 32'h0000_0000, rw_mask = 32'h003F_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h278 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h278 , 32'h003F_FFFF);

// 0x27C APB_AON_BUS_TIMEOUT_INT (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h27C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h27C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h27C , 32'h0000_0000);

// 0x280 APB_AON_BUS_TIMEOUT_ADDR (RO) : read only
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h280 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h280 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h280 , 32'h0000_0000);

// 0x2C0 SW_CFG_REG_0 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C0 , 32'hFFFF_FFFF);

// 0x2C4 SW_CFG_REG_1 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C4 , 32'hFFFF_FFFF);

// 0x2C8 SW_CFG_REG_2 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2C8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2C8 , 32'hFFFF_FFFF);

// 0x2CC SW_CFG_REG_3 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2CC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2CC , 32'hFFFF_FFFF);

// 0x2D0 SW_CFG_REG_4 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D0 , 32'hFFFF_FFFF);

// 0x2D4 SW_CFG_REG_5 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D4 , 32'hFFFF_FFFF);

// 0x2D8 SW_CFG_REG_6 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2D8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2D8 , 32'hFFFF_FFFF);

// 0x2DC SW_CFG_REG_7 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2DC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2DC , 32'hFFFF_FFFF);

// 0x2E0 SW_CFG_REG_8 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E0 , 32'hFFFF_FFFF);

// 0x2E4 SW_CFG_REG_9 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E4 , 32'hFFFF_FFFF);

// 0x2E8 SW_CFG_REG_10 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2E8 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2E8 , 32'hFFFF_FFFF);

// 0x2EC SW_CFG_REG_11 : default = 32'h0000_0000, rw_mask = 32'hFFFF_FFFF
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2EC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2EC , 32'hFFFF_FFFF);

// undefined addresses (holes) : write all 1s, read back must be 0
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h02C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h02C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h044 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h044 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h04C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h04C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h09C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h09C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0D4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0D4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h0EC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h0EC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1A4 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1A4 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1B0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1B0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1D0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1D0 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h1DC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h1DC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h224 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h224 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h22C , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h22C , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h284 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h284 , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2BC , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2BC , 32'h0000_0000);
        es_spi_master.ES_SPI_WR(32'ha000_c000 + 32'h2F0 , 32'hFFFF_FFFF);
        es_spi_master.ES_SPI_RD(32'ha000_c000 + 32'h2F0 , 32'h0000_0000);

$display("at %t , SCU register check ---- End", $time);
end
endtask
