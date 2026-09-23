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

按用途，STRAP PIN 分为两类，二者采样结构完全相同，区别在于下游驱动方式与是否支持软件重配置：

| 类别 | 信号 | 下游处理 | 软件重配置 |
|---|---|---|---|
| DFT 类 | `TEST_MODE` | 由独立模块采样，经时钟缓冲单元驱动、走时钟网络；配置寄存器排除在扫描链之外 | **不支持** |
| 功能类 | `FUNC_MODE`、`WORK_MODE[2:0]`、`CLK_PLL_OSC`、`BOOT_*` | 经普通逻辑驱动，供 Boot ROM 与软件读取 | 支持 |

`TEST_MODE` 扇出至全芯片每一个 scan mux，扇出量级与时钟、复位相当，必须按时钟网络处理才能保证全片低偏斜。

**复位释放后，功能类 STRAP 的生效值还可由软件通过 APB 寄存器重新配置**，用于免改板调试、启动源切换等场景，详见第 3 章。`TEST_MODE` 不在可重配置之列——其配置通路在硬件上即不存在，软件无论如何操作都无法置位该信号。由于进入任何一种测试子模式都以 `TEST_MODE = 1` 为前提，这一条即可保证运行中的软件无法将芯片切入测试模式。具体实现见附录 A。

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

## 3. STRAP PIN 的软件重配置

### 3.1 功能简介

复位释放后，芯片内部保存的 STRAP 生效值可由软件通过 APB 从机接口重新写入，无需改动板级上下拉电阻即可改变启动源、CPU 时钟源与 ES 工作模式。典型用途包括：

- 单板调试阶段动态切换启动介质（NOR Flash / SPI NAND / eMMC / USB / UART）；
- 产线上用同一块板卡验证多种启动路径；
- 软件读回当前实际生效的配置值，用于自检与故障定位。

**`TEST_MODE` 不支持软件重配置。** 该位的软件写入通路在硬件上即未实现：其配置寄存器不接受寄存器加载，触发位写入亦为空操作。因此运行中的软件（包括被攻破的软件）无法将芯片切入 DFT 测试模式，只能通过重新复位并在复位期间施加正确的引脚电平进入。

### 3.2 实现架构

重配置采用「数据寄存器 + 触发握手」的跨时钟域加载机制。APB 寄存器工作在 `PCLK` 域，STRAP 配置寄存器工作在 `STRAP_CLK` 域，两者通过触发位完成同步：

```
  PCLK 域                                  STRAP_CLK 域
  ┌──────────────────┐                     ┌──────────────────────┐
  │ STRAP_PIN_REG    │ ──── 数据 ────────▶ │ 配置寄存器            │
  │ (0x00/0x04/0x08) │                     │ r_*_cfg              │
  ├──────────────────┤                     │      ▲               │
  │ STRAP_PIN_TRIG   │ ─ 触发 ─▶ 两级同步 ─▶ 上升沿检测 ──加载使能─┘
  │ (0x0C, W1S)      │                     │      │               │
  │        ▲         │ ◀──── 清除脉冲 ─────┘      │               │
  └────────┴─────────┘  STRAP_PIN_CLEAR           │               │
                                                   └──────────────┘
```

触发位经两级同步器进入 `STRAP_CLK` 域后做上升沿检测，检出的单周期脉冲既作为配置寄存器的加载使能，又回送至 APB 侧清除触发位，形成完整握手。数据总线本身不做同步——软件先写数据、后写触发，触发经过两拍同步的时间足以保证数据早已稳定。

### 3.3 寄存器映射

基地址由 SOC 总线分配，下表为相对基地址的偏移。

| 偏移 | 名称 | 属性 | 位域定义 |
|---|---|---|---|
| 0x00 | BOOT_REG | R/W | [0] BOOT_USB_DEV<br>[1] BOOT_UART<br>[2] BOOT_NOR_NAND<br>[3] BOOT_EMMC |
| 0x04 | CLK_REG | R/W | [0] CLK_PLL_OSC |
| 0x08 | MODE_REG | R/W | [0] TEST_MODE（**写入无效**）<br>[1] FUNC_MODE<br>[4:2] WORK_MODE[2:0] |
| 0x0C | TRIG | W1S，硬件自清 | [0] BOOT_USB_DEV<br>[1] BOOT_UART<br>[2] BOOT_NOR_NAND<br>[3] BOOT_EMMC<br>[4] CLK_PLL_OSC<br>[5] TEST_MODE（**保留，写入无效**）<br>[6] FUNC_MODE<br>[7] WORK_MODE[2:0]（三位整体生效） |
| 0x10 | BOOT_RPT | RO | [3:0] 当前实际生效的启动配置，位序同 BOOT_REG |
| 0x14 | CLK_RPT | RO | [0] 当前实际生效的 CLK_PLL_OSC |
| 0x18 | MODE_RPT | RO | [0] 当前实际生效的 SCAN_MODE<br>[1] FUNC_MODE<br>[4:2] WORK_MODE[2:0] |

说明：

- `*_REG` 组为**暂存寄存器**，写入后并不立即生效，读回的是暂存值而非实际生效值；
- `*_RPT` 组为**只读回报寄存器**，反映 `STRAP_CLK` 域中当前真正驱动芯片的配置值。复位后其内容为引脚采样值，软件重配置成功后更新为新值；
- `MODE_RPT[0]` 回报的是 DFT 模式的实际状态，与 `MODE_REG[0]` 无关。软件可通过读取该位确认芯片当前是否处于测试模式。

### 3.4 编程流程

配置单项 STRAP 的标准流程如下（以切换至 eMMC 启动为例）：

1. **写数据**：向 `BOOT_REG`(0x00) 写入目标值，置位 bit[3]；
2. **发触发**：向 `TRIG`(0x0C) 写入 `0x08`，置位对应的 bit[3]；
3. **等生效**：轮询 `TRIG`(0x0C)，直至 bit[3] 读回 0，表示硬件已完成加载并自动清除触发位；
4. **核对**：读 `BOOT_RPT`(0x10)，确认 bit[3] 为 1。

步骤顺序不可颠倒，第 1 步必须先于第 2 步完成。多项 STRAP 需同时更新时，可先写完所有数据寄存器，再一次性向 `TRIG` 写入多个触发位。

### 3.5 使用约束

1. **写序约束**：必须先写 `*_REG` 数据寄存器，再写 `TRIG` 触发位。若顺序颠倒，硬件将加载到旧的数据值。
2. **触发位轮询约束**：向 `TRIG` 的某一位再次写 1 之前，必须先确认该位已读回 0。在触发位尚未被硬件清除时重复写入，本次请求不会产生新的上升沿，配置不会更新，且触发位可能保持为 1 不再自清。
3. **时钟频率约束**：`PCLK` 频率须不低于 `STRAP_CLK` 频率（建议留 1.5 倍以上裕量）。清除脉冲宽度为一个 `STRAP_CLK` 周期，若 `PCLK` 过慢将无法捕获该脉冲，触发位会滞留为 1。
4. **地址约束**：`PADDR` 须为已去除基地址的偏移量。寄存器内部按全 32 位地址比较，高位不为 0 时不会命中任何寄存器。
5. **TEST_MODE 约束**：`MODE_REG[0]` 与 `TRIG[5]` 均为无效位，写入不产生任何效果，亦不会返回错误。软件如需确认测试模式状态，应读取 `MODE_RPT[0]`。
6. **配置时机约束**：启动源类配置（`BOOT_*`）的重配置须在 Boot ROM 完成取指之前或之后明确的时点进行，运行中途切换将导致取指路径变更。具体可切换时点由软件架构决定，本文不作规定。

---

## 附录 A　RTL 实现说明

本附录说明 HS100 STRAP PIN 相关逻辑的 RTL 实现，供客户在系统集成、时序约束编写与板级调试时参考。完整源码随本文档一并交付。

### A.1 模块划分

| 模块 | 时钟域 | 职责 |
|---|---|---|
| `STRAP_PIN_SHELL` | — | 顶层封装，例化以下三个模块并输出各路生效配置 |
| `STRAP_SYS_REG` | `PCLK` | APB 从机，实现第 3 章的寄存器映射 |
| `PAD_STRAP` | `STRAP_CLK` | 引脚采样冻结、触发同步与软件重配置加载 |
| `DFT_MODE_CTRL` | `SRC_CLK` | `TEST_MODE` 的独立采样与时钟缓冲驱动 |

`DFT_MODE_CTRL` 独立于 `PAD_STRAP` 之外，且不接入任何寄存器通路——这是 `TEST_MODE` 无法被软件配置的结构性保证，而非依靠寄存器属性设置实现。

### A.2 上电采样：复位期间透明，释放后冻结

两处采样逻辑采用同一结构。以 `DFT_MODE_CTRL` 为例，其完整实现为：

```verilog
module DFT_MODE_CTRL (
    input  wire  DFT_MODE_IN , //From Strap Pin
    output wire  DFT_MODE    ,

    input  wire  SRC_CLK     ,
    input  wire  SRC_RSTJ   
);

reg DFT_MODE_REG ;
always @ (posedge SRC_CLK )begin 
    if(!SRC_RSTJ )begin 
        DFT_MODE_REG <= DFT_MODE_IN ;
    end 
end 

P_CLK_BUF DFT_MODE_BUF (.A (DFT_MODE_REG), .Y(DFT_MODE) );

endmodule
```

工作机制：

1. `SRC_RSTJ` 为低期间，触发器对 PAD 电平保持透明，每个 `SRC_CLK` 上升沿重新采样一次；
2. always 块**没有 else 分支**，`SRC_RSTJ` 拉高后触发器不存在任何写入通路，配置自然冻结；
3. 因此无需额外的 lock 标志位或捕获使能脉冲，锁存由电路结构本身保证。

综合工具对该 always 块的理解是：敏感表中只有 `posedge SRC_CLK`，故 `SRC_RSTJ` 并非复位，而是一个普通的数据使能，综合结果为一个带使能触发器（DFFE），使能端为 `~SRC_RSTJ`。

`PAD_STRAP` 中功能类 STRAP 的采样结构与之相同，区别仅在于 else 分支不为空——那里放的是软件重配置的加载通路（见 A.4）。

**关于配置寄存器不带复位**：`DFT_MODE_REG` 刻意不加复位。若为其添加复位，则需要另一个更早的复位信号来复位模式位本身，形成循环依赖。上电至首个 `SRC_CLK` 上升沿之间该寄存器值不确定，但此窗口内 `SRC_RSTJ` 恒为低、芯片处于复位态，不会产生误动作。RTL 仿真中该窗口会出现 X 值，属预期行为。

**关于不加同步器**：`DFT_MODE_IN` 直接取自 PINPAD 的 in 端，中间不插两级同步器。STRAP 电平由板级上下拉电阻决定，是直流静态电平，不存在跨时钟域问题；插入同步器只会额外增加对 T_hold 的要求。

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

### A.4 软件重配置的跨时钟域握手

`PAD_STRAP` 中，触发位先经两级同步器进入 `STRAP_CLK` 域，再做上升沿检测：

```verilog
reg  [TRIG_WIDTH-1:0] trig_d1;
reg  [TRIG_WIDTH-1:0] trig_d2;
wire [TRIG_WIDTH-1:0] trig_posedge = trig_d1 & (~trig_d2);

always @(posedge STRAP_CLK or negedge STRAP_RSTJ) begin
    if (!STRAP_RSTJ) begin
        trig_d1 <= #udly {TRIG_WIDTH{1'b0}};
        trig_d2 <= #udly {TRIG_WIDTH{1'b0}};
    end else begin
        trig_d1 <= #udly STRAP_PIN_TRIG;
        trig_d2 <= #udly trig_d1;
    end
end
```

检出的单周期脉冲有两个去向：一是作为配置寄存器的加载使能，二是回送 APB 侧清除触发位。

```verilog
always @(posedge STRAP_CLK )begin 
    if (!STRAP_RSTJ) begin
        r_boot_usb_dev_cfg  <= #udly BOOT_USB_DEV  ;   // 复位期间：引脚采样
        // ... 其余 strap 同理
    end else begin
        if (trig_posedge[0]) r_boot_usb_dev_cfg <= #udly STRAP_PIN_REG[0];  // 复位后：软件加载
        // ... 其余 strap 同理
    end
end

assign STRAP_PIN_CLEAR = trig_posedge;
```

注意 `trig_posedge[5]`（TEST_MODE）虽然照常产生并回送清除脉冲，但在加载逻辑中没有对应分支，故写 `TRIG[5]` 是一次完整但无副作用的空操作——触发位会被正常置位并自清，而不会改变任何配置。这正是 3.1 节所述安全特性在 RTL 层面的落实方式。

数据总线 `STRAP_PIN_REG` 本身不做同步，属于典型的「数据 + 握手」跨时钟域结构：数据在触发位置位之前就已稳定，触发位又额外经过两拍同步，数据早已越过亚稳态窗口。该结构成立的前提是软件遵守 3.5 节第 1 条写序约束。

### A.5 TEST_MODE 的驱动与 DFT 约束

`TEST_MODE` 扇出至全芯片每一个 scan mux，扇出量级与时钟、复位相当，因此使用时钟缓冲单元 `P_CLK_BUF` 驱动并走时钟网络，以保证全片低偏斜。若按普通逻辑交由综合工具自行 buffer，延迟与偏斜均不可控。

综合与 DFT 约束要求：

- `DFT_MODE_REG` 须排除在扫描链之外（`set_dont_touch` / no scan replacement）；
- `DFT_MODE` 网络须设置 `set_ideal_network`，并在 ATPG 中作为 test constant 处理；
- 扫描链移位期间 `TEST_MODE` 须全程保持稳定，该要求由「复位释放后无写入通路」的结构天然满足。

### A.6 时序参数推导

对应 2.3 节表 2-3，以 `SRC_CLK` / `STRAP_CLK` = 24 MHz 计：

| 文档参数 | 依据 | 推导值 | @24 MHz | 文档取值 |
|---|---|---|---|---|
| T_setup | STRAP 须在复位释放前最后一个时钟上升沿之前稳定 | ≥ 1 × T_clk + t_su(FF) | ≈ 42 ns | 1 μs |
| T_hold | 复位释放沿与时钟沿的相对位置不确定，须覆盖一个完整时钟周期 | ≥ 1 × T_clk | ≈ 42 ns | 1 μs |
| T_rstlow | 采样窗口内至少须发生一次采样 | ≥ 2 × T_clk | ≈ 84 ns | 1 μs |

对外统一取 1 μs，留 20 倍以上工程裕量，客户无需了解内部时钟频率。

另需注意：`SRC_RSTJ` / `STRAP_RSTJ` 在本结构中作为触发器的数据使能使用，其释放沿若落在使能端的建立保持窗口内会引发亚稳态。因此二者应取自「异步置位 / 同步释放」复位同步器的输出，与各自的采样时钟同步。

### A.7 验证用例清单

| 编号 | 用例 | 检查点 |
|---|---|---|
| 1 | 遍历全部 STRAP 引脚组合 | `ALL_STRAP_PIN_RPT` 与期望值一致 |
| 2 | 复位释放后翻转所有 STRAP 引脚 | 生效配置保持不变 |
| 3 | 复位低电平期间采样时钟不翻转 | 确认采样不发生，核对此时芯片行为是否可接受 |
| 4 | 复位释放沿在采样时钟沿附近扫动 | 无 X 传播，`TEST_MODE` 无毛刺 |
| 5 | 逐位执行「写数据 → 写触发 → 轮询自清 → 读回报」流程 | 各 `*_RPT` 位更新正确，`TRIG` 位自动清零 |
| 6 | 颠倒写序（先写触发后写数据） | 加载到旧值，验证 3.5 节第 1 条约束的必要性 |
| 7 | 写 `MODE_REG[0]` 与 `TRIG[5]` | 配置不变，`MODE_RPT[0]` 不受影响，触发位正常自清 |
| 8 | `PCLK` 与 `STRAP_CLK` 频率比扫描（含 `PCLK` 慢于 `STRAP_CLK`） | 确认清除脉冲不丢失，触发位不滞留 |
| 9 | 触发位尚未自清时重复写入同一位 | 复现并确认 3.5 节第 2 条约束描述的行为 |
| 10 | 扫描链移位期间监视 `TEST_MODE` | 全程稳定，且 `DFT_MODE_REG` 未被替换为 scan flop |

## 待确认事项

1. **三个子模式与 STRAP 的映射关系不完整。** 当前 `FUNC_MODE = 0` 对应 AIP/MBIST test mode，`TEST_MODE = 1` 对应 DFT test mode，但 SCAN_MODE 的选中条件、以及 AIP_ES_MODE 与 MBIST_MODE 的区分方式尚未给出。附录 A.4 中的译码表为暂定实现，需确认后更新。
2. **WORK_MODE[2:0] 的 8 种编码含义缺失**（表 2-2 待补充）。
3. **CLK_PLL_OSC 的缺省值请复核**：当前 PAD 为内部上拉，缺省 H = "A45 CPU clock use OSC"，即芯片缺省从 OSC 启动而非 PLL。若为预期行为（上电先跑 OSC，由软件后续切到 PLL），建议在文档中明确说明。
4. **BOOT_* 四根启动配置脚的优先级**：四者同时置 1 时的仲裁顺序需补充启动源优先级表。
5. **PAD 内部上下拉阻值典型值**需从 Datasheet 取值填入 2.3 节。
6. **命名不一致**：引脚表与 RTL 对同一信号的命名不统一——引脚表称 `TEST_MODE`（复用 `XGPIO_5`），而 RTL 中顶层端口为 `SCAN_MODE_IN`、模块内部为 `DFT_MODE`。交付客户前需统一，建议以引脚表的 `TEST_MODE` 为准。
7. **`FUNC_MODE` 的可重配置性请确认**：`FUNC_MODE` 目前走功能类通路，软件可通过 `TRIG[6]` 改写。按 2.2 节定义 `FUNC_MODE = 0` 即 AIP/MBIST test mode，因此该位是否应与 `TEST_MODE` 同样禁止软件写入，取决于待确认项 1 的模式译码真值表。RTL 中 `FUNC_MODE_CTRL` 的例化已被注释屏蔽，需确认这是最终决策还是遗留代码。
8. **`PCLK` 与 `STRAP_CLK` 的频率关系需在 Datasheet 中明确**，以支撑 3.5 节第 3 条约束。
