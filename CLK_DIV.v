//==============================================================================
// CLK_DIV : integer clock divider (posedge flops only, no negedge flops)
//
//   div = 0        : clk_o = clk (bypass)
//   div = 1~2^n-1  : clk_o = clk / (div+1), 50% duty for both odd and even ratios
//
//   Clock path: clk_o = clk_p | ICG(clk, gen_en)
//     even ratio : gen_en stays 0, clk_o = clk_p
//     odd ratio  : ICG adds the extra half cycle after clk_p
//                  (ends on the clk falling edge)
//     bypass     : clk_p stays 0, gen_en stays 1, clk_o = clk
//
//   Backend / STA notes:
//     1. Clock gating check on U_CLKDIV_OR2: in odd ratio mode the falling
//        edge of clk_p must arrive after the rising edge of the ICG output
//        (hold), otherwise clk_o glitches
//     2. Set dont_touch on U_CLKDIV_ICG / U_CLKDIV_OR2
//     3. DFT: ICG SE pin is connected during DFT insertion; clk_o needs
//        DFT autofix (test clock mux)
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
reg                  clk_p      ;   // divided clock
reg                  gen_en     ;   // ICG enable

wire [div_width-1:0] half_div   ;   // = (div_reg+1)>>1, overflow-free
wire                 clk_gate   ;

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
// clk_p: set after cnt_p==0, cleared after cnt_p==half_div (clear wins)
//   high for half_div clk cycles
//   div_reg==0 -> half_div==0, clear always wins -> clk_p stays 0
//------------------------------------------------------------
always@(posedge clk or negedge rstn) begin
  if (~rstn)
    clk_p <= 1'b0;
  else if (cnt_p == half_div)
    clk_p <= 1'b0;
  else if (cnt_p == {div_width{1'b0}})
    clk_p <= 1'b1;
end

//------------------------------------------------------------
// gen_en: ICG enable
//   At the end of a period, set to 1 if the next setting is bypass (div=0)
//   or an odd ratio (div even), i.e. div_sync[0]==0;
//   cleared after cnt_p==half_div
//   bypass     : every cycle is a period end -> stays 1
//   odd ratio  : set one cycle before clk_p rises, cleared together with
//                clk_p; the ICG pulses lag gen_en by one cycle, so the
//                last pulse fills the half cycle after clk_p falls
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
// Clock path: clk_o = clk_p | ICG(clk, gen_en)
//------------------------------------------------------------
P_CLK_GATE U_CLKDIV_ICG (
    .CLK   (clk     ),
    .EN    (gen_en  ),
    .SE    (1'b0    ),   // connected during DFT insertion
    .YGCLK (clk_gate)
);

OR2V2_8TR40 U_CLKDIV_OR2 (
    .A1 (clk_p   ),
    .A2 (clk_gate),
    .Z  (clk_o   )
);

`endif
endmodule
