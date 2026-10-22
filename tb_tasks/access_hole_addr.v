//=====================================================================
// File        : access_hole_addr.v
// Description : Testbench pattern / tasks to access the "hole" (unmapped /
//               reserved) address space of an IP over an APB-like bus and
//               check the bus response (error flag and/or default read
//               value). Intended to be `include`-d inside a testbench top
//               that drives the APB master signals below.
//
// Usage       : In the TB top, declare the APB master signals, then:
//                   `include "access_hole_addr.v"
//               and call:
//                   access_hole_range(32'h0000_1000, 32'h0000_1FFC, 32'h4);
//               or walk a user list via run_hole_pattern().
//
// Assumptions : - APB3 style: PSEL/PENABLE/PWRITE/PADDR/PWDATA/PRDATA/
//                 PREADY/PSLVERR, single clock pclk, active-low preset_n.
//               - A read to a hole address is expected to return PSLVERR=1
//                 (configurable) and/or a known default data value.
//               NOTE: All $display messages are in English on purpose.
//=====================================================================

// ---------------------------------------------------------------------
// APB master signals expected in the TB top (declare there, not here):
//   reg         pclk;
//   reg         preset_n;
//   reg         psel;
//   reg         penable;
//   reg         pwrite;
//   reg  [31:0] paddr;
//   reg  [31:0] pwdata;
//   wire [31:0] prdata;
//   wire        pready;
//   wire        pslverr;
// ---------------------------------------------------------------------

// Expected behaviour of a hole access (tweak to match your IP spec)
localparam HOLE_EXP_SLVERR    = 1'b1;        // hole read/write should assert PSLVERR
localparam HOLE_EXP_RDATA     = 32'h0000_0000; // and/or return this default data
localparam HOLE_CHECK_RDATA   = 1'b0;        // set 1 to also compare read data

integer hole_err_cnt;   // mismatch counter, check at end of test

//---------------------------------------------------------------------
// Single APB READ transfer (2-cycle APB access)
//---------------------------------------------------------------------
task apb_read;
    input  [31:0] addr;
    output [31:0] data;
    output        slverr;
    begin
        @(posedge pclk);
        psel    <= 1'b1;
        penable <= 1'b0;
        pwrite  <= 1'b0;
        paddr   <= addr;
        @(posedge pclk);
        penable <= 1'b1;
        // wait for slave ready
        @(posedge pclk);
        while (!pready) @(posedge pclk);
        data    = prdata;
        slverr  = pslverr;
        psel    <= 1'b0;
        penable <= 1'b0;
    end
endtask

//---------------------------------------------------------------------
// Single APB WRITE transfer (2-cycle APB access)
//---------------------------------------------------------------------
task apb_write;
    input [31:0] addr;
    input [31:0] data;
    output       slverr;
    begin
        @(posedge pclk);
        psel    <= 1'b1;
        penable <= 1'b0;
        pwrite  <= 1'b1;
        paddr   <= addr;
        pwdata  <= data;
        @(posedge pclk);
        penable <= 1'b1;
        @(posedge pclk);
        while (!pready) @(posedge pclk);
        slverr  = pslverr;
        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
    end
endtask

//---------------------------------------------------------------------
// Access ONE hole address: write then read, check the response.
// Increments hole_err_cnt on any unexpected behaviour.
//---------------------------------------------------------------------
task access_hole_addr;
    input [31:0] addr;
    reg   [31:0] rdata;
    reg          wr_err;
    reg          rd_err;
    begin
        $display("[HOLE][%0t] ---- Accessing hole address 0x%08h ----", $time, addr);

        // Write to the hole address
        apb_write(addr, 32'hDEAD_BEEF, wr_err);
        if (wr_err === HOLE_EXP_SLVERR)
            $display("[HOLE][%0t] WRITE 0x%08h : PSLVERR=%b as expected (PASS)",
                      $time, addr, wr_err);
        else begin
            $display("[HOLE][%0t] WRITE 0x%08h : PSLVERR=%b but expected %b (FAIL)",
                      $time, addr, wr_err, HOLE_EXP_SLVERR);
            hole_err_cnt = hole_err_cnt + 1;
        end

        // Read back the hole address
        apb_read(addr, rdata, rd_err);
        if (rd_err === HOLE_EXP_SLVERR)
            $display("[HOLE][%0t] READ  0x%08h : PSLVERR=%b as expected (PASS)",
                      $time, addr, rd_err);
        else begin
            $display("[HOLE][%0t] READ  0x%08h : PSLVERR=%b but expected %b (FAIL)",
                      $time, addr, rd_err, HOLE_EXP_SLVERR);
            hole_err_cnt = hole_err_cnt + 1;
        end

        // Optional read-data check (some IPs return 0 on hole reads)
        if (HOLE_CHECK_RDATA) begin
            if (rdata === HOLE_EXP_RDATA)
                $display("[HOLE][%0t] READ  0x%08h : data=0x%08h as expected (PASS)",
                          $time, addr, rdata);
            else begin
                $display("[HOLE][%0t] READ  0x%08h : data=0x%08h but expected 0x%08h (FAIL)",
                          $time, addr, rdata, HOLE_EXP_RDATA);
                hole_err_cnt = hole_err_cnt + 1;
            end
        end else begin
            $display("[HOLE][%0t] READ  0x%08h : data=0x%08h (info only)",
                      $time, addr, rdata);
        end
    end
endtask

//---------------------------------------------------------------------
// Walk a contiguous hole RANGE [start_addr .. end_addr] with 'step'.
//---------------------------------------------------------------------
task access_hole_range;
    input [31:0] start_addr;
    input [31:0] end_addr;
    input [31:0] step;
    reg   [31:0] a;
    begin
        $display("[HOLE][%0t] ==== Sweeping hole range 0x%08h .. 0x%08h (step 0x%0h) ====",
                  $time, start_addr, end_addr, step);
        a = start_addr;
        while (a <= end_addr) begin
            access_hole_addr(a);
            a = a + step;
        end
    end
endtask

//---------------------------------------------------------------------
// Top-level pattern: edit the hole regions to match YOUR IP memory map.
// Call this from the TB after reset de-assertion.
//---------------------------------------------------------------------
task run_hole_pattern;
    begin
        hole_err_cnt = 0;
        $display("[HOLE][%0t] ######## START hole-address access pattern ########", $time);

        // ---- Edit these ranges to match your IP's reserved/unmapped space ----
        access_hole_range(32'h0000_1000, 32'h0000_1FFC, 32'h4); // reserved block 1
        access_hole_range(32'h0000_3000, 32'h0000_30FC, 32'h4); // reserved block 2
        access_hole_addr (32'h0000_FFFC);                       // single top hole
        // ----------------------------------------------------------------------

        if (hole_err_cnt == 0)
            $display("[HOLE][%0t] ######## RESULT: PASS - all hole accesses behaved as expected ########", $time);
        else
            $display("[HOLE][%0t] ######## RESULT: FAIL - %0d unexpected hole responses ########",
                      $time, hole_err_cnt);

        $display("[HOLE][%0t] ######## END hole-address access pattern ########", $time);
    end
endtask
