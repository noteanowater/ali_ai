//==============================================================================
// PLL_SYS_SHELL
//
// DFS (硬件调频) 流程:
//   SW 0. CPU 执行 boot 流程
//   SW 1. CPU 读取 flash 中 CPU Freq 配置参数, 配置 SCU:
//         1.1 PLL_SYS_CFG_0/1/2 (不写 PLL_SYS_CFG_EN)
//         1.2 PLL_SYS_DFS_MODE[1:0]: 调频阶段 port0(F600) / port1(F400) 切到 24M (1) 或 gate (0)
//         1.3 PLL_SYS_INT_EN = 1 (上升沿启动 DFS)
//   SW 2. CPU (两个 core) 进入 WFI
//   HW 3. 等待 CORE_WFI_MODE_0 / CORE_WFI_MODE_1 均为 1, 且稳定 2 个 cycle
//   HW 4. 按 PLL_SYS_DFS_MODE 将 port0/1 切到 24M (clk_switch_2to1) 或 gate (P_CLK_GATE)
//   HW 5. power down PLL_SYS (pd=1)
//   HW 6. 加载 PLL_SYS_CFG_0/1/2 到 PLL_SYS
//   HW 7. pd 保持 DFS_PD_CYC 个 PLL_SYS_CLK 周期 (>=1us) 后 power up, 等待 LOCK
//   HW 8. port0/1 从 gate / 24M 切回 PLL 时钟
//   HW 9. 发出 PLL_SYS_LOCK_INT (-> A45_INT[30]) 唤醒 CPU
//   SW 10. CPU 配置 PLL_SYS_INT_EN = 0 (清中断, 关闭中断使能)
//
//   PLL_SYS_LOCK_INT 为电平中断, 由 PLL_SYS_INT_EN = 0 清除, 因此 ISR 中需清 PLL_SYS_INT_EN
//   LOCK 超时 (DFS_LOCK_TIMEOUT_CYC != 0): 切 24M 的 port 保持在 24M, gate 的 port 打开,
//   置 PLL_SYS_LOCK_TIMEOUT 并发中断
//   原 PLL_SYS_CFG_EN 上升沿立即加载路径保留; TEST_MODE / MBIST_ES_MODE 下 DFS 关闭
//   PLL_SYS_CLK 须为常开时钟 (DFS 状态机 / pd 计数 / clk_switch 选择寄存器)
//==============================================================================
module PLL_SYS_SHELL #(
    parameter DFS_PD_CYC           = 100,  // 加载配置后 pd 保持周期数 (>=1us, 与 PLL_PD_GEN 一致)
    parameter DFS_CLK_SW_CYC       = 16,   // clk_switch_2to1 切换等待周期数 (PLL_SYS_CLK)
    parameter DFS_SETTLE_CYC       = 16,   // power up 后, 开始检测 LOCK 前的等待周期
    parameter DFS_LOCK_STABLE_CYC  = 8,    // LOCK 需连续保持的周期数
    parameter DFS_LOCK_TIMEOUT_CYC = 0     // 等 LOCK 超时周期数 (0: 不超时)
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
    input  wire [1:0]  PLL_SYS_DFS_MODE      , // SCU: [0] port0(F600) / [1] port1(F400), 1: 切 24M, 0: gate
    input  wire        PLL_SYS_INT_EN        , // SCU PLL_INT_EN: 上升沿启动 DFS, 清 0 清中断
    input  wire        CORE_WFI_MODE_0       , // u_a45_top.core_wfi_mode_0
    input  wire        CORE_WFI_MODE_1       , // u_a45_top.core_wfi_mode_1
    output wire        PLL_SYS_LOCK_INT      , // -> A45_INT[30]
    output wire        PLL_SYS_DFS_BUSY      , // 状态, 可接 SCU 只读寄存器
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

// 配置加载: 原 CFG_EN 上升沿 或 DFS 流程 (port 已 gate / 切 24M 且 pd=1 后)
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
    if (PLL_SYS_CFG_PULSE)                                     // DFS 时 pd 由状态机控制, 不改 PD_REG
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

// DFS power down 与上电 pd 相或
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
// DFS port0/1 时钟通路: PLL clko -> clk_switch_2to1 (PLL / 24M) -> P_CLK_GATE -> PLL_SYS_F600/F400_CLK
//   clk_switch select : 1 切到 OSC_24M_CLK, TEST_MODE / MBIST_ES_MODE 下固定选 PLL
//   P_CLK_GATE EN     : DFS gate 请求同步到各自时钟域, 并回传握手; 复位值 1 (boot 时钟常开)
//------------------------------------------------------------------------------
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
    .clka       (PLL_SYS_F600_OUT_CLK   ),
    .clkb       (OSC_24M_CLK            ),
    .select     (PLL_SYS_SEL_24M_DFT[0] ),
    .sel_clk    (PLL_SYS_CLK            ),
    .clk_o      (PLL_SYS_F600_SW_CLK    )
);

clk_switch_2to1 U_PLL_SYS_F400_CLK_SW (
    .test_mode  (1'b0                   ),
    .test_se    (1'b0                   ),
    .rst_n      (PLL_SYS_RSTJ           ),
    .clka       (PLL_SYS_F400_OUT_CLK   ),
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
    .LOCK_TIMEOUT_CYC   (DFS_LOCK_TIMEOUT_CYC)
) U_PLL_SYS_DFS_CTRL (
    .CLK                (PLL_SYS_CLK         ),
    .RSTJ               (PLL_SYS_RSTJ        ),
    .INT_EN             (PLL_SYS_INT_EN_DFT  ),
    .DFS_MODE           (PLL_SYS_DFS_MODE    ),
    .CORE_WFI_MODE_0    (CORE_WFI_MODE_0     ),
    .CORE_WFI_MODE_1    (CORE_WFI_MODE_1     ),
    .PLL_LOCK           (PLL_SYS_LOCK        ),
    .SEL_24M            (PLL_SYS_DFS_SEL_24M ),
    .GATE_EN            (PLL_SYS_DFS_GATE_EN ),
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
// PLL_SYS_DFS_CTRL: DFS 状态机 (CLK 为常开时钟 PLL_SYS_CLK)
//
//   IDLE     --INT_EN↑, 锁存 DFS_MODE-->
//   WAIT_WFI --两 core WFI 稳定 WFI_STABLE_CYC--> (WAIT_WFI 中 INT_EN 清 0 则回 IDLE)
//   CLK_OFF  : MODE=1 的 port 切 24M, MODE=0 的 port gate; 等 gate 握手 & CLK_SW_CYC
//   PD       : pd=1
//   APPLY    : CFG_LOAD, pd 保持 PD_CYC
//   WAIT_LOCK: pd=0, 等 LOCK 稳定 / 超时
//   CLK_ON   : 切回 PLL / 打开 gate; 等 gate 握手 & CLK_SW_CYC
//   DONE     : LOCK_INT=1 --> IDLE
//==============================================================================
module PLL_SYS_DFS_CTRL #(
    parameter CNT_W            = 16,
    parameter N_PORT           = 2,      // PLL 输出 port 数
    parameter WFI_STABLE_CYC   = 2,      // WFI 需连续保持的周期数 (>=1)
    parameter PD_CYC           = 100,    // 加载配置后 pd 保持周期数 (>=1us)
    parameter CLK_SW_CYC       = 16,     // clk_switch 切换等待周期数 (>=1)
    parameter SETTLE_CYC       = 16,     // power up 后, 开始检测 LOCK 前的等待周期
    parameter LOCK_STABLE_CYC  = 8,      // LOCK 需连续保持的周期数 (>=1)
    parameter LOCK_TIMEOUT_CYC = 0       // 等 LOCK 超时周期数 (0: 不超时)
)(
    input  wire              CLK            ,
    input  wire              RSTJ           ,
    input  wire              INT_EN         ,  // 上升沿启动 DFS, 清 0 清中断
    input  wire [N_PORT-1:0] DFS_MODE       ,  // 1: 调频时切 24M, 0: 调频时 gate
    input  wire              CORE_WFI_MODE_0,
    input  wire              CORE_WFI_MODE_1,
    input  wire              PLL_LOCK       ,
    output reg  [N_PORT-1:0] SEL_24M        ,  // clk_switch select (1: 24M)
    output reg  [N_PORT-1:0] GATE_EN        ,  // ICG 请求 (1: 开)
    input  wire [N_PORT-1:0] GATE_EN_FB     ,  // 各时钟域实际 ICG EN, 回传握手
    output wire              CFG_LOAD       ,  // 加载 PLL 配置 (单周期, pd 已为 1)
    output reg               PLL_PD         ,  // PLL pd (高有效)
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

reg  [2:0]        state, state_nxt;
reg  [CNT_W-1:0]  cnt;
reg  [CNT_W-1:0]  tmo_cnt;
reg  [N_PORT-1:0] mode_l;

// 同步
wire              int_en_s, wfi0_s, wfi1_s, lock_s;
wire [N_PORT-1:0] gate_fb_s;
reg               int_en_s_d;

PLL_DFS_SYNC2 U_SYNC_INTEN (.CLK(CLK), .RSTJ(RSTJ), .D(INT_EN         ), .Q(int_en_s));
PLL_DFS_SYNC2 U_SYNC_WFI0  (.CLK(CLK), .RSTJ(RSTJ), .D(CORE_WFI_MODE_0), .Q(wfi0_s  ));
PLL_DFS_SYNC2 U_SYNC_WFI1  (.CLK(CLK), .RSTJ(RSTJ), .D(CORE_WFI_MODE_1), .Q(wfi1_s  ));
PLL_DFS_SYNC2 U_SYNC_LOCK  (.CLK(CLK), .RSTJ(RSTJ), .D(PLL_LOCK       ), .Q(lock_s  ));

genvar i;
generate
    for (i = 0; i < N_PORT; i = i + 1) begin : G_FB_SYNC
        PLL_DFS_SYNC2 #(.RST_VAL(1'b1)) U_SYNC_FB (.CLK(CLK), .RSTJ(RSTJ), .D(GATE_EN_FB[i]), .Q(gate_fb_s[i]));
    end
endgenerate

always @(posedge CLK or negedge RSTJ)
    if (!RSTJ) int_en_s_d <= 1'b0;
    else       int_en_s_d <= int_en_s;

wire start      = int_en_s & ~int_en_s_d;
wire wfi_all    = wfi0_s & wfi1_s;
wire clk_off_ok = &(mode_l | ~gate_fb_s);   // gate 模式的 port 均已关断
wire clk_on_ok  = &gate_fb_s;               // 所有 port ICG 均已打开

wire cnt_hit    = (cnt == {CNT_W{1'b0}});
wire tmo_en     = (LOCK_TIMEOUT_CYC != 0);
wire tmo_hit    = tmo_en & (tmo_cnt == {CNT_W{1'b0}});
wire lock_ok    = lock_s & cnt_hit;

always @(*) begin
    state_nxt = state;
    case (state)
        ST_IDLE     : if (start)                        state_nxt = ST_WAIT_WFI;
        ST_WAIT_WFI : if (!int_en_s)                    state_nxt = ST_IDLE;      // SW 取消
                      else if (wfi_all && cnt_hit)      state_nxt = ST_CLK_OFF;
        ST_CLK_OFF  : if (clk_off_ok && cnt_hit)        state_nxt = ST_PD;
        ST_PD       :                                   state_nxt = ST_APPLY;
        ST_APPLY    : if (cnt_hit)                      state_nxt = ST_WAIT_LOCK;
        ST_WAIT_LOCK: if (lock_ok || tmo_hit)           state_nxt = ST_CLK_ON;
        ST_CLK_ON   : if (clk_on_ok && cnt_hit)         state_nxt = ST_DONE;
        ST_DONE     :                                   state_nxt = ST_IDLE;
        default     :                                   state_nxt = ST_IDLE;
    endcase
end

always @(posedge CLK or negedge RSTJ)
    if (!RSTJ) state <= ST_IDLE;
    else       state <= state_nxt;

always @(posedge CLK or negedge RSTJ)
    if (!RSTJ)       mode_l <= {N_PORT{1'b0}};
    else if (start)  mode_l <= DFS_MODE;

// 通用计数器: 进入状态时装载, 状态内递减到 0
always @(posedge CLK or negedge RSTJ) begin
    if (!RSTJ)
        cnt <= {CNT_W{1'b0}};
    else begin
        case (state)
            ST_IDLE     : cnt <= WFI_STABLE_CYC - 1;
            ST_WAIT_WFI : if (!wfi_all)               cnt <= WFI_STABLE_CYC - 1;   // WFI 需连续保持
                          else if (!cnt_hit)          cnt <= cnt - 1'b1;
                          else                        cnt <= CLK_SW_CYC - 1;
            ST_CLK_OFF  : if (!cnt_hit)               cnt <= cnt - 1'b1;
            ST_PD       : cnt <= PD_CYC - 1;
            ST_APPLY    : if (!cnt_hit)               cnt <= cnt - 1'b1;
                          else                        cnt <= SETTLE_CYC + LOCK_STABLE_CYC - 1;
            ST_WAIT_LOCK: if (lock_ok || tmo_hit)     cnt <= CLK_SW_CYC - 1;
                          else if (cnt < LOCK_STABLE_CYC && !lock_s)
                                                      cnt <= LOCK_STABLE_CYC - 1;  // LOCK 需连续保持
                          else if (!cnt_hit)          cnt <= cnt - 1'b1;
            ST_CLK_ON   : if (!cnt_hit)               cnt <= cnt - 1'b1;
            default     : cnt <= {CNT_W{1'b0}};
        endcase
    end
end

// LOCK 超时计数
always @(posedge CLK or negedge RSTJ)
    if (!RSTJ)                        tmo_cnt <= {CNT_W{1'b0}};
    else if (state != ST_WAIT_LOCK)   tmo_cnt <= tmo_en ? LOCK_TIMEOUT_CYC - 1 : 0;
    else if (!tmo_hit)                tmo_cnt <= tmo_cnt - 1'b1;

wire timeout_now = (state == ST_WAIT_LOCK) && tmo_hit && !lock_ok;

// port 控制: CLK_OFF 时按 mode 切 24M / gate; CLK_ON 时恢复 (超时则切 24M 的 port 保持 24M)
always @(posedge CLK or negedge RSTJ) begin
    if (!RSTJ) begin
        SEL_24M <= {N_PORT{1'b0}};
        GATE_EN <= {N_PORT{1'b1}};
    end
    else if (state == ST_WAIT_WFI && state_nxt == ST_CLK_OFF) begin
        SEL_24M <=  mode_l;
        GATE_EN <=  mode_l;
    end
    else if (state == ST_WAIT_LOCK && state_nxt == ST_CLK_ON) begin
        SEL_24M <= timeout_now ? mode_l : {N_PORT{1'b0}};
        GATE_EN <= {N_PORT{1'b1}};
    end
end

// pd=1 之后一拍加载配置
assign CFG_LOAD = (state == ST_PD);

// pd: 进入 PD 时拉高, 加载后保持 PD_CYC 周期, 进入 WAIT_LOCK 时释放
always @(posedge CLK or negedge RSTJ)
    if (!RSTJ) PLL_PD <= 1'b0;
    else       PLL_PD <= (state_nxt == ST_PD) || (state_nxt == ST_APPLY);

assign DFS_BUSY = (state != ST_IDLE);

always @(posedge CLK or negedge RSTJ) begin
    if (!RSTJ) begin
        DFS_DONE     <= 1'b0;
        LOCK_TIMEOUT <= 1'b0;
    end
    else if (start) begin
        DFS_DONE     <= 1'b0;
        LOCK_TIMEOUT <= 1'b0;
    end
    else begin
        if (state == ST_DONE)
            DFS_DONE <= 1'b1;
        if (timeout_now)
            LOCK_TIMEOUT <= 1'b1;
    end
end

// 中断: port 恢复后置位, INT_EN 清 0 清除
always @(posedge CLK or negedge RSTJ)
    if (!RSTJ)                              LOCK_INT <= 1'b0;
    else if (!int_en_s)                     LOCK_INT <= 1'b0;
    else if (state == ST_DONE)              LOCK_INT <= 1'b1;

endmodule


//==============================================================================
// 2 级同步器 (综合时可替换为工艺库标准同步单元)
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
