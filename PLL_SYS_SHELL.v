//==========================================================================
// Module : PLL_SYS_SHELL
//   INNO PLL (SMIC40LL) wrapper for CPU / BUS clock
//   Fref = OSC_24M_CLK (24MHz)
//
//   Functional mode : divider setting selected by strap CPU_SPEED_SEL[1:0]
//   +------+----------+------+-----------+------+-----------+-----------+------+
//   | SEL  | NI       | M    | Fvco(MHz) | Mode | clko0     | clko1     | Note |
//   +------+----------+------+-----------+------+-----------+-----------+------+
//   | 2'b00| 83 +1/3  | 1    | 2000      | frac | /4  500   | /5  400   |      |
//   | 2'b01| 116+2/3  | 1    | 2800      | frac | /5  560   | /7  400   |      |
//   | 2'b10| 100      | 1    | 2400      | int  | /4  600   | /6  400   |      |
//   | 2'b11| 75       | 1    | 1800      | int  | /4  450   | /5  360   | low  |
//   +------+----------+------+-----------+------+-----------+-----------+------+
//
//   TEST_MODE / MBIST_ES_MODE : same divider setting as functional mode
//   (selected by CPU_SPEED_SEL), other PLL inputs fixed to default value
//
//   Register map (other fields come from strap, bits are reserved)
//   PLL_SYS_CFG_0[29]    : disable_sscg      default 1
//   PLL_SYS_CFG_0[30]    : testen            default 0
//   PLL_SYS_CFG_0[31]    : pd                default 0 (1 : power down)
//   PLL_SYS_CFG_1[15:14] : testsel           default 0
//   PLL_SYS_CFG_1[28]    : sel_extwave       default 0
//   PLL_SYS_CFG_2[7:0]   : ext_maxaddr       default 0
//   PLL_SYS_CFG_2[15:8]  : extwaveval        default 0
//   PLL_SYS_CFG_2[17:16] : gvco_bias         default 1
//   PLL_SYS_CFG_2[20:18] : cpp_bias          default 2
//   PLL_SYS_CFG_2[23:21] : cpi_bias          default 3
//   PLL_SYS_CFG_2[27:24] : divval            default 1
//   PLL_SYS_CFG_2[30:28] : spread            default 0
//   PLL_SYS_CFG_2[31]    : downspread        default 0
//   PLL_SYS_CFG_EN rising edge loads all fields (incl. CLK_DIV1/2)
//==========================================================================
module PLL_SYS_SHELL (
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

    input  wire [1:0]  CPU_SPEED_SEL         ,   // strap, latched outside
    input  wire        MBIST_ES_MODE         ,
    input  wire        TEST_MODE             ,
    input  wire        OSC_24M_CLK           ,
    input  wire        PLL_SYS_CLK           ,   // register clock, NOT PLL output
    input  wire        PLL_DFT_RSTJ          ,
    input  wire        PLL_SYS_RSTJ
);

wire DFT_MODE = TEST_MODE | MBIST_ES_MODE ;

//==========================================================================
// 1. config enable : synchronize & rising edge detect
//==========================================================================
wire PLL_SYS_CFG_EN_DFT = DFT_MODE ? 1'b0 : PLL_SYS_CFG_EN ;

reg  PLL_SYS_CFG_EN_D1 ;
reg  PLL_SYS_CFG_EN_D2 ;
reg  PLL_SYS_CFG_EN_D3 ;

always @ (posedge PLL_SYS_CLK or negedge PLL_SYS_RSTJ)begin
  if(!PLL_SYS_RSTJ)begin
    PLL_SYS_CFG_EN_D1 <= 1'b0 ;
    PLL_SYS_CFG_EN_D2 <= 1'b0 ;
    PLL_SYS_CFG_EN_D3 <= 1'b0 ;
  end
  else begin
    PLL_SYS_CFG_EN_D1 <= PLL_SYS_CFG_EN_DFT ;
    PLL_SYS_CFG_EN_D2 <= PLL_SYS_CFG_EN_D1  ;
    PLL_SYS_CFG_EN_D3 <= PLL_SYS_CFG_EN_D2  ;
  end
end

wire PLL_SYS_CFG_PULSE = PLL_SYS_CFG_EN_D2 & ~PLL_SYS_CFG_EN_D3 ;

//==========================================================================
// 2. register field source
//    DFT mode : CFG_EN is blocked (no CFG_PULSE) and PLL inputs are
//               overridden in section 5, so no DFT mux is needed here.
//==========================================================================
wire  [7:0]  PLL_SYS_CLK_DIV1_TEMP     = PLL_SYS_CLK_DIV1        ;
wire  [7:0]  PLL_SYS_CLK_DIV2_TEMP     = PLL_SYS_CLK_DIV2        ;

wire         PLL_SYS_DIS_SSCG_TEMP     =  PLL_SYS_CFG_0 [29]     ;
wire         PLL_SYS_TESTEN_TEMP       =  PLL_SYS_CFG_0 [30]     ;
wire         PLL_SYS_PWRON_TEMP        = ~PLL_SYS_CFG_0 [31]     ;   // SCU pd : 1 = power down
wire  [1:0]  PLL_SYS_TESTSEL_TEMP      =  PLL_SYS_CFG_1 [15:14]  ;
wire         PLL_SYS_SEL_EXTWAVE_TEMP  =  PLL_SYS_CFG_1 [28]     ;
wire  [7:0]  PLL_SYS_EXT_MAXADDR_TEMP  =  PLL_SYS_CFG_2 [ 7: 0]  ;
wire  [7:0]  PLL_SYS_EXT_WAVEVAL_TEMP  =  PLL_SYS_CFG_2 [15: 8]  ;
wire  [1:0]  PLL_SYS_GVCO_BIAS_TEMP    =  PLL_SYS_CFG_2 [17:16]  ;
wire  [2:0]  PLL_SYS_CPP_BIAS_TEMP     =  PLL_SYS_CFG_2 [20:18]  ;
wire  [2:0]  PLL_SYS_CPI_BIAS_TEMP     =  PLL_SYS_CFG_2 [23:21]  ;
wire  [3:0]  PLL_SYS_DIVVAL_TEMP       =  PLL_SYS_CFG_2 [27:24]  ;
wire  [2:0]  PLL_SYS_SPREAD_TEMP       =  PLL_SYS_CFG_2 [30:28]  ;
wire         PLL_SYS_DOWNSPREAD_TEMP   =  PLL_SYS_CFG_2 [31]     ;

//==========================================================================
// 3. configuration register
//==========================================================================
reg   [7:0]  PLL_SYS_CLK_DIV1_REG    ;
reg   [7:0]  PLL_SYS_CLK_DIV2_REG    ;
reg          PLL_SYS_DIS_SSCG_REG    ;
reg          PLL_SYS_TESTEN_REG      ;
reg          PLL_SYS_PWRON_REG       ;
reg   [1:0]  PLL_SYS_TESTSEL_REG     ;
reg          PLL_SYS_SEL_EXTWAVE_REG ;
reg   [7:0]  PLL_SYS_EXT_MAXADDR_REG ;
reg   [7:0]  PLL_SYS_EXT_WAVEVAL_REG ;
reg   [1:0]  PLL_SYS_GVCO_BIAS_REG   ;
reg   [2:0]  PLL_SYS_CPP_BIAS_REG    ;
reg   [2:0]  PLL_SYS_CPI_BIAS_REG    ;
reg   [3:0]  PLL_SYS_DIVVAL_REG      ;
reg   [2:0]  PLL_SYS_SPREAD_REG      ;
reg          PLL_SYS_DOWNSPREAD_REG  ;

always @ (posedge PLL_SYS_CLK or negedge PLL_SYS_RSTJ)begin
  if(!PLL_SYS_RSTJ)begin
    PLL_SYS_CLK_DIV1_REG      <= 8'h3b ;
    PLL_SYS_CLK_DIV2_REG      <= 8'h27 ;
    PLL_SYS_DIS_SSCG_REG      <= 1'b1  ;    // SSC off
    PLL_SYS_TESTEN_REG        <= 1'b0  ;    // monitor off
    PLL_SYS_PWRON_REG         <= 1'b1  ;    // power on after reset
    PLL_SYS_TESTSEL_REG       <= 2'h0  ;    // 00 : lock
    PLL_SYS_SEL_EXTWAVE_REG   <= 1'b0  ;    // internal triangle wave
    PLL_SYS_EXT_MAXADDR_REG   <= 8'h0  ;
    PLL_SYS_EXT_WAVEVAL_REG   <= 8'h0  ;
    PLL_SYS_GVCO_BIAS_REG     <= 2'h1  ;    // datasheet default
    PLL_SYS_CPP_BIAS_REG      <= 3'h2  ;    // datasheet default
    PLL_SYS_CPI_BIAS_REG      <= 3'h3  ;    // datasheet default
    PLL_SYS_DIVVAL_REG        <= 4'h1  ;    // S=1
    PLL_SYS_SPREAD_REG        <= 3'h0  ;    // modulation depth 0
    PLL_SYS_DOWNSPREAD_REG    <= 1'b0  ;    // center spread
  end
  else if (PLL_SYS_CFG_PULSE) begin
    PLL_SYS_CLK_DIV1_REG      <= PLL_SYS_CLK_DIV1_TEMP      ;
    PLL_SYS_CLK_DIV2_REG      <= PLL_SYS_CLK_DIV2_TEMP      ;
    PLL_SYS_DIS_SSCG_REG      <= PLL_SYS_DIS_SSCG_TEMP      ;
    PLL_SYS_TESTEN_REG        <= PLL_SYS_TESTEN_TEMP        ;
    PLL_SYS_PWRON_REG         <= PLL_SYS_PWRON_TEMP         ;
    PLL_SYS_TESTSEL_REG       <= PLL_SYS_TESTSEL_TEMP       ;
    PLL_SYS_SEL_EXTWAVE_REG   <= PLL_SYS_SEL_EXTWAVE_TEMP   ;
    PLL_SYS_EXT_MAXADDR_REG   <= PLL_SYS_EXT_MAXADDR_TEMP   ;
    PLL_SYS_EXT_WAVEVAL_REG   <= PLL_SYS_EXT_WAVEVAL_TEMP   ;
    PLL_SYS_GVCO_BIAS_REG     <= PLL_SYS_GVCO_BIAS_TEMP     ;
    PLL_SYS_CPP_BIAS_REG      <= PLL_SYS_CPP_BIAS_TEMP      ;
    PLL_SYS_CPI_BIAS_REG      <= PLL_SYS_CPI_BIAS_TEMP      ;
    PLL_SYS_DIVVAL_REG        <= PLL_SYS_DIVVAL_TEMP        ;
    PLL_SYS_SPREAD_REG        <= PLL_SYS_SPREAD_TEMP        ;
    PLL_SYS_DOWNSPREAD_REG    <= PLL_SYS_DOWNSPREAD_TEMP    ;
  end
end

//==========================================================================
// 4. strap decode : CPU_SPEED_SEL[1:0]
//==========================================================================
wire sel_500 = (CPU_SPEED_SEL[1:0] == 2'b00);
wire sel_560 = (CPU_SPEED_SEL[1:0] == 2'b01);
wire sel_600 = (CPU_SPEED_SEL[1:0] == 2'b10);
wire sel_low = (CPU_SPEED_SEL[1:0] == 2'b11);   // low speed : 500MHz setting with VCO -10%

// 4.1 functional mode
wire [11:0] PLL_SYS_FBDIV_FUNC       = {12{sel_500}} & 12'h053    |   // NI=83   -> 500MHz
                                       {12{sel_560}} & 12'h074    |   // NI=116  -> 560MHz
                                       {12{sel_600}} & 12'h064    |   // NI=100  -> 600MHz
                                       {12{sel_low}} & 12'h04B    ;   // NI=75   -> 450MHz

wire [23:0] PLL_SYS_FRAC_FUNC        = {24{sel_500}} & 24'h555555 |   // NF=1/3  -> 500MHz
                                       {24{sel_560}} & 24'hAAAAAB |   // NF=2/3  -> 560MHz
                                       {24{sel_600}} & 24'h000000 |   // NF=0    -> 600MHz
                                       {24{sel_low}} & 24'h000000 ;   // NF=0    -> 450MHz

wire [4:0]  PLL_SYS_PREDIV_FUNC      = {5{sel_500}}  & 5'h01      |   // M=1     -> 500MHz
                                       {5{sel_560}}  & 5'h01      |   // M=1     -> 560MHz
                                       {5{sel_600}}  & 5'h01      |   // M=1     -> 600MHz
                                       {5{sel_low}}  & 5'h01      ;   // M=1     -> 450MHz

wire [2:0]  PLL_SYS_POSTDIV0_0_FUNC  = {3{sel_500}}  & 3'h3       |   // /4  -> 500MHz
                                       {3{sel_560}}  & 3'h4       |   // /5  -> 560MHz
                                       {3{sel_600}}  & 3'h3       |   // /4  -> 600MHz
                                       {3{sel_low}}  & 3'h3       ;   // /4  -> 450MHz

wire [2:0]  PLL_SYS_POSTDIV0_1_FUNC  = {3{sel_500}}  & 3'h4       |   // /5  -> 400MHz
                                       {3{sel_560}}  & 3'h6       |   // /7  -> 400MHz
                                       {3{sel_600}}  & 3'h5       |   // /6  -> 400MHz
                                       {3{sel_low}}  & 3'h4       ;   // /5  -> 360MHz

wire [2:0]  PLL_SYS_POSTDIV1_0_FUNC  = 3'h0 ;                         // /1
wire [2:0]  PLL_SYS_POSTDIV1_1_FUNC  = 3'h0 ;                         // /1

wire        PLL_SYS_DACPD_FUNC       = sel_600 | sel_low ;            // 0 : frac , 1 : int
wire        PLL_SYS_DSMPD_FUNC       = sel_600 | sel_low ;            // 0 : frac , 1 : int

//==========================================================================
// 5. PLL input select : divider from strap, register fields fixed in DFT mode
//==========================================================================

wire  [11:0] PLL_SYS_FBDIV         =  PLL_SYS_FBDIV_FUNC      ;// NI
wire  [23:0] PLL_SYS_FRAC          =  PLL_SYS_FRAC_FUNC       ;
wire  [4:0]  PLL_SYS_PREDIV        =  PLL_SYS_PREDIV_FUNC     ;// M
wire  [2:0]  PLL_SYS_POSTDIV0_0    =  PLL_SYS_POSTDIV0_0_FUNC ;
wire  [2:0]  PLL_SYS_POSTDIV0_1    =  PLL_SYS_POSTDIV0_1_FUNC ;
wire  [2:0]  PLL_SYS_POSTDIV1_0    =  PLL_SYS_POSTDIV1_0_FUNC ;
wire  [2:0]  PLL_SYS_POSTDIV1_1    =  PLL_SYS_POSTDIV1_1_FUNC ;
wire         PLL_SYS_DACPD         =  PLL_SYS_DACPD_FUNC      ;
wire         PLL_SYS_DSMPD         =  PLL_SYS_DSMPD_FUNC      ;

wire         PLL_SYS_DIS_SSCG      = DFT_MODE  ? 1'b1             : PLL_SYS_DIS_SSCG_REG    ;
wire         PLL_SYS_TESTEN        = DFT_MODE  ? 1'b0             : PLL_SYS_TESTEN_REG      ;
wire  [1:0]  PLL_SYS_TESTSEL       = DFT_MODE  ? 2'h0             : PLL_SYS_TESTSEL_REG     ;
wire         PLL_SYS_SEL_EXTWAVE   = DFT_MODE  ? 1'b0             : PLL_SYS_SEL_EXTWAVE_REG ;
wire  [7:0]  PLL_SYS_EXT_MAXADDR   = DFT_MODE  ? 8'h0             : PLL_SYS_EXT_MAXADDR_REG ;
wire  [7:0]  PLL_SYS_EXT_WAVEVAL   = DFT_MODE  ? 8'h0             : PLL_SYS_EXT_WAVEVAL_REG ;
wire  [1:0]  PLL_SYS_GVCO_BIAS     = DFT_MODE  ? 2'h1             : PLL_SYS_GVCO_BIAS_REG   ;
wire  [2:0]  PLL_SYS_CPP_BIAS      = DFT_MODE  ? 3'h2             : PLL_SYS_CPP_BIAS_REG    ;
wire  [2:0]  PLL_SYS_CPI_BIAS      = DFT_MODE  ? 3'h3             : PLL_SYS_CPI_BIAS_REG    ;
wire  [3:0]  PLL_SYS_DIVVAL        = DFT_MODE  ? 4'h1             : PLL_SYS_DIVVAL_REG      ;
wire  [2:0]  PLL_SYS_SPREAD        = DFT_MODE  ? 3'h0             : PLL_SYS_SPREAD_REG      ;
wire         PLL_SYS_DOWNSPREAD    = DFT_MODE  ? 1'b0             : PLL_SYS_DOWNSPREAD_REG  ;

wire  [7:0]  PLL_SYS_CLK_DIV1_SEL  = DFT_MODE  ? 8'h3b            : PLL_SYS_CLK_DIV1_REG    ;
wire  [7:0]  PLL_SYS_CLK_DIV2_SEL  = DFT_MODE  ? 8'h27            : PLL_SYS_CLK_DIV2_REG    ;

//==========================================================================
// 6. power down : pd released 100 PLL_SYS_CLK cycles after power on request
//==========================================================================
wire  PLL_SYS_PWRON_DFT_SEL = TEST_MODE ? PLL_DFT_RSTJ : MBIST_ES_MODE ? 1'b1 : PLL_SYS_PWRON_REG ;
wire  PLL_SYS_PD ;

PLL_PD_GEN U_PLL_PD_GEN (
    .PLL_PD_IN    (PLL_SYS_PWRON_DFT_SEL ),   // 1 : power on request
    .PLL_PD_OUT   (PLL_SYS_PD            ),
    .PLL_CLK      (PLL_SYS_CLK           ),
    .PLL_RSTJ     (PLL_SYS_RSTJ          )
);

//==========================================================================
// 7. PLL instance
//==========================================================================
wire PLL_SYS_F600_OUT_CLK ;   // clko0 : CPU
wire PLL_SYS_F400_OUT_CLK ;   // clko1 : BUS/IP

INNO_PLL_TOP U_PLL_SYS (
    // Outputs
    .tbladdr        (PLL_SYS_TBLADDR      ),
    .lock           (PLL_SYS_LOCK         ),
    .testout        (PLL_SYS_TESTOUT      ),
    .clko0          (PLL_SYS_F600_OUT_CLK ),
    .clko1          (PLL_SYS_F400_OUT_CLK ),
    // Inputs
    .refclk         (OSC_24M_CLK          ),
    .pd             (PLL_SYS_PD           ),
    .prediv         (PLL_SYS_PREDIV       ),   // M
    .fbdiv          (PLL_SYS_FBDIV        ),   // NI
    .frac           (PLL_SYS_FRAC         ),   // NF
    .postdiv0_0     (PLL_SYS_POSTDIV0_0   ),   // Q0_0
    .postdiv0_1     (PLL_SYS_POSTDIV0_1   ),   // Q0_1
    .postdiv1_0     (PLL_SYS_POSTDIV1_0   ),   // Q1_0
    .postdiv1_1     (PLL_SYS_POSTDIV1_1   ),   // Q1_1
    .gvco_bias      (PLL_SYS_GVCO_BIAS    ),
    .cpp_bias       (PLL_SYS_CPP_BIAS     ),
    .cpi_bias       (PLL_SYS_CPI_BIAS     ),
    .dacpd          (PLL_SYS_DACPD        ),
    .dsmpd          (PLL_SYS_DSMPD        ),
    .testen         (PLL_SYS_TESTEN       ),
    .testsel        (PLL_SYS_TESTSEL      ),
    .disable_sscg   (PLL_SYS_DIS_SSCG     ),
    .divval         (PLL_SYS_DIVVAL       ),
    .downspread     (PLL_SYS_DOWNSPREAD   ),
    .ext_maxaddr    (PLL_SYS_EXT_MAXADDR  ),
    .extwaveval     (PLL_SYS_EXT_WAVEVAL  ),
    .sel_extwave    (PLL_SYS_SEL_EXTWAVE  ),
    .spread         (PLL_SYS_SPREAD       )
);

//==========================================================================
// 8. output clock gate
//==========================================================================
wire PLL_SYS_CLK_EN = 1'b1 ;

P_CLK_GATE U_PLL_SYS_F600_CLK_GATE (.CLK(PLL_SYS_F600_OUT_CLK), .EN(PLL_SYS_CLK_EN), .SE(DFT_MODE), .YGCLK(PLL_SYS_F600_CLK));
P_CLK_GATE U_PLL_SYS_F400_CLK_GATE (.CLK(PLL_SYS_F400_OUT_CLK), .EN(PLL_SYS_CLK_EN), .SE(DFT_MODE), .YGCLK(PLL_SYS_F400_CLK));

//==========================================================================
// 9. scan clock
//==========================================================================
reg PLL_SYS_SCAN_DIV2_CLK_REG ;

always @ (posedge PLL_SYS_F600_CLK or negedge PLL_SYS_RSTJ)begin
  if(!PLL_SYS_RSTJ)
    PLL_SYS_SCAN_DIV2_CLK_REG <= 1'b0 ;
  else if (TEST_MODE)
    PLL_SYS_SCAN_DIV2_CLK_REG <= ~PLL_SYS_SCAN_DIV2_CLK_REG ;
end

SRCKBUF U_PLL_SYS_SCAN_DIV1_CLK_BUF (.Z(PLL_SYS_SCAN_DIV1_CLK), .I(PLL_SYS_F600_CLK         ));
SRCKBUF U_PLL_SYS_SCAN_DIV2_CLK_BUF (.Z(PLL_SYS_SCAN_DIV2_CLK), .I(PLL_SYS_SCAN_DIV2_CLK_REG));

//==========================================================================
// 10. test clock divider (observe clock)
//==========================================================================
clk_div_256 U_PLL_SYS_TEST_DIV1 (.clk(PLL_SYS_F600_OUT_CLK), .rstn(PLL_SYS_RSTJ), .div(PLL_SYS_CLK_DIV1_SEL), .clk_o(PLL_SYS_TEST_DIV1_CLK));
clk_div_256 U_PLL_SYS_TEST_DIV2 (.clk(PLL_SYS_F400_OUT_CLK), .rstn(PLL_SYS_RSTJ), .div(PLL_SYS_CLK_DIV2_SEL), .clk_o(PLL_SYS_TEST_DIV2_CLK));

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
