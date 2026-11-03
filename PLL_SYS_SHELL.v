//==============================================================================
// PLL_SYS_SHELL
//
// DFS (hardware dynamic frequency switching) flow:
//   SW 0. CPU runs the boot flow
//   SW 1. CPU reads the CPU freq parameters from flash and programs SCU:
//         1.0 PLL_SYS_DFS_PLL_UPD: 1 = reprogram PLL (steps 5-7), 0 = keep PLL (e.g. 500MHz -> 250MHz by divider)
//             PLL_SYS_DFS_DIV2[1:0]: port0(F600) / port1(F400) divide-by-2 after DFS (1: /2, 0: /1)
//         1.1 PLL_SYS_CFG_0/1/2 (do NOT write PLL_SYS_CFG_EN), only needed if PLL_SYS_DFS_PLL_UPD = 1
//         1.2 PLL_SYS_DFS_MODE[1:0] (CLK_PLL_OSC): during DFS, port0(F600) / port1(F400) switches to 24M (1)
//             or stays on the PLL path (0, no clock while the PLL is powered down)
//         1.3 PLL_SYS_INT_EN = 1 (rising edge starts DFS)
//   SW 2. CPU (both cores) enters WFI
//   HW 3. Wait until both cores are in WFI (CORE_WFI_MODE_0 / CORE_WFI_MODE_1, see DFS_WFI_PULSE)
//   HW 4. Per PLL_SYS_DFS_MODE (CLK_PLL_OSC), switch port0/1 to 24M, or keep it on the PLL path;
//         if the PLL is reprogrammed, close the common GATE (a port kept on the PLL path then has no clock)
//   HW 5. power down PLL_SYS (pd=1)                                   (PLL_SYS_DFS_PLL_UPD = 1 only)
//   HW 6. Load PLL_SYS_CFG_0/1/2 into PLL_SYS                         (PLL_SYS_DFS_PLL_UPD = 1 only)
//         Apply PLL_SYS_DFS_DIV2 to A45_SRC_CLK_SEL (PLL / PLL /2 glitch-free mux)
//   HW 7. Hold pd for DFS_PD_CYC PLL_SYS_CLK cycles (>=1us), then power up and wait for LOCK
//         (PLL_SYS_DFS_PLL_UPD = 0: no pd, wait DFS_SETTLE_CYC for the divider switch, PLL stays locked)
//   HW 8. After LOCK open the GATE and switch 24M ports back to the PLL clock
//   HW 9. Raise PLL_SYS_LOCK_INT (-> A45_INT[30]) to wake up the CPU
//   SW 10. ISR writes 1 to the interrupt status bit (W1C, PLL_SYS_INT_CLR); PLL_SYS_INT_EN = 0 after boot
//
//   PLL_SYS_LOCK_INT is a level interrupt = status & PLL_SYS_INT_EN. The status is set when DFS completes and
//   cleared by write-1-to-clear: PLL_SYS_INT_CLR is the SCU W1C strobe (pulse or level, rising edge used) in the
//   SCU_CLK domain, synced to PLL_SYS_CLK by a toggle synchronizer, so a 1-cycle pulse from a fast SCU_CLK is not lost
//   LOCK timeout (DFS_LOCK_TIMEOUT_CYC != 0): ports in 24M mode stay on 24M, the GATE is opened,
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
    input  wire [1:0]  PLL_SYS_DFS_MODE      , // SCU: CLK_PLL_OSC during DFS, [0] port0 / [1] port1, 1: 24M, 0: PLL path
    input  wire        PLL_SYS_DFS_PLL_UPD   , // SCU: 1: DFS reprograms PLL (pd + CFG load + relock), 0: keep PLL
    input  wire [1:0]  PLL_SYS_DFS_DIV2      , // SCU: [0] port0 / [1] port1 divider after DFS, 1: /2, 0: /1
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
wire PLL_SYS_F600_LCK_CLK ;
wire PLL_SYS_F400_LCK_CLK ;

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

clk_div_256 U_PLL_SYS_TEST_DIV1 (.clk(PLL_SYS_F600_LCK_CLK), .rstn(PLL_SYS_RSTJ), .div(PLL_SYS_CLK_DIV1_REG), .clk_o(PLL_SYS_TEST_DIV1_CLK));
clk_div_256 U_PLL_SYS_TEST_DIV2 (.clk(PLL_SYS_F400_LCK_CLK), .rstn(PLL_SYS_RSTJ), .div(PLL_SYS_CLK_DIV2_REG), .clk_o(PLL_SYS_TEST_DIV2_CLK));


//------------------------------------------------------------------------------
// DFS port0/1 clock path (port0 = A45 core clock):
//
//   PLL clko --LOCK gate--GATE--> PLL_SYS_A45_CLK --+--> A45_CORE_CLK_DIV --> CORE_A45_DIV_CLK --+
//                                        |                                            |
//                                        +--------------------------------------------+--> Glitch-Free-MUX (A45_SRC_CLK_SEL)
//                                                                                              |
//                                                         OSC_24M_CLK ----> Glitch-Free-MUX (CLK_PLL_OSC) --> PLL_SYS_F600_CLK
//
//   GATE (P_CLK_GATE)   : one common enable for both ports, pure hardware: 0 only around the PLL power down
//                         (DFS with PLL_SYS_DFS_PLL_UPD = 1), 1 otherwise; synced into each PLL clko domain and
//                         fed back as handshake; reset value 1 (clock on during boot)
//   A45_SRC_CLK_SEL     : 1 selects the /2 clock (e.g. 500MHz -> 250MHz without touching the PLL); 0 in TEST / MBIST
//   CLK_PLL_OSC         : 1 selects OSC_24M_CLK; 0 in TEST_MODE / MBIST_ES_MODE
//   port1 (F400) uses the same structure
//------------------------------------------------------------------------------
wire [1:0] PLL_SYS_DFS_SEL_24M ;
wire       PLL_SYS_DFS_GATE_EN ;
wire [1:0] PLL_SYS_DFS_DIV2_SEL ;
wire       PLL_SYS_F600_GATE_EN ;
wire       PLL_SYS_F400_GATE_EN ;

wire [1:0] PLL_SYS_SEL_24M_DFT  = (TEST_MODE | MBIST_ES_MODE) ? 2'b00 : PLL_SYS_DFS_SEL_24M  ;   // CLK_PLL_OSC
wire [1:0] PLL_SYS_DIV2_SEL_DFT = (TEST_MODE | MBIST_ES_MODE) ? 2'b00 : PLL_SYS_DFS_DIV2_SEL ;   // A45_SRC_CLK_SEL

// ---------------- GATE ----------------
wire       PLL_SYS_A45_CLK      ;
wire       PLL_SYS_F400_G_CLK   ;

// Lock gate : PLL clko is X / unstable while the PLL is powered down or unlocked (e.g. during reset).
//   1) PLL_SYS_*_LCK_CLK = clko & LOCK : blocks X and stops the clock while unlocked (TODO: library clock AND cell)
//   2) the ICG enable also needs LOCK synced into the clock domain (reset 0), so the truncated pulse at the
//      LOCK rising edge never passes; only clean pulses after 2 locked cycles reach the gate output
wire PLL_SYS_LOCK_DFT = PLL_SYS_LOCK | TEST_MODE | MBIST_ES_MODE ;
wire PLL_SYS_F600_LOCK_S ;
wire PLL_SYS_F400_LOCK_S ;
assign PLL_SYS_F600_LCK_CLK = PLL_SYS_F600_OUT_CLK & PLL_SYS_LOCK_DFT ;
assign PLL_SYS_F400_LCK_CLK = PLL_SYS_F400_OUT_CLK & PLL_SYS_LOCK_DFT ;

PLL_DFS_SYNC2 #(.RST_VAL(1'b1)) U_PLL_SYS_F600_GATE_SYNC (.CLK(PLL_SYS_F600_LCK_CLK), .RSTJ(PLL_SYS_RSTJ), .D(PLL_SYS_DFS_GATE_EN   ), .Q(PLL_SYS_F600_GATE_EN));
PLL_DFS_SYNC2 #(.RST_VAL(1'b1)) U_PLL_SYS_F400_GATE_SYNC (.CLK(PLL_SYS_F400_LCK_CLK), .RSTJ(PLL_SYS_RSTJ), .D(PLL_SYS_DFS_GATE_EN   ), .Q(PLL_SYS_F400_GATE_EN));
PLL_DFS_SYNC2 #(.RST_VAL(1'b0)) U_PLL_SYS_F600_LOCK_SYNC (.CLK(PLL_SYS_F600_LCK_CLK), .RSTJ(PLL_SYS_RSTJ), .D(PLL_SYS_LOCK_DFT      ), .Q(PLL_SYS_F600_LOCK_S ));
PLL_DFS_SYNC2 #(.RST_VAL(1'b0)) U_PLL_SYS_F400_LOCK_SYNC (.CLK(PLL_SYS_F400_LCK_CLK), .RSTJ(PLL_SYS_RSTJ), .D(PLL_SYS_LOCK_DFT      ), .Q(PLL_SYS_F400_LOCK_S ));

P_CLK_GATE U_PLL_SYS_F600_CLK_GATE (.CLK(PLL_SYS_F600_LCK_CLK), .EN(PLL_SYS_F600_GATE_EN & PLL_SYS_F600_LOCK_S), .SE(TEST_MODE|MBIST_ES_MODE), .YGCLK  (PLL_SYS_A45_CLK   ));
P_CLK_GATE U_PLL_SYS_F400_CLK_GATE (.CLK(PLL_SYS_F400_LCK_CLK), .EN(PLL_SYS_F400_GATE_EN & PLL_SYS_F400_LOCK_S), .SE(TEST_MODE|MBIST_ES_MODE), .YGCLK  (PLL_SYS_F400_G_CLK));

// ---------------- /2 divider ----------------
wire       CORE_A45_DIV_CLK     ;
wire       PLL_SYS_F400_DIV_CLK ;

A45_CORE_CLK_DIV U_A45_CORE_CLK_DIV     (.CLK(PLL_SYS_A45_CLK   ), .RSTJ(PLL_SYS_RSTJ), .CLK_DIV(CORE_A45_DIV_CLK    ));
A45_CORE_CLK_DIV U_PLL_SYS_F400_CLK_DIV (.CLK(PLL_SYS_F400_G_CLK), .RSTJ(PLL_SYS_RSTJ), .CLK_DIV(PLL_SYS_F400_DIV_CLK));

// ---------------- Glitch-Free-MUX: PLL / PLL /2 (A45_SRC_CLK_SEL) ----------------
wire       PLL_SYS_A45_SRC_CLK  ;
wire       PLL_SYS_F400_SRC_CLK ;

clk_switch_2to1 U_A45_SRC_CLK_MUX (
    .test_mode  (1'b0                    ),
    .test_se    (1'b0                    ),
    .rst_n      (PLL_SYS_RSTJ            ),
    .clka       (PLL_SYS_A45_CLK         ),
    .clkb       (CORE_A45_DIV_CLK        ),
    .select     (PLL_SYS_DIV2_SEL_DFT[0] ),
    .sel_clk    (PLL_SYS_CLK             ),
    .clk_o      (PLL_SYS_A45_SRC_CLK     )
);

clk_switch_2to1 U_PLL_SYS_F400_SRC_CLK_MUX (
    .test_mode  (1'b0                    ),
    .test_se    (1'b0                    ),
    .rst_n      (PLL_SYS_RSTJ            ),
    .clka       (PLL_SYS_F400_G_CLK      ),
    .clkb       (PLL_SYS_F400_DIV_CLK    ),
    .select     (PLL_SYS_DIV2_SEL_DFT[1] ),
    .sel_clk    (PLL_SYS_CLK             ),
    .clk_o      (PLL_SYS_F400_SRC_CLK    )
);

// ---------------- Glitch-Free-MUX: PLL / OSC_24M (CLK_PLL_OSC) ----------------
clk_switch_2to1 U_A45_PLL_OSC_CLK_MUX (
    .test_mode  (1'b0                    ),
    .test_se    (1'b0                    ),
    .rst_n      (PLL_SYS_RSTJ            ),
    .clka       (PLL_SYS_A45_SRC_CLK     ),
    .clkb       (OSC_24M_CLK             ),
    .select     (PLL_SYS_SEL_24M_DFT[0]  ),
    .sel_clk    (PLL_SYS_CLK             ),
    .clk_o      (PLL_SYS_F600_CLK        )
);

clk_switch_2to1 U_PLL_SYS_F400_PLL_OSC_CLK_MUX (
    .test_mode  (1'b0                    ),
    .test_se    (1'b0                    ),
    .rst_n      (PLL_SYS_RSTJ            ),
    .clka       (PLL_SYS_F400_SRC_CLK    ),
    .clkb       (OSC_24M_CLK             ),
    .select     (PLL_SYS_SEL_24M_DFT[1]  ),
    .sel_clk    (PLL_SYS_CLK             ),
    .clk_o      (PLL_SYS_F400_CLK        )
);


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


endmodule


//==============================================================================
// A45_CORE_CLK_DIV: divide-by-2 clock divider, 50% duty
//   (define as a generated clock in SDC; may be replaced by the library / existing divider)
//==============================================================================
module A45_CORE_CLK_DIV (
    input  wire CLK     ,
    input  wire RSTJ    ,
    output wire CLK_DIV
);
reg CLK_DIV_REG ;
always @(posedge CLK or negedge RSTJ)
    if (!RSTJ) CLK_DIV_REG <= 1'b0 ;
    else       CLK_DIV_REG <= ~CLK_DIV_REG ;
assign CLK_DIV = CLK_DIV_REG ;
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
wire CLK_ON_OK  = (&GATE_FB_S) | LOCK_TIMEOUT;  // GATE open in all port clock domains (no PLL clock after LOCK timeout)

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
