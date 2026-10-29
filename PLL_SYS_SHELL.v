//==============================================================================
// PLL_SYS_SHELL
//
// 新增: 硬件调频 (DFS) 流程, 由 PLL_SYS_DFS_CTRL 完成 (见文件末尾)
//   SW 1. CPU 执行 boot 流程
//   SW 2. 写 PLL_SYS_CFG_0/1/2 (divider 等) / PLL_SYS_SEL, 再置位 PLL_SYS_INT_EN, 两个 core 执行 WFI
//         (DFS 流程中不要再写 PLL_SYS_CFG_EN, 否则配置会被立即加载)
//   HW 3. 等待 CORE_WFI_MODE_0 / CORE_WFI_MODE_1 均为 1
//   HW 4. Gate PLL_SYS_F600_CLK / PLL_SYS_F400_CLK (各自时钟域内 ICG 关断, 握手确认)
//   HW 5. pd=1 -> 加载 divider 配置 -> pd 保持 DFS_PD_CYC 个 PLL_SYS_CLK 周期 (>=1us) -> pd=0 -> 等 LOCK
//   HW 6. 打开 PLL_SYS_F600_CLK / PLL_SYS_F400_CLK
//   HW 7. 发出 PLL_SYS_LOCK_INT 唤醒 CPU, SW 写 PLL_SYS_INT_CLR 或清 PLL_SYS_INT_EN 清除
//
// 原 PLL_SYS_CFG_EN 上升沿立即加载配置的路径保留 (boot / DFT 使用), TEST_MODE / MBIST_MODE 下 DFS 关闭
// PLL_SYS_CLK 须为常开时钟 (DFS 状态机及 pd 计数在该时钟域)
//==============================================================================
module PLL_SYS_SHELL #(
    parameter DFS_PD_CYC           = 100,  // DFS 中设置 divider 后 pd 保持周期数 (>=1us, 与 PLL_PD_GEN 一致)
    parameter DFS_SETTLE_CYC       = 16,   // release pd 后, 开始检测 LOCK 前的等待周期
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
    input  wire [1:0]  PLL_SYS_SEL           , // SCU PLL_SYS_SEL[1:0]
    output reg  [1:0]  PLL_SYS_SEL_OUT       , // DFS 中 (时钟已 gate) 更新的 PLL_SYS_SEL
    input  wire        PLL_SYS_INT_EN        , // SCU PLL_INT_EN: 中断使能, 上升沿启动 DFS
    input  wire        PLL_SYS_INT_CLR       , // 中断清除 (电平, 高有效)
    input  wire        CORE_WFI_MODE_0       , // u_a45_top.core_wfi_mode_0
    input  wire        CORE_WFI_MODE_1       , // u_a45_top.core_wfi_mode_1
    output wire        PLL_SYS_LOCK_INT      , // PLL_SYS_LOCK_INT
    output wire        PLL_SYS_DFS_BUSY      ,
    output wire        PLL_SYS_DFS_DONE      ,
    output wire        PLL_SYS_LOCK_TIMEOUT  ,

    input  wire        DFT_CPU_SPEED_SEL     ,
    input  wire        MBIST_MODE            ,
    input  wire        TEST_MODE             ,
    input  wire        OSC_24M_CLK           ,
    input  wire        PLL_SYS_CLK           ,
    input  wire        PLL_DFT_RSTJ          ,
    input  wire        PLL_SYS_RSTJ
);




wire       PLL_SYS_CFG_EN_DFT     = TEST_MODE | MBIST_MODE ? 1'b0  : PLL_SYS_CFG_EN ;
wire [7:0] PLL_SYS_CLK_DIV1_DFT   = TEST_MODE | MBIST_MODE ? 8'h3b : PLL_SYS_CLK_DIV1 ;
wire [7:0] PLL_SYS_CLK_DIV2_DFT   = TEST_MODE | MBIST_MODE ? 8'h27 : PLL_SYS_CLK_DIV2 ;
wire       PLL_SYS_INT_EN_DFT     = TEST_MODE | MBIST_MODE ? 1'b0  : PLL_SYS_INT_EN ;


wire  [11:0] PLL_SYS_NI_DFT =	DFT_CPU_SPEED_SEL == 2'b00 ? 12'd250 : //A45--500MHz
				DFT_CPU_SPEED_SEL == 2'b01 ? 12'd233 : //A45--550MHz
				DFT_CPU_SPEED_SEL == 2'b10 ? 12'd400 : //A45--600MHz
							     12'd400 ; //A45--600MHz


wire [4:0]   PLL_SYS_M_DFT =	DFT_CPU_SPEED_SEL == 2'b00 ? 5'd2 : //A45--500MHz
                                DFT_CPU_SPEED_SEL == 2'b01 ? 5'd3 : //A45--550MHz
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



wire  [23:0] PLL_SYS_FRAC_DFT         = TEST_MODE ? 24'd0               : PLL_SYS_CFG_0 [23: 0] ;
wire  [4:0]  PLL_SYS_PREDIV_DFT       = TEST_MODE ? PLL_SYS_M_DFT       : PLL_SYS_CFG_0 [28:24] ;// M
wire         PLL_SYS_DIS_SSCG_DFT     = TEST_MODE ? 1'b1                : PLL_SYS_CFG_0 [29]    ;
wire         PLL_SYS_TESTEN_DFT       = TEST_MODE ? 1'b0                : PLL_SYS_CFG_0 [30]    ;
wire  [11:0] PLL_SYS_FBDIV_DFT        = TEST_MODE ? PLL_SYS_NI_DFT      : PLL_SYS_CFG_1 [11: 0] ;// NI
wire         PLL_SYS_DACPD_DFT        = TEST_MODE ? 1'b1                : PLL_SYS_CFG_1 [12]    ;
wire         PLL_SYS_DSMPD_DFT        = TEST_MODE ? 1'b1                : PLL_SYS_CFG_1 [13]    ;
wire         PLL_SYS_PD_DFT           = TEST_MODE ? 1'b1                : PLL_SYS_CFG_1 [13]    ;
wire  [1:0]  PLL_SYS_TESTSEL_DFT      = TEST_MODE ? 2'h0                : PLL_SYS_CFG_1 [15:14] ;
wire  [2:0]  PLL_SYS_POSTDIV0_0_DFT   = TEST_MODE ? PLL_SYS_Q0_0_DFT    : PLL_SYS_CFG_1 [18:16] ;
wire  [2:0]  PLL_SYS_POSTDIV0_1_DFT   = TEST_MODE ? PLL_SYS_Q0_1_DFT    : PLL_SYS_CFG_1 [21:19] ;
wire  [2:0]  PLL_SYS_POSTDIV1_0_DFT   = TEST_MODE ? 3'h0                : PLL_SYS_CFG_1 [24:22] ;
wire  [2:0]  PLL_SYS_POSTDIV1_1_DFT   = TEST_MODE ? 3'h0                : PLL_SYS_CFG_1 [27:25] ;
wire         PLL_SYS_SEL_EXTWAVE_DFT  = TEST_MODE ? 1'b0                : PLL_SYS_CFG_1 [28]    ;
wire  [7:0]  PLL_SYS_EXT_MAXADDR_DFT  = TEST_MODE ? 8'h0                : PLL_SYS_CFG_2 [ 7: 0] ;
wire  [7:0]  PLL_SYS_EXT_WAVEVAL_DFT  = TEST_MODE ? 8'h0                : PLL_SYS_CFG_2 [15: 8] ;
wire  [1:0]  PLL_SYS_GVCO_BIAS_DFT    = TEST_MODE ? 2'h1                : PLL_SYS_CFG_2 [17:16] ;
wire  [2:0]  PLL_SYS_CPP_BIAS_DFT     = TEST_MODE ? 3'h2                : PLL_SYS_CFG_2 [20:18] ;
wire  [2:0]  PLL_SYS_CPI_BIAS_DFT     = TEST_MODE ? 3'h3                : PLL_SYS_CFG_2 [23:21] ;
wire  [3:0]  PLL_SYS_DIVVAL_DFT       = TEST_MODE ? 4'h1                : PLL_SYS_CFG_2 [27:24] ;
wire  [2:0]  PLL_SYS_SPREAD_DFT       = TEST_MODE ? 3'h0                : PLL_SYS_CFG_2 [30:28] ;
wire         PLL_SYS_DOWNSPREAD_DFT   = TEST_MODE ? 1'b0                : PLL_SYS_CFG_2 [31]    ;



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

// 配置加载: 原 CFG_EN 上升沿 或 DFS 流程 (pd=1 且时钟已 gate 时)
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

always @ (posedge PLL_SYS_CLK or negedge PLL_SYS_RSTJ)begin
    if(!PLL_SYS_RSTJ)
         PLL_SYS_SEL_OUT <= 2'b0 ;
    else if (PLL_SYS_CFG_LOAD )
         PLL_SYS_SEL_OUT <= PLL_SYS_SEL ;
end

reg [23:0] PLL_SYS_FRAC          ;
reg [4:0]  PLL_SYS_PREDIV        ;
reg        PLL_SYS_DIS_SSCG      ;
reg        PLL_SYS_TESTEN        ;
reg        PLL_SYS_PD_REG        ;
reg [11:0] PLL_SYS_FBDIV         ;
reg        PLL_SYS_DACPD         ;
reg        PLL_SYS_DSMPD         ;
reg [1:0]  PLL_SYS_TESTSEL       ;
reg [2:0]  PLL_SYS_POSTDIV0_0    ;
reg [2:0]  PLL_SYS_POSTDIV0_1    ;
reg [2:0]  PLL_SYS_POSTDIV1_0    ;
reg [2:0]  PLL_SYS_POSTDIV1_1    ;
reg        PLL_SYS_SEL_EXTWAVE   ;
reg [7:0]  PLL_SYS_EXT_MAXADDR   ;
reg [7:0]  PLL_SYS_EXT_WAVEVAL   ;
reg [1:0]  PLL_SYS_GVCO_BIAS     ;
reg [2:0]  PLL_SYS_CPP_BIAS      ;
reg [2:0]  PLL_SYS_CPI_BIAS      ;
reg [3:0]  PLL_SYS_DIVVAL        ;
reg [2:0]  PLL_SYS_SPREAD        ;
reg        PLL_SYS_DOWNSPREAD    ;

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
    PLL_SYS_FRAC          <= 24'd0;
    PLL_SYS_PREDIV        <= 5'd4 ;    // M
    PLL_SYS_DIS_SSCG      <= 1'd1 ;
    PLL_SYS_TESTEN        <= 1'd0 ;
    PLL_SYS_PD_REG        <= 1'd1 ;
    PLL_SYS_FBDIV         <= 12'd333 ; // NI
    PLL_SYS_DACPD         <= 1'd1 ;
    PLL_SYS_DSMPD         <= 1'd1 ;
    PLL_SYS_TESTSEL       <= 2'd0 ;
    PLL_SYS_POSTDIV0_0    <= 3'd3 ;    // Q0_0
    PLL_SYS_POSTDIV0_1    <= 3'd4 ;    // Q0_1
    PLL_SYS_POSTDIV1_0    <= 3'd0 ;    // Q1_0
    PLL_SYS_POSTDIV1_1    <= 3'd0 ;    // Q1_1
    PLL_SYS_SEL_EXTWAVE   <= 1'd0 ;
    PLL_SYS_EXT_MAXADDR   <= 8'd0 ;
    PLL_SYS_EXT_WAVEVAL   <= 8'd0 ;
    PLL_SYS_GVCO_BIAS     <= 2'd1 ;
    PLL_SYS_CPP_BIAS      <= 3'd2 ;
    PLL_SYS_CPI_BIAS      <= 3'd3 ;
    PLL_SYS_DIVVAL        <= 4'd1 ;
    PLL_SYS_SPREAD        <= 3'd0 ;
    PLL_SYS_DOWNSPREAD    <= 1'd0 ;
  end
  else if (PLL_SYS_CFG_LOAD) begin
    PLL_SYS_FRAC            <= PLL_SYS_FRAC_DFT          ;
    PLL_SYS_PREDIV          <= PLL_SYS_PREDIV_DFT        ;
    PLL_SYS_DIS_SSCG        <= PLL_SYS_DIS_SSCG_DFT      ;
    PLL_SYS_TESTEN          <= PLL_SYS_TESTEN_DFT        ;
    if (PLL_SYS_CFG_PULSE)                                 // DFS 时 pd 由状态机控制, 不改 PD_REG
    PLL_SYS_PD_REG          <= PLL_SYS_PD_DFT            ;
    PLL_SYS_FBDIV           <= PLL_SYS_FBDIV_DFT         ;
    PLL_SYS_DACPD           <= PLL_SYS_DACPD_DFT         ;
    PLL_SYS_DSMPD           <= PLL_SYS_DSMPD_DFT         ;
    PLL_SYS_TESTSEL         <= PLL_SYS_TESTSEL_DFT       ;
    PLL_SYS_POSTDIV0_0      <= PLL_SYS_POSTDIV0_0_DFT    ;
    PLL_SYS_POSTDIV0_1      <= PLL_SYS_POSTDIV0_1_DFT    ;
    PLL_SYS_POSTDIV1_0      <= PLL_SYS_POSTDIV1_0_DFT    ;
    PLL_SYS_POSTDIV1_1      <= PLL_SYS_POSTDIV1_1_DFT    ;
    PLL_SYS_SEL_EXTWAVE     <= PLL_SYS_SEL_EXTWAVE_DFT   ;
    PLL_SYS_EXT_MAXADDR     <= PLL_SYS_EXT_MAXADDR_DFT   ;
    PLL_SYS_EXT_WAVEVAL     <= PLL_SYS_EXT_WAVEVAL_DFT   ;
    PLL_SYS_GVCO_BIAS       <= PLL_SYS_GVCO_BIAS_DFT     ;
    PLL_SYS_CPP_BIAS        <= PLL_SYS_CPP_BIAS_DFT      ;
    PLL_SYS_CPI_BIAS        <= PLL_SYS_CPI_BIAS_DFT      ;
    PLL_SYS_DIVVAL          <= PLL_SYS_DIVVAL_DFT        ;
    PLL_SYS_SPREAD          <= PLL_SYS_SPREAD_DFT        ;
    PLL_SYS_DOWNSPREAD      <= PLL_SYS_DOWNSPREAD_DFT    ;
  end
end

//reg [7:0] REF_CNT ;
//
//always @ (posedge PLL_SYS_CLK or negedge PLL_SYS_RSTJ)begin
//  if(!PLL_SYS_RSTJ)
//    REF_CNT <= 8'b0 ;
//  else if (!PLL_SYS_PD_REG)
//    REF_CNT <= 8'b0 ;
//  else if (REF_CNT == 8'd100)
//    REF_CNT <= REF_CNT ;
//  else
//    REF_CNT <= REF_CNT + 8'b1;
//end
//
//reg REF_FLAG ;
//
//always @ (posedge PLL_SYS_CLK or negedge PLL_SYS_RSTJ)begin
//  if(!PLL_SYS_RSTJ)
//    REF_FLAG <= 1'b0 ;
//  else if (!PLL_SYS_PD_REG)
//    REF_FLAG <= 1'b0 ;
//  else if(REF_CNT == 8'd100)
//    REF_FLAG <= 1'b1 ;
//end

//wire PLL_PD = ~REF_FLAG ;

//wire         PLL_SYS_PD_DFT           = TEST_MODE ? ~PLL_DFT_RSTJ : ~PLL_SYS_PD ;

//wire  [23:0] PLL_SYS_FRAC         = TEST_MODE ? 24'd0   : MBIST_MODE ? 24'd0    :PLL_SYS_FRAC_REG        ;
//wire  [4:0]  PLL_SYS_PREDIV       = TEST_MODE ? 5'd4    : MBIST_MODE ? 5'd4     :PLL_SYS_PREDIV_REG      ;
//wire         PLL_SYS_DIS_SSCG     = TEST_MODE ? 1'b1    : MBIST_MODE ? 1'b1     :PLL_SYS_DIS_SSCG_REG    ;
//wire         PLL_SYS_TESTEN       = TEST_MODE ? 1'b0    : MBIST_MODE ? 1'b0     :PLL_SYS_TESTEN_REG      ;
//wire  [11:0] PLL_SYS_FBDIV        = TEST_MODE ? 12'd333 : MBIST_MODE ? 12'd333  :PLL_SYS_FBDIV_REG       ;
//wire         PLL_SYS_DACPD        = TEST_MODE ? 1'b1    : MBIST_MODE ? 1'b1     :PLL_SYS_DACPD_REG       ;
//wire         PLL_SYS_DSMPD        = TEST_MODE ? 1'b1    : MBIST_MODE ? 1'b1     :PLL_SYS_DSMPD_REG       ;
//wire  [1:0]  PLL_SYS_TESTSEL      = TEST_MODE ? 2'b0    : MBIST_MODE ? 2'b0     :PLL_SYS_TESTSEL_REG     ;
//wire  [2:0]  PLL_SYS_POSTDIV0_0   = TEST_MODE ? 3'h3    : MBIST_MODE ? 3'h3     :PLL_SYS_POSTDIV0_0_REG  ;
//wire  [2:0]  PLL_SYS_POSTDIV0_1   = TEST_MODE ? 3'h4    : MBIST_MODE ? 3'h4     :PLL_SYS_POSTDIV0_1_REG  ;
//wire  [2:0]  PLL_SYS_POSTDIV1_0   = TEST_MODE ? 3'h0    : MBIST_MODE ? 3'h0     :PLL_SYS_POSTDIV1_0_REG  ;
//wire  [2:0]  PLL_SYS_POSTDIV1_1   = TEST_MODE ? 3'h0    : MBIST_MODE ? 3'h0     :PLL_SYS_POSTDIV1_1_REG  ;
//wire         PLL_SYS_SEL_EXTWAVE  = TEST_MODE ? 1'b0    : MBIST_MODE ? 1'b0     :PLL_SYS_SEL_EXTWAVE_REG ;
//wire  [7:0]  PLL_SYS_EXT_MAXADDR  = TEST_MODE ? 8'h0    : MBIST_MODE ? 8'h0     :PLL_SYS_EXT_MAXADDR_REG ;
//wire  [7:0]  PLL_SYS_EXT_WAVEVAL  = TEST_MODE ? 8'h0    : MBIST_MODE ? 8'h0     :PLL_SYS_EXT_WAVEVAL_REG ;
//wire  [1:0]  PLL_SYS_GVCO_BIAS    = TEST_MODE ? 2'h1    : MBIST_MODE ? 2'h1     :PLL_SYS_GVCO_BIAS_REG   ;
//wire  [2:0]  PLL_SYS_CPP_BIAS     = TEST_MODE ? 3'h2    : MBIST_MODE ? 3'h2     :PLL_SYS_CPP_BIAS_REG    ;
//wire  [2:0]  PLL_SYS_CPI_BIAS     = TEST_MODE ? 3'h3    : MBIST_MODE ? 3'h3     :PLL_SYS_CPI_BIAS_REG    ;
//wire  [3:0]  PLL_SYS_DIVVAL       = TEST_MODE ? 4'b1    : MBIST_MODE ? 4'b1     :PLL_SYS_DIVVAL_REG      ;
//wire  [2:0]  PLL_SYS_SPREAD       = TEST_MODE ? 3'b0    : MBIST_MODE ? 3'b0     :PLL_SYS_SPREAD_REG      ;
//wire         PLL_SYS_DOWNSPREAD   = TEST_MODE ? 1'b0    : MBIST_MODE ? 1'b0     :PLL_SYS_DOWNSPREAD_REG  ;


wire  PLL_SYS_PD ;
wire  PLL_PD_GEN_DFT = TEST_MODE ? PLL_DFT_RSTJ : PLL_SYS_PD_REG ;


PLL_PD_GEN U_PLL_PD_GEN (
 .PLL_PD_IN    (PLL_PD_GEN_DFT  ),
 .PLL_PD_OUT   (PLL_SYS_PD      ),

 .PLL_CLK      (PLL_SYS_CLK     ),
 .PLL_RSTJ     (PLL_SYS_RSTJ    )
);

// DFS pd: 与上电 pd 相或
wire PLL_SYS_DFS_PD ;
wire PLL_SYS_PD_ALL = PLL_SYS_PD | (PLL_SYS_DFS_PD & ~TEST_MODE) ;

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
// DFS clock gate: gate 请求 (PLL_SYS_CLK 域) 同步到各输出时钟域后驱动 ICG, 并回传握手
//   复位值为 1: 上电 / boot 阶段时钟常开
//------------------------------------------------------------------------------
wire PLL_SYS_DFS_GATE_EN  ;
wire PLL_SYS_F600_GATE_EN ;
wire PLL_SYS_F400_GATE_EN ;

PLL_DFS_SYNC2 #(.RST_VAL(1'b1)) U_PLL_SYS_F600_GATE_SYNC (.CLK(PLL_SYS_F600_OUT_CLK), .RSTJ(PLL_SYS_RSTJ), .D(PLL_SYS_DFS_GATE_EN), .Q(PLL_SYS_F600_GATE_EN));
PLL_DFS_SYNC2 #(.RST_VAL(1'b1)) U_PLL_SYS_F400_GATE_SYNC (.CLK(PLL_SYS_F400_OUT_CLK), .RSTJ(PLL_SYS_RSTJ), .D(PLL_SYS_DFS_GATE_EN), .Q(PLL_SYS_F400_GATE_EN));

P_CLK_GATE U_PLL_SYS_F600_CLK_GATE (.CLK(PLL_SYS_F600_OUT_CLK), .EN(PLL_SYS_F600_GATE_EN), .SE(TEST_MODE), .YGCLK  (PLL_SYS_F600_CLK));
P_CLK_GATE U_PLL_SYS_F400_CLK_GATE (.CLK(PLL_SYS_F400_OUT_CLK), .EN(PLL_SYS_F400_GATE_EN), .SE(TEST_MODE), .YGCLK  (PLL_SYS_F400_CLK));


PLL_SYS_DFS_CTRL #(
    .PD_CYC             (DFS_PD_CYC          ),
    .SETTLE_CYC         (DFS_SETTLE_CYC      ),
    .LOCK_STABLE_CYC    (DFS_LOCK_STABLE_CYC ),
    .LOCK_TIMEOUT_CYC   (DFS_LOCK_TIMEOUT_CYC)
) U_PLL_SYS_DFS_CTRL (
    .CLK                (PLL_SYS_CLK         ),
    .RSTJ               (PLL_SYS_RSTJ        ),
    .INT_EN             (PLL_SYS_INT_EN_DFT  ),
    .INT_CLR            (PLL_SYS_INT_CLR     ),
    .CORE_WFI_MODE_0    (CORE_WFI_MODE_0     ),
    .CORE_WFI_MODE_1    (CORE_WFI_MODE_1     ),
    .PLL_LOCK           (PLL_SYS_LOCK        ),
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
//   IDLE --INT_EN↑--> WAIT_WFI --两 core WFI 稳定--> GATE --全部 ICG 已关--> PD (pd=1)
//   --> APPLY (CFG_LOAD, pd 保持 PD_CYC) --> WAIT_LOCK (pd=0, 等 LOCK 稳定 / 超时)
//   --> UNGATE --全部 ICG 已开--> DONE (LOCK_INT=1) --> IDLE
//   WAIT_WFI 中 INT_EN 清 0 则取消回 IDLE
//==============================================================================
module PLL_SYS_DFS_CTRL #(
    parameter CNT_W            = 16,
    parameter N_GCLK           = 2,      // 被 gate 的时钟个数
    parameter WFI_STABLE_CYC   = 4,      // WFI 需连续保持的周期数 (>=1)
    parameter PD_CYC           = 100,    // 设置 divider 后 pd 保持周期数 (>=1us)
    parameter SETTLE_CYC       = 16,     // release pd 后, 开始检测 LOCK 前的等待周期
    parameter LOCK_STABLE_CYC  = 8,      // LOCK 需连续保持的周期数 (>=1)
    parameter LOCK_TIMEOUT_CYC = 0       // 等 LOCK 超时周期数 (0: 不超时)
)(
    input  wire              CLK          ,
    input  wire              RSTJ         ,
    input  wire              INT_EN       ,  // 中断使能, 上升沿启动 DFS
    input  wire              INT_CLR      ,  // 中断清除 (电平)
    input  wire              CORE_WFI_MODE_0,
    input  wire              CORE_WFI_MODE_1,
    input  wire              PLL_LOCK     ,
    output reg               GATE_EN      ,  // 时钟 gate 请求 (1: 开)
    input  wire [N_GCLK-1:0] GATE_EN_FB   ,  // 各时钟域实际 ICG EN, 回传握手
    output wire              CFG_LOAD     ,  // 加载 divider 配置 (单周期, pd 已为 1)
    output reg               PLL_PD       ,  // PLL pd (高有效)
    output wire              DFS_BUSY     ,
    output reg               DFS_DONE     ,
    output reg               LOCK_TIMEOUT ,
    output reg               LOCK_INT
);

localparam ST_IDLE      = 3'd0;
localparam ST_WAIT_WFI  = 3'd1;   // step 3
localparam ST_GATE      = 3'd2;   // step 4
localparam ST_PD        = 3'd3;   // step 5: pd=1
localparam ST_APPLY     = 3'd4;   // step 5: 设置 divider, pd 保持 >= 1us
localparam ST_WAIT_LOCK = 3'd5;   // step 5: pd=0, 等 LOCK
localparam ST_UNGATE    = 3'd6;   // step 6
localparam ST_DONE      = 3'd7;   // step 7

reg  [2:0]       state, state_nxt;
reg  [CNT_W-1:0] cnt;
reg  [CNT_W-1:0] tmo_cnt;

// 同步
wire              int_en_s, int_clr_s, wfi0_s, wfi1_s, lock_s;
wire [N_GCLK-1:0] gate_fb_s;
reg               int_en_s_d;

PLL_DFS_SYNC2 U_SYNC_INTEN (.CLK(CLK), .RSTJ(RSTJ), .D(INT_EN         ), .Q(int_en_s ));
PLL_DFS_SYNC2 U_SYNC_CLR   (.CLK(CLK), .RSTJ(RSTJ), .D(INT_CLR        ), .Q(int_clr_s));
PLL_DFS_SYNC2 U_SYNC_WFI0  (.CLK(CLK), .RSTJ(RSTJ), .D(CORE_WFI_MODE_0), .Q(wfi0_s   ));
PLL_DFS_SYNC2 U_SYNC_WFI1  (.CLK(CLK), .RSTJ(RSTJ), .D(CORE_WFI_MODE_1), .Q(wfi1_s   ));
PLL_DFS_SYNC2 U_SYNC_LOCK  (.CLK(CLK), .RSTJ(RSTJ), .D(PLL_LOCK       ), .Q(lock_s   ));

genvar i;
generate
    for (i = 0; i < N_GCLK; i = i + 1) begin : G_FB_SYNC
        PLL_DFS_SYNC2 #(.RST_VAL(1'b1)) U_SYNC_FB (.CLK(CLK), .RSTJ(RSTJ), .D(GATE_EN_FB[i]), .Q(gate_fb_s[i]));
    end
endgenerate

always @(posedge CLK or negedge RSTJ)
    if (!RSTJ) int_en_s_d <= 1'b0;
    else       int_en_s_d <= int_en_s;

wire start       = int_en_s & ~int_en_s_d;
wire wfi_all     = wfi0_s & wfi1_s;
wire gate_all_on = &gate_fb_s;
wire gate_all_off= ~|gate_fb_s;

wire cnt_hit     = (cnt == {CNT_W{1'b0}});
wire tmo_en      = (LOCK_TIMEOUT_CYC != 0);
wire tmo_hit     = tmo_en & (tmo_cnt == {CNT_W{1'b0}});

always @(*) begin
    state_nxt = state;
    case (state)
        ST_IDLE     : if (start)                          state_nxt = ST_WAIT_WFI;
        ST_WAIT_WFI : if (!int_en_s)                      state_nxt = ST_IDLE;      // SW 取消
                      else if (wfi_all && cnt_hit)        state_nxt = ST_GATE;
        ST_GATE     : if (gate_all_off)                   state_nxt = ST_PD;
        ST_PD       :                                     state_nxt = ST_APPLY;
        ST_APPLY    : if (cnt_hit)                        state_nxt = ST_WAIT_LOCK;
        ST_WAIT_LOCK: if ((lock_s && cnt_hit) || tmo_hit) state_nxt = ST_UNGATE;
        ST_UNGATE   : if (gate_all_on)                    state_nxt = ST_DONE;
        ST_DONE     :                                     state_nxt = ST_IDLE;
        default     :                                     state_nxt = ST_IDLE;
    endcase
end

always @(posedge CLK or negedge RSTJ)
    if (!RSTJ) state <= ST_IDLE;
    else       state <= state_nxt;

// 通用计数器: 进入状态时装载, 状态内递减到 0
always @(posedge CLK or negedge RSTJ) begin
    if (!RSTJ)
        cnt <= {CNT_W{1'b0}};
    else begin
        case (state)
            ST_IDLE     : cnt <= WFI_STABLE_CYC - 1;
            ST_WAIT_WFI : if (!wfi_all)               cnt <= WFI_STABLE_CYC - 1;   // WFI 需连续保持
                          else if (!cnt_hit)          cnt <= cnt - 1'b1;
            ST_PD       : cnt <= PD_CYC - 1;
            ST_APPLY    : if (!cnt_hit)               cnt <= cnt - 1'b1;
                          else                        cnt <= SETTLE_CYC + LOCK_STABLE_CYC - 1;
            ST_WAIT_LOCK: if (cnt < LOCK_STABLE_CYC && !lock_s)
                                                      cnt <= LOCK_STABLE_CYC - 1;  // LOCK 需连续保持
                          else if (!cnt_hit)          cnt <= cnt - 1'b1;
            default     : cnt <= {CNT_W{1'b0}};
        endcase
    end
end

// LOCK 超时计数
always @(posedge CLK or negedge RSTJ)
    if (!RSTJ)                        tmo_cnt <= {CNT_W{1'b0}};
    else if (state != ST_WAIT_LOCK)   tmo_cnt <= tmo_en ? LOCK_TIMEOUT_CYC - 1 : 0;
    else if (!tmo_hit)                tmo_cnt <= tmo_cnt - 1'b1;

// gate 请求: GATE 起拉低, UNGATE 起拉高
always @(posedge CLK or negedge RSTJ)
    if (!RSTJ)                                             GATE_EN <= 1'b1;
    else if (state == ST_WAIT_WFI && state_nxt == ST_GATE) GATE_EN <= 1'b0;
    else if (state_nxt == ST_UNGATE)                       GATE_EN <= 1'b1;

// pd=1 之后一拍加载 divider
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
        if (state == ST_WAIT_LOCK && tmo_hit && !(lock_s && cnt_hit))
            LOCK_TIMEOUT <= 1'b1;
    end
end

// 中断: 时钟重新打开后置位; INT_CLR 或清 INT_EN 清除; 置位优先
always @(posedge CLK or negedge RSTJ)
    if (!RSTJ)                              LOCK_INT <= 1'b0;
    else if (state == ST_DONE && int_en_s)  LOCK_INT <= 1'b1;
    else if (int_clr_s || !int_en_s)        LOCK_INT <= 1'b0;

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
