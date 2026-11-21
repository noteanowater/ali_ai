# GPIO chip-level pattern

| 文件 | 说明 |
|---|---|
| `gpio_chip_top_task.v` | pattern 主体（`chip_top_task`），在 tb 里 `include |
| `gpio_pad_map.vh` | 由 PinPad 表自动生成：GPIO_n ↔ PINPAD 映射、force/release、pad 名查表 |
| `gen_gpio_pad_map.py` | 生成脚本，PinPad 表更新后重新跑 |

## 使用前要改的 3 处

1. **pad 层次名**：默认 `test_chip_top.EXT_XGPIO_<GPIO号>`（tb 中 `tranif1(EXT_XGPIO_n, <Pin>, ... & <Pin>_SEL_000)`）。
   如果 EXT_XGPIO 的编号跳过了不存在的 GPIO_39（即 EXT_XGPIO_39 = GPIO_40 … EXT_XGPIO_109 = GPIO_110），加 `--ext-shift` 重新生成：
   ```bash
   python3 gen_gpio_pad_map.py HS100_PinPad.xlsx --ext-shift -o gpio_pad_map.vh
   ```
2. **`GPIO_PCLK`**：gpio_top 的 pclk 层次路径（所有等待都按 pclk 拍数）。
3. **`GPIO_INTR_SIG`**（可选）：定义后会同时检查 gpio_top 的 `gpio_intr` 输出线。

```
+define+GPIO_PCLK=test_chip_top.u_chip.u_gpio_top.pclk
+define+GPIO_INTR_SIG=test_chip_top.u_chip.u_gpio_top.gpio_intr
```

## 测试内容

| Step | 内容 |
|---|---|
| 1 | ID / Config 寄存器 |
| 2 | PINMUX 选 GPIO（沿用原写法，表中 GPIO = `*_SEL_000`） |
| 3 | 寄存器读写 / 默认值 |
| 4 | **输出映射**：逐通道 walking-1 / walking-0，检查全部 110 个 pad；Set/Clear 寄存器 |
| 5 | **输入映射**：逐 pad walking-1 / walking-0，读 4 组 DataIn |
| 6 | **中断映射**：逐 pad 上升沿，只允许对应 bit 置位；W1C；下降沿不触发；`gpio_intr` 线 |
| 7 | 高/低电平、上/下沿、双沿；电平模式清除后会重新置位、边沿不会；反向边沿不触发 |
| 8 | 中断使能屏蔽（全关 / 只开偶数通道） |
| 9 | Debounce：用 pclk 作采样时钟，短毛刺被滤、稳定电平通过、关闭后毛刺透传；可选 extclk |
| 10 | 0x00~0xFC 所有空洞地址读写，并确认不影响真实寄存器 |

出错打印示例：`Error : OUT walking-1 : GPIO_5 pad XPSYNC2 = 0, expect 1`

## 特殊 pad

* **GPIO_39**：没有 pad，所有检查都屏蔽。
* **GPIO_31 = XGPIO_5**：pad IO 类型是 **I（只能输入）**，同时是 **TEST_MODE strap（L）**。输出检查跳过；输入检查默认一直驱动 0，避免进 DFT 模式。确认 TEST_MODE 只在复位时锁存之后，可以加 `+define+GPIO_TEST_STRAP_TESTMODE` 把它纳入输入测试。
* **strap pad**（GPIO 24/28/29/30/48/49/50/52~55/60/61）：输出测试时 pad 由芯片驱动。如果 tb 用强驱动给 strap 赋值，这些 pad 会出现 X，要改成 pullup/pulldown。
* **GPIO 32~36 = JTAG pad**：测试中会被 force，tb 里的 JTAG 模型不要同时驱动。
