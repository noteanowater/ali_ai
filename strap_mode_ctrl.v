//=============================================================================
//  Module      : strap_mode_ctrl
//  Description : HS100 测试模式译码 + STRAP PIN 与复用功能的交接控制
//
//  CRITICAL    : test_mode_pin / func_mode_pin 由 PAD 异步直通, 中间不允许插入
//                任何触发器或锁存器。扫描测试时 ATE 尚未提供可靠时钟, 功能复位
//                也已被旁路, 若模式位依赖时钟沿建立, 芯片将永远无法进入
//                SCAN_MODE。综合脚本中必须对这两条路径设置
//                set_case_analysis / set_dont_touch, 并作为 DFT constant 处理。
//=============================================================================
module strap_mode_ctrl (
                // --- 来自 PAD 的原始电平 (异步, 不经采样) ---
                test_mode_pin,
                func_mode_pin,
                scan_rst_n_pin,
                scan_clk_pin,

                // --- 功能侧 ---
                por_rst_n,
                func_clk,
                strap_lock,
                func_oen,

                // --- 输出 ---
                test_mode,
                scan_mode,
                aip_es_mode,
                mbist_mode,
                sys_rst_n,
                sys_clk,
                pad_oen,
                pinmux_sel
                );

parameter PW = 8;               // 参与 STRAP 复用的 PAD 个数

input           test_mode_pin;
input           func_mode_pin;
input           scan_rst_n_pin;
input           scan_clk_pin;

input           por_rst_n;
input           func_clk;
input           strap_lock;
input  [PW-1:0] func_oen;

output          test_mode;
output          scan_mode;
output          aip_es_mode;
output          mbist_mode;
output          sys_rst_n;
output          sys_clk;
output [PW-1:0] pad_oen;
output          pinmux_sel;

//-----------------------------------------------------------------------------
// part 1 : 模式译码 -- 纯组合, 无任何时序元件
//-----------------------------------------------------------------------------
//   TEST_MODE  FUNC_MODE  |  mode
//   ----------------------+------------------------------------
//       0          x      |  Normal / Function Mode
//       1          1      |  SCAN_MODE
//       1          0      |  AIP_ES_MODE / MBIST_MODE
//                         |  (二者由 WORK_MODE[2:0] 进一步区分, 待补充)
//-----------------------------------------------------------------------------
assign test_mode   =  test_mode_pin;
assign scan_mode   =  test_mode_pin &   func_mode_pin;
assign aip_es_mode =  test_mode_pin & (~func_mode_pin);
assign mbist_mode  =  test_mode_pin & (~func_mode_pin);   // TODO: 按 WORK_MODE 区分

//-----------------------------------------------------------------------------
// part 2 : 复位与时钟旁路
//          扫描模式下复位必须由 ATE 直接可控, 因此绕开复位同步器;
//          时钟同理, 由 ATE 驱动。此处用普通 mux 只是示意, 时钟切换须使用
//          glitch-free 结构 (见 clk_switch_2to1.v) 或 DFT mux 单元。
//-----------------------------------------------------------------------------
assign sys_rst_n = test_mode_pin ? scan_rst_n_pin : por_rst_n;
assign sys_clk   = test_mode_pin ? scan_clk_pin   : func_clk;

//-----------------------------------------------------------------------------
// part 3 : PAD 交接
//          复位期间及采样完成前, 所有 STRAP 复用 PAD 强制为输入 (oen = 1),
//          输出驱动关闭, 内部上/下拉保持使能, 以免片内逻辑与外部配置电阻打架。
//          strap_lock 拉高后才交还给复用功能。
//-----------------------------------------------------------------------------
assign pad_oen    = strap_lock ? func_oen : {PW{1'b1}};
assign pinmux_sel = strap_lock;     // 0 = STRAP 采样态, 1 = 复用功能态

endmodule
