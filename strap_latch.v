//=============================================================================
//  Module      : strap_latch
//  Description : HS100 功能类 STRAP PIN 采样 (BOOT_*, WORK_MODE, CLK_PLL_OSC)
//
//                与 dft_mode_ctrl 采用同一结构: RSTJ 为低期间触发器保持透明,
//                RSTJ 释放后无 else 分支, 配置自然冻结, 本次复位周期内不可更改。
//
//                DFT 类 STRAP (TEST_MODE / FUNC_MODE) 不在本模块内, 见
//                dft_mode_ctrl.v -- 二者结构相同, 但 DFT 类需要时钟缓冲驱动。
//
//  Note        : 1. SRC_CLK 必须是上电即自由振荡的时钟 (OSC / XTAL)。
//                   RSTJ 低电平期间至少须有一个 SRC_CLK 上升沿。
//                2. STRAP_IN 直接取自 PINPAD 的 in 端, 不插同步器。
//                3. STRAP_CONFIG 带缺省值复位并非必需, 但功能类 STRAP 由
//                   Boot ROM 读取, 上电不定值可能被误采样, 故此处保留
//                   STRAP_DEF 作为上电初值, 由独立的上电复位 POR_N 置入。
//                   若 SOC 内无更早的 POR_N 可用, 可删除该复位, 行为与
//                   dft_mode_ctrl 完全一致。
//=============================================================================
module strap_latch (
                SRC_CLK,
                RSTJ,
                POR_N,

                STRAP_IN,
                STRAP_CFG
                );

//-----------------------------------------------------------------------------
// STRAP bit map (与《HS100 测试模式设计说明》2.2 节配置表一致)
//-----------------------------------------------------------------------------
//   bit       strap signal      mux pin        pad type      default
//   [0]       CLK_PLL_OSC       XUART0_RXD     PBSU8RNC      1 (pull-up)
//   [3:1]     WORK_MODE[2:0]    XIIC*          PBCU12RNC     111 (pull-up)
//   [4]       BOOT_USB_DEV      XMTR0          PBCD8RNC      0 (pull-down)
//   [5]       BOOT_UART         XMTR1          PBCD8RNC      0 (pull-down)
//   [6]       BOOT_NOR_NAND     XMTR2          PBCD8RNC      0 (pull-down)
//   [7]       BOOT_EMMC         XMTR3          PBCD8RNC      0 (pull-down)
//-----------------------------------------------------------------------------
parameter SW = 8;
parameter STRAP_DEF = 8'b0000_111_1;    // PAD 内部上/下拉决定的缺省电平

input               SRC_CLK;
input               RSTJ;               // 低有效复位, 兼作 STRAP 采样窗口
input               POR_N;              // 上电复位, 仅用于置入缺省初值
input  [SW-1:0]     STRAP_IN;           // 来自 PINPAD in 端的原始电平

output [SW-1:0]     STRAP_CFG;          // 冻结后的配置值, 供 Boot ROM / 软件读取

reg    [SW-1:0]     STRAP_CONFIG;

assign STRAP_CFG = STRAP_CONFIG;

always @ (posedge SRC_CLK or negedge POR_N)
begin
    if (!POR_N)
        STRAP_CONFIG <= #1 STRAP_DEF;   // 常量, 可正确映射为 DFFR/DFFS
    else if (!RSTJ)
        STRAP_CONFIG <= #1 STRAP_IN;    // RSTJ 低: 透明采样; RSTJ 高: 保持
end

//-----------------------------------------------------------------------------
// 断言 (仅用于仿真, 综合不可见)
//-----------------------------------------------------------------------------
// synopsys translate_off
`ifdef SVA_ON
    // RSTJ 释放后 STRAP_CFG 不得再发生任何变化
    property p_strap_frozen;
        @(posedge SRC_CLK) disable iff (!POR_N)
            RSTJ |=> $stable(STRAP_CFG);
    endproperty
    a_strap_frozen : assert property (p_strap_frozen)
        else $error("STRAP config changed after RSTJ release !");
`endif
// synopsys translate_on

endmodule
