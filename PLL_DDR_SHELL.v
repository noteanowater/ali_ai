//==========================================================================
// Module : PLL_DDR_SHELL
//   INNO PLL (SMIC40LL) wrapper for DDR clock
//   Fref = OSC_24M_CLK (24MHz)
//
//   All PLL inputs are register configurable (no strap).
//   Default (reset / DFT) = DDR-1600 setting
//   +----------+------+-----+----+---+-----------+------+------+-----------+
//   | Output   | Fref | NI  | NF | M | Fvco(MHz) | Qn_0 | Qn_1 | Fclk(MHz) |
//   +----------+------+-----+----+---+-----------+------+------+-----------+
//   | clko0    | 24   | 100 | 0  | 1 | 2400      | 5(/6)| 0(/1)| 400  DDR  |
//   | clko1    | 24   | 100 | 0  | 1 | 2400      | 7(/8)| 0(/1)| 300  IP   |
//   +----------+------+-----+----+---+-----------+------+------+-----------+
//   Fpfd = Fref / M (10~100MHz), Fvco = Fref * (NI + frac/2^24) / M (1~3.2GHz)
//
//   TEST_MODE / MBIST_ES_MODE : all PLL inputs fixed to the default above
//
//   Register map
//   PLL_DDR_CFG_0[23:0]  : frac          default 0
//   PLL_DDR_CFG_0[28:24] : prediv (M)    default 1
//   PLL_DDR_CFG_0[29]    : disable_sscg  default 1
//   PLL_DDR_CFG_0[30]    : testen        default 0
//   PLL_DDR_CFG_0[31]    : pd            default 0 (1 : power down)
//   PLL_DDR_CFG_1[11:0]  : fbdiv (NI)    default 100
//   PLL_DDR_CFG_1[12]    : dacpd         default 1
//   PLL_DDR_CFG_1[13]    : dsmpd         default 1
//   PLL_DDR_CFG_1[15:14] : testsel       default 0
//   PLL_DDR_CFG_1[18:16] : postdiv0_0    default 5 (/6)
//   PLL_DDR_CFG_1[21:19] : postdiv0_1    default 7 (/8)
//   PLL_DDR_CFG_1[24:22] : postdiv1_0    default 0 (/1)
//   PLL_DDR_CFG_1[27:25] : postdiv1_1    default 0 (/1)
//   PLL_DDR_CFG_1[28]    : sel_extwave   default 0
//   PLL_DDR_CFG_2[7:0]   : ext_maxaddr   default 0
//   PLL_DDR_CFG_2[15:8]  : extwaveval    default 0
//   PLL_DDR_CFG_2[17:16] : gvco_bias     default 1
//   PLL_DDR_CFG_2[20:18] : cpp_bias      default 2
//   PLL_DDR_CFG_2[23:21] : cpi_bias      default 3
//   PLL_DDR_CFG_2[27:24] : divval        default 1
//   PLL_DDR_CFG_2[30:28] : spread        default 0
//   PLL_DDR_CFG_2[31]    : downspread    default 0
//   PLL_DDR_CFG_EN rising edge loads all fields (incl. CLK_EN, CLK_DIV1/2)
//==========================================================================
module PLL_DDR_SHELL(
    output wire        PLL_DDR_F400_CLK      ,
    output wire        PLL_DDR_F300_CLK      ,

    output wire        PLL_DDR_LOCK          ,
    output wire        PLL_DDR_TESTOUT       ,
    output wire [7:0]  PLL_DDR_TBLADDR       ,
    output wire        PLL_DDR_TEST_DIV1_CLK ,
    output wire        PLL_DDR_TEST_DIV2_CLK ,

    input  wire        PLL_DDR_CLK_EN        ,
    input  wire [7:0]  PLL_DDR_CLK_DIV1      ,
    input  wire [7:0]  PLL_DDR_CLK_DIV2      ,
    input  wire [31:0] PLL_DDR_CFG_0         ,
    input  wire [28:0] PLL_DDR_CFG_1         ,
    input  wire [31:0] PLL_DDR_CFG_2         ,
    input  wire        PLL_DDR_CFG_EN        ,

    input  wire        TEST_MODE             ,
    input  wire        MBIST_ES_MODE         ,
    input  wire        OSC_24M_CLK           ,
    input  wire        PLL_DDR_CLK           ,   // register clock, NOT PLL output
    input  wire        PLL_DFT_RSTJ          ,
    input  wire        PLL_DDR_RSTJ
);

wire DFT_MODE = TEST_MODE | MBIST_ES_MODE ;

//==========================================================================
// 1. config enable : synchronize & rising edge detect
//==========================================================================
wire PLL_DDR_CFG_EN_DFT = DFT_MODE ? 1'b0 : PLL_DDR_CFG_EN ;

reg  PLL_DDR_CFG_EN_D1 ;
reg  PLL_DDR_CFG_EN_D2 ;
reg  PLL_DDR_CFG_EN_D3 ;

always @ (posedge PLL_DDR_CLK or negedge PLL_DDR_RSTJ)begin
  if(!PLL_DDR_RSTJ)begin
    PLL_DDR_CFG_EN_D1 <= 1'b0 ;
    PLL_DDR_CFG_EN_D2 <= 1'b0 ;
    PLL_DDR_CFG_EN_D3 <= 1'b0 ;
  end
  else begin
    PLL_DDR_CFG_EN_D1 <= PLL_DDR_CFG_EN_DFT ;
    PLL_DDR_CFG_EN_D2 <= PLL_DDR_CFG_EN_D1  ;
    PLL_DDR_CFG_EN_D3 <= PLL_DDR_CFG_EN_D2  ;
  end
end

wire PLL_DDR_CFG_PULSE = PLL_DDR_CFG_EN_D2 & ~PLL_DDR_CFG_EN_D3 ;

//==========================================================================
// 2. register field source
//    DFT mode : CFG_EN is blocked (no CFG_PULSE) and PLL inputs are
//               overridden in section 4, so no DFT mux is needed here.
//==========================================================================
wire         PLL_DDR_CLK_EN_TEMP       =  PLL_DDR_CLK_EN         ;
wire  [7:0]  PLL_DDR_CLK_DIV1_TEMP     =  PLL_DDR_CLK_DIV1       ;
wire  [7:0]  PLL_DDR_CLK_DIV2_TEMP     =  PLL_DDR_CLK_DIV2       ;

wire  [23:0] PLL_DDR_FRAC_TEMP         =  PLL_DDR_CFG_0 [23: 0]  ;
wire  [4:0]  PLL_DDR_PREDIV_TEMP       =  PLL_DDR_CFG_0 [28:24]  ;   // M
wire         PLL_DDR_DIS_SSCG_TEMP     =  PLL_DDR_CFG_0 [29]     ;
wire         PLL_DDR_TESTEN_TEMP       =  PLL_DDR_CFG_0 [30]     ;
wire         PLL_DDR_PWRON_TEMP        = ~PLL_DDR_CFG_0 [31]     ;   // SCU pd : 1 = power down
wire  [11:0] PLL_DDR_FBDIV_TEMP        =  PLL_DDR_CFG_1 [11: 0]  ;   // NI
wire         PLL_DDR_DACPD_TEMP        =  PLL_DDR_CFG_1 [12]     ;
wire         PLL_DDR_DSMPD_TEMP        =  PLL_DDR_CFG_1 [13]     ;
wire  [1:0]  PLL_DDR_TESTSEL_TEMP      =  PLL_DDR_CFG_1 [15:14]  ;
wire  [2:0]  PLL_DDR_POSTDIV0_0_TEMP   =  PLL_DDR_CFG_1 [18:16]  ;   // Q0_0
wire  [2:0]  PLL_DDR_POSTDIV0_1_TEMP   =  PLL_DDR_CFG_1 [21:19]  ;   // Q0_1
wire  [2:0]  PLL_DDR_POSTDIV1_0_TEMP   =  PLL_DDR_CFG_1 [24:22]  ;   // Q1_0
wire  [2:0]  PLL_DDR_POSTDIV1_1_TEMP   =  PLL_DDR_CFG_1 [27:25]  ;   // Q1_1
wire         PLL_DDR_SEL_EXTWAVE_TEMP  =  PLL_DDR_CFG_1 [28]     ;
wire  [7:0]  PLL_DDR_EXT_MAXADDR_TEMP  =  PLL_DDR_CFG_2 [ 7: 0]  ;
wire  [7:0]  PLL_DDR_EXT_WAVEVAL_TEMP  =  PLL_DDR_CFG_2 [15: 8]  ;
wire  [1:0]  PLL_DDR_GVCO_BIAS_TEMP    =  PLL_DDR_CFG_2 [17:16]  ;
wire  [2:0]  PLL_DDR_CPP_BIAS_TEMP     =  PLL_DDR_CFG_2 [20:18]  ;
wire  [2:0]  PLL_DDR_CPI_BIAS_TEMP     =  PLL_DDR_CFG_2 [23:21]  ;
wire  [3:0]  PLL_DDR_DIVVAL_TEMP       =  PLL_DDR_CFG_2 [27:24]  ;
wire  [2:0]  PLL_DDR_SPREAD_TEMP       =  PLL_DDR_CFG_2 [30:28]  ;
wire         PLL_DDR_DOWNSPREAD_TEMP   =  PLL_DDR_CFG_2 [31]     ;

//==========================================================================
// 3. configuration register (reset value = DDR-1600 setting)
//==========================================================================
reg          PLL_DDR_CLK_EN_REG      ;
reg   [7:0]  PLL_DDR_CLK_DIV1_REG    ;
reg   [7:0]  PLL_DDR_CLK_DIV2_REG    ;
reg   [23:0] PLL_DDR_FRAC_REG        ;
reg   [4:0]  PLL_DDR_PREDIV_REG      ;
reg          PLL_DDR_DIS_SSCG_REG    ;
reg          PLL_DDR_TESTEN_REG      ;
reg          PLL_DDR_PWRON_REG       ;
reg   [11:0] PLL_DDR_FBDIV_REG       ;
reg          PLL_DDR_DACPD_REG       ;
reg          PLL_DDR_DSMPD_REG       ;
reg   [1:0]  PLL_DDR_TESTSEL_REG     ;
reg   [2:0]  PLL_DDR_POSTDIV0_0_REG  ;
reg   [2:0]  PLL_DDR_POSTDIV0_1_REG  ;
reg   [2:0]  PLL_DDR_POSTDIV1_0_REG  ;
reg   [2:0]  PLL_DDR_POSTDIV1_1_REG  ;
reg          PLL_DDR_SEL_EXTWAVE_REG ;
reg   [7:0]  PLL_DDR_EXT_MAXADDR_REG ;
reg   [7:0]  PLL_DDR_EXT_WAVEVAL_REG ;
reg   [1:0]  PLL_DDR_GVCO_BIAS_REG   ;
reg   [2:0]  PLL_DDR_CPP_BIAS_REG    ;
reg   [2:0]  PLL_DDR_CPI_BIAS_REG    ;
reg   [3:0]  PLL_DDR_DIVVAL_REG      ;
reg   [2:0]  PLL_DDR_SPREAD_REG      ;
reg          PLL_DDR_DOWNSPREAD_REG  ;

always @ (posedge PLL_DDR_CLK or negedge PLL_DDR_RSTJ)begin
  if(!PLL_DDR_RSTJ)begin
    PLL_DDR_CLK_EN_REG        <= 1'b1    ;
    PLL_DDR_CLK_DIV1_REG      <= 8'h27   ;
    PLL_DDR_CLK_DIV2_REG      <= 8'h0c   ;
    PLL_DDR_FRAC_REG          <= 24'd0   ;    // integer mode
    PLL_DDR_PREDIV_REG        <= 5'd1    ;    // M=1    , Fpfd = 24MHz
    PLL_DDR_DIS_SSCG_REG      <= 1'b1    ;    // SSC off
    PLL_DDR_TESTEN_REG        <= 1'b0    ;    // monitor off
    PLL_DDR_PWRON_REG         <= 1'b1    ;    // power on after reset
    PLL_DDR_FBDIV_REG         <= 12'd100 ;    // NI=100 , Fvco = 2400MHz
    PLL_DDR_DACPD_REG         <= 1'b1    ;    // integer mode
    PLL_DDR_DSMPD_REG         <= 1'b1    ;    // integer mode
    PLL_DDR_TESTSEL_REG       <= 2'h0    ;    // 00 : lock
    PLL_DDR_POSTDIV0_0_REG    <= 3'd5    ;    // Q0_0 /6 -> 400MHz (DDR)
    PLL_DDR_POSTDIV0_1_REG    <= 3'd7    ;    // Q0_1 /8 -> 300MHz
    PLL_DDR_POSTDIV1_0_REG    <= 3'd0    ;    // Q1_0 /1
    PLL_DDR_POSTDIV1_1_REG    <= 3'd0    ;    // Q1_1 /1
    PLL_DDR_SEL_EXTWAVE_REG   <= 1'b0    ;    // internal triangle wave
    PLL_DDR_EXT_MAXADDR_REG   <= 8'h0    ;
    PLL_DDR_EXT_WAVEVAL_REG   <= 8'h0    ;
    PLL_DDR_GVCO_BIAS_REG     <= 2'h1    ;    // datasheet default
    PLL_DDR_CPP_BIAS_REG      <= 3'h2    ;    // datasheet default
    PLL_DDR_CPI_BIAS_REG      <= 3'h3    ;    // datasheet default
    PLL_DDR_DIVVAL_REG        <= 4'h1    ;    // S=1
    PLL_DDR_SPREAD_REG        <= 3'h0    ;    // modulation depth 0
    PLL_DDR_DOWNSPREAD_REG    <= 1'b0    ;    // center spread
  end
  else if (PLL_DDR_CFG_PULSE) begin
    PLL_DDR_CLK_EN_REG        <= PLL_DDR_CLK_EN_TEMP       ;
    PLL_DDR_CLK_DIV1_REG      <= PLL_DDR_CLK_DIV1_TEMP     ;
    PLL_DDR_CLK_DIV2_REG      <= PLL_DDR_CLK_DIV2_TEMP     ;
    PLL_DDR_FRAC_REG          <= PLL_DDR_FRAC_TEMP         ;
    PLL_DDR_PREDIV_REG        <= PLL_DDR_PREDIV_TEMP       ;
    PLL_DDR_DIS_SSCG_REG      <= PLL_DDR_DIS_SSCG_TEMP     ;
    PLL_DDR_TESTEN_REG        <= PLL_DDR_TESTEN_TEMP       ;
    PLL_DDR_PWRON_REG         <= PLL_DDR_PWRON_TEMP        ;
    PLL_DDR_FBDIV_REG         <= PLL_DDR_FBDIV_TEMP        ;
    PLL_DDR_DACPD_REG         <= PLL_DDR_DACPD_TEMP        ;
    PLL_DDR_DSMPD_REG         <= PLL_DDR_DSMPD_TEMP        ;
    PLL_DDR_TESTSEL_REG       <= PLL_DDR_TESTSEL_TEMP      ;
    PLL_DDR_POSTDIV0_0_REG    <= PLL_DDR_POSTDIV0_0_TEMP   ;
    PLL_DDR_POSTDIV0_1_REG    <= PLL_DDR_POSTDIV0_1_TEMP   ;
    PLL_DDR_POSTDIV1_0_REG    <= PLL_DDR_POSTDIV1_0_TEMP   ;
    PLL_DDR_POSTDIV1_1_REG    <= PLL_DDR_POSTDIV1_1_TEMP   ;
    PLL_DDR_SEL_EXTWAVE_REG   <= PLL_DDR_SEL_EXTWAVE_TEMP  ;
    PLL_DDR_EXT_MAXADDR_REG   <= PLL_DDR_EXT_MAXADDR_TEMP  ;
    PLL_DDR_EXT_WAVEVAL_REG   <= PLL_DDR_EXT_WAVEVAL_TEMP  ;
    PLL_DDR_GVCO_BIAS_REG     <= PLL_DDR_GVCO_BIAS_TEMP    ;
    PLL_DDR_CPP_BIAS_REG      <= PLL_DDR_CPP_BIAS_TEMP     ;
    PLL_DDR_CPI_BIAS_REG      <= PLL_DDR_CPI_BIAS_TEMP     ;
    PLL_DDR_DIVVAL_REG        <= PLL_DDR_DIVVAL_TEMP       ;
    PLL_DDR_SPREAD_REG        <= PLL_DDR_SPREAD_TEMP       ;
    PLL_DDR_DOWNSPREAD_REG    <= PLL_DDR_DOWNSPREAD_TEMP   ;
  end
end

//==========================================================================
// 4. PLL input select : DFT mode fixed to DDR-1600 setting
//==========================================================================
wire  [23:0] PLL_DDR_FRAC          = DFT_MODE  ? 24'd0            : PLL_DDR_FRAC_REG        ;
wire  [4:0]  PLL_DDR_PREDIV        = DFT_MODE  ? 5'd1             : PLL_DDR_PREDIV_REG      ;// M
wire  [11:0] PLL_DDR_FBDIV         = DFT_MODE  ? 12'd100          : PLL_DDR_FBDIV_REG       ;// NI
wire         PLL_DDR_DACPD         = DFT_MODE  ? 1'b1             : PLL_DDR_DACPD_REG       ;
wire         PLL_DDR_DSMPD         = DFT_MODE  ? 1'b1             : PLL_DDR_DSMPD_REG       ;
wire  [2:0]  PLL_DDR_POSTDIV0_0    = DFT_MODE  ? 3'd5             : PLL_DDR_POSTDIV0_0_REG  ;// /6 -> 400MHz
wire  [2:0]  PLL_DDR_POSTDIV0_1    = DFT_MODE  ? 3'd7             : PLL_DDR_POSTDIV0_1_REG  ;// /8 -> 300MHz
wire  [2:0]  PLL_DDR_POSTDIV1_0    = DFT_MODE  ? 3'd0             : PLL_DDR_POSTDIV1_0_REG  ;
wire  [2:0]  PLL_DDR_POSTDIV1_1    = DFT_MODE  ? 3'd0             : PLL_DDR_POSTDIV1_1_REG  ;

wire         PLL_DDR_DIS_SSCG      = DFT_MODE  ? 1'b1             : PLL_DDR_DIS_SSCG_REG    ;
wire         PLL_DDR_TESTEN        = DFT_MODE  ? 1'b0             : PLL_DDR_TESTEN_REG      ;
wire  [1:0]  PLL_DDR_TESTSEL       = DFT_MODE  ? 2'h0             : PLL_DDR_TESTSEL_REG     ;
wire         PLL_DDR_SEL_EXTWAVE   = DFT_MODE  ? 1'b0             : PLL_DDR_SEL_EXTWAVE_REG ;
wire  [7:0]  PLL_DDR_EXT_MAXADDR   = DFT_MODE  ? 8'h0             : PLL_DDR_EXT_MAXADDR_REG ;
wire  [7:0]  PLL_DDR_EXT_WAVEVAL   = DFT_MODE  ? 8'h0             : PLL_DDR_EXT_WAVEVAL_REG ;
wire  [1:0]  PLL_DDR_GVCO_BIAS     = DFT_MODE  ? 2'h1             : PLL_DDR_GVCO_BIAS_REG   ;
wire  [2:0]  PLL_DDR_CPP_BIAS      = DFT_MODE  ? 3'h2             : PLL_DDR_CPP_BIAS_REG    ;
wire  [2:0]  PLL_DDR_CPI_BIAS      = DFT_MODE  ? 3'h3             : PLL_DDR_CPI_BIAS_REG    ;
wire  [3:0]  PLL_DDR_DIVVAL        = DFT_MODE  ? 4'h1             : PLL_DDR_DIVVAL_REG      ;
wire  [2:0]  PLL_DDR_SPREAD        = DFT_MODE  ? 3'h0             : PLL_DDR_SPREAD_REG      ;
wire         PLL_DDR_DOWNSPREAD    = DFT_MODE  ? 1'b0             : PLL_DDR_DOWNSPREAD_REG  ;

wire         PLL_DDR_CLK_EN_SEL    = DFT_MODE  ? 1'b1             : PLL_DDR_CLK_EN_REG      ;
wire  [7:0]  PLL_DDR_CLK_DIV1_SEL  = DFT_MODE  ? 8'h27            : PLL_DDR_CLK_DIV1_REG    ;
wire  [7:0]  PLL_DDR_CLK_DIV2_SEL  = DFT_MODE  ? 8'h0c            : PLL_DDR_CLK_DIV2_REG    ;

//==========================================================================
// 5. power down : pd released 100 PLL_DDR_CLK cycles after power on request
//==========================================================================
wire  PLL_DDR_PWRON_DFT_SEL = TEST_MODE ? PLL_DFT_RSTJ : MBIST_ES_MODE ? 1'b1 : PLL_DDR_PWRON_REG ;
wire  PLL_DDR_PD ;

PLL_PD_GEN U_PLL_PD_GEN (
    .PLL_PD_IN    (PLL_DDR_PWRON_DFT_SEL ),   // 1 : power on request
    .PLL_PD_OUT   (PLL_DDR_PD            ),
    .PLL_CLK      (PLL_DDR_CLK           ),
    .PLL_RSTJ     (PLL_DDR_RSTJ          )
);

//==========================================================================
// 6. PLL instance
//==========================================================================
wire PLL_DDR_F400_OUT_CLK ;   // clko0 : DDR
wire PLL_DDR_F300_OUT_CLK ;   // clko1 : IP

INNO_PLL_TOP PLL_DDR (
    // Outputs
    .tbladdr        (PLL_DDR_TBLADDR      ),
    .lock           (PLL_DDR_LOCK         ),
    .testout        (PLL_DDR_TESTOUT      ),
    .clko0          (PLL_DDR_F400_OUT_CLK ),
    .clko1          (PLL_DDR_F300_OUT_CLK ),
    // Inputs
    .refclk         (OSC_24M_CLK          ),
    .pd             (PLL_DDR_PD           ),
    .prediv         (PLL_DDR_PREDIV       ),   // M
    .fbdiv          (PLL_DDR_FBDIV        ),   // NI
    .frac           (PLL_DDR_FRAC         ),   // NF
    .postdiv0_0     (PLL_DDR_POSTDIV0_0   ),   // Q0_0
    .postdiv0_1     (PLL_DDR_POSTDIV0_1   ),   // Q0_1
    .postdiv1_0     (PLL_DDR_POSTDIV1_0   ),   // Q1_0
    .postdiv1_1     (PLL_DDR_POSTDIV1_1   ),   // Q1_1
    .gvco_bias      (PLL_DDR_GVCO_BIAS    ),
    .cpp_bias       (PLL_DDR_CPP_BIAS     ),
    .cpi_bias       (PLL_DDR_CPI_BIAS     ),
    .dacpd          (PLL_DDR_DACPD        ),
    .dsmpd          (PLL_DDR_DSMPD        ),
    .testen         (PLL_DDR_TESTEN       ),
    .testsel        (PLL_DDR_TESTSEL      ),
    .disable_sscg   (PLL_DDR_DIS_SSCG     ),
    .divval         (PLL_DDR_DIVVAL       ),
    .downspread     (PLL_DDR_DOWNSPREAD   ),
    .ext_maxaddr    (PLL_DDR_EXT_MAXADDR  ),
    .extwaveval     (PLL_DDR_EXT_WAVEVAL  ),
    .sel_extwave    (PLL_DDR_SEL_EXTWAVE  ),
    .spread         (PLL_DDR_SPREAD       )
);

//==========================================================================
// 7. output clock gate
//==========================================================================
P_CLK_GATE U_PLL_DDR_F400_CLK_GATE (.CLK(PLL_DDR_F400_OUT_CLK), .EN(PLL_DDR_CLK_EN_SEL), .SE(DFT_MODE), .YGCLK(PLL_DDR_F400_CLK));
P_CLK_GATE U_PLL_DDR_F300_CLK_GATE (.CLK(PLL_DDR_F300_OUT_CLK), .EN(PLL_DDR_CLK_EN_SEL), .SE(DFT_MODE), .YGCLK(PLL_DDR_F300_CLK));

//==========================================================================
// 8. test clock divider (observe clock)
//==========================================================================
CLK_DIVIDER_256 U_PLL_DDR_TEST_DIV1 (.clk(PLL_DDR_F400_OUT_CLK), .rstn(PLL_DDR_RSTJ), .div(PLL_DDR_CLK_DIV1_SEL), .clk_o(PLL_DDR_TEST_DIV1_CLK));
CLK_DIVIDER_256 U_PLL_DDR_TEST_DIV2 (.clk(PLL_DDR_F300_OUT_CLK), .rstn(PLL_DDR_RSTJ), .div(PLL_DDR_CLK_DIV2_SEL), .clk_o(PLL_DDR_TEST_DIV2_CLK));

endmodule
