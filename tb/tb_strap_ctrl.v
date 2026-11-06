`timescale 1ns/1ps
//==============================================================================
// Testbench for strap_ctrl
//   T1: PAD_RSTJ released BEFORE MAIN power-up (ISO clamping) -> real value captured
//   T2: MAIN power cycle after capture, pads driven by function -> value kept
//   T3: PAD_RSTJ re-asserted -> cleared and re-captured with new value
//   T4: glitch on pad during confirm window -> restarts, captures stable value
//   T5: ISO drops during settle -> restart, no capture of clamp value
//   T6: MAIN never powers up -> strap_timeout set, strap_done stays 0
//   T7: AON_POR -> clears everything
//==============================================================================
module tb_strap_ctrl;

localparam W = 8;
localparam [W-1:0] CLAMP = 8'h00;     // ISO clamp value

reg          aon_clk = 0;
reg          aon_por_n = 0;
reg          pad_rstj_n = 0;
reg          main_pwr_ok = 0, sub_pwr_ok = 0;
reg          iso_main_en = 1, iso_sub_en = 1;
reg  [W-1:0] pad_real = 8'h00;        // value on the board
reg  [W-1:0] glitch   = 8'h00;
wire [W-1:0] strap_pad_in;
wire [W-1:0] strap_val;
wire         strap_done, strap_lock, strap_timeout;

// pads 0..3 = MAIN, 4..5 = SUB, 6..7 = AON
assign strap_pad_in[3:0] = iso_main_en ? CLAMP[3:0] : (pad_real[3:0] ^ glitch[3:0]);
assign strap_pad_in[5:4] = iso_sub_en  ? CLAMP[5:4] : (pad_real[5:4] ^ glitch[5:4]);
assign strap_pad_in[7:6] = pad_real[7:6] ^ glitch[7:6];

always #15 aon_clk = ~aon_clk;        // ~33MHz for sim speed

strap_ctrl #(
    .STRAP_W     (W),
    .WAIT_SUB    (1),
    .CNT_W       (16),
    .SETTLE_CYC  (16),
    .CONFIRM_N   (3),
    .TIMEOUT_CYC (500)
) dut (
    .aon_clk       (aon_clk      ),
    .aon_por_n     (aon_por_n    ),
    .pad_rstj_n    (pad_rstj_n   ),
    .test_mode     (1'b0         ),
    .test_rst_n    (1'b1         ),
    .main_pwr_ok   (main_pwr_ok  ),
    .sub_pwr_ok    (sub_pwr_ok   ),
    .iso_main_en   (iso_main_en  ),
    .iso_sub_en    (iso_sub_en   ),
    .strap_pad_in  (strap_pad_in ),
    .strap_val     (strap_val    ),
    .strap_done    (strap_done   ),
    .strap_lock    (strap_lock   ),
    .strap_timeout (strap_timeout)
);

integer errors = 0;
task cyc(input integer n); begin repeat (n) @(posedge aon_clk); #1; end endtask
task check(input [511:0] name, input cond); begin
    if (cond) $display("[PASS] %0s", name);
    else begin $display("[FAIL] %0s  done=%b val=%h to=%b @%0t", name, strap_done, strap_val, strap_timeout, $time); errors = errors + 1; end
end endtask

task main_sub_power_up; begin
    main_pwr_ok = 1; sub_pwr_ok = 1; cyc(5);
    iso_main_en = 0; iso_sub_en = 0;
end endtask

initial begin
    // ---------------- T1 ----------------
    pad_real = 8'hA5;
    cyc(3); aon_por_n = 1;                  // AON up
    cyc(5); pad_rstj_n = 1;                 // RSTJ released early, MAIN still off
    cyc(100);
    check("T1a no capture while MAIN off / ISO clamp", !strap_done && strap_lock);
    main_sub_power_up;                      // MAIN/SUB up 100 cycles later
    cyc(40);
    check("T1b captured real pad value 0xA5", strap_done && !strap_lock && strap_val == 8'hA5);
    check("T1c no timeout", !strap_timeout);

    // ---------------- T2 ----------------
    iso_main_en = 1; cyc(3); main_pwr_ok = 0;     // MAIN power down
    pad_real = 8'h3C;                             // pads now driven by function
    cyc(50);
    main_pwr_ok = 1; cyc(5); iso_main_en = 0;     // MAIN power up again
    cyc(50);
    check("T2 MAIN power cycle keeps 0xA5", strap_done && strap_val == 8'hA5);

    // ---------------- T3 ----------------
    pad_rstj_n = 0; cyc(5);
    check("T3a RSTJ assert clears", !strap_done && strap_val == 0 && strap_lock);
    pad_real = 8'h5A;
    pad_rstj_n = 1; cyc(40);
    check("T3b re-captured 0x5A", strap_done && strap_val == 8'h5A);

    // ---------------- T4 ----------------
    pad_rstj_n = 0; cyc(5); pad_real = 8'hC3; pad_rstj_n = 1;
    // sync(2) + rst_sync(2) + pwr sync + settle 16 -> first sample around cycle ~22
    cyc(22); glitch = 8'h01;
    check("T4a glitch hits CONFIRM window", dut.state == 2'd2);
    cyc(1); glitch = 8'h00;
    cyc(40);
    check("T4 glitch filtered, captured 0xC3", strap_done && strap_val == 8'hC3);

    // ---------------- T5 ----------------
    pad_rstj_n = 0; iso_sub_en = 1; sub_pwr_ok = 0; cyc(5);
    pad_real = 8'hF0;
    pad_rstj_n = 1; cyc(10);
    sub_pwr_ok = 1; iso_sub_en = 0; cyc(8);       // SUB released ...
    iso_sub_en = 1; cyc(30);                      // ... then isolated again mid-settle
    check("T5a ISO re-asserted -> no capture", !strap_done);
    iso_sub_en = 0; cyc(40);
    check("T5b captured 0xF0 after ISO release", strap_done && strap_val == 8'hF0);

    // ---------------- T6 ----------------
    pad_rstj_n = 0; iso_main_en = 1; main_pwr_ok = 0; cyc(5);
    pad_rstj_n = 1; cyc(600);
    check("T6 MAIN never up -> timeout, not done", strap_timeout && !strap_done);
    main_sub_power_up; cyc(40);
    check("T6b late MAIN power-up still captures", strap_done && strap_val == 8'hF0);

    // ---------------- T7 ----------------
    aon_por_n = 0; cyc(3);
    check("T7 AON_POR clears", !strap_done && !strap_timeout && strap_val == 0);

    if (errors == 0) $display("ALL TESTS PASSED");
    else             $display("%0d TEST(S) FAILED", errors);
    $finish;
end

initial begin
    $dumpfile("tb_strap_ctrl.vcd");
    $dumpvars(0, tb_strap_ctrl);
end

endmodule
