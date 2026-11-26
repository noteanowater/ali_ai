//==============================================================================
// check_freq : 检查信号频率的 task (SystemVerilog, 仿真用)
//
// 用法: 在 testbench module 内部 include 本文件, 然后直接调用
//
//   module tb;
//     logic clk_o;                       // 被测信号需声明为 logic (见注意事项)
//     `include "check_freq.svh"
//     initial begin
//       check_freq(clk_o, 100.0);   // 期望 100MHz, 允许 ±1MHz, 测 3 个周期
//       if (freq_chk_err_cnt != 0) $display("TEST FAIL");
//     end
//   endmodule
//
// 参数:
//   sig          : 被测信号
//   exp_freq_mhz : 期望频率 (MHz)
//   timeout_ns   : 超时时间 (ns), 可省略, 默认 100000
//
// 判定: 测 3 个周期取平均频率, 与期望值相差 <= 1MHz 为 PASS
//
// 注意:
//   sig 以 ref 方式传入, 才能在 task 内部看到信号变化.
//   SV 规定 ref 只能绑定变量, 不能绑定 wire, 所以 tb 里被测信号请声明成
//   logic (logic 可以直接接模块输出端口), 例如:
//       logic clk_o;
//       clk_switch_2to1 u_dut (..., .clk_o(clk_o));
//   时间单位与调用方 timescale 无关 (内部用 1ns 换算).
//==============================================================================

int freq_chk_err_cnt = 0;   // 累计失败次数

localparam real FREQ_CHK_TOL_MHZ  = 1.0;  // 允许误差 ±1MHz
localparam int  FREQ_CHK_N_CYCLES = 3;    // 测量周期数

task automatic check_freq(
    ref   logic sig,
    input real  exp_freq_mhz,
    input real  timeout_ns = 100000.0
);
    realtime t_start, t_end;
    real     period_ns, meas_freq_mhz, err_mhz;
    bit      done = 0;

    fork
        begin                                   // 测量线程
            @(posedge sig);
            t_start = $realtime;
            repeat (FREQ_CHK_N_CYCLES) @(posedge sig);
            t_end = $realtime;
            done  = 1;
        end
        begin                                   // 超时线程
            #(timeout_ns * 1ns);
        end
    join_any
    disable fork;

    if (!done) begin
        freq_chk_err_cnt++;
        $error("[%0t] FREQ_CHECK FAIL: timeout after %0.1f ns, signal not toggling (expect %0.3f MHz)",
               $realtime, timeout_ns, exp_freq_mhz);
        return;
    end

    period_ns     = (t_end - t_start) / FREQ_CHK_N_CYCLES / 1ns;
    meas_freq_mhz = 1000.0 / period_ns;
    err_mhz       = meas_freq_mhz - exp_freq_mhz;
    if (err_mhz < 0) err_mhz = -err_mhz;

    if (err_mhz <= FREQ_CHK_TOL_MHZ)
        $display("[%0t] FREQ_CHECK PASS: measured %0.3f MHz (period %0.3f ns), expect %0.3f MHz, err %0.3f MHz",
                 $realtime, meas_freq_mhz, period_ns, exp_freq_mhz, err_mhz);
    else begin
        freq_chk_err_cnt++;
        $error("[%0t] FREQ_CHECK FAIL: measured %0.3f MHz (period %0.3f ns), expect %0.3f MHz, err %0.3f MHz > %0.3f MHz",
               $realtime, meas_freq_mhz, period_ns, exp_freq_mhz, err_mhz, FREQ_CHK_TOL_MHZ);
    end
endtask
