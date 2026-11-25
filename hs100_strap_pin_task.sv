// =============================================================================
// HS100 Strap Pin register test pattern
// Source : HS100_Strap_Pin_Datasheet20261125.docx
// BASE   : 32'hA000_C400
//   0x00 STR_BOOT_REG  RW  [3:0]  BOOT_EMMC/BOOT_NOR_NAND/BOOT_UART/BOOT_USB_DEV
//   0x04 STR_CLK_REG   RW  [2:1]  EMMC_BOOT_RX_CLK_INV/EMMC_BOOT_TX_CLK_INV ([0] rsvd)
//   0x08 STR_MODE_REG  RW  [4:1]  WORK_MODE[2:0]/FUNC_MODE              ([0] rsvd)
//   0x0C STR_PIN_TRIG  W1S [7:0]  HW self-clear
//   0x10 STR_BOOT_RPT  RO  default 0x00
//   0x14 STR_CLK_RPT   RO  default 0x01 (CLK_PLL_OSC=1, CPU_SPEED_SEL=00)
//   0x18 STR_MODE_RPT  RO  default 0x1E (WORK_MODE=7, FUNC_MODE=1, TEST_MODE=0)
// Assumption: all strap pins at default level (no external strap driven by TB).
// read format: a45_io_read32b(base, offset, mask, expect)
// =============================================================================
task chip_top_task ;
begin
//------------------------------------------------------------------
// 1. Reset default value check
//------------------------------------------------------------------
a45_io_read32b (32'ha000_c400, 32'h00, 32'hffff_ffff, 32'h0000_0000 ); // STR_BOOT_REG
a45_io_read32b (32'ha000_c400, 32'h04, 32'hffff_ffff, 32'h0000_0000 ); // STR_CLK_REG
a45_io_read32b (32'ha000_c400, 32'h08, 32'hffff_ffff, 32'h0000_0000 ); // STR_MODE_REG
a45_io_read32b (32'ha000_c400, 32'h0c, 32'hffff_ffff, 32'h0000_0000 ); // STR_PIN_TRIG
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0000 ); // STR_BOOT_RPT
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0001 ); // STR_CLK_RPT
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e ); // STR_MODE_RPT

//------------------------------------------------------------------
// 2. RW register access (no TRIG -> effective value must NOT change)
//    mask = valid bits only (reserved bits read-back not defined in spec)
//------------------------------------------------------------------
// all 1
a45_io_write32b(32'ha000_c400, 32'h00, 32'hffff_ffff );
a45_io_write32b(32'ha000_c400, 32'h04, 32'hffff_ffff );
a45_io_write32b(32'ha000_c400, 32'h08, 32'hffff_ffff );
a45_io_read32b (32'ha000_c400, 32'h00, 32'h0000_000f, 32'h0000_000f );
a45_io_read32b (32'ha000_c400, 32'h04, 32'h0000_0006, 32'h0000_0006 );
a45_io_read32b (32'ha000_c400, 32'h08, 32'h0000_001e, 32'h0000_001e );
// 0101 pattern
a45_io_write32b(32'ha000_c400, 32'h00, 32'h5555_5555 );
a45_io_write32b(32'ha000_c400, 32'h04, 32'h5555_5555 );
a45_io_write32b(32'ha000_c400, 32'h08, 32'h5555_5555 );
a45_io_read32b (32'ha000_c400, 32'h00, 32'h0000_000f, 32'h0000_0005 );
a45_io_read32b (32'ha000_c400, 32'h04, 32'h0000_0006, 32'h0000_0004 );
a45_io_read32b (32'ha000_c400, 32'h08, 32'h0000_001e, 32'h0000_0014 );
// 1010 pattern
a45_io_write32b(32'ha000_c400, 32'h00, 32'haaaa_aaaa );
a45_io_write32b(32'ha000_c400, 32'h04, 32'haaaa_aaaa );
a45_io_write32b(32'ha000_c400, 32'h08, 32'haaaa_aaaa );
a45_io_read32b (32'ha000_c400, 32'h00, 32'h0000_000f, 32'h0000_000a );
a45_io_read32b (32'ha000_c400, 32'h04, 32'h0000_0006, 32'h0000_0002 );
a45_io_read32b (32'ha000_c400, 32'h08, 32'h0000_001e, 32'h0000_000a );
// effective value unchanged (no TRIG yet)
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0001 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );
// all 0
a45_io_write32b(32'ha000_c400, 32'h00, 32'h0000_0000 );
a45_io_write32b(32'ha000_c400, 32'h04, 32'h0000_0000 );
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h00, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h04, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h08, 32'hffff_ffff, 32'h0000_0000 );

//------------------------------------------------------------------
// 3. RO register write check (write must be ignored)
//------------------------------------------------------------------
a45_io_write32b(32'ha000_c400, 32'h10, 32'hffff_ffff );
a45_io_write32b(32'ha000_c400, 32'h14, 32'h0000_0000 );
a45_io_write32b(32'ha000_c400, 32'h18, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0001 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );

//------------------------------------------------------------------
// 4. BOOT strap : per-bit TRIG (only the triggered bit is loaded)
//    NOTE: if TRIG clear needs several REF_CLK cycles, add delay
//          between TRIG write and TRIG read.
//------------------------------------------------------------------
a45_io_write32b(32'ha000_c400, 32'h00, 32'h0000_000f );                  // target = 4'b1111
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0001 );                  // TRIG BOOT_USB_DEV
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );   // TRIG self-clear
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0001 );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0002 );                  // TRIG BOOT_UART
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0003 );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0004 );                  // TRIG BOOT_NOR_NAND
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0007 );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0008 );                  // TRIG BOOT_EMMC
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_000f );
// other RPT not affected
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0001 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );

// multi-bit TRIG with pattern 4'b1010
a45_io_write32b(32'ha000_c400, 32'h00, 32'h0000_000a );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_000f );
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_000a );

// write 0 to TRIG has no effect
a45_io_write32b(32'ha000_c400, 32'h00, 32'h0000_0005 );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_000a );   // still old value
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_000f );
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0005 );

// restore BOOT default
a45_io_write32b(32'ha000_c400, 32'h00, 32'h0000_0000 );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_000f );
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0000 );

//------------------------------------------------------------------
// 5. CLK strap : EMMC_BOOT_TX/RX_CLK_INV reconfig,
//    CLK_PLL_OSC / CPU_SPEED_SEL must NOT be changed by software
//------------------------------------------------------------------
a45_io_write32b(32'ha000_c400, 32'h04, 32'h0000_0006 );                  // TX_INV=1, RX_INV=1, bit0=0
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0010 );                  // TRIG TX_CLK_INV
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0003 );   // PLL_OSC=1, TX=1
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0020 );                  // TRIG RX_CLK_INV
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0007 );   // PLL_OSC=1, TX=1, RX=1

// try to clear CLK_PLL_OSC via reserved bit0 + all TRIG bits -> PLL_OSC stays 1
a45_io_write32b(32'ha000_c400, 32'h04, 32'h0000_0000 );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0030 );
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0001 );
// try to set CPU_SPEED_SEL via write -> stays 00
a45_io_write32b(32'ha000_c400, 32'h04, 32'h0000_0018 );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0030 );
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0001 );
a45_io_write32b(32'ha000_c400, 32'h04, 32'h0000_0000 );
// other RPT not affected
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );

//------------------------------------------------------------------
// 6. MODE strap : TEST_MODE must NOT be changed by software
//    (keep WORK_MODE/FUNC_MODE = default, only set reserved bit0)
//------------------------------------------------------------------
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_001f );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_00c0 );
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );   // TEST_MODE stays 0

//------------------------------------------------------------------
// 7. MODE strap : WORK_MODE reconfig (ES mode select)
//------------------------------------------------------------------
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_0000 );                  // WORK=000, FUNC=0
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0080 );                  // TRIG WORK_MODE only
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_0002 );   // WORK=000, FUNC keep 1
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_0014 );                  // WORK=101
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0080 );
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_0016 );
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_0008 );                  // WORK=010
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0080 );
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_000a );
// restore WORK_MODE=111
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_001e );
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0080 );
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );

//------------------------------------------------------------------
// 8. MODE strap : FUNC_MODE reconfig
//    FUNC_MODE=0 -> AIP/MBIST test mode, may affect system; enable by define
//------------------------------------------------------------------
`ifdef STRAP_FUNC_MODE_TEST
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_001c );                  // FUNC=0, WORK=111
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0040 );                  // TRIG FUNC_MODE only
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001c );
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_001e );                  // restore FUNC=1
a45_io_write32b(32'ha000_c400, 32'h0c, 32'h0000_0040 );
a45_io_read32b (32'ha000_c400, 32'h0c, 32'h0000_00ff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );
`endif

//------------------------------------------------------------------
// 9. Final check : all effective values back to default
//------------------------------------------------------------------
a45_io_write32b(32'ha000_c400, 32'h08, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h00, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h04, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h08, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h0c, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h10, 32'hffff_ffff, 32'h0000_0000 );
a45_io_read32b (32'ha000_c400, 32'h14, 32'hffff_ffff, 32'h0000_0001 );
a45_io_read32b (32'ha000_c400, 32'h18, 32'hffff_ffff, 32'h0000_001e );

end
endtask
