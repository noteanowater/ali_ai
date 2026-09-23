//=============================================================================
//  Module      : strap_latch
//  Description : HS100 STRAP PIN sampling & locking
//
//                功能类 STRAP (BOOT_*, WORK_MODE, CLK_PLL_OSC) 的复位采样逻辑。
//                DFT 类 STRAP (TEST_MODE / FUNC_MODE) 不在本模块内, 必须由 PAD
//                异步直通至 DFT 控制逻辑, 详见 strap_dft_ctrl 说明。
//
//  Note        : 1. clk 必须使用上电即自由振荡的 OSC 时钟, 不可使用 PLL 输出,
//                   否则 PLL 未锁定前无法完成采样。
//                2. por_rst_n 为经过"异步置位 / 同步释放"处理后的上电复位。
//                3. 复位期间 strap_cfg 保持 STRAP_DEF (等于 PAD 内部上/下拉的
//                   缺省电平), 保证时钟异常时芯片仍进入确定的缺省状态。
//=============================================================================
module strap_latch (
                test_mode,
                test_se,
                clk,
                por_rst_n,

                strap_pin,

                strap_cfg,
                strap_lock
                );

//-----------------------------------------------------------------------------
// STRAP bit map (与《HS100 TEST MODE》STRAP PIN 配置表一致)
//-----------------------------------------------------------------------------
//   bit       strap signal      mux pin        pad type      default
//   [0]       CLK_PLL_OSC       XUART0_RXD     PBSU8RNC      1 (pull-up)
//   [3:1]     WORK_MODE[2:0]    XIIC*          PBCU12RNC     111 (pull-up)
//   [4]       BOOT_USB_DEV      XMTR0          PBCD8RNC      0 (pull-down)
//   [5]       BOOT_UART         XMTR1          PBCD8RNC      0 (pull-down)
//   [6]       BOOT_NOR_NAND     XMTR2          PBCD8RNC      0 (pull-down)
//   [7]       BOOT_EMMC         XMTR3          PBCD8RNC      0 (pull-down)
//-----------------------------------------------------------------------------
parameter SW      = 8;                  // strap 位宽
parameter CAP_DLY = 4;                  // 解复位后第 CAP_DLY-1 拍捕获
parameter STRAP_DEF = 8'b0000_111_1;    // PAD 缺省电平

input               test_mode;
input               test_se;
input               clk;
input               por_rst_n;
input  [SW-1:0]     strap_pin;          // 来自 PAD 的原始电平 (未经处理)

output [SW-1:0]     strap_cfg;          // 锁存后的配置值, 复位前保持缺省值
output              strap_lock;         // 1 = 采样完成, 配置已锁定

reg    [SW-1:0]     strap_cfg;
reg                 strap_lock;

reg    [SW-1:0]     strap_sync_d0;
reg    [SW-1:0]     strap_sync_d1;
reg    [CAP_DLY-1:0] cap_sr;

//-----------------------------------------------------------------------------
// part 1 : 两级同步器, 消除 PAD 电平与采样时钟之间可能的亚稳态
//          strap 在 T_setup/T_hold 窗口内是静态的, 同步器仅作为工程裕量。
//-----------------------------------------------------------------------------
always @ (posedge clk or negedge por_rst_n)
begin
    if (!por_rst_n) begin
        strap_sync_d0 <= #1 STRAP_DEF;
        strap_sync_d1 <= #1 STRAP_DEF;
    end
    else begin
        strap_sync_d0 <= #1 strap_pin;
        strap_sync_d1 <= #1 strap_sync_d0;
    end
end

//-----------------------------------------------------------------------------
// part 2 : 解复位后产生单拍捕获使能。cap_sr 复位后依次为
//          0000 -> 0001 -> 0011 -> 0111 -> 1111 (此后饱和),
//          cap_en 只在 0111 这一拍为高, 全芯片仅捕获一次。
//-----------------------------------------------------------------------------
always @ (posedge clk or negedge por_rst_n)
begin
    if (!por_rst_n)
        cap_sr <= #1 {CAP_DLY{1'b0}};
    else
        cap_sr <= #1 {cap_sr[CAP_DLY-2:0], 1'b1};
end

wire cap_en = cap_sr[CAP_DLY-2] & (~cap_sr[CAP_DLY-1]);

//-----------------------------------------------------------------------------
// part 3 : 捕获并锁存。strap_lock 置位后无任何通路可改写 strap_cfg,
//          只有重新复位 (por_rst_n 拉低) 才能重新采样,
//          即"配置一经锁存, 本次复位周期内不可更改"。
//-----------------------------------------------------------------------------
always @ (posedge clk or negedge por_rst_n)
begin
    if (!por_rst_n)
        strap_cfg <= #1 STRAP_DEF;
    else if (cap_en && !strap_lock)
        strap_cfg <= #1 strap_sync_d1;
end

always @ (posedge clk or negedge por_rst_n)
begin
    if (!por_rst_n)
        strap_lock <= #1 1'b0;
    else if (cap_en)
        strap_lock <= #1 1'b1;
end

//-----------------------------------------------------------------------------
// part 4 : 断言 (仅用于仿真, 综合时不可见)
//-----------------------------------------------------------------------------
// synopsys translate_off
`ifdef SVA_ON
    // 锁存完成后, strap_cfg 不得再发生任何变化
    property p_strap_frozen;
        @(posedge clk) disable iff (!por_rst_n)
            strap_lock |=> $stable(strap_cfg);
    endproperty
    a_strap_frozen : assert property (p_strap_frozen)
        else $error("STRAP config changed after lock !");

    // 捕获使能在一次复位周期内有且仅有一拍
    property p_cap_once;
        @(posedge clk) disable iff (!por_rst_n)
            cap_en |=> always (!cap_en);
    endproperty
    a_cap_once : assert property (p_cap_once)
        else $error("STRAP capture pulse asserted more than once !");
`endif
// synopsys translate_on

endmodule
