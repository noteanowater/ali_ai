//==============================================================================
// pll_sys_dfs_all.v : PLL_SYS_SHELL (with DFS) + PLL_SYS_DFS_CTRL + testbench, all in one file
//
// Run:
//   iverilog : iverilog -g2005 -o sim pll_sys_dfs_all.v && vvp sim            (-DVCD : waveform)
//   VCS      : vcs -full64 -sverilog +v2k -debug_access+all +define+FSDB pll_sys_dfs_all.v -o simv && ./simv
//   Pass     : the last line prints "TEST PASSED"
//
// Defines for the real environment (avoid duplicate module definitions):
//   +define+USE_LIB_CELLS : use the library P_CLK_GATE / SRCKBUF / clk_div_256 / STATIC_CLK_DIV / CLK_SWITCH_2MUX1
//   +define+USE_PLL_MODEL : use the real INNO_PLL_TOP model (increase DFS_LOCK_TIMEOUT_CYC and the global timeout
//                           in the tb if its lock time is long; the LOCK timeout test forces U_PLL_SYS.lock low)
//   +define+WFI_LEVEL     : drive CORE_WFI_MODE_* as levels (DFS_WFI_PULSE = 0)
//==============================================================================
`timescale 1ns/1ps

//==============================================================================
// Behavioral library cell models (simulation only)
//   +define+USE_LIB_CELLS to use the real P_CLK_GATE / SRCKBUF / clk_div_256 / STATIC_CLK_DIV / CLK_SWITCH_2MUX1
//==============================================================================
`ifndef USE_LIB_CELLS
module P_CLK_GATE (input CLK, input EN, input SE, output YGCLK);
reg en_l;
always @(*) if (!CLK) en_l = EN | SE;
assign YGCLK = CLK & en_l;
endmodule

module SRCKBUF (input I, output Z);
assign Z = I;
endmodule

module clk_div_256 (input clk, input rstn, input [7:0] div, output clk_o);
assign clk_o = 1'b0;
endmodule

// static clock divider, even RATIO, 50% duty
module STATIC_CLK_DIV #(parameter RATIO = 2) (
    input  clk_in, input resetn, output clk_en, output reg clk_out);
reg [7:0] cnt;
assign clk_en = 1'b1;
always @(posedge clk_in or negedge resetn)
    if (!resetn)                    begin cnt <= 8'd0; clk_out <= 1'b0; end
    else if (cnt == RATIO/2 - 1)    begin cnt <= 8'd0; clk_out <= ~clk_out; end
    else                            cnt <= cnt + 8'd1;
endmodule

// glitch-free 2:1 clock switch (SELECT = 0: CLKA, 1: CLKB), same logic as the fixed clk_switch_2to1:
// the other clock is enabled only after the negedge copy of this clock's gate enable has dropped
module CLK_SWITCH_2MUX1 (
    input  CLKA, input CLKB, input SELECT, input SEL_CLK, output CLK_O,
    input  TEST_MODE, input TEST_SE, input RSTJ);
reg SEL_CLKA, SEL_CLKB;
reg SEL_CLKA_D0, SEL_CLKA_D1, SEL_CLKA_DLY1, SEL_CLKA_DLY2, SEL_CLKA_DLY3, SEL_CLKA_OFF_N;
reg SEL_CLKB_D0, SEL_CLKB_D1, SEL_CLKB_DLY1, SEL_CLKB_DLY2, SEL_CLKB_DLY3, SEL_CLKB_OFF_N;
reg EN_A_L, EN_B_L;
always @(posedge SEL_CLK or negedge RSTJ)
    if (!RSTJ) begin SEL_CLKA <= 1'b0; SEL_CLKB <= 1'b0; end
    else       begin SEL_CLKA <= ~SELECT; SEL_CLKB <= SELECT; end
always @(posedge CLKA or negedge RSTJ)
    if (!RSTJ) {SEL_CLKA_D0, SEL_CLKA_D1, SEL_CLKA_DLY1, SEL_CLKA_DLY2, SEL_CLKA_DLY3} <= 5'b0;
    else       {SEL_CLKA_D0, SEL_CLKA_D1, SEL_CLKA_DLY1, SEL_CLKA_DLY2, SEL_CLKA_DLY3} <=
               {SEL_CLKA & ~SEL_CLKB_OFF_N, SEL_CLKA_D0, SEL_CLKA_D1, SEL_CLKA_DLY1, SEL_CLKA_DLY2};
always @(posedge CLKB or negedge RSTJ)
    if (!RSTJ) {SEL_CLKB_D0, SEL_CLKB_D1, SEL_CLKB_DLY1, SEL_CLKB_DLY2, SEL_CLKB_DLY3} <= 5'b0;
    else       {SEL_CLKB_D0, SEL_CLKB_D1, SEL_CLKB_DLY1, SEL_CLKB_DLY2, SEL_CLKB_DLY3} <=
               {SEL_CLKB & ~SEL_CLKA_OFF_N, SEL_CLKB_D0, SEL_CLKB_D1, SEL_CLKB_DLY1, SEL_CLKB_DLY2};
always @(negedge CLKA or negedge RSTJ) if (!RSTJ) SEL_CLKA_OFF_N <= 1'b0; else SEL_CLKA_OFF_N <= SEL_CLKA_DLY3;
always @(negedge CLKB or negedge RSTJ) if (!RSTJ) SEL_CLKB_OFF_N <= 1'b0; else SEL_CLKB_OFF_N <= SEL_CLKB_DLY3;
always @(*) if (!CLKA) EN_A_L = TEST_MODE | TEST_SE | SEL_CLKA_DLY3;
always @(*) if (!CLKB) EN_B_L = TEST_MODE | TEST_SE | SEL_CLKB_DLY3;
assign CLK_O = (CLKA & EN_A_L) | (CLKB & EN_B_L);
endmodule
`endif


//==============================================================================
// Behavioral PLL model (simulation only), +define+USE_PLL_MODEL to use the real one
//==============================================================================
`ifndef USE_PLL_MODEL
// PLL model: Fvco = 24 * NI / M, clko0 = Fvco / (Q0_0+1), clko1 = Fvco / (Q0_1+1)
// pd=1 stops output and drops lock; locks LOCK_T after pd release (never locks when lock_block=1)
module INNO_PLL_TOP (
    output [7:0] tbladdr, output reg lock, output testout, output reg clko0, output reg clko1,
    input refclk, input pd, input [4:0] prediv, input [11:0] fbdiv, input [23:0] frac,
    input [2:0] postdiv0_0, postdiv0_1, postdiv1_0, postdiv1_1,
    input [1:0] gvco_bias, input [2:0] cpp_bias, cpi_bias, input dacpd, dsmpd, testen,
    input [1:0] testsel, input disable_sscg, input [3:0] divval, input downspread,
    input [7:0] ext_maxaddr, extwaveval, input sel_extwave, input [2:0] spread);
parameter real LOCK_T = 2000.0;
reg lock_block = 0;
assign tbladdr = 8'd0; assign testout = 1'b0;
real fvco, h0 = 1.0, h1 = 1.0;
initial begin lock = 0; clko0 = 0; clko1 = 0; end
always @(posedge pd) lock = 0;
always @(negedge pd) begin
    fvco = 24.0 * fbdiv / prediv;
    h0 = 1000.0 / (fvco / (postdiv0_0 + 1)) / 2.0;
    h1 = 1000.0 / (fvco / (postdiv0_1 + 1)) / 2.0;
    #(LOCK_T) if (!pd && !lock_block) lock = 1;
end
always #(h0) if (!pd) clko0 = ~clko0; else clko0 = 0;
always #(h1) if (!pd) clko1 = ~clko1; else clko1 = 0;
endmodule
`endif


//==============================================================================
// PLL_SYS_SHELL
//
// DFS flow:
//   SW : program PLL_SYS_CFG_0/1/2 (if PLL_SYS_DFS_PLL_UPD = 1), PLL_SYS_DFS_MODE, PLL_SYS_DFS_PLL_UPD,
//        PLL_SYS_DFS_DIV2, then PLL_SYS_INT_EN = 1 (rising edge starts DFS); both cores enter WFI
//   HW : wait both cores in WFI -> ports with DFS_MODE=1 switch to 24M (BYPASS mux) -> (PLL_UPD) close the common
//        GATE, pd=1, load CFG, hold pd >= 1us, pd=0, wait LOCK, open GATE -> apply DIV2 -> switch back from 24M
//        -> PLL_SYS_LOCK_INT (-> A45_INT[30])
//   SW : ISR writes 1 to the interrupt status (W1C, PLL_SYS_INT_CLR); PLL_SYS_INT_EN = 0 after boot
//
// Clock path:
//   A45 : PLL clko0 -> GATE -> STATIC_CLK_DIV /2 -+-> CLK_SWITCH_2MUX1 (/2 or /1) -> CLK_SWITCH_2MUX1 (PLL / 24M) -> PLL_SYS_F600_CLK
//                         `-----------------------'
//   F400: PLL clko1 -> GATE -> CLK_SWITCH_2MUX1 (PLL / 24M) -> PLL_SYS_F400_CLK
//==============================================================================
module PLL_SYS_SHELL #(
    parameter DFS_PD_CYC           = 100,  // pd hold cycles after config load (>=1us, same as PLL_PD_GEN)
    parameter DFS_CLK_SW_CYC       = 16,   // CLK_SWITCH_2MUX1 switch wait cycles (PLL_SYS_CLK)
    parameter DFS_SETTLE_CYC       = 16,   // wait cycles after power up before checking LOCK
    parameter DFS_LOCK_STABLE_CYC  = 8,    // cycles LOCK must stay high continuously
    parameter DFS_LOCK_TIMEOUT_CYC = 0,    // LOCK timeout cycles (0: no timeout)
    parameter DFS_WFI_PULSE        = 1     // 1: CORE_WFI_MODE_* may be pulses (sticky capture), 0: levels only
)(
    output wire        PLL_SYS_F600_CLK      , 
    output wire        PLL_SYS_F400_CLK      , 

    output wire        PLL_SYS_LOCK          ,
    output wire        PLL_SYS_TESTOUT       , 
    output wire [7:0]  PLL_SYS_TBLADDR       , 
    output wire        PLL_SYS_TEST_DIV1_CLK ,
    output wire        PLL_SYS_TEST_DIV2_CLK ,
    output wire        PLL_SYS_SCAN_DIV1_CLK ,
    output wire        PLL_SYS_SCAN_DIV2_CLK ,

    input  wire [7:0]  PLL_SYS_CLK_DIV1      , 
    input  wire [7:0]  PLL_SYS_CLK_DIV2      , 
    input  wire [31:0] PLL_SYS_CFG_0         , 
    input  wire [28:0] PLL_SYS_CFG_1         ,
    input  wire [31:0] PLL_SYS_CFG_2         ,
    input  wire        PLL_SYS_CFG_EN        , 

    //DFS 
    input  wire [1:0]  PLL_SYS_DFS_MODE      , // SCU: CLK_PLL_OSC during DFS, [0] A45 / [1] F400, 1: 24M, 0: PLL path (stopped by GATE)
    input  wire        PLL_SYS_DFS_PLL_UPD   , // SCU: 1: DFS reprograms PLL (GATE + pd + CFG load + relock), 0: keep PLL
    input  wire [1:0]  PLL_SYS_DFS_DIV2      , // SCU: [0] A45 divider after DFS, 1: /2, 0: /1 ([1] unused, F400 has no divider)
    input  wire        PLL_SYS_INT_EN        , // SCU PLL_INT_EN: rising edge starts DFS, interrupt enable (mask)
    input  wire        PLL_SYS_INT_CLR       , // SCU W1C strobe of the interrupt status (SCU_CLK domain)
    input  wire        SCU_CLK               , // clock of PLL_SYS_INT_CLR (SCU / APB clock)
    input  wire        CORE_WFI_MODE_0       , // u_a45_top.core_wfi_mode_0
    input  wire        CORE_WFI_MODE_1       , // u_a45_top.core_wfi_mode_1
    input  wire        CORE_CLK              , // clock driving CORE_WFI_MODE_0/1 (A45 core clock)
    output wire        PLL_SYS_LOCK_INT      , // -> A45_INT[30]
    output wire        PLL_SYS_DFS_BUSY      , // status, may connect to SCU read-only registers
    output wire        PLL_SYS_DFS_DONE      ,
    output wire        PLL_SYS_LOCK_TIMEOUT  ,

    input  wire [1:0]  DFT_CPU_SPEED_SEL     ,
    input  wire        MBIST_ES_MODE         ,
    input  wire        TEST_MODE             ,
    input  wire        OSC_24M_CLK           ,
    input  wire        PLL_SYS_CLK           ,
    input  wire        PLL_DFT_RSTJ          ,
    input  wire        PLL_SYS_RSTJ          
);


//DFT Signal
wire       PLL_SYS_CFG_EN_DFT     = ( TEST_MODE | MBIST_ES_MODE ) ? 1'b0  : PLL_SYS_CFG_EN ;
wire [7:0] PLL_SYS_CLK_DIV1_DFT   = ( TEST_MODE | MBIST_ES_MODE ) ? 8'h3b : PLL_SYS_CLK_DIV1 ;
wire [7:0] PLL_SYS_CLK_DIV2_DFT   = ( TEST_MODE | MBIST_ES_MODE ) ? 8'h27 : PLL_SYS_CLK_DIV2 ;
wire       PLL_SYS_INT_EN_DFT     = ( TEST_MODE | MBIST_ES_MODE ) ? 1'b0  : PLL_SYS_INT_EN ;

// clock switch test / reset (TODO: TEST_SE per DFT scan enable)
wire       TEST_SE                = 1'b0 ;
wire       CLK_RSTJ               = PLL_SYS_RSTJ ;


wire  [11:0] PLL_SYS_NI_DFT =	DFT_CPU_SPEED_SEL == 2'b00 ? 12'd250 : //A45--500MHz
				DFT_CPU_SPEED_SEL == 2'b01 ? 12'd233 : //A45--550MHz
				DFT_CPU_SPEED_SEL == 2'b10 ? 12'd400 : //A45--600MHz
							     12'd400 ; //A45--600MHz


wire [4:0]   PLL_SYS_M_DFT =	DFT_CPU_SPEED_SEL == 2'b00 ? 5'd3 : //A45--500MHz
                                DFT_CPU_SPEED_SEL == 2'b01 ? 5'd2 : //A45--550MHz
                                DFT_CPU_SPEED_SEL == 2'b10 ? 5'd4 : //A45--600MHz
                                                             5'd4 ; //A45--600MHz


wire [2:0] PLL_SYS_Q0_0_DFT = 	DFT_CPU_SPEED_SEL == 2'b00 ? 3'd3 : //A45--500MHz
                                DFT_CPU_SPEED_SEL == 2'b01 ? 3'd4 : //A45--550MHz
                                DFT_CPU_SPEED_SEL == 2'b10 ? 3'd3 : //A45--600MHz
                                                             3'd3 ; //A45--600MHz

wire [2:0] PLL_SYS_Q0_1_DFT =   DFT_CPU_SPEED_SEL == 2'b00 ? 3'd4 : //A45--500MHz
                                DFT_CPU_SPEED_SEL == 2'b01 ? 3'd6 : //A45--550MHz
                                DFT_CPU_SPEED_SEL == 2'b10 ? 3'd5 : //A45--600MHz
                                                             3'd5 ; //A45--600MHz



wire  [23:0] PLL_SYS_FRAC_DFT         = (TEST_MODE | MBIST_ES_MODE) ? 24'd0   : PLL_SYS_CFG_0 [23: 0] ;
wire  [4:0]  PLL_SYS_PREDIV_DFT       = (TEST_MODE | MBIST_ES_MODE) ? 5'd2    : PLL_SYS_CFG_0 [28:24] ;// M
wire         PLL_SYS_DIS_SSCG_DFT     = (TEST_MODE | MBIST_ES_MODE) ? 1'd1    : PLL_SYS_CFG_0 [29]    ;
wire         PLL_SYS_TESTEN_DFT       = (TEST_MODE | MBIST_ES_MODE) ? 1'd0    : PLL_SYS_CFG_0 [30]    ;
wire  [11:0] PLL_SYS_FBDIV_DFT        = (TEST_MODE | MBIST_ES_MODE) ? 12'd250 : PLL_SYS_CFG_1 [11: 0] ;// NI
wire         PLL_SYS_DACPD_DFT        = (TEST_MODE | MBIST_ES_MODE) ? 1'b1    : PLL_SYS_CFG_1 [12]    ;
wire         PLL_SYS_DSMPD_DFT        = (TEST_MODE | MBIST_ES_MODE) ? 1'b1    : PLL_SYS_CFG_1 [13]    ;
wire         PLL_SYS_PD_DFT           = (TEST_MODE | MBIST_ES_MODE) ? 1'b1    : PLL_SYS_CFG_1 [13]    ;
wire  [1:0]  PLL_SYS_TESTSEL_DFT      = (TEST_MODE | MBIST_ES_MODE) ? 2'h0    : PLL_SYS_CFG_1 [15:14] ;
wire  [2:0]  PLL_SYS_POSTDIV0_0_DFT   = (TEST_MODE | MBIST_ES_MODE) ? 3'd3    : PLL_SYS_CFG_1 [18:16] ;
wire  [2:0]  PLL_SYS_POSTDIV0_1_DFT   = (TEST_MODE | MBIST_ES_MODE) ? 3'd4    : PLL_SYS_CFG_1 [21:19] ;
wire  [2:0]  PLL_SYS_POSTDIV1_0_DFT   = (TEST_MODE | MBIST_ES_MODE) ? 3'h0    : PLL_SYS_CFG_1 [24:22] ;
wire  [2:0]  PLL_SYS_POSTDIV1_1_DFT   = (TEST_MODE | MBIST_ES_MODE) ? 3'h0    : PLL_SYS_CFG_1 [27:25] ;
wire         PLL_SYS_SEL_EXTWAVE_DFT  = (TEST_MODE | MBIST_ES_MODE) ? 1'b0    : PLL_SYS_CFG_1 [28]    ;
wire  [7:0]  PLL_SYS_EXT_MAXADDR_DFT  = (TEST_MODE | MBIST_ES_MODE) ? 8'h0    : PLL_SYS_CFG_2 [ 7: 0] ;
wire  [7:0]  PLL_SYS_EXT_WAVEVAL_DFT  = (TEST_MODE | MBIST_ES_MODE) ? 8'h0    : PLL_SYS_CFG_2 [15: 8] ;
wire  [1:0]  PLL_SYS_GVCO_BIAS_DFT    = (TEST_MODE | MBIST_ES_MODE) ? 2'h1    : PLL_SYS_CFG_2 [17:16] ;
wire  [2:0]  PLL_SYS_CPP_BIAS_DFT     = (TEST_MODE | MBIST_ES_MODE) ? 3'h2    : PLL_SYS_CFG_2 [20:18] ;
wire  [2:0]  PLL_SYS_CPI_BIAS_DFT     = (TEST_MODE | MBIST_ES_MODE) ? 3'h3    : PLL_SYS_CFG_2 [23:21] ;
wire  [3:0]  PLL_SYS_DIVVAL_DFT       = (TEST_MODE | MBIST_ES_MODE) ? 4'h1    : PLL_SYS_CFG_2 [27:24] ;
wire  [2:0]  PLL_SYS_SPREAD_DFT       = (TEST_MODE | MBIST_ES_MODE) ? 3'h0    : PLL_SYS_CFG_2 [30:28] ;
wire         PLL_SYS_DOWNSPREAD_DFT   = (TEST_MODE | MBIST_ES_MODE) ? 1'b1    : PLL_SYS_CFG_2 [31]    ;



reg PLL_SYS_CFG_EN_D1;
reg PLL_SYS_CFG_EN_D2;

always @ (posedge PLL_SYS_CLK or negedge PLL_SYS_RSTJ)begin 
    if(!PLL_SYS_RSTJ)begin 
        PLL_SYS_CFG_EN_D1 <= 1'b0 ; 
        PLL_SYS_CFG_EN_D2 <= 1'b0 ; 
    end 
    else begin 
        PLL_SYS_CFG_EN_D1 <= PLL_SYS_CFG_EN_DFT ;
        PLL_SYS_CFG_EN_D2 <= PLL_SYS_CFG_EN_D1 ;
    end 
end 

wire PLL_SYS_CFG_PULSE ;
assign PLL_SYS_CFG_PULSE =  PLL_SYS_CFG_EN_D1 & !PLL_SYS_CFG_EN_D2 ;

// PLL config load: CFG_EN rising edge, or DFS (after GATE closed and pd=1)
wire PLL_SYS_DFS_CFG_LOAD ;
wire PLL_SYS_CFG_LOAD = PLL_SYS_CFG_PULSE | PLL_SYS_DFS_CFG_LOAD ;


reg [7:0] PLL_SYS_CLK_DIV1_REG    ;
reg [7:0] PLL_SYS_CLK_DIV2_REG    ;

always @ (posedge PLL_SYS_CLK or negedge PLL_SYS_RSTJ)begin
    if(!PLL_SYS_RSTJ)begin
         PLL_SYS_CLK_DIV1_REG    <= 8'h3b ;
         PLL_SYS_CLK_DIV2_REG    <= 8'h27 ;
    end 
    else if (PLL_SYS_CFG_PULSE )begin 
         PLL_SYS_CLK_DIV1_REG    <= PLL_SYS_CLK_DIV1_DFT ;
         PLL_SYS_CLK_DIV2_REG    <= PLL_SYS_CLK_DIV2_DFT ;
    end 
end 

reg [23:0] PLL_SYS_FRAC_REG          ;
reg [4:0]  PLL_SYS_PREDIV_REG        ;
reg        PLL_SYS_DIS_SSCG_REG      ;
reg        PLL_SYS_TESTEN_REG        ;
reg        PLL_SYS_PD_REG            ;
reg [11:0] PLL_SYS_FBDIV_REG         ;
reg        PLL_SYS_DACPD_REG         ;
reg        PLL_SYS_DSMPD_REG         ;
reg [1:0]  PLL_SYS_TESTSEL_REG       ;
reg [2:0]  PLL_SYS_POSTDIV0_0_REG    ;
reg [2:0]  PLL_SYS_POSTDIV0_1_REG    ;
reg [2:0]  PLL_SYS_POSTDIV1_0_REG    ;
reg [2:0]  PLL_SYS_POSTDIV1_1_REG    ;
reg        PLL_SYS_SEL_EXTWAVE_REG   ;
reg [7:0]  PLL_SYS_EXT_MAXADDR_REG   ;
reg [7:0]  PLL_SYS_EXT_WAVEVAL_REG   ;
reg [1:0]  PLL_SYS_GVCO_BIAS_REG     ;
reg [2:0]  PLL_SYS_CPP_BIAS_REG      ;
reg [2:0]  PLL_SYS_CPI_BIAS_REG      ;
reg [3:0]  PLL_SYS_DIVVAL_REG        ;
reg [2:0]  PLL_SYS_SPREAD_REG        ;
reg        PLL_SYS_DOWNSPREAD_REG    ;

// * CPU Freq 500 MHz
// * +----------+------+-----+----+---+------------+------+------+------------+
// * | PLL      | Fref | NI  | NF | M | Fvco(MHz)  | Qn_0 | Qn_1 | Fclk(MHz)  |
// * +----------+------+-----+----+---+------------+------+------+------------+
// * | PLL_SYS0 | 24   | 333 | 0  | 4 | 1998       |  3   |  0   | 499.5      |
// * | PLL_SYS1 | 24   | 333 | 0  | 4 | 1998       |  4   |  0   | 399.6      |
// * +----------+------+-----+----+---+------------+------+------+------------+
// * CPU Freq 600 MHz
// * +----------+------+-----+----+---+------------+------+------+------------+
// * | PLL      | Fref | NI  | NF | M | Fvco(MHz)  | Qn_0 | Qn_1 | Fclk(MHz)  |
// * +----------+------+-----+----+---+------------+------+------+------------+
// * | PLL_SYS0 | 24   | 399 | 0  | 4 | 2394       |  3   |  0   | 598.5      |
// * | PLL_SYS1 | 24   | 399 | 0  | 4 | 2394       |  5   |  0   | 399        |
// * +----------+------+-----+----+---+------------+------+------+------------+

always @ (posedge PLL_SYS_CLK or negedge PLL_SYS_RSTJ)begin
  if(!PLL_SYS_RSTJ)begin
    PLL_SYS_FRAC_REG          <= 24'd0;
    PLL_SYS_PREDIV_REG        <= 5'd3 ;    // M
    PLL_SYS_DIS_SSCG_REG      <= 1'd1 ;
    PLL_SYS_TESTEN_REG        <= 1'd0 ;
    PLL_SYS_PD_REG            <= 1'd1 ;
    PLL_SYS_FBDIV_REG         <= 12'd250 ; // NI
    PLL_SYS_DACPD_REG         <= 1'd1 ;
    PLL_SYS_DSMPD_REG         <= 1'd1 ;
    PLL_SYS_TESTSEL_REG       <= 2'd0 ;
    PLL_SYS_POSTDIV0_0_REG    <= 3'd3 ;    // Q0_0
    PLL_SYS_POSTDIV0_1_REG    <= 3'd4 ;    // Q0_1
    PLL_SYS_POSTDIV1_0_REG    <= 3'd0 ;    // Q1_0
    PLL_SYS_POSTDIV1_1_REG    <= 3'd0 ;    // Q1_1
    PLL_SYS_SEL_EXTWAVE_REG   <= 1'd0 ;
    PLL_SYS_EXT_MAXADDR_REG   <= 8'd0 ;
    PLL_SYS_EXT_WAVEVAL_REG   <= 8'd0 ;
    PLL_SYS_GVCO_BIAS_REG     <= 2'd1 ;
    PLL_SYS_CPP_BIAS_REG      <= 3'd2 ;
    PLL_SYS_CPI_BIAS_REG      <= 3'd3 ;
    PLL_SYS_DIVVAL_REG        <= 4'd1 ;
    PLL_SYS_SPREAD_REG        <= 3'd0 ;
    PLL_SYS_DOWNSPREAD_REG    <= 1'd0 ;
  end
  else if (PLL_SYS_CFG_LOAD) begin
    PLL_SYS_FRAC_REG            <= PLL_SYS_FRAC_DFT          ;
    PLL_SYS_PREDIV_REG          <= PLL_SYS_PREDIV_DFT        ;
    PLL_SYS_DIS_SSCG_REG        <= PLL_SYS_DIS_SSCG_DFT      ;
    PLL_SYS_TESTEN_REG          <= PLL_SYS_TESTEN_DFT        ;
    if (PLL_SYS_CFG_PULSE)                                     // in DFS pd is driven by the FSM, PD_REG unchanged
    PLL_SYS_PD_REG              <= PLL_SYS_PD_DFT            ;
    PLL_SYS_FBDIV_REG           <= PLL_SYS_FBDIV_DFT         ;
    PLL_SYS_DACPD_REG           <= PLL_SYS_DACPD_DFT         ;
    PLL_SYS_DSMPD_REG           <= PLL_SYS_DSMPD_DFT         ;
    PLL_SYS_TESTSEL_REG         <= PLL_SYS_TESTSEL_DFT       ;
    PLL_SYS_POSTDIV0_0_REG      <= PLL_SYS_POSTDIV0_0_DFT    ;
    PLL_SYS_POSTDIV0_1_REG      <= PLL_SYS_POSTDIV0_1_DFT    ;
    PLL_SYS_POSTDIV1_0_REG      <= PLL_SYS_POSTDIV1_0_DFT    ;
    PLL_SYS_POSTDIV1_1_REG      <= PLL_SYS_POSTDIV1_1_DFT    ;
    PLL_SYS_SEL_EXTWAVE_REG     <= PLL_SYS_SEL_EXTWAVE_DFT   ;
    PLL_SYS_EXT_MAXADDR_REG     <= PLL_SYS_EXT_MAXADDR_DFT   ;
    PLL_SYS_EXT_WAVEVAL_REG     <= PLL_SYS_EXT_WAVEVAL_DFT   ;
    PLL_SYS_GVCO_BIAS_REG       <= PLL_SYS_GVCO_BIAS_DFT     ;
    PLL_SYS_CPP_BIAS_REG        <= PLL_SYS_CPP_BIAS_DFT      ;
    PLL_SYS_CPI_BIAS_REG        <= PLL_SYS_CPI_BIAS_DFT      ;
    PLL_SYS_DIVVAL_REG          <= PLL_SYS_DIVVAL_DFT        ;
    PLL_SYS_SPREAD_REG          <= PLL_SYS_SPREAD_DFT        ;
    PLL_SYS_DOWNSPREAD_REG      <= PLL_SYS_DOWNSPREAD_DFT    ;
  end
end

wire  [23:0] PLL_SYS_FRAC          = TEST_MODE ? 24'd0             : MBIST_ES_MODE ? 24'd0   : PLL_SYS_FRAC_REG        ;
wire  [4:0]  PLL_SYS_PREDIV        = TEST_MODE ? PLL_SYS_M_DFT     : MBIST_ES_MODE ? 5'd2    : PLL_SYS_PREDIV_REG      ;// M
wire         PLL_SYS_DIS_SSCG      = TEST_MODE ? 1'b1              : MBIST_ES_MODE ? 1'd1    : PLL_SYS_DIS_SSCG_REG    ;
wire         PLL_SYS_TESTEN        = TEST_MODE ? 1'b0              : MBIST_ES_MODE ? 1'd0    : PLL_SYS_TESTEN_REG      ;
wire  [11:0] PLL_SYS_FBDIV         = TEST_MODE ? PLL_SYS_NI_DFT    : MBIST_ES_MODE ? 12'd250 : PLL_SYS_FBDIV_REG       ;// NI
wire         PLL_SYS_DACPD         = TEST_MODE ? 1'b1              : MBIST_ES_MODE ? 1'b1    : PLL_SYS_DACPD_REG       ;
wire         PLL_SYS_DSMPD         = TEST_MODE ? 1'b1              : MBIST_ES_MODE ? 1'b1    : PLL_SYS_DSMPD_REG       ;
wire  [1:0]  PLL_SYS_TESTSEL       = TEST_MODE ? 2'h0              : MBIST_ES_MODE ? 2'h0    : PLL_SYS_TESTSEL_REG     ;
wire  [2:0]  PLL_SYS_POSTDIV0_0    = TEST_MODE ? PLL_SYS_Q0_0_DFT  : MBIST_ES_MODE ? 3'd3    : PLL_SYS_POSTDIV0_0_REG  ;
wire  [2:0]  PLL_SYS_POSTDIV0_1    = TEST_MODE ? PLL_SYS_Q0_1_DFT  : MBIST_ES_MODE ? 3'd4    : PLL_SYS_POSTDIV0_1_REG  ;
wire  [2:0]  PLL_SYS_POSTDIV1_0    = TEST_MODE ? 3'h0              : MBIST_ES_MODE ? 3'h0    : PLL_SYS_POSTDIV1_0_REG  ;
wire  [2:0]  PLL_SYS_POSTDIV1_1    = TEST_MODE ? 3'h0              : MBIST_ES_MODE ? 3'h0    : PLL_SYS_POSTDIV1_1_REG  ;
wire         PLL_SYS_SEL_EXTWAVE   = TEST_MODE ? 1'b0              : MBIST_ES_MODE ? 1'b0    : PLL_SYS_SEL_EXTWAVE_REG ;
wire  [7:0]  PLL_SYS_EXT_MAXADDR   = TEST_MODE ? 8'h0              : MBIST_ES_MODE ? 8'h0    : PLL_SYS_EXT_MAXADDR_REG ;
wire  [7:0]  PLL_SYS_EXT_WAVEVAL   = TEST_MODE ? 8'h0              : MBIST_ES_MODE ? 8'h0    : PLL_SYS_EXT_WAVEVAL_REG ;
wire  [1:0]  PLL_SYS_GVCO_BIAS     = TEST_MODE ? 2'h1              : MBIST_ES_MODE ? 2'h1    : PLL_SYS_GVCO_BIAS_REG   ;
wire  [2:0]  PLL_SYS_CPP_BIAS      = TEST_MODE ? 3'h2              : MBIST_ES_MODE ? 3'h2    : PLL_SYS_CPP_BIAS_REG    ;
wire  [2:0]  PLL_SYS_CPI_BIAS      = TEST_MODE ? 3'h3              : MBIST_ES_MODE ? 3'h3    : PLL_SYS_CPI_BIAS_REG    ;
wire  [3:0]  PLL_SYS_DIVVAL        = TEST_MODE ? 4'h1              : MBIST_ES_MODE ? 4'h1    : PLL_SYS_DIVVAL_REG      ;
wire  [2:0]  PLL_SYS_SPREAD        = TEST_MODE ? 3'h0              : MBIST_ES_MODE ? 3'h0    : PLL_SYS_SPREAD_REG      ;
wire         PLL_SYS_DOWNSPREAD    = TEST_MODE ? 1'b0              : MBIST_ES_MODE ? 1'b1    : PLL_SYS_DOWNSPREAD_REG  ;

wire  PLL_SYS_PD ;
wire  PLL_PD_GEN_DFT = TEST_MODE ? PLL_DFT_RSTJ : PLL_SYS_PD_REG ;

PLL_PD_GEN U_PLL_PD_GEN (
 .PLL_PD_IN    (PLL_PD_GEN_DFT  ),
 .PLL_PD_OUT   (PLL_SYS_PD      ), 

 .PLL_CLK      (PLL_SYS_CLK     ),
 .PLL_RSTJ     (PLL_SYS_RSTJ    )
);

// DFS power down ORed with power-on pd
wire PLL_SYS_DFS_PD ;
wire PLL_SYS_PD_ALL = PLL_SYS_PD | (PLL_SYS_DFS_PD & ~(TEST_MODE | MBIST_ES_MODE)) ;


//========================================================
// DFS FSM
wire [1:0] PLL_SYS_DFS_SEL_24M  ;
wire       PLL_SYS_DFS_GATE_EN  ;
wire [1:0] PLL_SYS_DFS_DIV2_SEL ;
wire       PLL_SYS_F600_GATE_EN ;
wire       PLL_SYS_F400_GATE_EN ;

PLL_SYS_DFS_CTRL #(
    .N_PORT             (2                   ),
    .PD_CYC             (DFS_PD_CYC          ),
    .CLK_SW_CYC         (DFS_CLK_SW_CYC      ),
    .SETTLE_CYC         (DFS_SETTLE_CYC      ),
    .LOCK_STABLE_CYC    (DFS_LOCK_STABLE_CYC ),
    .LOCK_TIMEOUT_CYC   (DFS_LOCK_TIMEOUT_CYC),
    .WFI_PULSE          (DFS_WFI_PULSE       )
) U_PLL_SYS_DFS_CTRL (
    .CLK                (PLL_SYS_CLK         ),
    .RSTJ               (PLL_SYS_RSTJ        ),
    .INT_EN             (PLL_SYS_INT_EN_DFT  ),
    .INT_CLR            (PLL_SYS_INT_CLR     ),
    .INT_CLR_CLK        (SCU_CLK             ),
    .DFS_MODE           (PLL_SYS_DFS_MODE    ),
    .PLL_UPD            (PLL_SYS_DFS_PLL_UPD ),
    .DIV2               (PLL_SYS_DFS_DIV2    ),
    .CORE_WFI_MODE_0    (CORE_WFI_MODE_0     ),
    .CORE_WFI_MODE_1    (CORE_WFI_MODE_1     ),
    .CORE_CLK           (CORE_CLK            ),
    .PLL_LOCK           (PLL_SYS_LOCK        ),
    .SEL_24M            (PLL_SYS_DFS_SEL_24M ),
    .GATE_EN            (PLL_SYS_DFS_GATE_EN ),
    .DIV2_SEL           (PLL_SYS_DFS_DIV2_SEL),
    .GATE_EN_FB         ({PLL_SYS_F400_GATE_EN, PLL_SYS_F600_GATE_EN}),
    .CFG_LOAD           (PLL_SYS_DFS_CFG_LOAD),
    .PLL_PD             (PLL_SYS_DFS_PD      ),
    .DFS_BUSY           (PLL_SYS_DFS_BUSY    ),
    .DFS_DONE           (PLL_SYS_DFS_DONE    ),
    .LOCK_TIMEOUT       (PLL_SYS_LOCK_TIMEOUT),
    .LOCK_INT           (PLL_SYS_LOCK_INT    )
);


wire PLL_SYS_F600_OUT_CLK ;
wire PLL_SYS_F400_OUT_CLK ;

INNO_PLL_TOP U_PLL_SYS(
//u_pll_cpu (
   // Outputs
        .tbladdr                (PLL_SYS_TBLADDR     ),//( tbladdr_cpu		),
        .lock                   (PLL_SYS_LOCK        ),//( lock_cpu		),
        .testout                (PLL_SYS_TESTOUT     ),//( testout_cpu	 	),
        .clko0                  (PLL_SYS_F600_OUT_CLK),//( pll_clk_out_600m	), 
        .clko1                  (PLL_SYS_F400_OUT_CLK),//( pll_clk_out_400m	),

   // Inputs
        .refclk                 (OSC_24M_CLK         ),//( clk_cpu		), 
        .pd                     (PLL_SYS_PD_ALL      ),//( ~ref_flag0      	),//pll0_pd
        .prediv                 (PLL_SYS_PREDIV      ),//( pll0_prediv		),//M
        .fbdiv                  (PLL_SYS_FBDIV       ),//( pll0_fbdiv		),//NI
        .frac                   (PLL_SYS_FRAC        ),//( pll0_frac		),
        .postdiv0_0             (PLL_SYS_POSTDIV0_0  ),//( pll0_postdiv0_0	),//Q1 
        .postdiv0_1             (PLL_SYS_POSTDIV0_1  ),//( pll0_postdiv0_1	),
        .postdiv1_0             (PLL_SYS_POSTDIV1_0  ),//( pll0_postdiv1_0	),//Q2
        .postdiv1_1             (PLL_SYS_POSTDIV1_1  ),//( pll0_postdiv1_1	),
        .gvco_bias              (PLL_SYS_GVCO_BIAS   ),//( pll0_gvco_bias	), 
        .cpp_bias               (PLL_SYS_CPP_BIAS    ),//( pll0_cpp_bias		),
        .cpi_bias               (PLL_SYS_CPI_BIAS    ),//( pll0_cpi_bias		), 
        .dacpd                  (PLL_SYS_DACPD       ),//( pll0_dacpd		), 
        .dsmpd                  (PLL_SYS_DSMPD       ),//( pll0_dsmpd		), 
        .testen                 (PLL_SYS_TESTEN      ),//( pll0_testen		), 
        .testsel                (PLL_SYS_TESTSEL     ),//( pll0_testsel		), 
        .disable_sscg           (PLL_SYS_DIS_SSCG    ),//( pll0_disable_sscg	), 
        .divval                 (PLL_SYS_DIVVAL      ),//( pll0_divval		),
        .downspread             (PLL_SYS_DOWNSPREAD  ),//( pll0_downspread	), 
        .ext_maxaddr            (PLL_SYS_EXT_MAXADDR ),//( pll0_ext_maxaddr	), 
        .extwaveval             (PLL_SYS_EXT_WAVEVAL ),//( pll0_extwaveval	), 
        .sel_extwave            (PLL_SYS_SEL_EXTWAVE ),//( pll0_sel_extwave	), 
        .spread                 (PLL_SYS_SPREAD      ) //( pll0_spread		)
);

reg PLL_SCAN_DIV2_CLK_REG ;
always @(posedge PLL_SYS_F600_CLK or negedge PLL_SYS_RSTJ)begin 
    if (!PLL_SYS_RSTJ)
	PLL_SCAN_DIV2_CLK_REG <= 1'b0 ;
    else if(TEST_MODE)
        PLL_SCAN_DIV2_CLK_REG <= !PLL_SCAN_DIV2_CLK_REG ;
end 

SRCKBUF  U_PLL_SYS_SCAN_DIV1_CLK_BUF(.Z(PLL_SYS_SCAN_DIV1_CLK), .I(PLL_SYS_F600_CLK));
SRCKBUF  U_PLL_SYS_SCAN_DIV2_CLK_BUF(.Z(PLL_SYS_SCAN_DIV2_CLK), .I(PLL_SCAN_DIV2_CLK_REG));

clk_div_256 U_PLL_SYS_TEST_DIV1 (.clk(PLL_SYS_F600_OUT_CLK), .rstn(PLL_SYS_RSTJ), .div(PLL_SYS_CLK_DIV1_REG), .clk_o(PLL_SYS_TEST_DIV1_CLK));
clk_div_256 U_PLL_SYS_TEST_DIV2 (.clk(PLL_SYS_F400_OUT_CLK), .rstn(PLL_SYS_RSTJ), .div(PLL_SYS_CLK_DIV2_REG), .clk_o(PLL_SYS_TEST_DIV2_CLK));

// Gate : one common enable from the DFS FSM (0 only around PLL power down), synced into each PLL clko domain
wire PLL_SYS_A45_GAT_CLK  ;
wire PLL_SYS_F400_GAT_CLK ;

PLL_DFS_SYNC2 #(.RST_VAL(1'b1)) U_PLL_SYS_F600_GATE_SYNC (.CLK(PLL_SYS_F600_OUT_CLK), .RSTJ(PLL_SYS_RSTJ), .D(PLL_SYS_DFS_GATE_EN), .Q(PLL_SYS_F600_GATE_EN));
PLL_DFS_SYNC2 #(.RST_VAL(1'b1)) U_PLL_SYS_F400_GATE_SYNC (.CLK(PLL_SYS_F400_OUT_CLK), .RSTJ(PLL_SYS_RSTJ), .D(PLL_SYS_DFS_GATE_EN), .Q(PLL_SYS_F400_GATE_EN));

P_CLK_GATE U_PLL_SYS_F600_CLK_GATE (.CLK(PLL_SYS_F600_OUT_CLK), .EN(PLL_SYS_F600_GATE_EN), .SE(TEST_MODE|MBIST_ES_MODE), .YGCLK  (PLL_SYS_A45_GAT_CLK ));
P_CLK_GATE U_PLL_SYS_F400_CLK_GATE (.CLK(PLL_SYS_F400_OUT_CLK), .EN(PLL_SYS_F400_GATE_EN), .SE(TEST_MODE|MBIST_ES_MODE), .YGCLK  (PLL_SYS_F400_GAT_CLK));

//========================================================
// PLL_A45
wire PLL_SYS_A45_DIV2_CLK ;
wire PLL_SYS_A45_SRC_CLK  ;
wire PLL_SYS_A45_CLK      ;

// CLKA = /2, CLKB = /1 : SELECT = 1 selects /1 (reset / TEST / MBIST), 0 selects /2
wire PLL_SYS_A45_DIV_SEL  = (TEST_MODE | MBIST_ES_MODE) ? 1'b1 : ~PLL_SYS_DFS_DIV2_SEL[0] ;
// CLK_PLL_OSC : 1 selects OSC_24M_CLK
wire PLL_SYS_A45_BYPASS_CLK_SEL  = (TEST_MODE | MBIST_ES_MODE) ? 1'b0 : PLL_SYS_DFS_SEL_24M[0] ;
wire PLL_SYS_F400_BYPASS_CLK_SEL = (TEST_MODE | MBIST_ES_MODE) ? 1'b0 : PLL_SYS_DFS_SEL_24M[1] ;

STATIC_CLK_DIV #(
    .RATIO(2)
) U_CORE_A45_CLK_DIV_2 (
    .clk_in   (PLL_SYS_A45_GAT_CLK ),
    .resetn   (PLL_SYS_RSTJ        ),
    .clk_en   (),
    .clk_out  (PLL_SYS_A45_DIV2_CLK)
);


CLK_SWITCH_2MUX1 U_PLL_SYS_A45_DIV_CLK_SEL(
  .CLKA       (PLL_SYS_A45_DIV2_CLK ),
  .CLKB       (PLL_SYS_A45_GAT_CLK  ),
  .SELECT     (PLL_SYS_A45_DIV_SEL  ),
  .SEL_CLK    (PLL_SYS_CLK          ),
  .CLK_O      (PLL_SYS_A45_SRC_CLK  ),

  .TEST_MODE  (TEST_MODE            ),
  .TEST_SE    (TEST_SE              ),        
  .RSTJ       (CLK_RSTJ             )
);



CLK_SWITCH_2MUX1 U_PLL_SYS_A45_SRC_CLK_SEL(
  .CLKA       (PLL_SYS_A45_SRC_CLK  ),
  .CLKB       (OSC_24M_CLK          ),
  .SELECT     (PLL_SYS_A45_BYPASS_CLK_SEL),
  .SEL_CLK    (PLL_SYS_CLK          ),
  .CLK_O      (PLL_SYS_A45_CLK      ),

  .TEST_MODE  (TEST_MODE            ),
  .TEST_SE    (TEST_SE              ),
  .RSTJ       (CLK_RSTJ             )
);

assign PLL_SYS_F600_CLK = PLL_SYS_A45_CLK ;


//========================================================
// PLL_400
CLK_SWITCH_2MUX1 U_PLL_SYS_F400_CLK_SEL(
  .CLKA       (PLL_SYS_F400_GAT_CLK ),
  .CLKB       (OSC_24M_CLK          ),
  .SELECT     (PLL_SYS_F400_BYPASS_CLK_SEL),
  .SEL_CLK    (PLL_SYS_CLK          ),
  .CLK_O      (PLL_SYS_F400_CLK     ),

  .TEST_MODE  (TEST_MODE            ),
  .TEST_SE    (TEST_SE              ),
  .RSTJ       (CLK_RSTJ             )
);

endmodule


module PLL_PD_GEN (
 input   wire  PLL_PD_IN    ,
 output  wire  PLL_PD_OUT   ,

 input   wire  PLL_CLK      ,
 input   wire  PLL_RSTJ
);

reg [7:0] REF_CNT ;

always @ (posedge PLL_CLK or negedge PLL_RSTJ)begin
  if(!PLL_RSTJ)
    REF_CNT <= 8'b0 ;
  else if (!PLL_PD_IN)
    REF_CNT <= 8'b0 ;
  else if (REF_CNT == 8'd100)
    REF_CNT <= REF_CNT ;
  else
    REF_CNT <= REF_CNT + 8'b1;  
end

reg REF_FLAG ; 
 
always @ (posedge PLL_CLK or negedge PLL_RSTJ)begin
  if(!PLL_RSTJ)
    REF_FLAG <= 1'b0 ;
  else if (!PLL_PD_IN)
    REF_FLAG <= 1'b0 ;
  else if(REF_CNT == 8'd100)
    REF_FLAG <= 1'b1 ;
end

assign PLL_PD_OUT = ~REF_FLAG ;

endmodule


//==============================================================================
// PLL_SYS_DFS_CTRL: DFS FSM (CLK is the free-running PLL_SYS_CLK)
//
//   IDLE     --INT_EN rise, latch DFS_MODE / PLL_UPD / DIV2-->
//   WAIT_WFI --both cores in WFI (stable WFI_STABLE_CYC)--> (INT_EN cleared in WAIT_WFI returns to IDLE)
//   CLK_OFF  : MODE=1 ports switch to 24M (CLK_PLL_OSC=1), MODE=0 ports stay on the PLL path; wait CLK_SW_CYC,
//              then (PLL_UPD) close the common GATE and wait for its handshake
//   PD       : pd=1 (PLL_UPD only); update DIV2_SEL
//   APPLY    : CFG_LOAD, hold pd for PD_CYC (PLL_UPD only)
//   WAIT_LOCK: pd=0, wait SETTLE_CYC, then stable LOCK / timeout
//   CLK_ON   : open GATE, wait for its handshake, then switch 24M ports back to PLL and wait CLK_SW_CYC
//   DONE     : set interrupt status (W1C) --> IDLE
//
//   GATE is pure hardware: 0 only around the PLL power down (CLK_OFF .. WAIT_LOCK with PLL_UPD), 1 otherwise.
//   A MODE=0 port has no clock while GATE is 0; with PLL_UPD=0 its divider switches through the glitch-free mux.
//   The glitch-free muxes need both input clocks while switching, so the GATE closes only after the 24M switch
//   is done and opens before switching back.
//==============================================================================
module PLL_SYS_DFS_CTRL #(
    parameter CNT_W            = 16,
    parameter N_PORT           = 2,      // number of PLL output ports
    parameter WFI_STABLE_CYC   = 2,      // cycles WFI must stay high continuously (>=1)
    parameter PD_CYC           = 100,    // pd hold cycles after config load (>=1us)
    parameter CLK_SW_CYC       = 16,     // clk_switch switch wait cycles (>=1)
    parameter SETTLE_CYC       = 16,     // wait cycles after power up before checking LOCK
    parameter LOCK_STABLE_CYC  = 8,      // cycles LOCK must stay high continuously (>=1)
    parameter LOCK_TIMEOUT_CYC = 0,      // LOCK timeout cycles (0: no timeout)
    parameter WFI_PULSE        = 1       // 1: CORE_WFI_MODE_* may be pulses (sticky capture), 0: levels only
)(
    input  wire              CLK            ,
    input  wire              RSTJ           ,
    input  wire              INT_EN         ,  // rising edge starts DFS, interrupt enable (mask)
    input  wire              INT_CLR        ,  // W1C strobe of the interrupt status (pulse or level, INT_CLR_CLK domain)
    input  wire              INT_CLR_CLK    ,  // clock of INT_CLR
    input  wire [N_PORT-1:0] DFS_MODE       ,  // CLK_PLL_OSC during DFS, 1: switch to 24M, 0: stay on PLL (stopped by GATE)
    input  wire              PLL_UPD        ,  // 1: reprogram PLL (GATE + pd + CFG_LOAD + relock), 0: keep PLL
    input  wire [N_PORT-1:0] DIV2           ,  // port divider after DFS, 1: /2, 0: /1
    input  wire              CORE_WFI_MODE_0,
    input  wire              CORE_WFI_MODE_1,
    input  wire              CORE_CLK       ,  // clock of CORE_WFI_MODE_0/1
    input  wire              PLL_LOCK       ,

    output reg  [N_PORT-1:0] SEL_24M        ,  // CLK_PLL_OSC (1: 24M)
    output reg               GATE_EN        ,  // common GATE enable of all ports (0 only around PLL power down)
    output reg  [N_PORT-1:0] DIV2_SEL       ,  // A45_SRC_CLK_SEL (1: /2)

    input  wire [N_PORT-1:0] GATE_EN_FB     ,  // GATE_EN synced in each port clock domain, handshake feedback

    output wire              CFG_LOAD       ,  // load PLL config (one cycle, pd already 1; PLL_UPD only)
    output reg               PLL_PD         ,  // PLL pd (active high)
    output wire              DFS_BUSY       ,
    output reg               DFS_DONE       ,
    output reg               LOCK_TIMEOUT   ,
    output reg               LOCK_INT
);

localparam ST_IDLE      = 3'd0;
localparam ST_WAIT_WFI  = 3'd1;   // step 3
localparam ST_CLK_OFF   = 3'd2;   // step 4
localparam ST_PD        = 3'd3;   // step 5
localparam ST_APPLY     = 3'd4;   // step 6
localparam ST_WAIT_LOCK = 3'd5;   // step 7
localparam ST_CLK_ON    = 3'd6;   // step 8
localparam ST_DONE      = 3'd7;   // step 9

reg  [2:0]        STATE, STATE_NXT;
reg  [CNT_W-1:0]  CNT;
reg  [CNT_W-1:0]  TMO_CNT;
reg  [N_PORT-1:0] MODE_L;
reg               PLL_UPD_L;
reg  [N_PORT-1:0] DIV2_L;

// synchronizers
wire              INT_EN_S, WFI0_S, WFI1_S, LOCK_S;
wire [N_PORT-1:0] GATE_FB_S;
reg               INT_EN_S_D;

PLL_DFS_SYNC2 U_SYNC_INTEN (.CLK(CLK), .RSTJ(RSTJ), .D(INT_EN         ), .Q(INT_EN_S));
PLL_DFS_SYNC2 U_SYNC_LOCK  (.CLK(CLK), .RSTJ(RSTJ), .D(PLL_LOCK       ), .Q(LOCK_S  ));

PLL_DFS_SYNC2 #(.RST_VAL(1'b1)) U_SYNC_FB0 (.CLK(CLK), .RSTJ(RSTJ), .D(GATE_EN_FB[0]), .Q(GATE_FB_S[0]));
PLL_DFS_SYNC2 #(.RST_VAL(1'b1)) U_SYNC_FB1 (.CLK(CLK), .RSTJ(RSTJ), .D(GATE_EN_FB[1]), .Q(GATE_FB_S[1]));

// WFI CDC: CORE_CLK (fast) -> CLK (slow)
//   WFI_PULSE = 1: sticky capture in CORE_CLK domain, armed by INT_EN, so a 1-cycle pulse is never missed
//   WFI_PULSE = 0: level, synced directly
wire       ARM_C;
reg  [1:0] WFI_SEEN;
wire       WFI0_IN = WFI_PULSE ? WFI_SEEN[0] : CORE_WFI_MODE_0;
wire       WFI1_IN = WFI_PULSE ? WFI_SEEN[1] : CORE_WFI_MODE_1;

PLL_DFS_SYNC2 U_SYNC_ARM (.CLK(CORE_CLK), .RSTJ(RSTJ), .D(INT_EN), .Q(ARM_C));

always @(posedge CORE_CLK or negedge RSTJ)
    if (!RSTJ)       WFI_SEEN <= 2'b00;
    else if (!ARM_C) WFI_SEEN <= 2'b00;
    else             WFI_SEEN <= WFI_SEEN | {CORE_WFI_MODE_1, CORE_WFI_MODE_0};

PLL_DFS_SYNC2 U_SYNC_WFI0  (.CLK(CLK), .RSTJ(RSTJ), .D(WFI0_IN), .Q(WFI0_S));
PLL_DFS_SYNC2 U_SYNC_WFI1  (.CLK(CLK), .RSTJ(RSTJ), .D(WFI1_IN), .Q(WFI1_S));

always @(posedge CLK or negedge RSTJ)
    if (!RSTJ) INT_EN_S_D <= 1'b0;
    else       INT_EN_S_D <= INT_EN_S;

wire START      = INT_EN_S & ~INT_EN_S_D;
wire WFI_ALL    = WFI0_S & WFI1_S;
wire CLK_OFF_OK = !PLL_UPD_L || !(|GATE_FB_S);  // PLL_UPD: GATE closed in all port clock domains
wire CLK_ON_OK  = &GATE_FB_S;                   // GATE open in all port clock domains

wire CNT_HIT    = (CNT == {CNT_W{1'b0}});
wire TMO_EN     = (LOCK_TIMEOUT_CYC != 0);
wire TMO_HIT    = TMO_EN & (TMO_CNT == {CNT_W{1'b0}});
wire LOCK_OK    = LOCK_S & CNT_HIT;

always @(*) begin
    STATE_NXT = STATE;
    case (STATE)
        ST_IDLE     : if (START)                        STATE_NXT = ST_WAIT_WFI;
        ST_WAIT_WFI : if (!INT_EN_S)                    STATE_NXT = ST_IDLE;      // SW cancel
                      else if (WFI_ALL && CNT_HIT)      STATE_NXT = ST_CLK_OFF;
        ST_CLK_OFF  : if (CLK_OFF_OK && CNT_HIT)        STATE_NXT = ST_PD;
        ST_PD       :                                   STATE_NXT = ST_APPLY;
        ST_APPLY    : if (CNT_HIT)                      STATE_NXT = ST_WAIT_LOCK;
        ST_WAIT_LOCK: if (LOCK_OK || TMO_HIT)           STATE_NXT = ST_CLK_ON;
        ST_CLK_ON   : if (CLK_ON_OK && CNT_HIT)         STATE_NXT = ST_DONE;
        ST_DONE     :                                   STATE_NXT = ST_IDLE;
        default     :                                   STATE_NXT = ST_IDLE;
    endcase
end

always @(posedge CLK or negedge RSTJ)
    if (!RSTJ) STATE <= ST_IDLE;
    else       STATE <= STATE_NXT;

always @(posedge CLK or negedge RSTJ)
    if (!RSTJ) begin
        MODE_L    <= {N_PORT{1'b0}};
        PLL_UPD_L <= 1'b1;
        DIV2_L    <= {N_PORT{1'b0}};
    end
    else if (START) begin
        MODE_L    <= DFS_MODE;
        PLL_UPD_L <= PLL_UPD;
        DIV2_L    <= DIV2;
    end

// shared counter: loaded on state entry, counts down to 0 within the state
always @(posedge CLK or negedge RSTJ) begin
    if (!RSTJ)
        CNT <= {CNT_W{1'b0}};
    else begin
        case (STATE)
            ST_IDLE     : CNT <= WFI_STABLE_CYC - 1;
            ST_WAIT_WFI : if (!WFI_ALL)               CNT <= WFI_STABLE_CYC - 1;   // WFI must stay high continuously
                          else if (!CNT_HIT)          CNT <= CNT - 1'b1;
                          else                        CNT <= CLK_SW_CYC - 1;
            ST_CLK_OFF  : if (!CNT_HIT)               CNT <= CNT - 1'b1;
            ST_PD       : CNT <= PLL_UPD_L ? PD_CYC - 1 : {CNT_W{1'b0}};
            ST_APPLY    : if (!CNT_HIT)               CNT <= CNT - 1'b1;
                          else                        CNT <= SETTLE_CYC + LOCK_STABLE_CYC - 1;
            ST_WAIT_LOCK: if (LOCK_OK || TMO_HIT)     CNT <= CLK_SW_CYC - 1;
                          else if (CNT < LOCK_STABLE_CYC && !LOCK_S)
                                                      CNT <= LOCK_STABLE_CYC - 1;  // LOCK must stay high continuously
                          else if (!CNT_HIT)          CNT <= CNT - 1'b1;
            ST_CLK_ON   : if (!CLK_ON_OK)             CNT <= CLK_SW_CYC - 1;       // count after GATE is open
                          else if (!CNT_HIT)          CNT <= CNT - 1'b1;
            default     : CNT <= {CNT_W{1'b0}};
        endcase
    end
end

// LOCK timeout counter
always @(posedge CLK or negedge RSTJ)
    if (!RSTJ)                        TMO_CNT <= {CNT_W{1'b0}};
    else if (STATE != ST_WAIT_LOCK)   TMO_CNT <= TMO_EN ? LOCK_TIMEOUT_CYC - 1 : 0;
    else if (!TMO_HIT)                TMO_CNT <= TMO_CNT - 1'b1;

wire TIMEOUT_NOW = (STATE == ST_WAIT_LOCK) && TMO_HIT && !LOCK_OK;

// CLK_PLL_OSC: CLK_OFF switches MODE=1 ports to 24M; CLK_ON switches back once the GATE is open
// (on LOCK timeout, MODE=1 ports stay on 24M)
always @(posedge CLK or negedge RSTJ) begin
    if (!RSTJ)
        SEL_24M <= {N_PORT{1'b0}};
    else if (STATE == ST_WAIT_WFI && STATE_NXT == ST_CLK_OFF)
        SEL_24M <= MODE_L;
    else if (STATE == ST_CLK_ON && CLK_ON_OK)
        SEL_24M <= LOCK_TIMEOUT ? MODE_L : {N_PORT{1'b0}};
end

// common GATE: closed after the 24M switch and before PLL power down, opened after LOCK (or timeout);
// always 1 when PLL_UPD = 0
always @(posedge CLK or negedge RSTJ) begin
    if (!RSTJ)
        GATE_EN <= 1'b1;
    else if (STATE == ST_CLK_OFF && CNT_HIT && PLL_UPD_L)
        GATE_EN <= 1'b0;
    else if (STATE == ST_WAIT_LOCK && STATE_NXT == ST_CLK_ON)
        GATE_EN <= 1'b1;
end

// load config one cycle after pd=1
assign CFG_LOAD = (STATE == ST_PD) && PLL_UPD_L;

// port divider: switched while ports are gated / on 24M (or through the glitch-free mux when PLL_UPD = 0)
always @(posedge CLK or negedge RSTJ)
    if (!RSTJ)                 DIV2_SEL <= {N_PORT{1'b0}};
    else if (STATE == ST_PD)   DIV2_SEL <= DIV2_L;

// pd: set on entering PD, held PD_CYC cycles after load, released on entering WAIT_LOCK (PLL_UPD only)
always @(posedge CLK or negedge RSTJ)
    if (!RSTJ) PLL_PD <= 1'b0;
    else       PLL_PD <= PLL_UPD_L && ((STATE_NXT == ST_PD) || (STATE_NXT == ST_APPLY));

assign DFS_BUSY = (STATE != ST_IDLE);

always @(posedge CLK or negedge RSTJ) begin
    if (!RSTJ) begin
        DFS_DONE     <= 1'b0;
        LOCK_TIMEOUT <= 1'b0;
    end
    else if (START) begin
        DFS_DONE     <= 1'b0;
        LOCK_TIMEOUT <= 1'b0;
    end
    else begin
        if (STATE == ST_DONE)
            DFS_DONE <= 1'b1;
        if (TIMEOUT_NOW)
            LOCK_TIMEOUT <= 1'b1;
    end
end

// W1C strobe CDC: INT_CLR_CLK -> CLK (toggle synchronizer, any clock ratio)
reg  INT_CLR_D, INT_CLR_TGL, INT_CLR_TGL_S_D;
wire INT_CLR_TGL_S;

always @(posedge INT_CLR_CLK or negedge RSTJ)
    if (!RSTJ) begin
        INT_CLR_D   <= 1'b0;
        INT_CLR_TGL <= 1'b0;
    end
    else begin
        INT_CLR_D   <= INT_CLR;
        if (INT_CLR && !INT_CLR_D)
            INT_CLR_TGL <= ~INT_CLR_TGL;
    end

PLL_DFS_SYNC2 U_SYNC_INT_CLR (.CLK(CLK), .RSTJ(RSTJ), .D(INT_CLR_TGL), .Q(INT_CLR_TGL_S));

always @(posedge CLK or negedge RSTJ)
    if (!RSTJ) INT_CLR_TGL_S_D <= 1'b0;
    else       INT_CLR_TGL_S_D <= INT_CLR_TGL_S;

wire INT_CLR_P = INT_CLR_TGL_S ^ INT_CLR_TGL_S_D;

// interrupt status: set after ports are restored, write-1-to-clear; set has priority
reg INT_STATUS;
always @(posedge CLK or negedge RSTJ)
    if (!RSTJ)                  INT_STATUS <= 1'b0;
    else if (STATE == ST_DONE)  INT_STATUS <= 1'b1;
    else if (INT_CLR_P)         INT_STATUS <= 1'b0;

// interrupt output: status masked by INT_EN
always @(posedge CLK or negedge RSTJ)
    if (!RSTJ) LOCK_INT <= 1'b0;
    else       LOCK_INT <= INT_STATUS & INT_EN_S;

endmodule


//==============================================================================
// 2-stage synchronizer (replace with the library sync cell in synthesis)
//==============================================================================
module PLL_DFS_SYNC2 #(
    parameter RST_VAL = 1'b0
)(
    input  wire CLK  ,
    input  wire RSTJ ,
    input  wire D    ,
    output wire Q
);
reg [1:0] SYNC ;
always @(posedge CLK or negedge RSTJ)
    if (!RSTJ) SYNC <= {2{RST_VAL}};
    else       SYNC <= {SYNC[0], D};
assign Q = SYNC[1];
endmodule


//==============================================================================
module tb_PLL_SYS_SHELL;
reg osc = 0, rstj = 0, scu_clk = 0;
always #20.833 osc = ~osc;                   // 24MHz, also used as PLL_SYS_CLK
always #2.5    scu_clk = ~scu_clk;          // 200MHz SCU / APB clock

reg  [31:0] cfg0; reg [28:0] cfg1; reg [31:0] cfg2;
reg  cfg_en = 0, int_en = 0, int_clr = 0, wfi0 = 0, wfi1 = 0;
reg  [1:0] mode = 0;
reg        upd = 1;
reg  [1:0] div2 = 0;
wire f600, f400, lock, irq, busy, done, tmo;
integer err = 0;

`ifdef WFI_LEVEL
localparam WFI_PULSE = 0;
`else
localparam WFI_PULSE = 1;
`endif

PLL_SYS_SHELL #(.DFS_LOCK_TIMEOUT_CYC(2000), .DFS_WFI_PULSE(WFI_PULSE)) dut (
    .PLL_SYS_F600_CLK(f600), .PLL_SYS_F400_CLK(f400), .PLL_SYS_LOCK(lock),
    .PLL_SYS_TESTOUT(), .PLL_SYS_TBLADDR(), .PLL_SYS_TEST_DIV1_CLK(), .PLL_SYS_TEST_DIV2_CLK(),
    .PLL_SYS_SCAN_DIV1_CLK(), .PLL_SYS_SCAN_DIV2_CLK(),
    .PLL_SYS_CLK_DIV1(8'h3b), .PLL_SYS_CLK_DIV2(8'h27),
    .PLL_SYS_CFG_0(cfg0), .PLL_SYS_CFG_1(cfg1), .PLL_SYS_CFG_2(cfg2), .PLL_SYS_CFG_EN(cfg_en),
    .PLL_SYS_DFS_MODE(mode), .PLL_SYS_DFS_PLL_UPD(upd), .PLL_SYS_DFS_DIV2(div2), .PLL_SYS_INT_EN(int_en),
    .PLL_SYS_INT_CLR(int_clr), .SCU_CLK(scu_clk),
    .CORE_WFI_MODE_0(wfi0), .CORE_WFI_MODE_1(wfi1), .CORE_CLK(f600),
    .PLL_SYS_LOCK_INT(irq), .PLL_SYS_DFS_BUSY(busy), .PLL_SYS_DFS_DONE(done), .PLL_SYS_LOCK_TIMEOUT(tmo),
    .DFT_CPU_SPEED_SEL(2'b00), .MBIST_ES_MODE(1'b0), .TEST_MODE(1'b0),
    .OSC_24M_CLK(osc), .PLL_SYS_CLK(osc), .PLL_DFT_RSTJ(1'b1), .PLL_SYS_RSTJ(rstj));

// Config (same CFG bit mapping as the shell): DIS_SSCG=1, DACPD=1, DSMPD=1 (shared with PD_REG)
task set_cfg(input [11:0] ni, input [4:0] m, input [2:0] q0, input [2:0] q1);
begin
    cfg0 = {1'b0, 1'b0, 1'b1, m, 24'd0};
    cfg1 = {1'b0, 3'd0, 3'd0, q1, q0, 2'd0, 1'b1, 1'b1, ni};
    cfg2 = {1'b0, 3'd0, 4'd1, 3'd3, 3'd2, 2'd1, 8'd0, 8'd0};
end
endtask

// ---------------- checks ----------------
wire [2:0] st = dut.U_PLL_SYS_DFS_CTRL.STATE;
wire [1:0] ml = dut.U_PLL_SYS_DFS_CTRL.MODE_L;
// 1) divider changes only while pd=1 (during DFS); 2) pd released >= 1us after divider change
realtime cfg_t = 0;
always @(dut.PLL_SYS_FBDIV_REG or dut.PLL_SYS_PREDIV_REG or dut.PLL_SYS_POSTDIV0_0_REG or dut.PLL_SYS_POSTDIV0_1_REG) begin
    cfg_t = $realtime;
    if (rstj && busy && !dut.PLL_SYS_PD_ALL) begin err = err + 1; $display("ERR: divider changed while pd=0"); end
end
always @(negedge dut.PLL_SYS_PD_ALL)
    if (rstj && busy && $realtime - cfg_t < 1000.0) begin err = err + 1; $display("ERR: pd released < 1us after divider set"); end
// 3) during PD..WAIT_LOCK: 24M-mode ports run only at 24M; PLL-path ports have no clock if the PLL is reprogrammed
// 4) glitch-free outputs: every high/low phase >= 0.75ns (fastest PLL half period ~0.835ns)
realtime l600 = 0, l400 = 0, e600 = 0, e400 = 0;
always @(posedge f600) if (st >= 3 && st <= 5) begin
    if (!ml[0]) begin if (dut.U_PLL_SYS_DFS_CTRL.PLL_UPD_L) begin err = err + 1; $display("ERR: F600 edge while gated"); end end
    else if (l600 != 0 && $realtime - l600 < 40.0) begin err = err + 1; $display("ERR: F600 not 24M during pd"); end
    l600 = $realtime;
end else l600 = 0;
always @(posedge f400) if (st >= 3 && st <= 5) begin
    if (!ml[1]) begin if (dut.U_PLL_SYS_DFS_CTRL.PLL_UPD_L) begin err = err + 1; $display("ERR: F400 edge while gated"); end end
    else if (l400 != 0 && $realtime - l400 < 40.0) begin err = err + 1; $display("ERR: F400 not 24M during pd"); end
    l400 = $realtime;
end else l400 = 0;
// 5) 24M-mode ports must keep running at 24M during pd
always @(posedge dut.U_PLL_SYS_DFS_CTRL.CLK) if (st == 4 && dut.U_PLL_SYS_DFS_CTRL.STATE_NXT == 5 && dut.U_PLL_SYS_DFS_CTRL.PLL_UPD_L) begin
    if (ml[0] && l600 == 0) begin err = err + 1; $display("ERR: F600 no 24M clock during pd"); end
    if (ml[1] && l400 == 0) begin err = err + 1; $display("ERR: F400 no 24M clock during pd"); end
end
always @(f600) begin if (rstj && e600 != 0 && $realtime - e600 < 0.75) begin err = err + 1; $display("ERR: F600 glitch @%0t", $time); end e600 = $realtime; end
always @(f400) begin if (rstj && e400 != 0 && $realtime - e400 < 0.75) begin err = err + 1; $display("ERR: F400 glitch @%0t", $time); end e400 = $realtime; end

// 6) PLL_UPD = 0: PLL must not be powered down and its config must not change
always @(posedge dut.PLL_SYS_PD_ALL) if (rstj && busy && !dut.U_PLL_SYS_DFS_CTRL.PLL_UPD_L) begin err = err + 1; $display("ERR: pd asserted with PLL_UPD=0"); end
always @(dut.PLL_SYS_FBDIV_REG or dut.PLL_SYS_POSTDIV0_0_REG) if (rstj && busy && !dut.U_PLL_SYS_DFS_CTRL.PLL_UPD_L) begin err = err + 1; $display("ERR: PLL config changed with PLL_UPD=0"); end

// 8) the common GATE is 0 only around the PLL power down (CLK_OFF..WAIT_LOCK with PLL_UPD)
always @(posedge osc) #1 if (rstj && !dut.PLL_SYS_DFS_GATE_EN &&
                            !(dut.U_PLL_SYS_DFS_CTRL.PLL_UPD_L && st >= 2 && st <= 5)) begin
    err = err + 1; $display("ERR: GATE closed outside PLL power down @%0t", $time); end

// 7) when the interrupt fires, both glitch-free muxes have finished switching to the target clock
//    (uses behavioral CLK_SWITCH_2MUX1 internals, skipped with +define+USE_LIB_CELLS)
`ifndef USE_LIB_CELLS
always @(posedge irq) begin
    if (dut.U_PLL_SYS_A45_DIV_CLK_SEL.SEL_CLKA_DLY3 !== dut.PLL_SYS_DFS_DIV2_SEL[0]) begin err = err + 1; $display("ERR: divider mux not settled at IRQ"); end
    if (dut.U_PLL_SYS_A45_SRC_CLK_SEL.SEL_CLKB_DLY3 !== dut.PLL_SYS_DFS_SEL_24M[0] ||
        dut.U_PLL_SYS_F400_CLK_SEL.SEL_CLKB_DLY3    !== dut.PLL_SYS_DFS_SEL_24M[1]) begin err = err + 1; $display("ERR: 24M mux not settled at IRQ"); end
end
`endif

// SCU W1C write: 1-cycle strobe in the 200MHz SCU_CLK domain (shorter than one PLL_SYS_CLK cycle)
task w1c_int;
begin
    @(posedge scu_clk) #0.1 int_clr = 1;
    @(posedge scu_clk) #0.1 int_clr = 0;
end
endtask

// CPU model: interrupt wakes it from WFI; ISR clears the status by W1C (INT_EN stays 1),
// then INT_EN is cleared later (end of boot) so the next DFS gets a new rising edge
always @(posedge irq) begin
    #50 wfi0 = 0; wfi1 = 0;
    $display("[%0t] IRQ: mode=%b NI=%0d M=%0d done=%b tmo=%b", $time, ml,
             dut.PLL_SYS_FBDIV_REG, dut.PLL_SYS_PREDIV_REG, done, tmo);
    #200 w1c_int;
    #300 if (irq) begin err = err + 1; $display("ERR: interrupt not cleared by W1C"); end
    #200 int_en = 0;
end

task measure(input real exp600, input real exp400);
real a, b, c, d;
begin
    @(posedge f600) a = $realtime; @(posedge f600) b = $realtime;
    @(posedge f400) c = $realtime; @(posedge f400) d = $realtime;
    $display("  F600 = %0.1f MHz, F400 = %0.1f MHz", 1000.0/(b-a), 1000.0/(d-c));
    if (1000.0/(b-a) < exp600-2 || 1000.0/(b-a) > exp600+2 ||
        1000.0/(d-c) < exp400-2 || 1000.0/(d-c) > exp400+2) begin err = err + 1; $display("ERR: freq"); end
end
endtask

// WFI as a 1-cycle pulse in the CPU clock (F600) domain
task wfi_pulse(input integer core);
begin
    @(posedge f600) #0.1; if (core == 0) wfi0 = 1; else wfi1 = 1;
    @(posedge f600) #0.1; if (core == 0) wfi0 = 0; else wfi1 = 0;
end
endtask

reg pulse_mode = 0;
task dfs(input [1:0] md, input [11:0] ni, input [4:0] m, input [2:0] q0, input [2:0] q1);
begin
    set_cfg(ni, m, q0, q1); mode = md;       // SW 1.1 / 1.2
    #100 int_en = 1;                         // SW 1.3
    if (pulse_mode) begin                    // SW 2: WFI
        #500 wfi_pulse(0); #300 wfi_pulse(1);
    end else begin
        #500 wfi0 = 1; #300 wfi1 = 1;
    end
    wait (irq); wait (!irq);
    #500;
    if (busy || !done) begin err = err + 1; $display("ERR: state after dfs"); end
end
endtask

initial begin
    set_cfg(12'd250, 5'd3, 3'd3, 3'd4);
    #300 rstj = 1;
    wait (lock); #500;
    $display("boot (reset cfg):"); measure(500.0, 400.0);

    // divider only, PLL kept at 500MHz (PLL_UPD = 0)
    upd = 0;
    div2 = 2'b01; dfs(2'b00, 12'd250, 5'd3, 3'd3, 3'd4);   // A45 /2, both on PLL path -> 250 / 400
    measure(250.0, 400.0);
    div2 = 2'b01; dfs(2'b11, 12'd250, 5'd3, 3'd3, 3'd4);   // A45 /2, both on 24M     -> 250 / 400
    measure(250.0, 400.0);
    div2 = 2'b00; dfs(2'b01, 12'd250, 5'd3, 3'd3, 3'd4);   // back to /1              -> 500 / 400
    measure(500.0, 400.0);
    upd = 1;

    dfs(2'b00, 12'd399, 5'd4, 3'd3, 3'd5);   // both ports gated,   -> 598.5 / 399
    measure(598.5, 399.0);
    dfs(2'b11, 12'd333, 5'd4, 3'd3, 3'd4);   // both ports on 24M,  -> 499.5 / 399.6
    measure(499.5, 399.6);
    dfs(2'b01, 12'd399, 5'd4, 3'd3, 3'd5);   // port0 24M, port1 gate
    measure(598.5, 399.0);
    dfs(2'b10, 12'd333, 5'd4, 3'd3, 3'd4);   // port0 gate, port1 24M
    measure(499.5, 399.6);

    // LOCK timeout: port0 (24M mode) stays on 24M
`ifndef USE_PLL_MODEL
    dut.U_PLL_SYS.lock_block = 1;
`else
    force dut.U_PLL_SYS.lock = 1'b0;
`endif
    dfs(2'b01, 12'd399, 5'd4, 3'd3, 3'd5);
    if (!tmo) begin err = err + 1; $display("ERR: timeout flag"); end
    $display("timeout:"); measure(24.0, 399.0);
`ifndef USE_PLL_MODEL
    dut.U_PLL_SYS.lock_block = 0;
`else
    release dut.U_PLL_SYS.lock;
`endif
    dfs(2'b01, 12'd333, 5'd4, 3'd3, 3'd4);   // recover with another DFS
    measure(499.5, 399.6);

    if (WFI_PULSE) begin
        // WFI as 1-cycle pulses (fast -> slow CDC)
        pulse_mode = 1;
        dfs(2'b00, 12'd399, 5'd4, 3'd3, 3'd5);
        measure(598.5, 399.0);
        // a WFI pulse before INT_EN must be ignored: only core1 pulses after arming -> no DFS
        set_cfg(12'd333, 5'd4, 3'd3, 3'd4);
        wfi_pulse(0); #500 int_en = 1; #500 wfi_pulse(1); #5000;
        if (dut.U_PLL_SYS_DFS_CTRL.STATE > 1 || dut.PLL_SYS_FBDIV_REG != 399) begin err = err + 1; $display("ERR: pre-arm WFI pulse not ignored"); end
        wfi_pulse(0); wait (irq); wait (!irq); #500;   // core0 WFI after arming completes it
        if (dut.PLL_SYS_FBDIV_REG != 333) begin err = err + 1; $display("ERR: dfs after pre-arm test"); end
        measure(499.5, 399.6);
        pulse_mode = 0;
    end

    // WFI without INT_EN does not trigger DFS
    set_cfg(12'd399, 5'd4, 3'd3, 3'd5);
    wfi0 = 1; wfi1 = 1; #5000;
    if (busy || dut.PLL_SYS_FBDIV_REG != 333) begin err = err + 1; $display("ERR: dfs without INT_EN"); end
    wfi0 = 0; wfi1 = 0;

    // legacy CFG_EN path still works
    cfg_en = 1; #500 cfg_en = 0; #200;
    if (dut.PLL_SYS_FBDIV_REG != 399) begin err = err + 1; $display("ERR: legacy CFG_EN"); end

    if (err == 0) $display("TEST PASSED"); else $display("TEST FAILED err=%0d", err);
    $finish;
end
initial #5_000_000 begin $display("TIMEOUT"); $finish; end

// waveform dump: +define+FSDB (Verdi) or +define+VCD / -DVCD
`ifdef FSDB
initial begin $fsdbDumpfile("tb_PLL_SYS_SHELL.fsdb"); $fsdbDumpvars(0, tb_PLL_SYS_SHELL); end
`endif
`ifdef VCD
initial begin $dumpfile("tb_PLL_SYS_SHELL.vcd"); $dumpvars(0, tb_PLL_SYS_SHELL); end
`endif
endmodule
