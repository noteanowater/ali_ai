//==============================================================================
// PLL_SYS_SHELL
//
// DFS (hardware dynamic frequency switching) flow:
//   SW 0. CPU runs the boot flow
//   SW 1. CPU reads the CPU freq parameters from flash and programs SCU:
//         1.0 PLL_SYS_DFS_PLL_UPD: 1 = reprogram PLL (steps 5-7), 0 = keep PLL (e.g. 500MHz -> 250MHz by divider)
//             PLL_SYS_DFS_DIV2[1:0]: port0(F600) / port1(F400) divide-by-2 after DFS (1: /2, 0: /1)
//         1.1 PLL_SYS_CFG_0/1/2 (do NOT write PLL_SYS_CFG_EN), only needed if PLL_SYS_DFS_PLL_UPD = 1
//         1.2 PLL_SYS_DFS_MODE[1:0]: during DFS, port0(F600) / port1(F400) switches to 24M (1) or is gated (0)
//         1.3 PLL_SYS_INT_EN = 1 (rising edge starts DFS)
//   SW 2. CPU (both cores) enters WFI
//   HW 3. Wait until both cores are in WFI (CORE_WFI_MODE_0 / CORE_WFI_MODE_1, see DFS_WFI_PULSE)
//   HW 4. Per PLL_SYS_DFS_MODE, switch port0/1 to 24M (clk_switch_2to1) or gate it (P_CLK_GATE)
//   HW 5. power down PLL_SYS (pd=1)                                   (PLL_SYS_DFS_PLL_UPD = 1 only)
//   HW 6. Load PLL_SYS_CFG_0/1/2 into PLL_SYS                         (PLL_SYS_DFS_PLL_UPD = 1 only)
//         Apply PLL_SYS_DFS_DIV2 to the port dividers
//   HW 7. Hold pd for DFS_PD_CYC PLL_SYS_CLK cycles (>=1us), then power up and wait for LOCK
//         (PLL_SYS_DFS_PLL_UPD = 0: no pd, wait DFS_SETTLE_CYC for the divider switch, PLL stays locked)
//   HW 8. Switch port0/1 back from gated / 24M to the PLL clock
//   HW 9. Raise PLL_SYS_LOCK_INT (-> A45_INT[30]) to wake up the CPU
//   SW 10. CPU writes PLL_SYS_INT_EN = 0 (clears the interrupt and disables it)
//
//   PLL_SYS_LOCK_INT is a level interrupt cleared by PLL_SYS_INT_EN = 0, so the ISR must clear PLL_SYS_INT_EN
//   LOCK timeout (DFS_LOCK_TIMEOUT_CYC != 0): ports in 24M mode stay on 24M, gated ports are ungated,
//   PLL_SYS_LOCK_TIMEOUT is set and the interrupt is raised
//   The original PLL_SYS_CFG_EN rising-edge immediate load path is kept; DFS is disabled in TEST_MODE / MBIST_ES_MODE
//   PLL_SYS_CLK must be free-running (DFS FSM / pd counter / clk_switch select registers)
//
//   CORE_WFI_MODE_0/1 CDC (CORE_CLK -> PLL_SYS_CLK):
//     DFS_WFI_PULSE = 1: WFI may be a pulse (>= 1 CORE_CLK cycle) or a level. While PLL_SYS_INT_EN is 1,
//                        each WFI is captured into a sticky flag in the CORE_CLK domain, then synced to
//                        PLL_SYS_CLK. Flags clear when PLL_SYS_INT_EN = 0. SW must make sure PLL_SYS_INT_EN = 1
//                        has reached the shell before WFI (e.g. read it back, then DSB), and that no other
//                        interrupt wakes a core before DFS completes.
//     DFS_WFI_PULSE = 0: WFI is a level, synced directly and required stable for 2 PLL_SYS_CLK cycles.
//==============================================================================
module PLL_SYS_SHELL #(
    parameter DFS_PD_CYC           = 100,  // pd hold cycles after config load (>=1us, same as PLL_PD_GEN)
    parameter DFS_CLK_SW_CYC       = 16,   // clk_switch_2to1 switch wait cycles (PLL_SYS_CLK)
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

    // ---------------- DFS ----------------
    input  wire [1:0]  PLL_SYS_DFS_MODE      , // SCU: [0] port0(F600) / [1] port1(F400), 1: switch to 24M, 0: gate
    input  wire        PLL_SYS_DFS_PLL_UPD   , // SCU: 1: DFS reprograms PLL (pd + CFG load + relock), 0: keep PLL
    input  wire [1:0]  PLL_SYS_DFS_DIV2      , // SCU: [0] port0 / [1] port1 divider after DFS, 1: /2, 0: /1
    input  wire        PLL_SYS_INT_EN        , // SCU PLL_INT_EN: rising edge starts DFS, 0 clears the interrupt
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




wire       PLL_SYS_CFG_EN_DFT     = ( TEST_MODE | MBIST_ES_MODE ) ? 1'b0  : PLL_SYS_CFG_EN ;
wire [7:0] PLL_SYS_CLK_DIV1_DFT   = ( TEST_MODE | MBIST_ES_MODE ) ? 8'h3b : PLL_SYS_CLK_DIV1 ;
wire [7:0] PLL_SYS_CLK_DIV2_DFT   = ( TEST_MODE | MBIST_ES_MODE ) ? 8'h27 : PLL_SYS_CLK_DIV2 ;
wire       PLL_SYS_INT_EN_DFT     = ( TEST_MODE | MBIST_ES_MODE ) ? 1'b0  : PLL_SYS_INT_EN ;


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

// Config load: CFG_EN rising edge, or DFS flow (after ports are gated / on 24M and pd=1)
wire PLL_SYS_DFS_CFG_LOAD ;
wire PLL_SYS_CFG_LOAD = PLL_SYS_CFG_PULSE | PLL_SYS_DFS_CFG_LOAD ;


reg [7:0] PLL_SYS_CLK_DIV1_REG    ;
reg [7:0] PLL_SYS_CLK_DIV2_REG    ;

always @ (posedge PLL_SYS_CLK or negedge PLL_SYS_RSTJ)begin
    if(!PLL_SYS_RSTJ)begin
         PLL_SYS_CLK_DIV1_REG    <= 8'h3b ;
         PLL_SYS_CLK_DIV2_REG    <= 8'h27 ;
    end
    else if (PLL_SYS_CFG_LOAD )begin
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
//wire         PLL_SYS_PD            = TEST_MODE ? 1'b1              : MBIST_ES_MODE ? 1'b1    : PLL_SYS_PD_REG          ;
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


//------------------------------------------------------------------------------
// DFS port0/1 clock path:
//   PLL clko -> P_CLK_GATE (/1 or /2) -> clk_switch_2to1 (PLL / 24M) -> P_CLK_GATE -> PLL_SYS_F600/F400_CLK
//   divider    : ICG passes every other clko pulse when /2 (high phase = clko high phase, 25% duty);
//                select changes only while the port is gated / on 24M during DFS; /1 in TEST_MODE / MBIST_ES_MODE
//   clk_switch select : 1 selects OSC_24M_CLK; fixed to PLL in TEST_MODE / MBIST_ES_MODE
//   P_CLK_GATE EN     : DFS gate request synced into each clock domain and fed back as handshake; reset value 1 (clock on during boot)
//------------------------------------------------------------------------------
wire [1:0] PLL_SYS_DFS_DIV2_SEL ;
wire       PLL_SYS_F600_DIV2_S ;
wire       PLL_SYS_F400_DIV2_S ;
reg        PLL_SYS_F600_DIV2_TGL ;
reg        PLL_SYS_F400_DIV2_TGL ;
wire       PLL_SYS_F600_DIV_CLK ;
wire       PLL_SYS_F400_DIV_CLK ;

PLL_DFS_SYNC2 U_PLL_SYS_F600_DIV2_SYNC (.CLK(PLL_SYS_F600_OUT_CLK), .RSTJ(PLL_SYS_RSTJ), .D(PLL_SYS_DFS_DIV2_SEL[0]), .Q(PLL_SYS_F600_DIV2_S));
PLL_DFS_SYNC2 U_PLL_SYS_F400_DIV2_SYNC (.CLK(PLL_SYS_F400_OUT_CLK), .RSTJ(PLL_SYS_RSTJ), .D(PLL_SYS_DFS_DIV2_SEL[1]), .Q(PLL_SYS_F400_DIV2_S));

always @ (posedge PLL_SYS_F600_OUT_CLK or negedge PLL_SYS_RSTJ)
    if (!PLL_SYS_RSTJ) PLL_SYS_F600_DIV2_TGL <= 1'b0 ;
    else               PLL_SYS_F600_DIV2_TGL <= PLL_SYS_F600_DIV2_S & ~PLL_SYS_F600_DIV2_TGL ;

always @ (posedge PLL_SYS_F400_OUT_CLK or negedge PLL_SYS_RSTJ)
    if (!PLL_SYS_RSTJ) PLL_SYS_F400_DIV2_TGL <= 1'b0 ;
    else               PLL_SYS_F400_DIV2_TGL <= PLL_SYS_F400_DIV2_S & ~PLL_SYS_F400_DIV2_TGL ;

P_CLK_GATE U_PLL_SYS_F600_DIV_GATE (.CLK(PLL_SYS_F600_OUT_CLK), .EN(~PLL_SYS_F600_DIV2_S | PLL_SYS_F600_DIV2_TGL), .SE(TEST_MODE|MBIST_ES_MODE), .YGCLK(PLL_SYS_F600_DIV_CLK));
P_CLK_GATE U_PLL_SYS_F400_DIV_GATE (.CLK(PLL_SYS_F400_OUT_CLK), .EN(~PLL_SYS_F400_DIV2_S | PLL_SYS_F400_DIV2_TGL), .SE(TEST_MODE|MBIST_ES_MODE), .YGCLK(PLL_SYS_F400_DIV_CLK));

wire [1:0] PLL_SYS_DFS_SEL_24M ;
wire [1:0] PLL_SYS_DFS_GATE_EN ;
wire       PLL_SYS_F600_SW_CLK ;
wire       PLL_SYS_F400_SW_CLK ;
wire       PLL_SYS_F600_GATE_EN ;
wire       PLL_SYS_F400_GATE_EN ;

wire [1:0] PLL_SYS_SEL_24M_DFT = (TEST_MODE | MBIST_ES_MODE) ? 2'b00 : PLL_SYS_DFS_SEL_24M ;

clk_switch_2to1 U_PLL_SYS_F600_CLK_SW (
    .test_mode  (1'b0                   ),
    .test_se    (1'b0                   ),
    .rst_n      (PLL_SYS_RSTJ           ),
    .clka       (PLL_SYS_F600_DIV_CLK   ),
    .clkb       (OSC_24M_CLK            ),
    .select     (PLL_SYS_SEL_24M_DFT[0] ),
    .sel_clk    (PLL_SYS_CLK            ),
    .clk_o      (PLL_SYS_F600_SW_CLK    )
);

clk_switch_2to1 U_PLL_SYS_F400_CLK_SW (
    .test_mode  (1'b0                   ),
    .test_se    (1'b0                   ),
    .rst_n      (PLL_SYS_RSTJ           ),
    .clka       (PLL_SYS_F400_DIV_CLK   ),
    .clkb       (OSC_24M_CLK            ),
    .select     (PLL_SYS_SEL_24M_DFT[1] ),
    .sel_clk    (PLL_SYS_CLK            ),
    .clk_o      (PLL_SYS_F400_SW_CLK    )
);

PLL_DFS_SYNC2 #(.RST_VAL(1'b1)) U_PLL_SYS_F600_GATE_SYNC (.CLK(PLL_SYS_F600_SW_CLK), .RSTJ(PLL_SYS_RSTJ), .D(PLL_SYS_DFS_GATE_EN[0]), .Q(PLL_SYS_F600_GATE_EN));
PLL_DFS_SYNC2 #(.RST_VAL(1'b1)) U_PLL_SYS_F400_GATE_SYNC (.CLK(PLL_SYS_F400_SW_CLK), .RSTJ(PLL_SYS_RSTJ), .D(PLL_SYS_DFS_GATE_EN[1]), .Q(PLL_SYS_F400_GATE_EN));

P_CLK_GATE U_PLL_SYS_F600_CLK_GATE (.CLK(PLL_SYS_F600_SW_CLK), .EN(PLL_SYS_F600_GATE_EN), .SE(TEST_MODE|MBIST_ES_MODE), .YGCLK  (PLL_SYS_F600_CLK));
P_CLK_GATE U_PLL_SYS_F400_CLK_GATE (.CLK(PLL_SYS_F400_SW_CLK), .EN(PLL_SYS_F400_GATE_EN), .SE(TEST_MODE|MBIST_ES_MODE), .YGCLK  (PLL_SYS_F400_CLK));


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
//   IDLE     --INT_EN rise, latch DFS_MODE-->
//   WAIT_WFI --both cores in WFI (stable WFI_STABLE_CYC)--> (INT_EN cleared in WAIT_WFI returns to IDLE)
//   CLK_OFF  : MODE=1 ports switch to 24M, MODE=0 ports are gated; wait gate handshake & CLK_SW_CYC
//   PD       : pd=1 (PLL_UPD only); update DIV2_SEL
//   APPLY    : CFG_LOAD, hold pd for PD_CYC (PLL_UPD only)
//   WAIT_LOCK: pd=0, wait SETTLE_CYC, then stable LOCK / timeout
//   CLK_ON   : switch back to PLL / ungate; wait gate handshake & CLK_SW_CYC
//   DONE     : LOCK_INT=1 --> IDLE
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
    input  wire              INT_EN         ,  // rising edge starts DFS, 0 clears the interrupt
    input  wire [N_PORT-1:0] DFS_MODE       ,  // 1: switch to 24M during DFS, 0: gate during DFS
    input  wire              PLL_UPD        ,  // 1: reprogram PLL (pd + CFG_LOAD + relock), 0: keep PLL
    input  wire [N_PORT-1:0] DIV2           ,  // port divider after DFS, 1: /2, 0: /1
    input  wire              CORE_WFI_MODE_0,
    input  wire              CORE_WFI_MODE_1,
    input  wire              CORE_CLK       ,  // clock of CORE_WFI_MODE_0/1
    input  wire              PLL_LOCK       ,
    output reg  [N_PORT-1:0] SEL_24M        ,  // clk_switch select (1: 24M)
    output reg  [N_PORT-1:0] GATE_EN        ,  // ICG request (1: on)
    output reg  [N_PORT-1:0] DIV2_SEL       ,  // port divider select (1: /2), changes only while ports are off
    input  wire [N_PORT-1:0] GATE_EN_FB     ,  // actual ICG EN in each clock domain, handshake feedback
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

// WFI CDC: CORE_CLK (fast) -> CLK (slow)
generate
    if (WFI_PULSE) begin : G_WFI_PULSE
        // sticky capture in CORE_CLK domain, armed by INT_EN, so a 1-cycle pulse is never missed
        wire       ARM_C;
        reg  [1:0] WFI_SEEN;
        PLL_DFS_SYNC2 U_SYNC_ARM (.CLK(CORE_CLK), .RSTJ(RSTJ), .D(INT_EN), .Q(ARM_C));
        always @(posedge CORE_CLK or negedge RSTJ)
            if (!RSTJ)       WFI_SEEN <= 2'b00;
            else if (!ARM_C) WFI_SEEN <= 2'b00;
            else             WFI_SEEN <= WFI_SEEN | {CORE_WFI_MODE_1, CORE_WFI_MODE_0};
        PLL_DFS_SYNC2 U_SYNC_WFI0 (.CLK(CLK), .RSTJ(RSTJ), .D(WFI_SEEN[0]), .Q(WFI0_S));
        PLL_DFS_SYNC2 U_SYNC_WFI1 (.CLK(CLK), .RSTJ(RSTJ), .D(WFI_SEEN[1]), .Q(WFI1_S));
    end
    else begin : G_WFI_LEVEL
        PLL_DFS_SYNC2 U_SYNC_WFI0 (.CLK(CLK), .RSTJ(RSTJ), .D(CORE_WFI_MODE_0), .Q(WFI0_S));
        PLL_DFS_SYNC2 U_SYNC_WFI1 (.CLK(CLK), .RSTJ(RSTJ), .D(CORE_WFI_MODE_1), .Q(WFI1_S));
    end
endgenerate
genvar I;
generate
    for (I = 0; I < N_PORT; I = I + 1) begin : G_FB_SYNC
        PLL_DFS_SYNC2 #(.RST_VAL(1'b1)) U_SYNC_FB (.CLK(CLK), .RSTJ(RSTJ), .D(GATE_EN_FB[I]), .Q(GATE_FB_S[I]));
    end
endgenerate

always @(posedge CLK or negedge RSTJ)
    if (!RSTJ) INT_EN_S_D <= 1'b0;
    else       INT_EN_S_D <= INT_EN_S;

wire START      = INT_EN_S & ~INT_EN_S_D;
wire WFI_ALL    = WFI0_S & WFI1_S;
wire CLK_OFF_OK = &(MODE_L | ~GATE_FB_S);   // all gate-mode ports are off
wire CLK_ON_OK  = &GATE_FB_S;               // all port ICGs are on

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
            ST_CLK_ON   : if (!CNT_HIT)               CNT <= CNT - 1'b1;
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

// port control: CLK_OFF switches to 24M / gates per mode; CLK_ON restores (on timeout, 24M-mode ports stay on 24M)
always @(posedge CLK or negedge RSTJ) begin
    if (!RSTJ) begin
        SEL_24M <= {N_PORT{1'b0}};
        GATE_EN <= {N_PORT{1'b1}};
    end
    else if (STATE == ST_WAIT_WFI && STATE_NXT == ST_CLK_OFF) begin
        SEL_24M <=  MODE_L;
        GATE_EN <=  MODE_L;
    end
    else if (STATE == ST_WAIT_LOCK && STATE_NXT == ST_CLK_ON) begin
        SEL_24M <= TIMEOUT_NOW ? MODE_L : {N_PORT{1'b0}};
        GATE_EN <= {N_PORT{1'b1}};
    end
end

// load config one cycle after pd=1
assign CFG_LOAD = (STATE == ST_PD) && PLL_UPD_L;

// port divider: switched while ports are gated / on 24M
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

// interrupt: set after ports are restored, cleared by INT_EN = 0
always @(posedge CLK or negedge RSTJ)
    if (!RSTJ)                              LOCK_INT <= 1'b0;
    else if (!INT_EN_S)                     LOCK_INT <= 1'b0;
    else if (STATE == ST_DONE)              LOCK_INT <= 1'b1;

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
