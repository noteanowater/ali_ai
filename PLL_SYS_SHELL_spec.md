# PLL_SYS_SHELL 设计说明

## 1. 概述

PLL_SYS_SHELL 是 INNO PLL（SMIC 40LL）的封装模块，为 A45 CPU 和系统总线提供时钟。

- 参考时钟：OSC_24M_CLK，24 MHz
- clko0：CPU 时钟（PLL_SYS_F600_CLK）
- clko1：BUS/IP 时钟（PLL_SYS_F400_CLK）
- 分频比（NI、frac、M、postdiv）：由 strap pin CPU_SPEED_SEL[1:0] 决定
- 环路参数、SSC、测试监测和断电控制：由 SCU 寄存器配置
- TEST_MODE、MBIST_ES_MODE：分频配置仍由 strap 决定，寄存器配置的字段固定为默认值

## 2. 频率计算

```
Fpfd  = Fref / M                         规格 10 ~ 100 MHz
Fvco  = Fref × (NI + frac/2^24) / M      规格 1000 ~ 3200 MHz
Fclko = Fvco / (postdiv0_x + 1) / (postdiv1_x + 1)
```

- NI 可取 8、9、10、12~4095，不能取 11
- M 可取 1~31
- postdiv 寄存器编码 = 分频值 − 1（3'h0 为 ÷1，3'h7 为 ÷8）
- 整数模式：frac = 0，dacpd = 1，dsmpd = 1
- 小数模式：dacpd = 0，dsmpd = 0

## 3. 频率配置

### 3.1 功能模式（由 CPU_SPEED_SEL 选择）

| CPU_SPEED_SEL | NI | frac | M | Fvco (MHz) | 模式 | CPU（clko0） | BUS（clko1） |
|---|---|---|---|---|---|---|---|
| 2'b00 | 83 | 24'h555555 | 1 | 2000 | 小数 | ÷4 → 500 | ÷5 → 400 |
| 2'b01 | 116 | 24'hAAAAAB | 1 | 2800 | 小数 | ÷5 → 560 | ÷7 → 400 |
| 2'b10 | 100 | 0 | 1 | 2400 | 整数 | ÷4 → 600 | ÷6 → 400 |
| 2'b11（低频） | 133 | 24'h555555 | 1 | 3200 | 小数 | ÷7 → 457.14 | ÷8 → 400 |

- 小数模式的频率误差小于 ±0.5 Hz，可以忽略。
- 低频档：BUS 维持 400 MHz（UART、LVDS 等 IP 以它为参考时钟），CPU 取 450 ± 10 MHz 范围内唯一可行的 457.14 MHz。Fvco = 3200 MHz，位于 VCO 规格上限（1 ~ 3.2 GHz），需与 IP 厂商确认全 PVT 下的余量。

### 3.2 TEST_MODE / MBIST_ES_MODE

分频配置（NI、frac、M、postdiv、dacpd、dsmpd）和功能模式相同，由 CPU_SPEED_SEL 决定；寄存器配置的字段固定为默认值（见第 8 节）。

> - ATE 上 CPU_SPEED_SEL 必须给确定的值，测试频率完全由它决定。
> - CPU_SPEED_SEL = 2'b00 或 2'b01 时，测试期间 PLL 工作在小数模式（Delta-Sigma 调制器运行）。如果希望测试时只用整数模式，ATE 上 strap 应给 2'b10（600/400 MHz）。

## 4. 端口说明

| 端口 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| PLL_SYS_F600_CLK | O | 1 | CPU 时钟（clko0 经过门控） |
| PLL_SYS_F400_CLK | O | 1 | BUS 时钟（clko1 经过门控） |
| PLL_SYS_LOCK | O | 1 | PLL 锁定指示 |
| PLL_SYS_TESTOUT | O | 1 | PLL 内部监测输出 |
| PLL_SYS_TBLADDR | O | 8 | 外部 SSC 波形表地址 |
| PLL_SYS_TEST_DIV1_CLK / DIV2_CLK | O | 1 | clko0 / clko1 的分频观测时钟 |
| PLL_SYS_SCAN_DIV1_CLK / DIV2_CLK | O | 1 | 扫描时钟（÷1 / ÷2） |
| PLL_SYS_CLK_DIV1 / DIV2 | I | 8 | 观测时钟分频值 |
| PLL_SYS_CFG_0 / 1 / 2 | I | 32 / 29 / 32 | SCU 配置寄存器 |
| PLL_SYS_CFG_EN | I | 1 | 配置装载使能，上升沿有效 |
| CPU_SPEED_SEL | I | 2 | strap pin 频率选择，需在模块外锁存 |
| TEST_MODE | I | 1 | 扫描测试模式 |
| MBIST_ES_MODE | I | 1 | MBIST 模式 |
| OSC_24M_CLK | I | 1 | PLL 参考时钟 |
| PLL_SYS_CLK | I | 1 | 寄存器时钟，必须是 24 MHz，不能来自本 PLL 的输出 |
| PLL_DFT_RSTJ | I | 1 | TEST_MODE 下的 PLL 上电控制 |
| PLL_SYS_RSTJ | I | 1 | 异步复位，低有效 |

## 5. 寄存器映射

只有下表中的字段有效。分频相关的字段（frac、prediv、fbdiv、dacpd、dsmpd、postdiv）由 strap 决定，对应的 SCU 寄存器位不起作用，建议标为 reserved。

| SCU 地址 | 位 | CFG 位 | 字段 | 复位值 | 说明 |
|---|---|---|---|---|---|
| 0x54 | [29] | CFG_0[29] | disable_sscg | 1 | 1 = 关闭 SSC |
| 0x54 | [30] | CFG_0[30] | testen | 0 | 1 = 打开内部监测，正常工作时为 0 |
| 0x54 | [31] | CFG_0[31] | pd | **0** | 1 = PLL 断电 |
| 0x58 | [15:14] | CFG_1[15:14] | testsel | 0 | 00 = lock，01 = refclk，10 = fbclk |
| 0x58 | [31] | CFG_1[28] | sel_extwave | 0 | 0 = 内部三角波，1 = 外部波形表 |
| 0x5C | [7:0] | CFG_2[7:0] | ext_maxaddr | 0 | 外部波形表最大地址 |
| 0x5C | [15:8] | CFG_2[15:8] | extwaveval | 0 | 外部波形表数据 |
| 0x5C | [17:16] | CFG_2[17:16] | gvco_bias | 1 | 手册默认值 |
| 0x5C | [20:18] | CFG_2[20:18] | cpp_bias | 2 | 手册默认值 |
| 0x5C | [23:21] | CFG_2[23:21] | cpi_bias | 3 | 手册默认值 |
| 0x5C | [27:24] | CFG_2[27:24] | divval | 1 | SSC 分频，取值 1~15 |
| 0x5C | [30:28] | CFG_2[30:28] | spread | 0 | SSC 调制深度 |
| 0x5C | [31] | CFG_2[31] | downspread | 0 | 0 = 中心扩频，1 = 向下扩频 |

注意事项：

1. **SCU 中 pd 的复位值必须为 0。** 每次 CFG_EN 上升沿会装载全部字段。如果 pd 的复位值是 1，软件只改其他字段并触发 CFG_EN，PLL 就会断电。
2. SCU 寄存器文档里 0x58 中 postdiv0_1、postdiv1_0、postdiv1_1、sel_extwave 的位号，和 CFG_1 中的位置不同。需要确认 SCU 的寄存器译码和文档一致，重点核对 sel_extwave（0x58[31]，对应 CFG_1[28]）。
3. SSC 只在小数模式下有效，也就是 CPU_SPEED_SEL = 2'b00 或 2'b01。

## 6. 配置更新流程

1. 软件写 PLL_SYS_CFG_0/1/2 和 PLL_SYS_CLK_DIV1/2。
2. 软件把 PLL_SYS_CFG_EN 由 0 拉到 1。
3. 模块内部两级同步后检测上升沿，产生一个周期的 CFG_PULSE，所有字段同时装载。
4. 下次更新前，先把 PLL_SYS_CFG_EN 拉回 0。

修改 cpi_bias、cpp_bias、gvco_bias 等环路参数时，建议先写 pd=1，至少 1 µs 后再写 pd=0。

## 7. 上电与断电

| 条件 | PLL pd 行为 |
|---|---|
| 复位释放后 | 寄存器默认上电，PLL_PD_GEN 计满 100 个 PLL_SYS_CLK 周期（24 MHz 时约 4.2 µs）后释放 pd |
| 软件写 pd = 1 | pd 立即拉高，PLL 断电 |
| 软件写 pd = 0 | 计 100 个周期后释放 pd |
| TEST_MODE | 由 PLL_DFT_RSTJ 控制：1 = 上电（同样延时 100 个周期） |
| MBIST_ES_MODE | 固定上电 |

pd 释放后，等 PLL_SYS_LOCK = 1（手册规定不超过 500 个参考周期，约 21 µs），再把 CPU 和 BUS 时钟从 24 MHz 切到 PLL 输出。

## 8. DFT 处理

| 信号 | TEST_MODE | MBIST_ES_MODE |
|---|---|---|
| NI / frac / M / postdiv / dacpd / dsmpd | 由 CPU_SPEED_SEL 决定（同功能模式） | 由 CPU_SPEED_SEL 决定（同功能模式） |
| disable_sscg / testen / testsel | 1 / 0 / 0 | 1 / 0 / 0 |
| gvco / cpp / cpi_bias | 1 / 2 / 3 | 1 / 2 / 3 |
| divval / spread / downspread | 1 / 0 / 0 | 1 / 0 / 0 |
| CLK_DIV1 / CLK_DIV2 | 8'h3b / 8'h27 | 8'h3b / 8'h27 |
| PLL_SYS_CFG_EN | 屏蔽 | 屏蔽 |
| 输出时钟门控 | SE = 1，强制打开 | SE = 1，强制打开 |
| SCAN_DIV2_CLK | 由 F600_CLK 二分频产生 | 不翻转 |

寄存器字段的测试值都在寄存器之后、紧挨 PLL 输入的地方选择，扫描移位期间寄存器值会变化，但 PLL 的配置引脚保持不变。分频配置直接来自 strap，不经过寄存器，也不受扫描影响。

## 9. 设计约束和待确认事项

1. **CPU_SPEED_SEL** 需要在模块外锁存。strap pad 要有板级上拉或下拉电阻，保证默认档位确定。
2. **PLL_SYS_CLK** 必须是 24 MHz 时钟，保证 pd 延时不少于 1 µs，并且不能来自本 PLL 的输出。
3. **PLL_PD_GEN** 沿用现有模块，没有改动。如果综合时其他文件也定义了它，删掉本文件末尾的定义即可。
4. **fbdiv / prediv 的编码**：手册没有写明，这里按直接二进制理解，建议和 IP 厂商确认。
5. **中档频率**：客户需求里同时出现了 560 MHz 和 550 MHz，目前按 560 MHz 实现。如果改为 550 MHz，BUS 就无法保持精确的 400 MHz。
6. **低频档编码**：目前放在 2'b11，需要和客户的 strap 定义确认。
