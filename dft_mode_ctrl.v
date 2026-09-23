//=============================================================================
//  Module      : dft_mode_ctrl
//  Description : HS100 DFT 模式配置采样 (TEST_MODE / FUNC_MODE)
//
//                实现方式与量产芯片 DFT_MODE_CTRL 保持一致:
//                RSTJ 为低期间, 触发器对 PAD 电平保持透明, 每个 SRC_CLK 上升沿
//                重新采样一次; RSTJ 释放后 always 块无 else 分支, 触发器自然
//                保持, 配置即被冻结 -- 锁存无需额外的 lock 标志位。
//
//                该结构同时提供安全特性: 模式位一经冻结, 引脚上的毛刺/串扰/ESD
//                不再能改变芯片模式, 必须重新复位才能重新配置。
//
//  Note        : 1. SRC_CLK 必须是上电即自由振荡的时钟 (OSC / XTAL), 不可使用
//                   PLL 输出。RSTJ 低电平期间 SRC_CLK 至少须有一个上升沿,
//                   否则采样不会发生。
//                2. RSTJ 应取自"异步置位 / 同步释放"复位同步器的输出, 与
//                   SRC_CLK 同步, 以免其释放沿落在触发器使能端的建立保持窗口内。
//                3. *_STRAP_IN 直接取自 PINPAD 的 in 端 (如 XGPIO_RA_14_IN),
//                   中间不插同步器 -- STRAP 由板级电阻决定, 是直流静态电平。
//                4. *_CONFIG 不带复位: 加复位会形成循环依赖 (用哪个复位去复位
//                   模式位本身)。上电至首个 SRC_CLK 上升沿之间其值不确定,
//                   但此窗口内 RSTJ 恒为低, 芯片处于复位态, 不会误动作。
//
//  DFT         : TEST_MODE_CONFIG / FUNC_MODE_CONFIG 必须排除在扫描链之外
//                (set_dont_touch / no scan replacement); TEST_MODE 与 FUNC_MODE
//                须设置 set_ideal_network, 并在 ATPG 中作为 test constant 处理。
//=============================================================================
module dft_mode_ctrl (
                SRC_CLK,
                RSTJ,

                TEST_STRAP_IN,
                FUNC_STRAP_IN,

                TEST_MODE,
                FUNC_MODE
                );

input           SRC_CLK;        // 自由振荡时钟, 复位期间即有效
input           RSTJ;           // 低有效复位, 同时作为 STRAP 采样窗口
input           TEST_STRAP_IN;  // XGPIO_5  PAD in 端 (PBCD8RNC, 缺省 L)
input           FUNC_STRAP_IN;  // XUART0_TXD PAD in 端 (PBSU8RNC, 缺省 H)

output          TEST_MODE;      // 1 = 进入 DFT Test Mode
output          FUNC_MODE;      // 1 = Function Mode, 0 = AIP / MBIST Test Mode

reg             TEST_MODE_CONFIG;
reg             FUNC_MODE_CONFIG;

//-----------------------------------------------------------------------------
// part 1 : 复位期间透明采样, 复位释放后自然冻结
//-----------------------------------------------------------------------------
always @ (posedge SRC_CLK)
begin
    if (!RSTJ) begin
        TEST_MODE_CONFIG <= #1 TEST_STRAP_IN;
        FUNC_MODE_CONFIG <= #1 FUNC_STRAP_IN;
    end
end

//-----------------------------------------------------------------------------
// part 2 : 输出缓冲
//          TEST_MODE / FUNC_MODE 扇出至全芯片每一个 scan mux, 扇出量级与
//          时钟、复位相当, 因此使用时钟缓冲单元驱动并走时钟网络, 以保证全片
//          低 skew。若交由综合工具按普通逻辑自行 buffer, 延迟与偏斜不可控。
//-----------------------------------------------------------------------------
P1_CLKBUF U_TEST_MODE (.A(TEST_MODE_CONFIG), .Z(TEST_MODE));
P1_CLKBUF U_FUNC_MODE (.A(FUNC_MODE_CONFIG), .Z(FUNC_MODE));

endmodule
