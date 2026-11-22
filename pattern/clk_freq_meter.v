//==========================================================================
// FILE    : clk_freq_meter.v
// PURPOSE : generic clock frequency meter for testbench
//           - one instance per clock, the clock is connected by port
//             (any hierarchical signal can be connected)
//           - measure() : average frequency, min / max period, duty cycle
//           - compare with expected frequency (tolerance in %), or print only
//           - timeout if clock is not toggling
//           - own `timescale 1ns/1ps, independent of the caller's timescale
//
// USAGE (inside test_chip_top) :
//   clk_freq_meter #(.NAME("PLL_DDR_F400")) u_meas_ddr_f400 (.clk(`PLLDDR.PLL_DDR_F400_CLK));
//   clk_freq_meter #(.NAME("PLL_DDR_F300")) u_meas_ddr_f300 (.clk(`PLLDDR.PLL_DDR_F300_CLK));
//   clk_freq_meter #(.NAME("PLL_MFP_F1000")) u_meas_mfp_f1000 (.clk(`PLLMFP.PLL_MFP_F1000_CLK));
//   clk_freq_meter #(.NAME("PLL_MFP_F500" )) u_meas_mfp_f500  (.clk(`PLLMFP.PLL_MFP_F500_CLK ));
//
//   real f;
//   u_meas_ddr_f400.measure(400.0, 400, 0.1, f);   // expect 400MHz, 400 cycles, +-0.1%
//   u_meas_ddr_f300.measure(300.0, 400, 0.1, f);
//   u_meas_ddr_f400.measure(  0.0, 100, 0.0, f);   // f_exp = 0 : print only, no check
//   u_meas_ddr_f400.check_stop(1000);              // clock must NOT toggle for 1000ns
//
//   error count of each instance : u_meas_ddr_f400.err_cnt
//==========================================================================
`timescale 1ns/1ps

module clk_freq_meter #(
    parameter NAME        = "CLK",
    parameter SKIP        = 8,          // edges skipped before measuring
    parameter TIMEOUT_NS  = 200000      // measure timeout
)(
    input wire clk
);

integer err_cnt;
initial err_cnt = 0;

//------------------------------------------------------------------
// measure
//   f_exp   : expected frequency in MHz (0 = print only)
//   n       : number of cycles to measure
//   tol_pct : tolerance in % (e.g. 0.1)
//   f_meas  : measured average frequency in MHz (0 if timeout)
//------------------------------------------------------------------
task measure;
    input  real    f_exp;
    input  integer n;
    input  real    tol_pct;
    output real    f_meas;
    real    t_start, t_rise, t_fall, t_prev;
    real    per, per_min, per_max, high_sum, duty, err;
    integer i;
    reg     timeout;
    begin
        timeout  = 1'b0;
        per_min  = 1.0e12;
        per_max  = 0.0;
        high_sum = 0.0;
        t_start  = 0.0;
        t_prev   = 0.0;

        fork : MEAS
            begin
                repeat (SKIP) @(posedge clk);
                t_start = $realtime;
                t_prev  = t_start;
                for (i = 0; i < n; i = i + 1) begin
                    @(negedge clk); t_fall = $realtime;
                    @(posedge clk); t_rise = $realtime;
                    per = t_rise - t_prev;
                    if (per < per_min) per_min = per;
                    if (per > per_max) per_max = per;
                    high_sum = high_sum + (t_fall - t_prev);
                    t_prev = t_rise;
                end
                disable MEAS;
            end
            begin
                #(TIMEOUT_NS);
                timeout = 1'b1;
                disable MEAS;
            end
        join

        if (timeout) begin
            f_meas  = 0.0;
            err_cnt = err_cnt + 1;
            $display("[%0t] FREQ_ERROR : %0s not toggling (timeout %0d ns)", $realtime, NAME, TIMEOUT_NS);
        end
        else begin
            f_meas = n * 1000.0 / (t_prev - t_start);
            duty   = high_sum / (t_prev - t_start) * 100.0;
            if (f_exp > 0.0) begin
                err = (f_meas - f_exp) / f_exp * 100.0;
                if (err < 0.0) err = -err;
                if (err > tol_pct) begin
                    err_cnt = err_cnt + 1;
                    $display("[%0t] FREQ_ERROR : %0s = %f MHz , expect %f MHz , err %f %% (tol %f %%)",
                             $realtime, NAME, f_meas, f_exp, err, tol_pct);
                end
                else
                    $display("[%0t] FREQ_PASS  : %0s = %f MHz , expect %f MHz , err %f %%",
                             $realtime, NAME, f_meas, f_exp, err);
            end
            else
                $display("[%0t] FREQ_INFO  : %0s = %f MHz", $realtime, NAME, f_meas);

            $display("[%0t] FREQ_INFO  : %0s period min %f ns , max %f ns , duty %f %% (%0d cycles)",
                     $realtime, NAME, per_min, per_max, duty, n);
        end
    end
endtask

//------------------------------------------------------------------
// check_stop : clock must not toggle during t_ns (e.g. while gated off)
//------------------------------------------------------------------
task check_stop;
    input integer t_ns;
    integer edges;
    begin
        edges = 0;
        fork : STOP
            begin
                forever begin
                    @(posedge clk);
                    edges = edges + 1;
                end
            end
            begin
                #(t_ns);
                disable STOP;
            end
        join
        if (edges != 0) begin
            err_cnt = err_cnt + 1;
            $display("[%0t] FREQ_ERROR : %0s toggled %0d times during %0d ns (expect stopped)",
                     $realtime, NAME, edges, t_ns);
        end
        else
            $display("[%0t] FREQ_PASS  : %0s stopped for %0d ns", $realtime, NAME, t_ns);
    end
endtask

endmodule
