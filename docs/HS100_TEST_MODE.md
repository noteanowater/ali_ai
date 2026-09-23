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

HS100 不提供软件方式进入测试模式，测试模式只能通过 STRAP PIN 的外部电平配置进入。

芯片复位期间（`RSTJ` 为低），片内配置寄存器对 STRAP 引脚电平保持透明，每个自由振荡时钟 `SRC_CLK` 的上升沿重新采样一次；复位释放后配置寄存器不再有写入通路，配置即被冻结。因此：

- STRAP 只需在复位释放前后的一个时钟周期窗口内稳定，对板级时序要求宽松；
- 配置一经冻结，在本次复位周期内不可更改，必须重新复位才能使新的配置生效；
- 冻结后引脚上的毛刺、串扰或 ESD 不再能改变芯片模式，运行中的软件亦无法激活测试模式，有利于产品安全性。

按用途，STRAP PIN 分为两类，二者采样结构完全相同，区别仅在于下游驱动方式：

| 类别 | 信号 | 下游处理 |
|---|---|---|
| DFT 类 | `TEST_MODE`、`FUNC_MODE` | 经时钟缓冲单元驱动、走时钟网络；配置寄存器排除在扫描链之外 |
| 功能类 | `BOOT_*`、`WORK_MODE[2:0]`、`CLK_PLL_OSC` | 经普通逻辑驱动，供 Boot ROM 与软件读取 |

DFT 类信号扇出至全芯片每一个 scan mux，扇出量级与时钟、复位相当，必须按时钟网络处理才能保证全片低偏斜。具体实现见附录 A。

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
4. **测试模式引脚防误触发**：量产板卡上 `TEST_MODE`、`FUNC_MODE` 应保持缺省状态（悬空或明确固定到正常模式电平），避免因走线耦合或外部干扰在复位窗口内误入测试模式。复位释放后该配置已冻结，引脚上的后续干扰不再生效，但复位期间的布线质量仍需保证：走线应远离高速信号，必要时就近加去耦电容。

**表 2-3　STRAP PIN 采样时序要求**

| 参数 | 说明 | 最小值 | 单位 |
|---|---|---|---|
| T_setup | 复位释放沿之前 STRAP 电平须稳定的时间 | 1 | μs |
| T_hold | 复位释放沿之后 STRAP 电平须保持的时间 | 1 | μs |
| T_rstlow | 复位低电平须持续的时间（期间 `SRC_CLK` 至少须有一个上升沿） | 1 | μs |

> 上述指标按内部 24 MHz OSC 时钟推导（详见附录 A 第 A.6 节），已包含 20 倍以上工程裕量。

---

## 附录 A　STRAP PIN 参考实现

本附录给出 STRAP PIN 采样与测试模式译码的 RTL 参考实现，供客户在系统集成、时序约束编写以及板级调试时参考。该结构与已量产芯片所采用的实现方式一致。

### A.1 实现架构

STRAP 相关逻辑分为三层：

| 层次 | 内容 | 对应模块 |
|---|---|---|
| 采样冻结层（DFT 类） | `TEST_MODE` / `FUNC_MODE` 的采样、冻结与时钟缓冲驱动 | `dft_mode_ctrl` |
| 采样冻结层（功能类） | `BOOT_*` / `WORK_MODE` / `CLK_PLL_OSC` 的采样与冻结 | `strap_latch` |
| 译码与交接层 | 模式译码、复位与时钟旁路、PAD 复用功能交接 | `strap_mode_ctrl` |

### A.2 采样冻结的标准写法

核心结构只有四行：

```verilog
reg TEST_MODE_CONFIG;

always @ (posedge SRC_CLK)
begin
    if (!RSTJ)
        TEST_MODE_CONFIG <= DFT_STRAP_IN;
end
```

其工作机制为：

1. `RSTJ` 为低期间，触发器对 PAD 电平保持透明，每个 `SRC_CLK` 上升沿重新采样一次；
2. always 块**没有 else 分支**，`RSTJ` 拉高后触发器不存在任何写入通路，配置自然冻结；
3. 因此**无需额外的 lock 标志位或捕获使能脉冲**，锁存由电路结构本身保证。

综合工具对该 always 块的理解是：敏感表中只有 `posedge SRC_CLK`，故 `RSTJ` 并非复位，而是一个普通的数据使能。综合结果为一个带使能触发器（DFFE），使能端 `EN = ~RSTJ`。

### A.3 与异步复位写法的区别

下述写法形似而实质不同，**不可采用**：

```verilog
// ✗ 错误：敏感表中含 rst_n，该 always 块描述的是异步复位触发器，
//        其复位分支必须是常量，否则无法映射为 DFFR，综合会报错或推出锁存器
always @ (posedge clk or negedge rst_n)
    if (!rst_n) q <= D;
```

```verilog
// ✓ 正确：敏感表中只有 clk，rst_n 仅是普通数据使能，映射为 DFFE
always @ (posedge clk)
    if (!rst_n) q <= D;
```

两者综合出的是完全不同的电路，编写时须特别注意敏感表的写法。

### A.4 DFT 模式配置模块 dft_mode_ctrl

```verilog
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
```

**关于 `P1_CLKBUF`**：`TEST_MODE` / `FUNC_MODE` 扇出至全芯片每一个 scan mux，扇出量级与时钟、复位相当。使用时钟缓冲单元驱动并走时钟网络，才能保证全片低偏斜；若按普通逻辑交由综合工具自行 buffer，延迟与偏斜均不可控。综合时须对这两条网络设置 `set_ideal_network`，并在 ATPG 中作为 test constant 处理。

**关于配置寄存器不带复位**：`TEST_MODE_CONFIG` 刻意不加复位。若为其添加复位，则需要另一个更早的复位信号来复位模式位本身，形成循环依赖。上电至首个 `SRC_CLK` 上升沿之间该寄存器值不确定，但此窗口内 `RSTJ` 恒为低、芯片处于复位态，不会产生误动作。RTL 仿真中该窗口会出现 X 值，属预期行为。

**关于不加同步器**：`*_STRAP_IN` 直接取自 PINPAD 的 in 端（如 `XGPIO_RA_14_IN`），中间不插两级同步器。STRAP 电平由板级上下拉电阻决定，是直流静态电平，不存在跨时钟域问题；插入同步器只会额外增加对 T_hold 的要求。

### A.5 功能类 STRAP 采样模块 strap_latch

```verilog
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
```

### A.6 译码与 PAD 交接模块 strap_mode_ctrl

```verilog
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
```

### A.7 顶层集成示例与时序参数推导

`CLK_PLL_OSC` 用于选择 A45 CPU 的时钟源。该信号**必须**先经 `strap_latch` 冻结后再驱动时钟切换单元；若直接从 PAD 接入，复用功能（`XUART0_RXD` 串口接收）一旦开始收数据，CPU 时钟源就会被误切换。

```verilog
dft_mode_ctrl U_DFT_MODE_CTRL (
        .SRC_CLK        (osc_clk            ),      // 必须用 OSC, 不能用 PLL
        .RSTJ           (rstj_sync          ),
        .TEST_STRAP_IN  (XGPIO_5_IN         ),      // PINPAD in 端
        .FUNC_STRAP_IN  (XUART0_TXD_IN      ),      // PINPAD in 端
        .TEST_MODE      (test_mode          ),
        .FUNC_MODE      (func_mode          )
        );

strap_latch U_STRAP_LATCH (
        .SRC_CLK        (osc_clk            ),
        .RSTJ           (rstj_sync          ),
        .POR_N          (por_n              ),
        .STRAP_IN       (strap_in[7:0]      ),
        .STRAP_CFG      (strap_cfg[7:0]     )
        );

clk_switch_2to1 U_A45_CLK_SW (
        .test_mode      (test_mode          ),
        .test_se        (test_se            ),
        .rst_n          (rstj_sync          ),
        .clka           (osc_clk            ),
        .clkb           (pll_clk            ),
        .select         (~strap_cfg[0]      ),      // strap_cfg[0] = 1 -> OSC (clka)
        .sel_clk        (osc_clk            ),
        .clk_o          (a45_clk            )
        );
```

`sel_clk` 取 OSC 而非被切换的时钟本身，是为了在 PLL 尚未锁定时切换请求仍能被正常采样。

**时序参数推导**（对应 2.3 节表 2-3）：

| 文档参数 | RTL 依据 | 推导值 | @24 MHz | 文档取值 |
|---|---|---|---|---|
| T_setup | STRAP 须在 `RSTJ` 释放前最后一个 `SRC_CLK` 上升沿之前稳定 | ≥ 1 × T_src + t_su(FF) | ≈ 42 ns | 1 μs |
| T_hold | `RSTJ` 释放沿与 `SRC_CLK` 沿的相对位置不确定，须覆盖一个完整时钟周期 | ≥ 1 × T_src | ≈ 42 ns | 1 μs |
| T_rstlow | 采样窗口内至少须发生一次采样 | ≥ 2 × T_src | ≈ 84 ns | 1 μs |

对外文档统一取 1 μs，留 20 倍以上工程裕量，客户无需了解内部时钟频率。

另需注意：`RSTJ` 在本结构中作为触发器的数据使能使用，其释放沿若落在使能端的建立保持窗口内会引发亚稳态。因此 `RSTJ` 应取自"异步置位 / 同步释放"复位同步器的输出，与 `SRC_CLK` 同步。

### A.8 验证用例清单

| 编号 | 用例 | 检查点 |
|---|---|---|
| 1 | 遍历全部 STRAP 组合 | `STRAP_CFG`、`TEST_MODE`、`FUNC_MODE` 与期望值一致 |
| 2 | `RSTJ` 释放后翻转所有 STRAP 引脚 | 配置保持不变（断言 `a_strap_frozen`） |
| 3 | `RSTJ` 低电平期间 `SRC_CLK` 不翻转 | 确认采样不发生，并核对此时芯片行为是否可接受 |
| 4 | PLL 不起振（`pll_clk` 静默） | 芯片仍以 `STRAP_DEF` 缺省值从 NOR Flash 启动 |
| 5 | `RSTJ` 释放沿在 `SRC_CLK` 沿附近扫动 | 无 X 传播，`TEST_MODE` 无毛刺 |
| 6 | 扫描链移位期间监视 `TEST_MODE` | 全程保持稳定，且该配置寄存器未被替换为 scan flop |

## 待确认事项

1. **三个子模式与 STRAP 的映射关系不完整。** 当前 `FUNC_MODE = 0` 对应 AIP/MBIST test mode，`TEST_MODE = 1` 对应 DFT test mode，但 SCAN_MODE 的选中条件、以及 AIP_ES_MODE 与 MBIST_MODE 的区分方式尚未给出。附录 A.4 中的译码表为暂定实现，需确认后更新。
2. **WORK_MODE[2:0] 的 8 种编码含义缺失**（表 2-2 待补充）。
3. **CLK_PLL_OSC 的缺省值请复核**：当前 PAD 为内部上拉，缺省 H = "A45 CPU clock use OSC"，即芯片缺省从 OSC 启动而非 PLL。若为预期行为（上电先跑 OSC，由软件后续切到 PLL），建议在文档中明确说明。
4. **BOOT_* 四根启动配置脚的优先级**：四者同时置 1 时的仲裁顺序需补充启动源优先级表。
5. **PAD 内部上下拉阻值典型值**需从 Datasheet 取值填入 2.3 节。
