//==============================================================================
// freq_checker : 信号频率检查器 (仿真用, 不可综合)
//
// 用法:
//   1. 在 testbench 中例化, 把要检查的信号接到 sig 端口:
//        freq_checker u_chk_clk_o (.sig(clk_o));
//
//   2. 调用 task 检查频率 (频率单位 MHz):
//        u_chk_clk_o.check_freq(100.0);                       // 默认容差/周期数
//        u_chk_clk_o.check_freq_ex(100.0, 0.5, 64, 10000.0, ok);  // 自定义参数
//
// 原理:
//   在 sig 的 n_cycles 个上升沿之间计时, 计算平均周期 -> 频率,
//   与期望频率比较, 误差在 tol_pct (%) 以内判定 PASS.
//   若在 timeout_ns 内没测完 (信号不翻转/频率过低), 判定 FAIL.
//==============================================================================
`timescale 1ns/1ps

module freq_checker #(
    parameter real    DEFAULT_TOL_PCT    = 1.0,      // 默认容差 (%)
    parameter integer DEFAULT_CYCLES     = 32,       // 默认测量周期数
    parameter real    DEFAULT_TIMEOUT_NS = 100000.0  // 默认超时 (ns)
)(
    input sig
);

    integer err_cnt;      // 累计失败次数, 可在 tb 结尾打印
    initial err_cnt = 0;

    //--------------------------------------------------------------------------
    // 简化版: 只需给出期望频率 (MHz)
    //--------------------------------------------------------------------------
    task check_freq;
        input real exp_freq_mhz;
        reg        ok;
        begin
            check_freq_ex(exp_freq_mhz, DEFAULT_TOL_PCT, DEFAULT_CYCLES,
                          DEFAULT_TIMEOUT_NS, ok);
        end
    endtask

    //--------------------------------------------------------------------------
    // 完整版
    //   exp_freq_mhz : 期望频率 (MHz)
    //   tol_pct      : 允许误差 (%)
    //   n_cycles     : 测量多少个周期取平均
    //   timeout_ns   : 超时时间 (ns)
    //   pass         : 输出, 1=PASS 0=FAIL
    //--------------------------------------------------------------------------
    task check_freq_ex;
        input  real    exp_freq_mhz;
        input  real    tol_pct;
        input  integer n_cycles;
        input  real    timeout_ns;
        output reg     pass;

        real    t_start, t_end;
        real    period_ns, meas_freq_mhz, err_pct;
        reg     done;
        begin
            done = 1'b0;
            pass = 1'b0;

            fork : measure_blk
                // 测量线程
                begin
                    @(posedge sig);
                    t_start = $realtime;
                    repeat (n_cycles) @(posedge sig);
                    t_end = $realtime;
                    done  = 1'b1;
                    disable measure_blk;
                end
                // 超时线程
                begin
                    #(timeout_ns);
                    disable measure_blk;
                end
            join

            if (!done) begin
                err_cnt = err_cnt + 1;
                $display("[%0t] FREQ_CHECK FAIL: %m : timeout after %0.1f ns, signal not toggling (expect %0.3f MHz)",
                         $realtime, timeout_ns, exp_freq_mhz);
            end
            else begin
                period_ns     = (t_end - t_start) / n_cycles;
                meas_freq_mhz = 1000.0 / period_ns;
                err_pct       = (meas_freq_mhz - exp_freq_mhz) / exp_freq_mhz * 100.0;
                if (err_pct < 0.0) err_pct = -err_pct;

                if (err_pct <= tol_pct) begin
                    pass = 1'b1;
                    $display("[%0t] FREQ_CHECK PASS: %m : measured %0.3f MHz (period %0.3f ns), expect %0.3f MHz, err %0.3f%% <= %0.3f%%",
                             $realtime, meas_freq_mhz, period_ns, exp_freq_mhz, err_pct, tol_pct);
                end
                else begin
                    err_cnt = err_cnt + 1;
                    $display("[%0t] FREQ_CHECK FAIL: %m : measured %0.3f MHz (period %0.3f ns), expect %0.3f MHz, err %0.3f%% > %0.3f%%",
                             $realtime, meas_freq_mhz, period_ns, exp_freq_mhz, err_pct, tol_pct);
                end
            end
        end
    endtask

endmodule
