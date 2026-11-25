// =============================================================================
// HS100 Strap Pin register test pattern
// Source : HS100_Strap_Pin_Datasheet20261125.docx (+ update 2026-11-25)
// BASE   : 32'hA000_C400
//   0x00 STR_BOOT_REG  RW  [3:0]  BOOT_EMMC/BOOT_NOR_NAND/BOOT_UART/BOOT_USB_DEV
//   0x04 STR_CLK_REG   RW  [2:1]  EMMC_BOOT_RX_CLK_INV/EMMC_BOOT_TX_CLK_INV ([0] rsvd)
//   0x08 STR_MODE_REG  RW  [4:2]  WORK_MODE[2:0]                ([1:0] rsvd)
//   0x0C STR_PIN_TRIG  W1S [7],[5:0]  HW self-clear              ([6] rsvd)
//   0x10 STR_BOOT_RPT  RO  default 0x00
//   0x14 STR_CLK_RPT   RO  default 0x00 (CLK_PLL_OSC=0, CPU_SPEED_SEL=00)
//   0x18 STR_MODE_RPT  RO  default 0x1E (WORK_MODE[4:2]=111, FUNC_MODE[1]=1, TEST_MODE[0]=0)
// CLK_PLL_OSC / FUNC_MODE / TEST_MODE / CPU_SPEED_SEL : NOT software configurable
// Assumption: all strap pins at default level (no external strap driven by TB).
// read format: a45_io_read32b(base, offset, mask, expect)
// =============================================================================
// wait time after writing STR_PIN_TRIG before checking self-clear
// (unit follows the timescale of the file that includes this task)
`ifndef STRAP_TRIG_DLY
  `define STRAP_TRIG_DLY 1000
`endif

task chip_top_task ;
begin
//==================================================================
// 1. Reset default value check
//==================================================================
$display("at %t, [STRAP] ===== 1. Reset default value check =====", $realtime);
$display("at %t, [STRAP] 1.1 STR_BOOT_REG/CLK_REG/MODE_REG/PIN_TRIG default = 0", $realtime);
a45_io_read32b (32'ha000_c400, 32'h00, 32'hffff_ffff, 32'h0000_0000 ); // STR_BOOT_REG
a45_io_read32b (32'ha000_c400, 32'h04, 32'hffff_ffff, 32'h0000_0000 ); // STR_CLK_REG
a45_io_read32b (32'ha000_c400, 32'h08, 32'hffff_ffff, 32'h0000_0000 ); // STR_MODE_REG
a45_io_read32b (32'ha000_c400, 32'h0c, 32'hffff_ffff, 32'h0000_0000 ); // STR_PIN_TRIG
$display("at %t, [STRAP] 1.2 STR_BOOT_RPT=0x00, STR_CLK_RPT=0x00 (PLL_OSC=0,CPU_SPEED=00), STR_MODE_RPT=0x1E (WORK=111,FUNC=1,TEST=0)", $realtime);
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0000 ); // STR_BOOT_RPT
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0000 ); // STR_CLK_RPT
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e ); // STR_MODE_RPT

//==================================================================
// 2. RW register access (no TRIG -> effective value must NOT change)
//    mask = valid bits only (reserved bits read-back not defined in spec)
//==================================================================
$display("at %t, [STRAP] ===== 2. RW register access =====", $realtime);
$display("at %t, [STRAP] 2.1 write all 1 -> BOOT_REG[3:0]=F, CLK_REG[2:1]=11, MODE_REG[4:2]=111", $realtime);
a45_io_write32b(32'ha000_c400, 32'h00, 32'hffff_ffff );
a45_io_write32b(32'ha000_c400, 32'h04, 32'hffff_ffff );
a45_io_write32b(32'ha000_c400, 32'h08, 32'hffff_ffff );
a45_io_read32b (32'ha000_c400, 32'h00, 32'h0000_000f, 32'h0000_000f );
a45_io_read32b (32'ha000_c400, 32'h04, 32'h0000_0006, 32'h0000_0006 );
a45_io_read32b (32'ha000_c400, 32'h08, 32'h0000_001c, 32'h0000_001c );
$display("at %t, [STRAP] 2.2 write 0x5555_5555 -> BOOT_REG=5, CLK_REG=4, MODE_REG=14", $realtime);
a45_io_write32b(32'ha000_c400, 32'h00, 32'h5555_5555 );
a45_io_write32b(32'ha000_c400, 32'h04, 32'h5555_5555 );
a45_io_write32b(32'ha000_c400, 32'h08, 32'h5555_5555 );
a45_io_read32b (32'ha000_c400, 32'h00, 32'h0000_000f, 32'h0000_0005 );
a45_io_read32b (32'ha000_c400, 32'h04, 32'h0000_0006, 32'h0000_0004 );
a45_io_read32b (32'ha000_c400, 32'h08, 32'h0000_001c, 32'h0000_0014 );
$display("at %t, [STRAP] 2.3 write 0xAAAA_AAAA -> BOOT_REG=A, CLK_REG=2, MODE_REG=08", $realtime);
a45_io_write32b(32'ha000_c400, 32'h00, 32'haaaa_aaaa );
a45_io_write32b(32'ha000_c400, 32'h04, 32'haaaa_aaaa );
a45_io_write32b(32'ha000_c400, 32'h08, 32'haaaa_aaaa );
a45_io_read32b (32'ha000_c400, 32'h00, 32'h0000_000f, 32'h0000_000a );
a45_io_read32b (32'ha000_c400, 32'h04, 32'h0000_0006, 32'h0000_0002 );
a45_io_read32b (32'ha000_c400, 32'h08, 32'h0000_001c, 32'h0000_0008 );
$display("at %t, [STRAP] 2.4 no TRIG -> RPT keep default (00/00/1E)", $realtime);
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );
$display("at %t, [STRAP] 2.5 write all 0 -> BOOT/CLK/MODE_REG = 0", $realtime);
a45_io_write32b(32'ha000_c400, 32'h00, 32'h0000_0000 );
a45_io_write32b(32'ha000_c400, 32'h04, 32'h0000_0000 );
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h00, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h04, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h08, 32'hffff_ffff, 32'h0000_0000 );

//==================================================================
// 3. RO register write check (write must be ignored)
//==================================================================
$display("at %t, [STRAP] ===== 3. RO register write check: write RPT, expect no change (00/00/1E) =====", $realtime);
a45_io_write32b(32'ha000_c400, 32'h10, 32'hffff_ffff );
a45_io_write32b(32'ha000_c400, 32'h14, 32'hffff_ffff );
a45_io_write32b(32'ha000_c400, 32'h18, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );

//==================================================================
// 4. BOOT strap : per-bit TRIG (only the triggered bit is loaded)
//==================================================================
$display("at %t, [STRAP] ===== 4. BOOT strap TRIG test =====", $realtime);
$display("at %t, [STRAP] 4.0 BOOT_REG = 4'b1111 (target)", $realtime);
a45_io_write32b(32'ha000_c400, 32'h00, 32'h0000_000f );
$display("at %t, [STRAP] 4.1 TRIG[0] BOOT_USB_DEV -> BOOT_RPT=0x1", $realtime);
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0001 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );   // TRIG self-clear
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0001 );
$display("at %t, [STRAP] 4.2 TRIG[1] BOOT_UART -> BOOT_RPT=0x3", $realtime);
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0002 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0003 );
$display("at %t, [STRAP] 4.3 TRIG[2] BOOT_NOR_NAND -> BOOT_RPT=0x7", $realtime);
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0004 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0007 );
$display("at %t, [STRAP] 4.4 TRIG[3] BOOT_EMMC -> BOOT_RPT=0xF", $realtime);
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0008 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_000f );
$display("at %t, [STRAP] 4.5 CLK_RPT / MODE_RPT not affected (00/1E)", $realtime);
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );

$display("at %t, [STRAP] 4.6 BOOT_REG=0xA, TRIG[3:0] together -> BOOT_RPT=0xA", $realtime);
a45_io_write32b(32'ha000_c400, 32'h00, 32'h0000_000a );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_000f );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_000a );

$display("at %t, [STRAP] 4.7 BOOT_REG=0x5, write TRIG=0 (no effect) -> BOOT_RPT keep 0xA", $realtime);
a45_io_write32b(32'ha000_c400, 32'h00, 32'h0000_0005 );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0000 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_000a );
$display("at %t, [STRAP] 4.8 TRIG[3:0] -> BOOT_RPT=0x5", $realtime);
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_000f );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0005 );

$display("at %t, [STRAP] 4.9 restore BOOT default -> BOOT_RPT=0x0", $realtime);
a45_io_write32b(32'ha000_c400, 32'h00, 32'h0000_0000 );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_000f );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0000 );

//==================================================================
// 5. CLK strap : EMMC_BOOT_TX/RX_CLK_INV reconfig,
//    CLK_PLL_OSC / CPU_SPEED_SEL must NOT be changed by software
//==================================================================
$display("at %t, [STRAP] ===== 5. CLK strap TRIG test =====", $realtime);
$display("at %t, [STRAP] 5.0 CLK_REG = 0x6 (TX_INV=1, RX_INV=1)", $realtime);
a45_io_write32b(32'ha000_c400, 32'h04, 32'h0000_0006 );
$display("at %t, [STRAP] 5.1 TRIG[4] EMMC_BOOT_TX_CLK_INV -> CLK_RPT=0x2", $realtime);
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0010 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0002 );
$display("at %t, [STRAP] 5.2 TRIG[5] EMMC_BOOT_RX_CLK_INV -> CLK_RPT=0x6", $realtime);
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0020 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0006 );

$display("at %t, [STRAP] 5.3 CLK_REG=0x1 (try PLL_OSC=1), TRIG[5:4] -> CLK_RPT=0x0 (PLL_OSC stays 0)", $realtime);
a45_io_write32b(32'ha000_c400, 32'h04, 32'h0000_0001 );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0030 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0000 );
$display("at %t, [STRAP] 5.4 CLK_REG=0x19 (try CPU_SPEED=11,PLL_OSC=1), TRIG[5:4] -> CLK_RPT=0x0", $realtime);
a45_io_write32b(32'ha000_c400, 32'h04, 32'h0000_0019 );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0030 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0000 );
a45_io_write32b(32'ha000_c400, 32'h04, 32'h0000_0000 );
$display("at %t, [STRAP] 5.5 BOOT_RPT / MODE_RPT not affected (00/1E)", $realtime);
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );

//==================================================================
// 6. MODE strap : FUNC_MODE / TEST_MODE must NOT be changed by software
//==================================================================
$display("at %t, [STRAP] ===== 6. FUNC_MODE/TEST_MODE not SW configurable =====", $realtime);
$display("at %t, [STRAP] 6.1 MODE_REG=0x1D (WORK=111,try FUNC=0,TEST=1), TRIG[7:6] -> MODE_RPT=0x1E", $realtime);
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_001d );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_00c0 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );
$display("at %t, [STRAP] 6.2 MODE_REG=0x1F (WORK=111,FUNC=1,try TEST=1), TRIG[7:6] -> MODE_RPT=0x1E", $realtime);
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_001f );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_00c0 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );

//==================================================================
// 7. MODE strap : WORK_MODE reconfig (ES mode select)
//==================================================================
$display("at %t, [STRAP] ===== 7. WORK_MODE TRIG test =====", $realtime);
$display("at %t, [STRAP] 7.1 WORK_MODE=000, TRIG[7] -> MODE_RPT=0x02", $realtime);
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_0000 );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0080 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_0002 );
$display("at %t, [STRAP] 7.2 WORK_MODE=101, TRIG[7] -> MODE_RPT=0x16", $realtime);
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_0014 );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0080 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_0016 );
$display("at %t, [STRAP] 7.3 WORK_MODE=010, TRIG[7] -> MODE_RPT=0x0A", $realtime);
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_0008 );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0080 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_000a );
$display("at %t, [STRAP] 7.4 restore WORK_MODE=111, TRIG[7] -> MODE_RPT=0x1E", $realtime);
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_001c );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0080 );
#(`STRAP_TRIG_DLY);
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );

//==================================================================
// 8. Final check : all registers back to default
//==================================================================
$display("at %t, [STRAP] ===== 8. Final check: all registers back to default =====", $realtime);
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h00, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h04, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h08, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h0c, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );
$display("at %t, [STRAP] ===== Strap pin register test done =====", $realtime);

end
endtask
