# GPIO chip-level pattern

| 文件 | 说明 |
|---|---|
| `chip_top_task.v` | 单文件 pattern：`chip_top_task` + GPIO↔PINPAD 映射（BEGIN/END GPIO PAD MAP 区段由脚本生成） |
| `gen_gpio_pad_map.py` | 生成脚本，PinPad 表更新后重新跑 |

## 使用前

1. **pad 层次名**：默认 `test_chip_top.EXT_XGPIO_<GPIO号>`（tb 中 `tranif1(EXT_XGPIO_n, <Pin>, ... & <Pin>_SEL_000)`）。
   如果 EXT_XGPIO 的编号跳过了不存在的 GPIO_39（即 EXT_XGPIO_39 = GPIO_40 … EXT_XGPIO_109 = GPIO_110），加 `--ext-shift` 重新生成：
   ```bash
   python3 gen_gpio_pad_map.py HS100_PinPad.xlsx --ext-shift -o chip_top_task.v
   ```
2. **`GPIO_TOP_PATH`**：gpio_top 实例路径，默认 `test_chip_top.chip_top.core_aon.apb_subsystem_aon.u03_gpio_top`。
   `GPIO_PCLK`（等待用的 pclk）和 `GPIO_INTR_SIG`（中断输出线检查）都由它派生。

## 开关（`+define+` 或在文件开头打开）

| define | 作用 |
|---|---|
| `GPIO_ONLY_DB` | 只跑 PINMUX + Step 9（debounce） |
| `GPIO_NO_DB_PER_CH` | 跳过 Step 9-5 逐通道 debounce |
| `GPIO_DB_EXTCLK_TEST` | 加跑 Step 9-6：extclk 作 debounce 时钟（配合 `GPIO_EXTCLK_WAIT`） |
| `GPIO_NO_INTR_SIG` | 不检查 gpio_intr 输出线 |
| `GPIO_NO_RESET_CHK` | 跳过复位值检查（task 之前已经动过 GPIO 时用） |

## 测试内容

| Step | 内容 |
|---|---|
| 1 | ID / Config；1-1 所有寄存器复位值 |
| 2 | PINMUX 选 GPIO（表中 GPIO = `*_SEL_000`） |
| 3 | 寄存器读写；3-1 四组实例写不同值互相读回（APB 片选不串） |
| 4 | **输出映射**：逐通道 walking-1/0，检查全部 110 个 pad；4-3 Set/Clear；4-4 ChannelDir 位 n 只驱动 pad n |
| 5 | **输入映射**：逐 pad walking-1/0，读 4 组 DataIn |
| 6 | **中断映射**：逐 pad 上升沿只置对应位、`gpio_intr` 线；6-1 IntrEn 位 n 只开 GPIO_n；6-2 W1C 位 n 只清 GPIO_n |
| 7 | 高/低电平、上/下沿、双沿（含反向/清除后行为）；7-1 IntrMode nibble n 只控制 GPIO_n |
| 8 | 中断使能屏蔽；8-1 输出方向时不采样输入、不产生中断 |
| 9 | Debounce：9-1~9-4 全通道毛刺过滤/通过/关闭透传；9-5 逐通道 DebounceEn；9-6 extclk（可选） |
| 10 | 0x00~0xFC 所有空洞地址读写，并确认不影响真实寄存器 |

出错打印示例：`Error : OUT walking-1 : GPIO_5 pad EXT_XGPIO_5/XPSYNC2 = 0, expect 1`

## 特殊 pad

* **GPIO_39**：没有 pad，所有检查都屏蔽。
* **strap pad**（GPIO 24/28~31/48~50/52~55/60/61）：只在复位释放时采样，正常参与全部测试。如果 tb 用强驱动给 strap 赋值，输出测试时这些 pad 会出现 X，要改成 pullup/pulldown。
* **GPIO 32~36 = JTAG pad**：测试中会被 force，tb 里的 JTAG 模型不要同时驱动。
