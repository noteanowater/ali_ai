//==============================================================================
// CLK_DIV : integer clock divider (posedge flops only, no negedge flops)
//
//   div = 0        : clk_o = clk (bypass)
//   div = 1~2^n-1  : clk_o = clk / (div+1), 50% duty for both odd and even ratios
//
//   Clock path: clk_o = clk_p | (odd_fill | ICG(clk, gen_en))
//     even ratio : only clk_p toggles (clocked by clk)
//     odd ratio  : clk_p stays 0; ICG passes H+1 clk pulses and odd_fill
//                  (clocked by the ICG output) fills the low phases between
//                  them, so the output ends on a clk falling edge
//     bypass     : clk_p / odd_fill stay 0, gen_en stays 1, clk_o = clk
//
//   odd_fill is clocked by the ICG output, so it can only change after the
//   ICG output has risen: the handoff at the OR gate is race-free for any
//   ICG delay (no clock gating check needed on the OR gates).
//
//   Backend / STA notes:
//     1. odd_fill D input (from clk domain) is captured by the ICG output:
//        a normal clk -> gated-clk hold check, fixed by data-path buffering
//     2. Set dont_touch on U_CLKDIV_ICG / U_CLKDIV_OR_ODD / U_CLKDIV_OR_OUT
//     3. DFT: ICG SE pin must be connected to scan enable during DFT
//        insertion (it clocks odd_fill); clk_o is replaced by TEST_CLK at
//        the top-level test clock mux
//==============================================================================
module CLK_DIV(
      clk  ,
      rstn ,
      div  ,
      clk_o
);

parameter div_width = 4;

input  wire                 clk   ;
input  wire                 rstn  ;
input  wire [div_width-1:0] div   ;
output wire                 clk_o ;

`ifdef FPGA
assign clk_o = clk;
`else

reg  [div_width-1:0] div_sync_1 ;
reg  [div_width-1:0] div_sync_2 ;
reg  [div_width-1:0] div_sync   ;
reg  [div_width-1:0] div_reg    ;
reg  [div_width-1:0] cnt_p      ;
reg                  clk_p      ;   // even ratio divided clock
reg                  gen_en     ;   // ICG enable
reg                  odd_fill   ;   // odd ratio low-phase fill

wire [div_width-1:0] half_div   ;   // = (div_reg+1)>>1, overflow-free
wire                 clk_gate   ;
wire                 clk_odd    ;

assign half_div = (div_reg >> 1) + {{(div_width-1){1'b0}}, div_reg[0]};

//------------------------------------------------------------
// div synchronizer
//------------------------------------------------------------
always@(posedge clk or negedge rstn) begin
  if (~rstn)
    div_sync_1 <= {div_width{1'b1}};
  else
    div_sync_1 <= div;
end

always@(posedge clk or negedge rstn) begin
  if (~rstn)
    div_sync_2 <= {div_width{1'b1}};
  else
    div_sync_2 <= div_sync_1;
end

always@(posedge clk or negedge rstn) begin
  if (~rstn)
    div_sync <= {div_width{1'b1}};
  else if (div_sync_1 == div_sync_2)
    div_sync <= div_sync_2;
end

//------------------------------------------------------------
// Ratio update: only at the end of a divided period
//------------------------------------------------------------
always@(posedge clk or negedge rstn) begin
  if (~rstn)
    div_reg <= {div_width{1'b1}};
  else if (cnt_p == div_reg)
    div_reg <= div_sync;
end

//------------------------------------------------------------
// Counter: 0 ~ div_reg
//------------------------------------------------------------
always@(posedge clk or negedge rstn) begin
  if (~rstn)
    cnt_p <= {div_width{1'b0}};
  else if (cnt_p == div_reg)
    cnt_p <= {div_width{1'b0}};
  else
    cnt_p <= cnt_p + 1'b1;
end

//------------------------------------------------------------
// clk_p (even ratio only, div_reg odd):
//   set after cnt_p==0, cleared after cnt_p==half_div (clear wins)
//   high for half_div clk cycles; stays 0 for odd ratio and bypass
//------------------------------------------------------------
always@(posedge clk or negedge rstn) begin
  if (~rstn)
    clk_p <= 1'b0;
  else if (cnt_p == half_div)
    clk_p <= 1'b0;
  else if ((cnt_p == {div_width{1'b0}}) && (div_reg[0] == 1'b1))
    clk_p <= 1'b1;
end

//------------------------------------------------------------
// gen_en: ICG enable
//   At the end of a period, set to 1 if the next setting is bypass (div=0)
//   or an odd ratio (div even), i.e. div_sync[0]==0;
//   cleared after cnt_p==half_div
//   bypass     : every cycle is a period end -> stays 1
//   odd ratio  : high while cnt_p = 0 ~ half_div; the ICG latches it, so
//                its pulses appear while cnt_p = 1 ~ half_div+1
//   even ratio : stays 0
//------------------------------------------------------------
always@(posedge clk or negedge rstn) begin
  if (~rstn)
    gen_en <= 1'b0;
  else if (cnt_p == div_reg)
    gen_en <= (div_sync[0] == 1'b0);
  else if (cnt_p == half_div)
    gen_en <= 1'b0;
end

//------------------------------------------------------------
// odd_fill (odd ratio): clocked by the ICG output
//   ICG pulses at cnt_p = 1 ~ half_div+1:
//     set   at the pulse of cnt_p = 1          (captures cnt_p == 0)
//     clear at the pulse of cnt_p = half_div+1 (captures cnt_p == half_div)
//   -> high from cnt_p = 1 to cnt_p = half_div, covering the clk low
//      phases between ICG pulses; both edges happen while clk_gate is high
//   bypass: half_div==0, clear always wins -> stays 0
//------------------------------------------------------------
always@(posedge clk_gate or negedge rstn) begin
  if (~rstn)
    odd_fill <= 1'b0;
  else if (cnt_p == half_div)
    odd_fill <= 1'b0;
  else if (cnt_p == {div_width{1'b0}})
    odd_fill <= 1'b1;
end

//------------------------------------------------------------
// Clock path: clk_o = clk_p | (odd_fill | ICG(clk, gen_en))
//------------------------------------------------------------
P_CLK_GATE U_CLKDIV_ICG (
    .CLK   (clk     ),
    .EN    (gen_en  ),
    .SE    (1'b0    ),   // connect to scan enable during DFT insertion
    .YGCLK (clk_gate)
);

OR2V2_8TR40 U_CLKDIV_OR_ODD (
    .A1 (odd_fill),
    .A2 (clk_gate),
    .Z  (clk_odd )
);

OR2V2_8TR40 U_CLKDIV_OR_OUT (
    .A1 (clk_p   ),
    .A2 (clk_odd ),
    .Z  (clk_o   )
);

`endif
endmodule
