//==============================================================================
// Module      : strap_ctrl
// Domain      : CORE_AON (always-on)
// Description : Strap pin capture controller.
//
//   The STRAP PADs come from CORE_MAIN, CORE_SUB and CORE_AON. Capture is not
//   triggered by the PAD_RSTJ release edge, because the MAIN/SUB domains may
//   not be powered yet, or their ISO may still be clamping, when PAD_RSTJ is
//   released. Instead, sampling waits until:
//
//     1. PAD_RSTJ is released (synchronized into the AON clock domain)
//     2. MAIN (and SUB, if WAIT_SUB=1) report power-good
//     3. The MAIN->AON (and SUB->AON) ISO cells are released
//     4. SETTLE_CYC AON clock cycles have passed after 1~3 hold
//        (covers ISO release, PAD input buffer and external strap R settling)
//     5. CONFIRM_N consecutive samples are identical (de-glitch)
//
//   The captured value is held in AON flops. strap_done is sticky. Both are
//   cleared ONLY by AON_POR or PAD_RSTJ assertion. A MAIN/SUB power cycle
//   never re-samples, so it cannot pick up a value driven by functional
//   logic while AON/SUB keep running.
//
//   strap_lock (= ~strap_done) must gate the PINMUX: while strap_lock=1, every
//   STRAP PAD is forced to input mode (OE=0, default pull per spec) so that no
//   functional logic can drive the PAD inside the capture window.
//
// Notes:
//   * strap_pad_in must be taken from the AON side of the MAIN/SUB->AON ISO
//     cells. Its clamp value is irrelevant because no capture happens while
//     ISO is active.
//   * iso_*_en polarity: 1 = isolated (clamped), 0 = released.
//   * If the PMU de-asserts ISO only after power-good, the iso_*_en
//     check alone is enough. The pwr_ok inputs are kept for robustness.
//   * Replace strap_sync2 / strap_rst_sync behavioral code with the
//     library synchronizer cells for real implementation.
//==============================================================================
module strap_ctrl #(
    parameter STRAP_W     = 8,        // number of strap pins
    parameter WAIT_SUB    = 1,        // 1: also wait for SUB power + ISO release
    parameter CNT_W       = 24,       // width of settle / timeout counter
    parameter SETTLE_CYC  = 32,       // settle cycles after power/ISO ready (>=1)
    parameter CONFIRM_N   = 3,        // consecutive identical samples (>=1, <=15)
    parameter TIMEOUT_CYC = 24'hFF_FFFF // cycles before strap_timeout is flagged
)(
    // clock / reset
    input                    aon_clk,       // AON free-running clock (e.g. 32K / RC osc)
    input                    aon_por_n,     // AON power-on reset, active low (async)
    input                    pad_rstj_n,    // PAD_RSTJ, active low (async, from PAD)

    // DFT
    input                    test_mode,     // 1: bypass reset synchronizer
    input                    test_rst_n,    // scan reset

    // power / isolation status (async to aon_clk, synchronized inside)
    input                    main_pwr_ok,   // CORE_MAIN power good
    input                    sub_pwr_ok,    // CORE_SUB  power good
    input                    iso_main_en,   // MAIN->AON ISO active (1=clamped)
    input                    iso_sub_en,    // SUB ->AON ISO active (1=clamped)

    // strap pad inputs (MAIN / SUB / AON pads, AON side of ISO)
    input  [STRAP_W-1:0]     strap_pad_in,

    // outputs
    output reg [STRAP_W-1:0] strap_val,     // latched strap value (valid when strap_done=1)
    output reg               strap_done,    // sticky: strap captured
    output                   strap_lock,    // to PINMUX: force strap pads to input
    output reg               strap_timeout  // sticky: power/ISO/stable not reached in time
);

//------------------------------------------------------------------------------
// 1. Reset: AON_POR or PAD_RSTJ asserted -> reset (async assert, sync release)
//------------------------------------------------------------------------------
wire rst_raw_n = aon_por_n & pad_rstj_n;
wire rst_n;

strap_rst_sync u_rst_sync (
    .clk        (aon_clk    ),
    .rst_in_n   (rst_raw_n  ),
    .test_mode  (test_mode  ),
    .test_rst_n (test_rst_n ),
    .rst_out_n  (rst_n      )
);

//------------------------------------------------------------------------------
// 2. Synchronize async status and pad inputs into aon_clk
//------------------------------------------------------------------------------
wire main_ok_s, sub_ok_s, iso_main_s, iso_sub_s;
wire [STRAP_W-1:0] pad_s;

// ISO sync resets to 1 (isolated), power-good syncs reset to 0 (not ready)
strap_sync2 #(.W(1), .RST_VAL(1'b0)) u_sync_main_ok (.clk(aon_clk), .rst_n(rst_n), .d(main_pwr_ok), .q(main_ok_s ));
strap_sync2 #(.W(1), .RST_VAL(1'b0)) u_sync_sub_ok  (.clk(aon_clk), .rst_n(rst_n), .d(sub_pwr_ok ), .q(sub_ok_s  ));
strap_sync2 #(.W(1), .RST_VAL(1'b1)) u_sync_iso_m   (.clk(aon_clk), .rst_n(rst_n), .d(iso_main_en), .q(iso_main_s));
strap_sync2 #(.W(1), .RST_VAL(1'b1)) u_sync_iso_s   (.clk(aon_clk), .rst_n(rst_n), .d(iso_sub_en ), .q(iso_sub_s ));

// Per-bit sync is safe here: the value is accepted only after CONFIRM_N
// identical consecutive samples, so bit skew across the bus is filtered.
strap_sync2 #(.W(STRAP_W), .RST_VAL(1'b0)) u_sync_pad (
    .clk   (aon_clk      ),
    .rst_n (rst_n        ),
    .d     (strap_pad_in ),
    .q     (pad_s        )
);

wire main_rdy = main_ok_s & ~iso_main_s;
wire sub_rdy  = (WAIT_SUB != 0) ? (sub_ok_s & ~iso_sub_s) : 1'b1;
wire pwr_rdy  = main_rdy & sub_rdy;

//------------------------------------------------------------------------------
// 3. Capture FSM
//------------------------------------------------------------------------------
localparam [1:0] S_WAIT_PWR = 2'd0,   // wait power-good & ISO release
                 S_SETTLE   = 2'd1,   // wait SETTLE_CYC
                 S_CONFIRM  = 2'd2,   // CONFIRM_N identical samples
                 S_DONE     = 2'd3;   // captured, sticky until reset

reg [1:0]         state;
reg [CNT_W-1:0]   settle_cnt;
reg [3:0]         confirm_cnt;
reg [STRAP_W-1:0] cand_val;           // candidate value under confirmation
reg [CNT_W-1:0]   to_cnt;             // timeout counter

always @(posedge aon_clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= S_WAIT_PWR;
        settle_cnt  <= {CNT_W{1'b0}};
        confirm_cnt <= 4'd0;
        cand_val    <= {STRAP_W{1'b0}};
        strap_val   <= {STRAP_W{1'b0}};
        strap_done  <= 1'b0;
    end
    else begin
        case (state)
        //----------------------------------------------------------------------
        S_WAIT_PWR: begin
            settle_cnt  <= {CNT_W{1'b0}};
            confirm_cnt <= 4'd0;
            if (pwr_rdy)
                state <= S_SETTLE;
        end
        //----------------------------------------------------------------------
        S_SETTLE: begin
            if (!pwr_rdy) begin
                state <= S_WAIT_PWR;                 // power/ISO dropped: restart
            end
            else if (settle_cnt >= SETTLE_CYC - 1) begin
                cand_val    <= pad_s;                // first sample
                confirm_cnt <= 4'd1;
                state       <= S_CONFIRM;
            end
            else begin
                settle_cnt <= settle_cnt + 1'b1;
            end
        end
        //----------------------------------------------------------------------
        S_CONFIRM: begin
            if (!pwr_rdy) begin
                state <= S_WAIT_PWR;                 // power/ISO dropped: restart
            end
            else if (confirm_cnt >= CONFIRM_N) begin
                strap_val  <= cand_val;              // accept
                strap_done <= 1'b1;
                state      <= S_DONE;
            end
            else if (pad_s == cand_val) begin
                confirm_cnt <= confirm_cnt + 1'b1;
            end
            else begin
                cand_val    <= pad_s;                // value changed: restart confirm
                confirm_cnt <= 4'd1;
            end
        end
        //----------------------------------------------------------------------
        S_DONE: begin
            // Sticky: MAIN/SUB power cycles or ISO toggles are ignored.
            // Only AON_POR / PAD_RSTJ can leave this state (via reset).
            state <= S_DONE;
        end
        default: state <= S_WAIT_PWR;
        endcase
    end
end

assign strap_lock = ~strap_done;

//------------------------------------------------------------------------------
// 4. Timeout monitor (status only, capture keeps waiting)
//------------------------------------------------------------------------------
always @(posedge aon_clk or negedge rst_n) begin
    if (!rst_n) begin
        to_cnt        <= {CNT_W{1'b0}};
        strap_timeout <= 1'b0;
    end
    else if (!strap_done && !strap_timeout) begin
        if (to_cnt >= TIMEOUT_CYC - 1)
            strap_timeout <= 1'b1;
        else
            to_cnt <= to_cnt + 1'b1;
    end
end

endmodule


//==============================================================================
// 2-stage synchronizer (behavioral, replace with library sync cell)
//==============================================================================
module strap_sync2 #(
    parameter W       = 1,
    parameter RST_VAL = 1'b0
)(
    input              clk,
    input              rst_n,
    input  [W-1:0]     d,
    output [W-1:0]     q
);
reg [W-1:0] s0, s1;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s0 <= {W{RST_VAL}};
        s1 <= {W{RST_VAL}};
    end
    else begin
        s0 <= d;
        s1 <= s0;
    end
end
assign q = s1;
endmodule


//==============================================================================
// Reset synchronizer: async assert, sync de-assert, DFT bypass
//==============================================================================
module strap_rst_sync (
    input  clk,
    input  rst_in_n,
    input  test_mode,
    input  test_rst_n,
    output rst_out_n
);
reg r0, r1;
always @(posedge clk or negedge rst_in_n) begin
    if (!rst_in_n) begin
        r0 <= 1'b0;
        r1 <= 1'b0;
    end
    else begin
        r0 <= 1'b1;
        r1 <= r0;
    end
end
assign rst_out_n = test_mode ? test_rst_n : r1;
endmodule
