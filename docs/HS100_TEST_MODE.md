# HS100 测试模式（TEST MODE）设计说明

| 项目 | 内容 |
|---|---|
| 文档名称 | HS100 测试模式设计说明 |
| 适用芯片 | HS100 |
| 版本 | V0.1（草稿） |
| 状态 | 编写中 |

---

## 1. HS100 测试模式概述

### 1.1 功能简介

HS100 除正常功能模式（Function Mode）外，还提供一组面向芯片可测性设计（DFT, Design For Testability）的测试模式，用于晶圆测试（CP）、成品测试（FT）以及硅后调试（Post-Silicon Debug）。

HS100 的测试模式划分为以下三个子模式：

| 子模式 | 全称 | 用途 |
|---|---|---|
| SCAN_MODE | Scan Chain Test Mode | 扫描链测试，用于逻辑单元的固定型故障（Stuck-at）与时延故障（At-Speed）检测 |
| AIP_ES_MODE | Analog IP Engineering Sample Mode | 模拟 IP 工程样片评估模式，用于 PLL、ADC、PHY 等模拟模块的单独观测与特性评估 |
| MBIST_MODE | Memory Built-In Self-Test Mode | 存储器内建自测试，用于片上 SRAM/ROM 的读写功能与冗余修复测试 |

### 1.2 测试模式的进入方式

HS100 不提供软件方式进入测试模式，测试模式只能通过 STRAP PIN 的外部电平配置进入。按生效机制的不同，STRAP PIN 分为两类：

- **DFT 类（异步直通）**：`TEST_MODE`、`FUNC_MODE`。由引脚电平实时、异步地决定芯片所处模式，不依赖时钟与复位。
- **功能类（复位锁存）**：`BOOT_*`、`WORK_MODE[2:0]`、`CLK_PLL_OSC`。在复位释放时刻被采样并锁存，锁存后在本次复位周期内不可更改，必须重新复位才能使新的配置生效。

DFT 类信号之所以不做锁存，是因为扫描测试开始前 ATE 尚未提供可靠时钟、功能复位也已被测试逻辑接管；若模式位依赖时钟沿建立，芯片将无法进入 SCAN_MODE。具体实现见附录 A。

该设计保证测试模式无法由运行中的软件激活，有利于产品安全性。

---

## 2. STRAP PIN 机制说明

### 2.1 定义

**STRAP PIN（配置引脚，又称 Bootstrap Pin / Configuration Pin）** 是指芯片在复位释放时刻对其电平进行一次性采样、并将采样结果锁存至内部配置寄存器的一组引脚。芯片依据锁存值确定上电后的启动行为与工作模式。

STRAP PIN 具有以下典型特征：

1. **复用性**：STRAP 功能是引脚的"第二功能"。采样完成后，该引脚立即释放并切换回其正常功能（如 UART、I²C、GPIO 等），不会因作为 STRAP 使用而损失 I/O 资源。
2. **一次性采样**：仅在复位释放后采样一次，采样后引脚电平的变化不再影响已锁存的配置。
3. **默认值确定性**：每个 STRAP PIN 的 PAD 均内置上拉或下拉电阻，在外部不施加任何配置时，芯片进入确定的缺省状态（正常功能模式 + NOR Flash 启动）。

### 2.2 STRAP PIN 配置一览表

| STRAP 信号 | 复用 Pin 名 | PAD 类型 | 缺省电平 | 复位后功能 | 取值定义 |
|---|---|---|---|---|---|
| FUNC_MODE | XUART0_TXD | PBSU8RNC | H | GPIO_24 | 1：Function Mode（正常功能模式）<br>0：AIP / MBIST Test Mode |
| CLK_PLL_OSC | XUART0_RXD | PBSU8RNC | H | GPIO_25 | 1：A45 CPU 时钟源选择 OSC<br>0：A45 CPU 时钟源选择 PLL |
| TEST_MODE | XGPIO_5 | PBCD8RNC | L | GPIO_31 | 1：进入 DFT Test Mode<br>0：Normal Mode |
| WORK_MODE[0] | XIIC1_SCL | PBCU12RNC | H | GPIO_72 | ES Mode 选择，详见表 2-2 |
| WORK_MODE[1] | XIIC1_SDA | PBCU12RNC | H | GPIO_73 | ES Mode 选择，详见表 2-2 |
| WORK_MODE[2] | XIIC0_SCL | PBCU12RNC | H | GPIO_74 | ES Mode 选择，详见表 2-2 |
| BOOT_USB_DEV | XMTR0 | PBCD8RNC | L | GPIO_76 | 1：从 USB 启动<br>0：正常启动（Flash） |
| BOOT_UART | XMTR1 | PBCD8RNC | L | GPIO_77 | 1：从 UART 启动<br>0：正常启动（Flash） |
| BOOT_NOR_NAND | XMTR2 | PBCD8RNC | L | GPIO_78 | 1：从 SPI NAND Flash 启动<br>0：从 NOR Flash 启动 |
| BOOT_EMMC | XMTR3 | PBCD8RNC | L | GPIO_79 | 1：从 eMMC 启动<br>0：从 Flash 启动 |

**PAD 类型命名规则**

| 字段 | 含义 |
|---|---|
| PB | Pad, Bi-directional（双向 I/O PAD） |
| S / C | S = Schmitt Trigger 输入；C = CMOS 标准输入 |
| U / D | U = 内部上拉（Pull-Up）；D = 内部下拉（Pull-Down） |
| 8 / 12 | 输出驱动能力，单位 mA |

由该规则可知，上表"缺省电平"一列与 PAD 内部上/下拉方向完全对应：`PBSU*` / `PBCU*` 缺省为高电平，`PBCD*` 缺省为低电平。

**缺省状态**：在所有 STRAP PIN 均悬空（不外接配置电阻）时，HS100 进入 `FUNC_MODE = 1`、`TEST_MODE = 0` 的正常功能模式，并由 NOR Flash 启动。该缺省组合即为量产板卡的典型配置。

### 2.3 硬件设计注意事项

1. **配置电阻取值**：若需将某 STRAP PIN 配置为与其缺省电平相反的状态，须外接下拉/上拉电阻，阻值建议为 1 kΩ～4.7 kΩ，以确保能够可靠翻转 PAD 内部上下拉（内部上下拉典型值约为 **XX kΩ，待补充**）。若配置为与缺省电平一致的状态，可直接悬空，无需外接器件。
2. **建立/保持时间**：STRAP PIN 电平须在复位释放沿之前稳定建立，并在复位释放沿之后继续保持，具体要求见表 2-3。
3. **复用功能冲突规避**：STRAP PIN 在采样完成后会切换为 UART / I²C / GPIO 等功能，设计时须确认外接的配置电阻及下游器件不会干扰其正常功能。尤其注意：
   - `XUART0_TXD` / `XUART0_RXD` 复用为调试串口，其配置电阻不应影响串口通信的上升/下降沿质量；
   - `XIIC0_SCL` / `XIIC1_SCL` / `XIIC1_SDA` 复用为 I²C 总线，其 STRAP 配置电阻应与 I²C 总线上拉电阻统筹考虑，避免与总线规定的上拉阻值冲突。
4. **测试模式引脚防误触发**：量产板卡上 `TEST_MODE`、`FUNC_MODE` 应保持缺省状态（悬空或明确固定到正常模式电平），避免因走线耦合或外部干扰误入测试模式。由于这两根信号为异步直通，运行过程中的电平变化会立即生效，因此其布线应远离高速信号，必要时串联小阻值电阻并就近加去耦。

**表 2-3　STRAP PIN 采样时序要求**

| 参数 | 说明 | 最小值 | 单位 |
|---|---|---|---|
| T_setup | 复位释放沿之前 STRAP 电平须稳定的时间 | 1 | μs |
| T_hold | 复位释放沿之后 STRAP 电平须保持的时间 | 1 | μs |

> 上述指标按内部 24 MHz OSC 时钟推导（详见附录 A 第 A.5 节），已包含 4 倍工程裕量。

---

## 附录 A　STRAP PIN 参考实现

本附录给出 STRAP PIN 采样与测试模式译码的 RTL 参考实现，供客户在系统集成、时序约束编写以及板级调试时参考。

### A.1 实现架构

STRAP 相关逻辑分为三层：

| 层次 | 内容 | 对应模块 |
|---|---|---|
| PAD 层 | 内部上/下拉使能、输出驱动关断、复用功能切换 | `strap_mode_ctrl`（part 3） |
| 采样锁存层 | 功能类 STRAP 的复位采样与上锁 | `strap_latch` |
| 模式使用层 | DFT 类 STRAP 的异步直通与模式译码 | `strap_mode_ctrl`（part 1、part 2） |

两类 STRAP 的实现方式对比：

| 类别 | 信号 | 实现方式 | 原因 |
|---|---|---|---|
| DFT 类（异步直通） | TEST_MODE、FUNC_MODE、SCAN_EN | PAD → buffer → 直接驱动 DFT mux，不经任何触发器 | 必须在无时钟、复位被旁路的条件下生效 |
| 功能类（复位锁存） | BOOT_*、WORK_MODE[2:0]、CLK_PLL_OSC | 解复位后固定拍数捕获一次，随即上锁 | 供 Boot ROM / 软件读取，需防止运行中被复用功能干扰 |

### A.2 常见错误写法

以下写法无法综合出正确电路，请勿采用：

```verilog
// ✗ 错误：异步复位触发器的复位值必须是常量
always @(posedge clk or negedge rst_n)
    if (!rst_n) strap_cfg <= strap_pin;   // 综合推不出 DFFR，会报错或推成锁存器
    else        strap_cfg <= strap_cfg;
```

正确做法是将复位值取为 PAD 缺省电平（常量），解复位后再用一个一次性使能脉冲去捕获真实管脚值。

### A.3 采样锁存模块 strap_latch

```verilog
//=============================================================================
//  Module      : strap_latch
//  Description : HS100 STRAP PIN sampling & locking
//
//                功能类 STRAP (BOOT_*, WORK_MODE, CLK_PLL_OSC) 的复位采样逻辑。
//                DFT 类 STRAP (TEST_MODE / FUNC_MODE) 不在本模块内, 必须由 PAD
//                异步直通至 DFT 控制逻辑, 详见 strap_mode_ctrl 说明。
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
// STRAP bit map (与 2.2 节 STRAP PIN 配置表一致)
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
```

### A.4 模式译码与 PAD 交接模块 strap_mode_ctrl

```verilog
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
```

### A.5 顶层集成示例与时序参数推导

`CLK_PLL_OSC` 用于选择 A45 CPU 的时钟源。该信号**必须**先经 `strap_latch` 锁存后再驱动时钟切换单元；若直接从 PAD 接入，复用功能（`XUART0_RXD` 串口接收）一旦开始收数据，CPU 时钟源就会被误切换。

```verilog
strap_latch U_STRAP_LATCH (
        .test_mode  (test_mode      ),
        .test_se    (test_se        ),
        .clk        (osc_clk        ),      // 必须用 OSC, 不能用 PLL
        .por_rst_n  (por_rst_n_sync ),
        .strap_pin  (strap_pin[7:0] ),
        .strap_cfg  (strap_cfg[7:0] ),
        .strap_lock (strap_lock     )
        );

clk_switch_2to1 U_A45_CLK_SW (
        .test_mode  (test_mode      ),
        .test_se    (test_se        ),
        .rst_n      (por_rst_n_sync ),
        .clka       (osc_clk        ),
        .clkb       (pll_clk        ),
        .select     (~strap_cfg[0]  ),      // strap_cfg[0] = 1 -> OSC (clka)
        .sel_clk    (osc_clk        ),
        .clk_o      (a45_clk        )
        );
```

`sel_clk` 取 OSC 而非被切换的时钟本身，是为了在 PLL 尚未锁定时切换请求仍能被正常采样。

**时序参数推导**（对应 2.3 节表 2-3）：

| 文档参数 | RTL 依据 | 推导值 | 文档取值 |
|---|---|---|---|
| T_setup | 同步器两级 + 建立余量 | ≥ 3 × T_osc | 1 μs |
| T_hold | 复位释放 → cap_en → 同步器延迟 | ≥ (CAP_DLY + 2) × T_osc = 6 × T_osc | 1 μs |

以 OSC = 24 MHz 计，T_hold 理论最小值为 250 ns。对外文档统一取 1 μs，留 4 倍工程裕量，客户无需了解内部时钟频率。

### A.6 验证用例清单

| 编号 | 用例 | 检查点 |
|---|---|---|
| 1 | 遍历全部 STRAP 组合 | `strap_cfg` 与期望值一致 |
| 2 | `strap_lock` 拉高后翻转所有 `strap_pin` | `strap_cfg` 保持不变（断言 `a_strap_frozen`） |
| 3 | PLL 不起振（`pll_clk` 静默） | 芯片仍以 `STRAP_DEF` 缺省值从 NOR Flash 启动 |
| 4 | 采样窗口内使 `strap_pin` 在时钟沿附近跳变 | 同步器不产生 X 传播 |
| 5 | 无时钟、无复位条件下拉高 `test_mode_pin` | `scan_mode` 立即建立（DFT 直通路径关键验证点） |

---

## 待确认事项

1. **三个子模式与 STRAP 的映射关系不完整。** 当前 `FUNC_MODE = 0` 对应 AIP/MBIST test mode，`TEST_MODE = 1` 对应 DFT test mode，但 SCAN_MODE 的选中条件、以及 AIP_ES_MODE 与 MBIST_MODE 的区分方式尚未给出。附录 A.4 中的译码表为暂定实现，需确认后更新。
2. **WORK_MODE[2:0] 的 8 种编码含义缺失**（表 2-2 待补充）。
3. **CLK_PLL_OSC 的缺省值请复核**：当前 PAD 为内部上拉，缺省 H = "A45 CPU clock use OSC"，即芯片缺省从 OSC 启动而非 PLL。若为预期行为（上电先跑 OSC，由软件后续切到 PLL），建议在文档中明确说明。
4. **BOOT_* 四根启动配置脚的优先级**：四者同时置 1 时的仲裁顺序需补充启动源优先级表。
5. **PAD 内部上下拉阻值典型值**需从 Datasheet 取值填入 2.3 节。
