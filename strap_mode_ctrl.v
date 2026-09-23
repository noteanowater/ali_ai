//=============================================================================
//  Module      : strap_mode_ctrl
//  Description : HS100 测试模式译码 + STRAP PIN 与复用功能的交接控制
//
//                TEST_MODE / FUNC_MODE 由 dft_mode_ctrl 采样冻结后送入本模块,
//                本模块只做纯组合译码与 PAD 交接, 不含任何时序元件。
//=============================================================================
module strap_mode_ctrl (
                // --- 来自 dft_mode_ctrl 的已冻结模式位 ---
                TEST_MODE,
                FUNC_MODE,
                WORK_MODE,

                // --- ATE 侧 ---
                SCAN_RSTJ_PIN,
                SCAN_CLK_PIN,

                // --- 功能侧 ---
                RSTJ,
                FUNC_CLK,
                FUNC_OEN,

                // --- 输出 ---
                SCAN_MODE,
                AIP_ES_MODE,
                MBIST_MODE,
                SYS_RSTJ,
                SYS_CLK,
                PAD_OEN,
                PINMUX_SEL
                );

parameter PW = 8;               // 参与 STRAP 复用的 PAD 个数

input           TEST_MODE;
input           FUNC_MODE;
input  [2:0]    WORK_MODE;

input           SCAN_RSTJ_PIN;
input           SCAN_CLK_PIN;

input           RSTJ;
input           FUNC_CLK;
input  [PW-1:0] FUNC_OEN;

output          SCAN_MODE;
output          AIP_ES_MODE;
output          MBIST_MODE;
output          SYS_RSTJ;
output          SYS_CLK;
output [PW-1:0] PAD_OEN;
output          PINMUX_SEL;

//-----------------------------------------------------------------------------
// part 1 : 模式译码 -- 纯组合
//-----------------------------------------------------------------------------
//   TEST_MODE  FUNC_MODE  WORK_MODE  |  mode
//   ---------------------------------+------------------------------------
//       0          x          x      |  Normal / Function Mode
//       1          1          x      |  SCAN_MODE
//       1          0        (待定)    |  AIP_ES_MODE / MBIST_MODE
//-----------------------------------------------------------------------------
assign SCAN_MODE   =  TEST_MODE &   FUNC_MODE;
assign AIP_ES_MODE =  TEST_MODE & (~FUNC_MODE);
assign MBIST_MODE  =  TEST_MODE & (~FUNC_MODE);   // TODO: 按 WORK_MODE 区分

//-----------------------------------------------------------------------------
// part 2 : 复位与时钟旁路
//          扫描模式下复位与时钟必须由 ATE 直接可控, 因此绕开功能复位与功能时钟。
//          此处 mux 仅为示意, 时钟切换须使用 glitch-free 结构
//          (见 clk_switch_2to1.v) 或工艺库提供的 DFT mux 单元。
//-----------------------------------------------------------------------------
assign SYS_RSTJ = TEST_MODE ? SCAN_RSTJ_PIN : RSTJ;
assign SYS_CLK  = TEST_MODE ? SCAN_CLK_PIN  : FUNC_CLK;

//-----------------------------------------------------------------------------
// part 3 : PAD 交接
//          RSTJ 为低期间所有 STRAP 复用 PAD 强制为输入 (oen = 1), 输出驱动关闭,
//          内部上/下拉保持使能, 以免片内逻辑与外部配置电阻打架。
//          RSTJ 释放时配置已在同一时刻冻结, 故可直接以 RSTJ 作为交接信号。
//-----------------------------------------------------------------------------
assign PAD_OEN    = RSTJ ? FUNC_OEN : {PW{1'b1}};
assign PINMUX_SEL = RSTJ;       // 0 = STRAP 采样态, 1 = 复用功能态

endmodule
