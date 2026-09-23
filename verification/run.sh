#!/bin/sh
# HS100 STRAP PIN 仿真回归
# 用法: sh verification/run.sh        (在仓库根目录执行)
#
# 注意: rtl/*.v 均未声明 `timescale, 必须把 timescale.v 放在文件列表最前面,
#       否则 RTL 中的 #udly / #UDLY 延迟会按默认时间单位解释, 全部信号变 X。

RTL="verification/timescale.v rtl/STRAP_PIN_SHELL.v rtl/STRAP_SYS_REG.v rtl/PAD_STRAP.v rtl/DFT_MODE_CTRL.v verification/lib_stub.v"

echo "===== 1. 基本功能 + PCLK/STRAP_CLK 频率比扫描 ====="
for h in 100 30 12 10 5 2.5 ; do
    iverilog -g2005 -DPCLK_HALF=$h -o /tmp/tb_basic $RTL verification/tb_strap_basic.v || exit 1
    vvp /tmp/tb_basic | grep -E '###|PASS|FAIL'
done

echo "===== 2. TRIG 位重写卡死 ====="
iverilog -g2005 -o /tmp/tb_lock $RTL verification/tb_strap_trig_lockup.v || exit 1
vvp /tmp/tb_lock | grep -E '###|卡死|PASS|FAIL'

echo "===== 3. 模式位软件改写 ====="
iverilog -g2005 -o /tmp/tb_mode $RTL verification/tb_strap_mode_override.v || exit 1
vvp /tmp/tb_mode | grep -vE '^$|^/'
