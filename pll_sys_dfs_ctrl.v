//==============================================================================
// Module  : pll_sys_dfs_ctrl
// Function: PLL_SYS 硬件调频 (DFS) 控制器
//
// 软件 / 硬件分工:
//   SW 1. CPU 执行 boot 流程
//   SW 2. 配置 SCU: PLL_SYS_SEL[1:0] / PLL_CFG, 然后置位 PLL_INI_EN, CPU 两个 core 执行 WFI
//   HW 3. 等待 core_wfi_mode_0 / core_wfi_mode_1 均为 1 (并保持 WFI_STABLE_CYC 个周期)
//   HW 4. Gate PLL CLK (pll_clk 域内 ICG 关断, 握手确认已关断)
//   HW 5. 将 PLL_SYS_SEL / PLL_CFG 更新到 PLL, 可选输出 pll_rst 脉冲, 等待 PLL LOCK
//   HW 6. 开启 PLL_SYS_Gate (握手确认已打开)
//   HW 7. 发出 PLL_SYS_LOCK_INT (电平中断, 需 SW 通过 pll_int_clr 清除), 唤醒 CPU
//
//   若配置了 LOCK_TIMEOUT_CYC 且超时: 仍打开时钟并发中断 (否则 CPU 无法被唤醒),
//   同时置 pll_lock_timeout, SW 在 ISR 中检查并处理
//
// 时钟说明:
//   clk_ref : 常开参考时钟 (如 OSC 24MHz), 状态机工作在该时钟域, 调频过程中不能停
//   pll_clk : PLL 输出时钟, 本模块在 pll_clk 域内用 ICG 无毛刺地 gate, 输出 pll_clk_gated
//
// 跨时钟域说明:
//   pll_ini_en / pll_int_en / pll_int_clr / core_wfi_mode_* / pll_lock 均做 2 级同步
//   pll_sys_sel_i / pll_cfg_i 为准静态信号: SW 必须先写 SEL/CFG, 再写 PLL_INI_EN,
//   硬件在 PLL CLK 已 gate 之后才采样, 因此无需逐位同步
//
// 中断说明:
//   CPU 中断号已占满时, 可在顶层将 pll_sys_lock_int 与 boot 后不再使用的中断 OR 在一起,
//   SW 在 ISR 中读 pll_dfs_done / pll_lock_timeout 状态区分中断源
//==============================================================================
module pll_sys_dfs_ctrl #(
    parameter CFG_W            = 32,     // PLL_CFG 位宽
    parameter CNT_W            = 16,     // 计数器位宽
    parameter WFI_STABLE_CYC   = 4,      // WFI 需连续保持的 clk_ref 周期数 (>=1)
    parameter PLL_RST_CYC      = 0,      // 更新配置后 pll_rst 脉宽 (0: 不输出复位)
    parameter PLL_SETTLE_CYC   = 16,     // 更新配置后, 开始检测 LOCK 前的等待周期 (屏蔽旧 LOCK)
    parameter LOCK_STABLE_CYC  = 8,      // LOCK 需连续保持的周期数 (>=1)
    parameter LOCK_TIMEOUT_CYC = 0       // 等 LOCK 超时周期数 (0: 不超时)
)(
    input                   clk_ref,
    input                   rst_n,
    input                   test_mode,
    input                   test_se,

    // ---------------- SCU ----------------
    input                   pll_ini_en,        // PLL_INI_EN, 上升沿启动调频
    input       [1:0]       pll_sys_sel_i,     // PLL_SYS_SEL[1:0]
    input       [CFG_W-1:0] pll_cfg_i,         // PLL_CFG
    input                   pll_int_en,        // 中断使能
    input                   pll_int_clr,       // 中断清除 (电平, 高有效)

    // ---------------- CPU ----------------
    input                   core_wfi_mode_0,   // u_a45_top.core_wfi_mode_0
    input                   core_wfi_mode_1,   // u_a45_top.core_wfi_mode_1

    // ---------------- PLL ----------------
    input                   pll_clk,           // PLL 输出时钟
    input                   pll_lock,          // PLL LOCK
    output reg  [1:0]       pll_sys_sel_o,     // 送 PLL / 时钟 mux 的 SEL
    output reg  [CFG_W-1:0] pll_cfg_o,         // 送 PLL 的配置
    output reg              pll_rst,           // PLL 复位 (高有效, 可选)
    output                  pll_clk_gated,     // gate 后的 PLL_SYS 时钟

    // ---------------- 状态 / 中断 ----------------
    output                  pll_dfs_busy,      // 调频进行中
    output reg              pll_dfs_done,      // 调频完成 (下一次启动时清 0)
    output reg              pll_lock_timeout,  // 等待 LOCK 超时 (下一次启动时清 0)
    output reg              pll_sys_lock_int   // PLL_SYS_LOCK_INT
);

//------------------------------------------------------------------------------
// FSM 编码
//------------------------------------------------------------------------------
localparam ST_IDLE      = 3'd0;
localparam ST_WAIT_WFI  = 3'd1;   // step 3
localparam ST_GATE      = 3'd2;   // step 4
localparam ST_APPLY     = 3'd3;   // step 5: 更新配置 / PLL 复位
localparam ST_WAIT_LOCK = 3'd4;   // step 5: 等 LOCK
localparam ST_UNGATE    = 3'd5;   // step 6
localparam ST_DONE      = 3'd6;   // step 7

reg  [2:0]       state, state_nxt;
reg  [CNT_W-1:0] cnt;
reg  [CNT_W-1:0] tmo_cnt;

//------------------------------------------------------------------------------
// 同步到 clk_ref 域
//------------------------------------------------------------------------------
wire ini_en_s, int_en_s, int_clr_s, wfi0_s, wfi1_s, lock_s, gate_ack_s;
reg  ini_en_s_d;

pll_dfs_sync2 u_sync_ini   (.clk(clk_ref), .rst_n(rst_n), .d(pll_ini_en     ), .q(ini_en_s ));
pll_dfs_sync2 u_sync_inten (.clk(clk_ref), .rst_n(rst_n), .d(pll_int_en     ), .q(int_en_s ));
pll_dfs_sync2 u_sync_clr   (.clk(clk_ref), .rst_n(rst_n), .d(pll_int_clr    ), .q(int_clr_s));
pll_dfs_sync2 u_sync_wfi0  (.clk(clk_ref), .rst_n(rst_n), .d(core_wfi_mode_0), .q(wfi0_s   ));
pll_dfs_sync2 u_sync_wfi1  (.clk(clk_ref), .rst_n(rst_n), .d(core_wfi_mode_1), .q(wfi1_s   ));
pll_dfs_sync2 u_sync_lock  (.clk(clk_ref), .rst_n(rst_n), .d(pll_lock       ), .q(lock_s   ));

always @(posedge clk_ref or negedge rst_n)
    if (!rst_n) ini_en_s_d <= 1'b0;
    else        ini_en_s_d <= ini_en_s;

wire start   = ini_en_s & ~ini_en_s_d;
wire wfi_all = wfi0_s & wfi1_s;

//------------------------------------------------------------------------------
// gate 请求 (clk_ref 域) -> pll_clk 域 ICG enable -> 回传 ack (clk_ref 域)
//   复位值为 1: 上电 / boot 阶段时钟常开
//------------------------------------------------------------------------------
reg  gate_en_req;
wire gate_en_pll;

pll_dfs_sync2 #(.RST_VAL(1'b1)) u_sync_gate (.clk(pll_clk), .rst_n(rst_n), .d(gate_en_req), .q(gate_en_pll));
pll_dfs_sync2 #(.RST_VAL(1'b1)) u_sync_ack  (.clk(clk_ref), .rst_n(rst_n), .d(gate_en_pll), .q(gate_ack_s ));

wire clk_gate_en = test_mode ? 1'b1 : gate_en_pll;

P1_CLK_GATE u_pll_sys_gate (
    .CLK   (pll_clk      ),
    .EN    (clk_gate_en  ),
    .SE    (test_se      ),
    .YGCLK (pll_clk_gated)
);

//------------------------------------------------------------------------------
// FSM
//------------------------------------------------------------------------------
wire cnt_hit      = (cnt == {CNT_W{1'b0}});
wire tmo_en       = (LOCK_TIMEOUT_CYC != 0);
wire tmo_hit      = tmo_en & (tmo_cnt == {CNT_W{1'b0}});

always @(*) begin
    state_nxt = state;
    case (state)
        ST_IDLE     : if (start)                          state_nxt = ST_WAIT_WFI;
        ST_WAIT_WFI : if (!ini_en_s)                      state_nxt = ST_IDLE;      // SW 取消
                      else if (wfi_all && cnt_hit)        state_nxt = ST_GATE;
        ST_GATE     : if (!gate_ack_s)                    state_nxt = ST_APPLY;
        ST_APPLY    : if (cnt_hit)                        state_nxt = ST_WAIT_LOCK;
        ST_WAIT_LOCK: if ((lock_s && cnt_hit) || tmo_hit) state_nxt = ST_UNGATE;
        ST_UNGATE   : if (gate_ack_s)                     state_nxt = ST_DONE;
        ST_DONE     :                                     state_nxt = ST_IDLE;
        default     :                                     state_nxt = ST_IDLE;
    endcase
end

always @(posedge clk_ref or negedge rst_n)
    if (!rst_n) state <= ST_IDLE;
    else        state <= state_nxt;

// 通用计数器: 进入状态时装载, 状态内递减到 0
always @(posedge clk_ref or negedge rst_n) begin
    if (!rst_n)
        cnt <= {CNT_W{1'b0}};
    else begin
        case (state)
            ST_IDLE     : cnt <= WFI_STABLE_CYC - 1;
            ST_WAIT_WFI : if (!wfi_all)               cnt <= WFI_STABLE_CYC - 1;   // WFI 需连续保持
                          else if (!cnt_hit)          cnt <= cnt - 1'b1;
            ST_GATE     : cnt <= (PLL_RST_CYC != 0) ? PLL_RST_CYC - 1 : 0;
            ST_APPLY    : if (!cnt_hit)               cnt <= cnt - 1'b1;
                          else                        cnt <= PLL_SETTLE_CYC + LOCK_STABLE_CYC - 1;
            ST_WAIT_LOCK: if (cnt < LOCK_STABLE_CYC && !lock_s)
                                                      cnt <= LOCK_STABLE_CYC - 1;  // LOCK 需连续保持
                          else if (!cnt_hit)          cnt <= cnt - 1'b1;
            default     : cnt <= {CNT_W{1'b0}};
        endcase
    end
end

// LOCK 超时计数
always @(posedge clk_ref or negedge rst_n)
    if (!rst_n)                       tmo_cnt <= {CNT_W{1'b0}};
    else if (state != ST_WAIT_LOCK)   tmo_cnt <= tmo_en ? LOCK_TIMEOUT_CYC - 1 : 0;
    else if (!tmo_hit)                tmo_cnt <= tmo_cnt - 1'b1;

// gate 请求: GATE 起拉低, UNGATE 起拉高
always @(posedge clk_ref or negedge rst_n)
    if (!rst_n)                                        gate_en_req <= 1'b1;
    else if (state == ST_WAIT_WFI && state_nxt == ST_GATE) gate_en_req <= 1'b0;
    else if (state_nxt == ST_UNGATE)                   gate_en_req <= 1'b1;

// PLL 配置输出: 在时钟已 gate 后 (进入 APPLY 时) 更新
always @(posedge clk_ref or negedge rst_n) begin
    if (!rst_n) begin
        pll_sys_sel_o <= 2'b0;
        pll_cfg_o     <= {CFG_W{1'b0}};
    end
    else if (state == ST_GATE && state_nxt == ST_APPLY) begin
        pll_sys_sel_o <= pll_sys_sel_i;
        pll_cfg_o     <= pll_cfg_i;
    end
end

// PLL 复位脉冲 (PLL_RST_CYC 个 clk_ref 周期)
always @(posedge clk_ref or negedge rst_n)
    if (!rst_n) pll_rst <= 1'b0;
    else        pll_rst <= (PLL_RST_CYC != 0) && (state_nxt == ST_APPLY);

// 状态
assign pll_dfs_busy = (state != ST_IDLE);

always @(posedge clk_ref or negedge rst_n) begin
    if (!rst_n) begin
        pll_dfs_done     <= 1'b0;
        pll_lock_timeout <= 1'b0;
    end
    else if (start) begin
        pll_dfs_done     <= 1'b0;
        pll_lock_timeout <= 1'b0;
    end
    else begin
        if (state == ST_DONE)
            pll_dfs_done <= 1'b1;
        if (state == ST_WAIT_LOCK && tmo_hit && !(lock_s && cnt_hit))
            pll_lock_timeout <= 1'b1;
    end
end

// 中断: 时钟重新打开后置位, SW 清除; 置位优先
always @(posedge clk_ref or negedge rst_n)
    if (!rst_n)                             pll_sys_lock_int <= 1'b0;
    else if (state == ST_DONE && int_en_s)  pll_sys_lock_int <= 1'b1;
    else if (int_clr_s || !int_en_s)        pll_sys_lock_int <= 1'b0;

endmodule


//==============================================================================
// 2 级同步器 (综合时可替换为工艺库标准同步单元)
//==============================================================================
module pll_dfs_sync2 #(
    parameter RST_VAL = 1'b0
)(
    input  clk,
    input  rst_n,
    input  d,
    output q
);
reg [1:0] sync;
always @(posedge clk or negedge rst_n)
    if (!rst_n) sync <= {2{RST_VAL}};
    else        sync <= {sync[0], d};
assign q = sync[1];
endmodule
