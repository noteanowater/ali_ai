# GPIO chip-level pattern

| 文件 | 说明 |
|---|---|
| `chip_top_task.v` | 单文件 pattern：`chip_top_task` + GPIO↔PINPAD 映射（BEGIN/END GPIO PAD MAP 区段由脚本生成） |
| `gen_gpio_pad_map.py` | 生成脚本，PinPad 表更新后重新跑 |

## 怎么用

1. **替换文件**：用 `chip_top_task.v` 覆盖原来的 pattern 文件。task 名还是 `chip_top_task`，tb 里调用它的地方不用改。原 pattern 里的 `GPIO_FORCE_VALUE`、`gpio_pad_value`、`EXT_GPIO_GROUP0~3` 都不再需要，删掉。
2. **放的位置**：和原来一样，在 `test_chip_top` 模块这一层 `include`，不能放进 `initial` 或 task 里面。文件里会直接用到 tb 里已有的 `a45_io_write32b`、`a45_io_read32b`、`IOBASE_GPIO0~3`、`IOBASE_PINMUX`。
3. **调用时机**：在复位释放之后、其他代码还没动过 GPIO 之前调用 `chip_top_task`。如果之前已经有代码写过 GPIO 寄存器，加 `+define+GPIO_NO_RESET_CHK`。
4. **看结果**：
   ```
   GPIO TEST Summary : pad errors 0, gpio_intr errors 0 (register read errors are reported by a45_io_read32b)
   GPIO TEST End : pad / gpio_intr checks PASS        （或 FAIL, N pad / gpio_intr errors）
   ```
   寄存器读比对的错误由 `a45_io_read32b` 自己打印，不计入上面的汇总。判定时要同时看汇总行和 log 里的寄存器 Error，`grep -i error` 仿真 log 即可。

## 代码结构

* 寄存器读写全部直接调用 `a45_io_write32b` / `a45_io_read32b`，写在 `chip_top_task` 里，没有再包一层 task。基地址用 `gpio_base[0..3]`（= `IOBASE_GPIO0~3`）按组号选择。
* 逐通道测试时只写当前通道所在的那一组；换到下一组时把上一组恢复一次，其他组只在开头配置一次。
* 保留的辅助 task 只做等待和 pad / 中断线检查，不访问寄存器：`gpio_wait_clk`、`gpio_chk_pad`、`gpio_chk_pad_mask`、`gpio_chk_intr_line`，以及映射区段里的 `gpio_pad_force_all` / `gpio_pad_release_all`。

## 路径设置

1. **pad 层次名**：默认 `test_chip_top.EXT_XGPIO_<GPIO号>`（tb 中 `tranif1(EXT_XGPIO_n, <Pin>, ... & <Pin>_SEL_000)`）。
   如果 EXT_XGPIO 的编号跳过了不存在的 GPIO_39（即 EXT_XGPIO_39 = GPIO_40 … EXT_XGPIO_109 = GPIO_110），也就是编译时报 `EXT_XGPIO_110` 找不到，就加 `--ext-shift` 重新生成：
   ```bash
   python3 gen_gpio_pad_map.py HS100_PinPad.xlsx --ext-shift -o chip_top_task.v
   ```
2. **`GPIO_TOP_PATH`**：gpio_top 实例路径，默认 `test_chip_top.chip_top.core_aon.apb_subsystem_aon.u03_gpio_top`。
   `GPIO_PCLK`（等待用的 pclk）和 `GPIO_INTR_SIG`（检查中断输出线用）都由它派生。

## 开关（`+define+` 或在文件开头打开）

| define | 作用 |
|---|---|
| `GPIO_NO_DB_PER_CH` | 跳过 Step 9-5 逐通道 debounce |
| `GPIO_DB_EXTCLK_TEST` | 加跑 Step 9-6：extclk 作 debounce 采样时钟（配合 `GPIO_EXTCLK_WAIT`） |
| `GPIO_NO_INTR_SIG` | 不检查 gpio_intr 输出线 |
| `GPIO_NO_RESET_CHK` | 跳过复位值检查（调用 task 之前已经动过 GPIO 时用） |

## 测试内容

**约定**

* **寄存器偏移**：`0x20` DataIn、`0x24` DataOut、`0x28` 方向寄存器（1 = 输出）、`0x2C` 清零 DataOut、`0x30` 置位 DataOut、`0x50` 中断使能、`0x54~0x60` 中断模式、`0x64` 中断状态（写 1 清除）、`0x70` debounce 使能、`0x74` debounce 控制。
* **"全部通道"**：指 110 个有 pad 的 GPIO，即 GPIO_0~110 去掉 GPIO_39。
* **三类检查**：
  * 寄存器检查：直接调用 `a45_io_read32b` 比对，错误由它自己打印（不计入汇总）。
  * pad 检查：直接看 `EXT_XGPIO_n` 的电平（x/z 也算错），计入汇总。
  * 中断线检查：看 gpio_top 的 `gpio_intr`，计入汇总。

### Step 1：ID / 配置寄存器 / 复位值
**目的**：确认 4 组 GPIO 都在、配置正确、复位后是干净状态。

| 子步骤 | 操作 | 期望 | 能发现的问题 |
|---|---|---|---|
| 1 | 读 4 组的 0x00、0x10 | ID = `0x02031002`，配置 = `0x60000020`（有中断、有 debounce、无 pull、32 通道） | IP 版本或配置宏不对，地址映射错 |
| 1-1 | 读 4 组所有可读写寄存器（0x24、0x28、0x2C、0x30、0x50、0x54~0x60、0x64、0x70、0x74） | 全部为 0 | 复位值错、复位没连好；上电时某些 pad 默认是输出 |

### Step 2：PINMUX 选择 GPIO 功能
**目的**：让 110 个 pad 都切到 GPIO 功能，表格里对应的是 `*_SEL_000`。

* **操作**：对 PINMUX 的 0x00~0x50、0x5C 写 `0x90909090`，对 0x80~0xB0 写 `0x01900190`（沿用原来的配置）。
* **怎么验证**：这一步本身不检查。如果没配对，tb 里 tranif1 的使能（`..._SEL_000`）为 0，后面 Step 4 会在 pad 上看到 `z`，从而暴露问题。

### Step 3：寄存器读写 / 4 组实例隔离
**目的**：确认 APB 读写通路，以及 4 组 GPIO 之间没有串写。

| 子步骤 | 操作 | 期望 | 能发现的问题 |
|---|---|---|---|
| 3 | 每组的 0x28、0x50、0x70 写 `A5A55A5A`、`5A5AA5A5`、0 并读回；0x54~0x60 写全 1；0x74 写全 1 | 写什么读回什么；中断模式寄存器读回 `0x77777777`（每个 nibble 的 bit3 不存在）；0x74 读回 `0x800000FF`（只有 bit31 和 [7:0]）；0x2C、0x30 读回 0 | 寄存器位宽或可写位不对，数据线粘连 |
| 3-1 | 4 组写入互不相同的值，先按 0→3 的顺序写、全部读回，再按 3→0 的顺序写另一组值、全部读回 | 每组读回的都是自己的值 | 片选译码错，写一组时连带写到了另一组。两个顺序都要做：只按 0→3 写的话，被误写的那组随后又被自己的写入覆盖，问题会被掩盖 |

### Step 4：输出方向，GPIO → PINPAD
**目的**：寄存器写出去的值，要出现在**正确的那个 pad** 上。

| 子步骤 | 操作 | 期望 | 能发现的问题 |
|---|---|---|---|
| 4 | 放开 pad（芯片驱动），全部设成输出，DataOut = 0 | 110 个 pad 全为 0 | pad 不受 GPIO 控制，或者是 z/x |
| 4-1 walking-1 | 每次只让一个通道输出 1，逐个走完 110 个通道，每一步检查**全部 110 个 pad** | 只有对应的那个 pad 为 1 | **pad 和 GPIO 对应关系错**（两路接反、接到别的 pad），短路，输出恒为 0 |
| 4-2 walking-0 | 每次只让一个通道输出 0，其余为 1 | 只有对应的那个 pad 为 0 | 输出恒为 1、两路相互粘连 |
| 4-3 置位/清零 | 先清 0；写 0x30 = `A5A5A5A5`；再写 0x30 = `5A5A0000`（与原值相或）；写 0x2C = `0F0F00FF`；最后写 0x2C 全 1 | pad 和 DataOut 依次为 `A5A5A5A5` → `FFFFA5A5` → `F0F0A500` → 0 | 置位、清零寄存器的逻辑错（比如变成直接覆盖） |
| 4-4 方向位逐通道 | DataOut 全为 1，方向寄存器每次只把一个通道设成输出 | 被设成输出的那个 pad 为 1 | **方向寄存器 bit n 没对应到通道 n**（例如 bit3、bit4 接反） |

出错时打印 GPIO 号和 pad 名，例如 `GPIO_5 pad EXT_XGPIO_5/XPSYNC2 = 0, expect 1`。

### Step 5：输入方向，PINPAD → GPIO
**目的**：pad 上的电平，要读到**正确的那个 DataIn 位**。

| 子步骤 | 操作 | 期望 | 能发现的问题 |
|---|---|---|---|
| 5 | 全部设成输入，tb 把所有 pad force 为 0 | 4 组 DataIn 全为 0 | 输入恒为 1 |
| 5-1 walking-1 | 每次只把一个 pad force 为 1，逐个走完 | 4 组 DataIn 里只有对应的那一位为 1 | **输入方向的对应关系错**，输入恒为 0 |
| 5-2 walking-0 | 每次只把一个 pad force 为 0，其余为 1 | 只有对应的那一位为 0 | 输入粘连，输入恒为 1 |

### Step 6：中断，逐通道对应关系
**目的**：一个 pad 的事件只触发自己那一位中断，各控制位只管自己的通道。全部使用**上升沿**模式。

| 子步骤 | 操作 | 期望 | 能发现的问题 |
|---|---|---|---|
| 6 | 打开全部通道中断；每次只给一个 pad 上升沿，然后写 1 清除这一位，再给下降沿 | 中断状态只有对应的那一位为 1，`gpio_intr` 为 1；清除后全为 0，下降沿不触发，`gpio_intr` 回到 0 | 中断状态位对应错，顶层中断线没连，清除不生效 |
| 6-1 中断使能逐通道 | 每次只使能一个通道，**所有 pad 同时**给上升沿 | 只有被使能的那一位置 1 | **中断使能 bit n 没对应到通道 n** |
| 6-2 写 1 清除逐 bit | 全部使能，所有 pad 给上升沿让全部状态位置 1，然后只清 bit n | 只有 bit n 被清掉，其他位保持 1 | 写 1 清除时清错了位，或者清掉了整个寄存器 |

### Step 7：中断触发模式
**目的**：5 种触发模式在全部通道上行为都正确，包括"不应该触发"的情况。

每种模式的流程：先关中断 → 设好空闲电平 → 设模式 → 清除状态 → 打开中断 →
1. **读回模式寄存器**：期望每个 nibble 等于设置值，bit3 读回 0。
2. **空闲电平保持**：期望不触发。
3. **给有效事件**：期望全部通道置 1，`gpio_intr` 为 1。
4. **保持有效电平，写 1 清除**：电平模式下会重新置 1，边沿模式下保持 0。
5. **回到空闲电平**：双沿模式会再次触发；单沿模式的反向边沿不能触发。
6. **清除后**：期望全为 0，`gpio_intr` 为 0。

| 模式 | 值 | 空闲电平 → 有效事件 |
|---|---|---|
| 高电平 | 2 | 0 → 1 |
| 低电平 | 3 | 1 → 0 |
| 上升沿 | 6 | 0 → 1 |
| 下降沿 | 5 | 1 → 0 |
| 双沿（先上升） | 7 | 0 → 1 → 0，两次都触发 |
| 双沿（先下降） | 7 | 1 → 0 → 1，两次都触发 |

| 子步骤 | 操作 | 期望 | 能发现的问题 |
|---|---|---|---|
| 7-1 模式 nibble 逐通道 | 通道 n 设为上升沿，其余设为下降沿；所有 pad 先给上升沿、再给下降沿 | 上升沿时只有 bit n 置 1；下降沿时除 bit n 外全部置 1 | **中断模式寄存器的第 n 个 nibble 没对应到通道 n** |

能发现的问题：模式编码错、电平和边沿搞反、电平中断清除后不重新置位、边沿检测漏触发或多触发。

### Step 8：中断屏蔽 / 输出方向

| 子步骤 | 操作 | 期望 | 能发现的问题 |
|---|---|---|---|
| 8 | 高电平模式，中断使能全关，所有 pad 拉高 | 状态全为 0，`gpio_intr` 为 0 | 关掉使能后仍然产生中断 |
| | 中断使能 = `0x55555555`（只开偶数通道） | 只有偶数位置 1 | 使能屏蔽错位 |
| 8-1 | 全部设成输出、输出 1、打开高电平中断 | pad 为 1，但 DataIn 保持之前的 0，不产生中断 | **输出方向下仍在采样输入或产生中断**（自己的输出触发自己的中断） |
| | 切回输入，pad 保持 1 | DataIn 变成 1，高电平中断置位 | 切回输入后不恢复采样 |

### Step 9：Debounce（去抖）
**目的**：短毛刺被滤掉、稳定电平能通过；关掉 debounce 后毛刺直接透过去；每个通道的 debounce 使能只管自己。

全部采用**上升沿中断**，用来判断"有没有边沿通过 debounce"。采样时钟用 pclk（0x74 的 bit31 = 1）。

| 子步骤 | 操作 | 期望 | 能发现的问题 |
|---|---|---|---|
| 准备 | 采样周期 256 拍 pclk，全部通道打开 debounce，所有 pad 为 0 | DataIn 全为 0 | |
| 9-1 | 所有 pad 给一个 128 拍的高脉冲（不到一个采样周期） | DataIn 保持 0，**没有**中断 | 毛刺没有被滤掉 |
| 9-2 | 所有 pad 拉高并保持；131 拍时读一次，再等约 770 拍读一次 | 131 拍时还是 0（仍在滤波窗口里）；之后变成 1，中断置位 | 没有起到去抖作用（变化太快），或者一直不通过（卡死） |
| 9-3 | 在高电平上给一个 128 拍的低毛刺 | DataIn 保持 1，没有新的上升沿中断 | 下降方向的毛刺没有被滤掉 |
| 9-4 | 关掉 debounce，给一个 2 拍的脉冲 | 中断置位，说明脉冲直接通过了 | debounce 关不掉 |
| 9-5 逐通道 | 采样周期 64 拍。每次**只打开一个通道** n 的 debounce，所有 pad 同时给一个 32 拍的毛刺；然后再给一个长脉冲 | 毛刺：除通道 n 以外都产生中断，通道 n 被滤掉；长脉冲：全部通过 | **debounce 使能 bit n 没对应到通道 n**，单个通道的滤波失效。可以用 `GPIO_NO_DB_PER_CH` 关掉这一项 |
| 9-6（可选） | 用 extclk 作采样时钟（scale = 1），给长脉冲 | 能通过 | extclk 没接或者不翻转。只有加了 `GPIO_DB_EXTCLK_TEST` 才会跑 |

### Step 10：空洞地址
**目的**：没有定义寄存器的地址不能读写到东西，也不能影响真实寄存器。

| 操作 | 期望 | 能发现的问题 |
|---|---|---|
| 先往 0x28、0x50、0x70 写入特定值作为"哨兵" | | |
| 4 组的 0x00~0xFC 中所有未定义地址（0x04~0x0C、0x14~0x1C、0x34~0x4C、0x68、0x6C、0x78~0xFC）写全 1 后读回 | 读回 0 | 地址译码不完整，空洞地址上有不该有的寄存器 |
| 再读哨兵和 0x24、0x74 | 哨兵值不变，0x24、0x74 为 0 | 写空洞地址时别名到了真实寄存器 |

### 结束
* 放开所有 pad，打印汇总：pad / gpio_intr 各错多少，最后 `PASS` 或 `FAIL`。寄存器读错误看 `a45_io_read32b` 的打印。

### 报错格式
| 类型 | 示例 |
|---|---|
| 寄存器值不对 | 由 `a45_io_read32b` 打印，格式按 BFM |
| pad 电平不对 | `Error : OUT walking-1 : GPIO_5 pad EXT_XGPIO_5/XPSYNC2 = 0, expect 1` |
| 中断线不对 | `Error : map set : gpio_intr = 0, expect 1` |

## 特殊 pad

* **GPIO_39**：没有 pad，所有检查都屏蔽。
* **GPIO_31 = XGPIO_5**：双向 pad，参与全部测试（PinPad 表 IO 列写的是 I，建议改成 B）。
* **strap pad**（GPIO 24/28~31/48~50/52~55/60/61）：只在复位释放时采样，正常参与全部测试。如果 tb 用强驱动给 strap 赋值，输出测试时这些 pad 会出现 X，要改成 pullup/pulldown。
* **GPIO 32~36 = JTAG pad**：测试中会被 force，tb 里的 JTAG 模型不要同时驱动。

## 第一次跑可能遇到的问题

| 现象 | 原因 / 处理 |
|---|---|
| 编译报 `EXT_XGPIO_110` 找不到 | tb 的 EXT_XGPIO 编号跳过了 39，用 `--ext-shift` 重新生成映射 |
| 编译报 `...u03_gpio_top.pclk` 找不到 | 路径或端口名不对，加 `+define+GPIO_TOP_PATH=实际路径` |
| Step 4 报 pad 值是 `z` | tranif1 没有导通，检查 `PAD_RSTJ`、`FUNC_MODE`、`PKG_SEL`，以及 PINMUX 是否真正选到 `*_SEL_000` |
| 只有 strap pad 报 `x` | tb 用强驱动给 strap 赋值，和芯片输出冲突，改成 pullup/pulldown |
| debounce 步骤报错，其他都通过 | 读寄存器的总线延迟太长（每次读超过约 100 个 pclk）。把 `GPIO_DB_SCALE` 和 `GPIO_DB_PERIOD` 调大，两者要满足 PERIOD = SCALE + 1 |
