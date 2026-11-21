// ============================================================================
// GPIO chip-level pattern  (gpio_top = 4 x atcgpio100, GPIO_0 ~ GPIO_110)
//
// Checks
//   1. ID / Config / register R/W
//   2. GPIO <-> PINPAD mapping, OUTPUT direction  : walking-1 / walking-0 per channel
//   3. GPIO <-> PINPAD mapping, INPUT  direction  : walking-1 / walking-0 per channel
//   4. GPIO <-> PINPAD mapping, INTERRUPT         : per-channel status bit + gpio_intr line
//   5. Interrupt modes (high / low / pos / neg / dual) incl. negative checks
//   6. Interrupt enable mask
//   7. De-bounce : short glitch filtered, long pulse passes
//   8. Hole address (no aliasing into real registers)
//
// Pad <-> GPIO table comes from HS100_PinPad.xlsx -> gpio_pad_map.vh
// (regenerate with gen_gpio_pad_map.py if the pin table changes).
// ============================================================================

// ----------------------------------------------------------------------------
// User configuration  (override with +define+ on the command line)
// ----------------------------------------------------------------------------
`ifndef GPIO_PCLK
  // TODO: hierarchical path of gpio_top.pclk
  `define GPIO_PCLK      test_chip_top.u_chip_top.u_gpio_top.pclk
`endif
// `define GPIO_INTR_SIG test_chip_top.u_chip_top.u_gpio_top.gpio_intr  // define to check the interrupt line
// `define GPIO_TEST_STRAP_TESTMODE   // also drive GPIO_31 (XGPIO_5 = TEST_MODE strap) high in input tests
// `define GPIO_DB_EXTCLK_TEST        // also run debounce on extclk (needs GPIO_EXTCLK_WAIT)
`ifndef GPIO_EXTCLK_WAIT
  `define GPIO_EXTCLK_WAIT  #200_000  // >= 3 * (scale+1) * T_extclk, scale = 1 below
`endif

`define GPIO_SYNC_CLK   6            // pclk cycles: pad -> din(3) -> intr status(+2) + margin
`define GPIO_DB_SCALE   8'hFF        // debounce sample period = scale+1 pclk (db_clk = pclk)
`define GPIO_DB_PERIOD  256          // = scale+1; large enough that bus read latency stays inside the window

`include "gpio_pad_map.vh"

// ----------------------------------------------------------------------------
// Masks  (bit n = GPIO_n, 128 bits = 4 instances x 32)
// ----------------------------------------------------------------------------
// output check : pad exists and is not input-only (GPIO_31 / XGPIO_5 is input-only)
wire [127:0] GPIO_OUT_CHK = GPIO_PAD_EXIST & ~GPIO_PAD_INONLY;
// input check  : GPIO_31 is the TEST_MODE strap -> keep it low unless allowed
`ifdef GPIO_TEST_STRAP_TESTMODE
wire [127:0] GPIO_IN_CHK  = GPIO_PAD_EXIST;
`else
wire [127:0] GPIO_IN_CHK  = GPIO_PAD_EXIST & ~(128'b1 << 31);
`endif

integer gpio_err_cnt;
initial gpio_err_cnt = 0;

// ----------------------------------------------------------------------------
// Basic helpers
// ----------------------------------------------------------------------------
task gpio_wait_clk;
input integer n;
integer k;
begin
    for (k = 0; k < n; k = k + 1) @(posedge `GPIO_PCLK);
    #1;
end
endtask

task gpio_wr;                         // write one instance
input [1:0]  g;
input [31:0] off;
input [31:0] data;
begin
    case (g)
    2'd0 : a45_io_write32b(IOBASE_GPIO0, off, data);
    2'd1 : a45_io_write32b(IOBASE_GPIO1, off, data);
    2'd2 : a45_io_write32b(IOBASE_GPIO2, off, data);
    2'd3 : a45_io_write32b(IOBASE_GPIO3, off, data);
    endcase
end
endtask

task gpio_rd;                         // read & compare one instance
input [1:0]  g;
input [31:0] off;
input [31:0] mask;
input [31:0] exp;
begin
    case (g)
    2'd0 : a45_io_read32b(IOBASE_GPIO0, off, mask, exp);
    2'd1 : a45_io_read32b(IOBASE_GPIO1, off, mask, exp);
    2'd2 : a45_io_read32b(IOBASE_GPIO2, off, mask, exp);
    2'd3 : a45_io_read32b(IOBASE_GPIO3, off, mask, exp);
    endcase
end
endtask

task gpio_wr_all;                     // same value to all 4 instances
input [31:0] off;
input [31:0] data;
integer g;
begin
    for (g = 0; g < 4; g = g + 1) gpio_wr(g, off, data);
end
endtask

task gpio_wr_vec;                     // 128-bit vector -> 4 instances
input [31:0]  off;
input [127:0] vec;
integer g;
begin
    for (g = 0; g < 4; g = g + 1) gpio_wr(g, off, vec[32*g +: 32]);
end
endtask

task gpio_rd_vec;                     // compare 4 instances against 128-bit vector
input [31:0]  off;
input [127:0] mask;
input [127:0] exp;
integer g;
begin
    for (g = 0; g < 4; g = g + 1) gpio_rd(g, off, mask[32*g +: 32], exp[32*g +: 32] & mask[32*g +: 32]);
end
endtask

// Compare pads at chip boundary, report every mismatching channel with its pad name
task gpio_chk_pad;
input [127:0]    exp;
input [8*48:1]   tag;
reg   [127:0]    diff;
integer          k;
begin
    diff = (gpio_pad_obs ^ exp) & GPIO_OUT_CHK;
    if (diff !== 128'b0) begin
        for (k = 0; k < 111; k = k + 1)
            if (GPIO_OUT_CHK[k] && (gpio_pad_obs[k] !== exp[k])) begin
                gpio_err_cnt = gpio_err_cnt + 1;
                $display("    at %t, Error : %0s : GPIO_%0d pad %0s = %b, expect %b",
                         $time, tag, k, gpio_pad_name(k), gpio_pad_obs[k], exp[k]);
            end
    end
end
endtask

task gpio_chk_intr_line;
input            exp;
input [8*48:1]   tag;
begin
`ifdef GPIO_INTR_SIG
    if (`GPIO_INTR_SIG !== exp) begin
        gpio_err_cnt = gpio_err_cnt + 1;
        $display("    at %t, Error : %0s : gpio_intr = %b, expect %b", $time, tag, `GPIO_INTR_SIG, exp);
    end
`endif
end
endtask

task gpio_set_intr_mode;              // same 4-bit mode for every channel
input [3:0] mode;
begin
    gpio_wr_all(32'h54, {8{mode}});
    gpio_wr_all(32'h58, {8{mode}});
    gpio_wr_all(32'h5C, {8{mode}});
    gpio_wr_all(32'h60, {8{mode}});
end
endtask

// ----------------------------------------------------------------------------
// One interrupt mode on all channels
//   mode     : 2 high / 3 low / 5 neg / 6 pos / 7 dual
//   idle     : inactive pad level before the event
//   is_level : 1 = level mode   dual : 1 = dual edge
// ----------------------------------------------------------------------------
task gpio_intr_mode_test;
input [3:0]    mode;
input          idle;
input          is_level;
input          dual;
input [8*24:1] name;
begin
    $display("  at %t, -- Interrupt mode %0s (mode=%0d) --", $time, name, mode);
    gpio_wr_all(32'h50, 32'h0);                         // disable
    gpio_pad_drv = idle ? GPIO_IN_CHK : 128'b0;
    gpio_wait_clk(`GPIO_SYNC_CLK);
    gpio_set_intr_mode(mode);
    gpio_wr_all(32'h64, 32'hFFFF_FFFF);                 // clear stale
    gpio_wr_vec(32'h50, GPIO_IN_CHK);                   // enable
    gpio_wait_clk(`GPIO_SYNC_CLK);
    // readback of mode register (bit3 of each nibble reads 0)
    gpio_rd_vec(32'h54, {4{32'hFFFF_FFFF}}, {4{ {8{1'b0, mode[2:0]}} }});
    // idle level must not trigger
    gpio_rd_vec(32'h64, GPIO_IN_CHK, 128'b0);
    gpio_chk_intr_line(1'b0, "intr idle");

    // active event
    gpio_pad_drv = idle ? 128'b0 : GPIO_IN_CHK;
    gpio_wait_clk(`GPIO_SYNC_CLK);
    gpio_rd_vec(32'h64, GPIO_IN_CHK, GPIO_IN_CHK);
    gpio_chk_intr_line(1'b1, "intr active");

    // W1C while the active level is still held
    gpio_wr_all(32'h64, 32'hFFFF_FFFF);
    gpio_wait_clk(`GPIO_SYNC_CLK);
    if (is_level)                                       // level re-asserts
        gpio_rd_vec(32'h64, GPIO_IN_CHK, GPIO_IN_CHK);
    else                                                // edge stays cleared
        gpio_rd_vec(32'h64, GPIO_IN_CHK, 128'b0);

    // back to idle
    gpio_pad_drv = idle ? GPIO_IN_CHK : 128'b0;
    gpio_wait_clk(`GPIO_SYNC_CLK);
    if (dual) begin                                     // second edge also triggers
        gpio_rd_vec(32'h64, GPIO_IN_CHK, GPIO_IN_CHK);
        gpio_chk_intr_line(1'b1, "dual 2nd edge");
    end
    else if (!is_level) begin                           // opposite edge must not trigger
        gpio_rd_vec(32'h64, GPIO_IN_CHK, 128'b0);
        gpio_chk_intr_line(1'b0, "opposite edge");
    end
    gpio_wr_all(32'h64, 32'hFFFF_FFFF);
    gpio_wait_clk(`GPIO_SYNC_CLK);
    gpio_rd_vec(32'h64, GPIO_IN_CHK, 128'b0);
    gpio_chk_intr_line(1'b0, "after clear");
    gpio_wr_all(32'h50, 32'h0);
end
endtask

// ============================================================================
task chip_top_task ;
integer       n, g, k;
reg [127:0]   vec;
reg [31:0]    off;
begin

$display ("at %t, GPIO TEST Begin ...", $time);
gpio_pad_release_all;

// ----------------------------------------------------------------------------
$display ("Step 1 -- ID / Configuration register ... %t", $time);
    for (g = 0; g < 4; g = g + 1) begin
        gpio_rd(g, 32'h00, 32'hFFFF_FFFF, 32'h0203_1002);   // ID & revision
        gpio_rd(g, 32'h10, 32'hFFFF_FFFF, 32'h6000_0020);   // INTR=1 DB=1 PULL=0 NUM=32
    end

// ----------------------------------------------------------------------------
$display ("Step 2 -- PINMUX select GPIO function ... %t", $time);
    // Pin table: GPIO function = <PAD>_SEL_000 for every GPIO pad.
    // TODO: confirm 0x90 / 0x0190 really decodes to SEL_000 in the pinmux spec.
    for (off = 32'h00; off <= 32'h50; off = off + 4)
        a45_io_write32b(IOBASE_PINMUX, off, 32'h9090_9090);
    a45_io_write32b(IOBASE_PINMUX, 32'h5C, 32'h9090_9090);
    for (off = 32'h80; off <= 32'hB0; off = off + 4)
        a45_io_write32b(IOBASE_PINMUX, off, 32'h0190_0190);
    #100;

// ----------------------------------------------------------------------------
$display ("Step 3 -- Register R/W ... %t", $time);
    for (g = 0; g < 4; g = g + 1) begin
        gpio_wr(g, 32'h28, 32'hA5A5_5A5A);  gpio_rd(g, 32'h28, 32'hFFFF_FFFF, 32'hA5A5_5A5A);
        gpio_wr(g, 32'h28, 32'h5A5A_A5A5);  gpio_rd(g, 32'h28, 32'hFFFF_FFFF, 32'h5A5A_A5A5);
        gpio_wr(g, 32'h28, 32'h0);          gpio_rd(g, 32'h28, 32'hFFFF_FFFF, 32'h0);
        gpio_wr(g, 32'h50, 32'hA5A5_5A5A);  gpio_rd(g, 32'h50, 32'hFFFF_FFFF, 32'hA5A5_5A5A);
        gpio_wr(g, 32'h50, 32'h0);          gpio_rd(g, 32'h50, 32'hFFFF_FFFF, 32'h0);
        for (off = 32'h54; off <= 32'h60; off = off + 4) begin
            gpio_wr(g, off, 32'hFFFF_FFFF); gpio_rd(g, off, 32'hFFFF_FFFF, 32'h7777_7777);
            gpio_wr(g, off, 32'h0);         gpio_rd(g, off, 32'hFFFF_FFFF, 32'h0);
        end
        gpio_wr(g, 32'h70, 32'hFFFF_FFFF);  gpio_rd(g, 32'h70, 32'hFFFF_FFFF, 32'hFFFF_FFFF);
        gpio_wr(g, 32'h70, 32'h0);          gpio_rd(g, 32'h70, 32'hFFFF_FFFF, 32'h0);
        gpio_wr(g, 32'h74, 32'hFFFF_FFFF);  gpio_rd(g, 32'h74, 32'hFFFF_FFFF, 32'h8000_00FF);
        gpio_wr(g, 32'h74, 32'h0);          gpio_rd(g, 32'h74, 32'hFFFF_FFFF, 32'h0);
        gpio_rd(g, 32'h2C, 32'hFFFF_FFFF, 32'h0);           // DoutClear reads 0
        gpio_rd(g, 32'h30, 32'hFFFF_FFFF, 32'h0);           // DoutSet   reads 0
    end

// ----------------------------------------------------------------------------
$display ("Step 4 -- OUTPUT : GPIO <-> PINPAD mapping ... %t", $time);
    gpio_pad_release_all;                                   // chip drives the pads
    gpio_wr_vec(32'h24, 128'b0);
    gpio_wr_all(32'h28, 32'hFFFF_FFFF);                     // all output
    gpio_wait_clk(2);
    gpio_chk_pad(128'b0, "OUT all-0");

    $display ("  Step 4-1 -- walking 1 ... %t", $time);
    for (n = 0; n < 111; n = n + 1) if (GPIO_OUT_CHK[n]) begin
        vec = 128'b1 << n;
        gpio_wr_vec(32'h24, vec);
        gpio_wait_clk(2);
        gpio_chk_pad(vec, "OUT walking-1");
    end

    $display ("  Step 4-2 -- walking 0 ... %t", $time);
    for (n = 0; n < 111; n = n + 1) if (GPIO_OUT_CHK[n]) begin
        vec = ~(128'b1 << n);
        gpio_wr_vec(32'h24, vec);
        gpio_wait_clk(2);
        gpio_chk_pad(vec, "OUT walking-0");
    end

    $display ("  Step 4-3 -- DataOut / Set / Clear registers ... %t", $time);
    gpio_wr_vec(32'h24, 128'b0);
    gpio_wr_vec(32'h30, {4{32'hA5A5_A5A5}});                // set
    gpio_wait_clk(2);
    gpio_chk_pad({4{32'hA5A5_A5A5}}, "OUT set A5A5A5A5");
    gpio_rd_vec(32'h24, {4{32'hFFFF_FFFF}}, {4{32'hA5A5_A5A5}});
    gpio_wr_vec(32'h30, {4{32'h5A5A_0000}});                // set (OR)
    gpio_wait_clk(2);
    gpio_chk_pad({4{32'hFFFF_A5A5}}, "OUT set 5A5A0000");
    gpio_wr_vec(32'h2C, {4{32'h0F0F_00FF}});                // clear
    gpio_wait_clk(2);
    gpio_chk_pad({4{32'hF0F0_A500}}, "OUT clear 0F0F00FF");
    gpio_rd_vec(32'h24, {4{32'hFFFF_FFFF}}, {4{32'hF0F0_A500}});
    gpio_wr_vec(32'h2C, {4{32'hFFFF_FFFF}});
    gpio_wait_clk(2);
    gpio_chk_pad(128'b0, "OUT clear all");


// ----------------------------------------------------------------------------
$display ("Step 5 -- INPUT : PINPAD <-> GPIO mapping ... %t", $time);
    gpio_wr_all(32'h28, 32'h0);                             // all input
    gpio_pad_drv = 128'b0;
    gpio_pad_force_all;
    gpio_wait_clk(`GPIO_SYNC_CLK);
    gpio_rd_vec(32'h20, GPIO_IN_CHK, 128'b0);

    $display ("  Step 5-1 -- walking 1 ... %t", $time);
    for (n = 0; n < 111; n = n + 1) if (GPIO_IN_CHK[n]) begin
        gpio_pad_drv = 128'b1 << n;
        gpio_wait_clk(`GPIO_SYNC_CLK);
        gpio_rd_vec(32'h20, GPIO_IN_CHK, gpio_pad_drv);
    end

    $display ("  Step 5-2 -- walking 0 ... %t", $time);
    for (n = 0; n < 111; n = n + 1) if (GPIO_IN_CHK[n]) begin
        gpio_pad_drv = GPIO_IN_CHK & ~(128'b1 << n);
        gpio_wait_clk(`GPIO_SYNC_CLK);
        gpio_rd_vec(32'h20, GPIO_IN_CHK, gpio_pad_drv);
    end
    gpio_pad_drv = 128'b0;
    gpio_wait_clk(`GPIO_SYNC_CLK);

// ----------------------------------------------------------------------------
$display ("Step 6 -- INTERRUPT : per-channel mapping (posedge) ... %t", $time);
    gpio_wr_all(32'h50, 32'h0);
    gpio_set_intr_mode(4'h6);
    gpio_wr_all(32'h64, 32'hFFFF_FFFF);
    gpio_wr_vec(32'h50, GPIO_IN_CHK);
    gpio_wait_clk(`GPIO_SYNC_CLK);
    gpio_rd_vec(32'h64, GPIO_IN_CHK, 128'b0);
    gpio_chk_intr_line(1'b0, "map idle");
    for (n = 0; n < 111; n = n + 1) if (GPIO_IN_CHK[n]) begin
        gpio_pad_drv = 128'b1 << n;                         // rising edge on GPIO_n only
        gpio_wait_clk(`GPIO_SYNC_CLK);
        gpio_rd_vec(32'h64, GPIO_IN_CHK, gpio_pad_drv);     // only bit n set
        gpio_chk_intr_line(1'b1, "map set");
        gpio_wr(n / 32, 32'h64, 32'b1 << (n % 32));         // W1C bit n
        gpio_pad_drv = 128'b0;                              // falling edge: no trigger
        gpio_wait_clk(`GPIO_SYNC_CLK);
        gpio_rd_vec(32'h64, GPIO_IN_CHK, 128'b0);
        gpio_chk_intr_line(1'b0, "map clear");
    end
    gpio_wr_all(32'h50, 32'h0);

// ----------------------------------------------------------------------------
$display ("Step 7 -- INTERRUPT : trigger modes ... %t", $time);
    //                   mode  idle level dual
    gpio_intr_mode_test(4'h2, 1'b0, 1'b1, 1'b0, "HIGH-LEVEL");
    gpio_intr_mode_test(4'h3, 1'b1, 1'b1, 1'b0, "LOW-LEVEL");
    gpio_intr_mode_test(4'h6, 1'b0, 1'b0, 1'b0, "POS-EDGE");
    gpio_intr_mode_test(4'h5, 1'b1, 1'b0, 1'b0, "NEG-EDGE");
    gpio_intr_mode_test(4'h7, 1'b0, 1'b0, 1'b1, "DUAL-EDGE(rise first)");
    gpio_intr_mode_test(4'h7, 1'b1, 1'b0, 1'b1, "DUAL-EDGE(fall first)");
    gpio_pad_drv = 128'b0;
    gpio_wait_clk(`GPIO_SYNC_CLK);

// ----------------------------------------------------------------------------
$display ("Step 8 -- INTERRUPT : enable mask ... %t", $time);
    gpio_set_intr_mode(4'h2);                               // high level
    gpio_wr_all(32'h50, 32'h0);
    gpio_wr_all(32'h64, 32'hFFFF_FFFF);
    gpio_pad_drv = GPIO_IN_CHK;
    gpio_wait_clk(`GPIO_SYNC_CLK);
    gpio_rd_vec(32'h64, GPIO_IN_CHK, 128'b0);               // masked -> no status
    gpio_chk_intr_line(1'b0, "mask all");
    gpio_wr_all(32'h50, 32'h5555_5555);                     // even channels only
    gpio_wait_clk(`GPIO_SYNC_CLK);
    gpio_rd_vec(32'h64, GPIO_IN_CHK, {4{32'h5555_5555}});
    gpio_chk_intr_line(1'b1, "mask even");
    gpio_wr_all(32'h50, 32'h0);
    gpio_pad_drv = 128'b0;
    gpio_wait_clk(`GPIO_SYNC_CLK);
    gpio_wr_all(32'h64, 32'hFFFF_FFFF);
    gpio_wait_clk(`GPIO_SYNC_CLK);
    gpio_rd_vec(32'h64, GPIO_IN_CHK, 128'b0);
    gpio_chk_intr_line(1'b0, "mask cleared");

// ----------------------------------------------------------------------------
$display ("Step 9 -- DE-BOUNCE (db_clk = pclk, period = %0d pclk) ... %t", `GPIO_DB_PERIOD, $time);
    gpio_pad_drv = 128'b0;
    gpio_wr_all(32'h74, {1'b1, 23'd0, `GPIO_DB_SCALE});     // bit31 = 1 : use pclk
    gpio_wr_all(32'h70, 32'hFFFF_FFFF);
    gpio_set_intr_mode(4'h6);
    gpio_wait_clk(4 * `GPIO_DB_PERIOD);
    gpio_wr_all(32'h64, 32'hFFFF_FFFF);
    gpio_wr_vec(32'h50, GPIO_IN_CHK);
    gpio_rd_vec(32'h20, GPIO_IN_CHK, 128'b0);

    $display ("  Step 9-1 -- glitch shorter than one sample period must be filtered ... %t", $time);
    gpio_pad_drv = GPIO_IN_CHK;
    gpio_wait_clk(`GPIO_DB_PERIOD / 2);
    gpio_pad_drv = 128'b0;
    gpio_wait_clk(4 * `GPIO_DB_PERIOD);
    gpio_rd_vec(32'h20, GPIO_IN_CHK, 128'b0);
    gpio_rd_vec(32'h64, GPIO_IN_CHK, 128'b0);
    gpio_chk_intr_line(1'b0, "db glitch");

    $display ("  Step 9-2 -- stable level passes after 2~3 sample periods ... %t", $time);
    gpio_pad_drv = GPIO_IN_CHK;
    gpio_wait_clk(`GPIO_DB_PERIOD / 2 + 3);                 // still inside the filter window
    gpio_rd_vec(32'h20, GPIO_IN_CHK, 128'b0);
    gpio_wait_clk(3 * `GPIO_DB_PERIOD);
    gpio_rd_vec(32'h20, GPIO_IN_CHK, GPIO_IN_CHK);
    gpio_rd_vec(32'h64, GPIO_IN_CHK, GPIO_IN_CHK);
    gpio_chk_intr_line(1'b1, "db pass");
    gpio_wr_all(32'h64, 32'hFFFF_FFFF);

    $display ("  Step 9-3 -- low glitch on a high level must be filtered ... %t", $time);
    gpio_pad_drv = 128'b0;
    gpio_wait_clk(`GPIO_DB_PERIOD / 2);
    gpio_pad_drv = GPIO_IN_CHK;
    gpio_wait_clk(4 * `GPIO_DB_PERIOD);
    gpio_rd_vec(32'h20, GPIO_IN_CHK, GPIO_IN_CHK);
    gpio_rd_vec(32'h64, GPIO_IN_CHK, 128'b0);               // no new rising edge

    $display ("  Step 9-4 -- debounce disabled : glitch goes through ... %t", $time);
    gpio_wr_all(32'h70, 32'h0);
    gpio_pad_drv = 128'b0;
    gpio_wait_clk(`GPIO_SYNC_CLK);
    gpio_wr_all(32'h64, 32'hFFFF_FFFF);
    gpio_pad_drv = GPIO_IN_CHK;
    gpio_wait_clk(2);
    gpio_pad_drv = 128'b0;
    gpio_wait_clk(`GPIO_SYNC_CLK);
    gpio_rd_vec(32'h64, GPIO_IN_CHK, GPIO_IN_CHK);          // 2-clk pulse seen
    gpio_wr_all(32'h64, 32'hFFFF_FFFF);

`ifdef GPIO_DB_EXTCLK_TEST
    $display ("  Step 9-5 -- debounce on extclk (scale = 1) ... %t", $time);
    gpio_wr_all(32'h74, 32'h0000_0001);
    gpio_wr_all(32'h70, 32'hFFFF_FFFF);
    `GPIO_EXTCLK_WAIT;
    gpio_wr_all(32'h64, 32'hFFFF_FFFF);
    gpio_pad_drv = GPIO_IN_CHK;
    `GPIO_EXTCLK_WAIT;
    gpio_rd_vec(32'h20, GPIO_IN_CHK, GPIO_IN_CHK);
    gpio_rd_vec(32'h64, GPIO_IN_CHK, GPIO_IN_CHK);
    gpio_pad_drv = 128'b0;
    `GPIO_EXTCLK_WAIT;
    gpio_rd_vec(32'h20, GPIO_IN_CHK, 128'b0);
    gpio_wr_all(32'h70, 32'h0);
`endif
    gpio_wr_all(32'h50, 32'h0);
    gpio_wr_all(32'h64, 32'hFFFF_FFFF);
    gpio_wr_all(32'h74, 32'h0);

// ----------------------------------------------------------------------------
$display ("Step 10 -- Hole address ... %t", $time);
    // decoded : 00 10 20 24 28 2C 30 50 54 58 5C 60 64 70 74 (PULL not configured: 40/44 are holes)
    // each instance only sees paddr[7:0]; paddr[9:8] selects the instance.
    gpio_wr_all(32'h28, 32'h1234_5678);                     // sentinels
    gpio_wr_all(32'h50, 32'h8765_4321);
    gpio_wr_all(32'h70, 32'h0F0F_F0F0);
    for (g = 0; g < 4; g = g + 1)
        for (off = 32'h00; off < 32'h100; off = off + 4)
            case (off[7:0])
            8'h00, 8'h10, 8'h20, 8'h24, 8'h28, 8'h2C, 8'h30,
            8'h50, 8'h54, 8'h58, 8'h5C, 8'h60, 8'h64, 8'h70, 8'h74 : ;
            default : begin
                gpio_wr(g, off, 32'hFFFF_FFFF);
                gpio_rd(g, off, 32'hFFFF_FFFF, 32'h0);
            end
            endcase
    for (g = 0; g < 4; g = g + 1) begin                     // sentinels untouched
        gpio_rd(g, 32'h28, 32'hFFFF_FFFF, 32'h1234_5678);
        gpio_rd(g, 32'h50, 32'hFFFF_FFFF, 32'h8765_4321);
        gpio_rd(g, 32'h70, 32'hFFFF_FFFF, 32'h0F0F_F0F0);
        gpio_rd(g, 32'h24, 32'hFFFF_FFFF, 32'h0);
        gpio_rd(g, 32'h74, 32'hFFFF_FFFF, 32'h0);
    end
    gpio_wr_all(32'h50, 32'h0);
    gpio_wr_all(32'h70, 32'h0);
    gpio_wr_all(32'h28, 32'h0);
    gpio_wr_all(32'h64, 32'hFFFF_FFFF);

// ----------------------------------------------------------------------------
    gpio_pad_drv = 128'b0;
    gpio_pad_release_all;
    if (gpio_err_cnt == 0)
        $display ("at %t, GPIO TEST End : pad/intr-line checks PASS (register compares: see a45_io_read32b log)", $time);
    else
        $display ("at %t, GPIO TEST End : Error : %0d pad/intr-line mismatches", $time, gpio_err_cnt);

end
endtask
