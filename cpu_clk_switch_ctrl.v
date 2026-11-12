//-----------------------------------------------------------------------------
// cpu_clk_switch_ctrl
//
// CPU (A45 dual core) clock source switch controller.
//
// Sequence:
//   1. The requested clock select (clk_sel_req) differs from the select that
//      is currently applied to the glitch-free mux (clk_sel).
//   2. Wait until CORE0 and CORE1 are both in WFI.
//   3. Drive the new select to the glitch-free mux.
//   4. Wait cfg_stable_cnt cycles of clk for the muxed clock to be stable,
//      then raise switch_done_irq to tell the CPU the switch has completed.
//
// Notes:
//   - clk must be a free running clock that does NOT depend on the muxed CPU
//     clock (it is also intended to drive sel_clk of clk_switch_2to1).
//   - clk_sel_req, core0_wfi and core1_wfi are treated as asynchronous and
//     are synchronised to clk here.
//   - If clk_sel_req returns to the current select before both cores have
//     entered WFI, the request is dropped and no interrupt is generated.
//   - A change of clk_sel_req while a switch is in progress is picked up
//     after the current switch has completed (a new sequence is started).
//   - cfg_stable_cnt must cover the hand-over time of the glitch-free mux:
//     about 5 cycles of the old clock + 5 cycles of the new clock + 1 cycle
//     of clk for clk_switch_2to1, plus any PLL/divider settle margin wanted.
//-----------------------------------------------------------------------------
module cpu_clk_switch_ctrl #(
    parameter CNT_W = 8
) (
    input                   clk,             // free running control clock
    input                   rst_n,

    input                   clk_sel_req,     // requested select (A45_SRC_CLK_SEL register)
    input                   core0_wfi,       // CORE0 STANDBYWFI
    input                   core1_wfi,       // CORE1 STANDBYWFI

    input      [CNT_W-1:0]  cfg_stable_cnt,  // clk cycles to wait after switching
    input                   irq_en,          // interrupt enable
    input                   irq_clr,         // 1-cycle pulse (clk domain), clears switch_done_irq

    output reg              clk_sel,         // select to glitch-free mux
    output                  switch_busy,     // switch sequence in progress
    output reg              switch_done,     // 1-cycle pulse when switch completes
    output                  switch_done_irq  // level interrupt, sticky until irq_clr
);

localparam ST_IDLE     = 2'd0;
localparam ST_WAIT_WFI = 2'd1;
localparam ST_SWITCH   = 2'd2;
localparam ST_STABLE   = 2'd3;

reg  [1:0]        state;
reg  [CNT_W-1:0]  stable_cnt;
reg               irq_status;

//----------------- part 1 synchronisers -----------------
reg  [1:0] sel_req_sync;
reg  [1:0] core0_wfi_sync;
reg  [1:0] core1_wfi_sync;

always @ (posedge clk or negedge rst_n)
    if (!rst_n) begin
        sel_req_sync   <= 2'b00;
        core0_wfi_sync <= 2'b00;
        core1_wfi_sync <= 2'b00;
    end
    else begin
        sel_req_sync   <= {sel_req_sync[0],   clk_sel_req};
        core0_wfi_sync <= {core0_wfi_sync[0], core0_wfi};
        core1_wfi_sync <= {core1_wfi_sync[0], core1_wfi};
    end

wire sel_req    = sel_req_sync[1];
wire all_wfi    = core0_wfi_sync[1] & core1_wfi_sync[1];
wire sel_change = (sel_req != clk_sel);

//----------------- part 2 switch sequence -----------------
always @ (posedge clk or negedge rst_n)
    if (!rst_n) begin
        state       <= ST_IDLE;
        clk_sel     <= 1'b0;
        stable_cnt  <= {CNT_W{1'b0}};
        switch_done <= 1'b0;
    end
    else begin
        switch_done <= 1'b0;

        case (state)
        // step 1: wait for the clock select to change
        ST_IDLE:
            if (sel_change)
                state <= ST_WAIT_WFI;

        // step 2: wait for both cores to enter WFI
        ST_WAIT_WFI:
            if (!sel_change)
                state <= ST_IDLE;
            else if (all_wfi)
                state <= ST_SWITCH;

        // step 3: switch the clock
        ST_SWITCH: begin
            clk_sel    <= sel_req;
            stable_cnt <= cfg_stable_cnt;
            state      <= ST_STABLE;
        end

        // step 4: wait for the switched clock to be stable
        ST_STABLE:
            if (stable_cnt == {CNT_W{1'b0}}) begin
                switch_done <= 1'b1;
                state       <= ST_IDLE;
            end
            else
                stable_cnt <= stable_cnt - 1'b1;

        default:
            state <= ST_IDLE;
        endcase
    end

assign switch_busy = (state != ST_IDLE);

//----------------- part 3 interrupt -----------------
always @ (posedge clk or negedge rst_n)
    if (!rst_n)
        irq_status <= 1'b0;
    else if (switch_done)
        irq_status <= 1'b1;
    else if (irq_clr)
        irq_status <= 1'b0;

assign switch_done_irq = irq_status & irq_en;

endmodule
