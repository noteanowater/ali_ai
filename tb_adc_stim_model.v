//==============================================================================
// tb_adc_stim_model : self-check testbench for adc_stim_model
//
//   iverilog -o tb.vvp tb_adc_stim_model.v adc_stim_model.v && vvp tb.vvp
//
// Checks:
//   - sine min/max vs 0.009*VDDA ~ 0.891*VDDA
//   - sine frequency error (zero-crossing) < 100ppm
//   - THD < -62dB (coherent DFT: 625 points sampled by ADC_SOC = 7 cycles)
//   - ADC_CLK 11MHz / ADC_SOC 1MHz frequency and 50% duty
//==============================================================================
`timescale 1ns/1fs

module tb_adc_stim_model;

parameter real VDDA   = 1.8;
parameter real PI     = 3.14159265358979323846;
parameter integer NPT = 625;     // samples @1MHz
parameter integer NCY = 7;       // 625 * 11.2k / 1M = 7 cycles (coherent)
parameter integer NH  = 9;       // harmonics counted in THD

wire [63:0] XADC_CH0;
wire [11:0] XADC_CH0_CODE;
wire        XTR0;
wire        XTR1;

adc_stim_model #(.VDDA(VDDA)) u_model (
    .XADC_CH0      (XADC_CH0),
    .XADC_CH0_CODE (XADC_CH0_CODE),
    .XTR0          (XTR0),
    .XTR1          (XTR1)
);

real v;
always @(XADC_CH0) v = $bitstoreal(XADC_CH0);

integer err_cnt;
initial err_cnt = 0;

//------------------------------------------------------------------------------
// min / max
//------------------------------------------------------------------------------
real vmin, vmax;
initial begin vmin = 1.0e9; vmax = -1.0e9; end
always @(XADC_CH0) if ($realtime > 0) begin
    if ($bitstoreal(XADC_CH0) < vmin) vmin = $bitstoreal(XADC_CH0);
    if ($bitstoreal(XADC_CH0) > vmax) vmax = $bitstoreal(XADC_CH0);
end

//------------------------------------------------------------------------------
// sine frequency: rising crossings of mid level, linear interpolation
//------------------------------------------------------------------------------
real    vmid, v_prev, t_prev, t_x, t_x0, t_x1;
integer nx;
initial begin
    vmid = VDDA * 0.45; v_prev = 0.0; t_prev = 0.0; nx = 0;
end
always @(XADC_CH0) begin
    if (v_prev < vmid && $bitstoreal(XADC_CH0) >= vmid && $realtime > 0) begin
        t_x = t_prev + ($realtime - t_prev) * (vmid - v_prev)
                       / ($bitstoreal(XADC_CH0) - v_prev);
        if (nx == 0) t_x0 = t_x;
        t_x1 = t_x;
        nx   = nx + 1;
    end
    v_prev = $bitstoreal(XADC_CH0);
    t_prev = $realtime;
end

//------------------------------------------------------------------------------
// clock measurement
//------------------------------------------------------------------------------
real    clk_r0, clk_r1, clk_hi, clk_lr;
integer clk_nr;
initial begin clk_nr = 0; clk_hi = 0.0; end
always @(posedge XTR0) begin
    if (clk_nr == 0) clk_r0 = $realtime;
    clk_r1 = $realtime; clk_lr = $realtime; clk_nr = clk_nr + 1;
end
always @(negedge XTR0) if (clk_nr > 0) clk_hi = clk_hi + ($realtime - clk_lr);

real    soc_r0, soc_r1, soc_hi, soc_lr;
integer soc_nr;
initial begin soc_nr = 0; soc_hi = 0.0; end
always @(posedge XTR1) begin
    if (soc_nr == 0) soc_r0 = $realtime;
    soc_r1 = $realtime; soc_lr = $realtime; soc_nr = soc_nr + 1;
end
always @(negedge XTR1) if (soc_nr > 0) soc_hi = soc_hi + ($realtime - soc_lr);

//------------------------------------------------------------------------------
// sample by ADC_SOC rising edge (value just before the edge)
//------------------------------------------------------------------------------
real    smp [0:NPT-1];
integer ns;
initial ns = 0;
always @(posedge XTR1) begin
    if (ns < NPT) begin
        smp[ns] = v;
        ns      = ns + 1;
    end
end

//------------------------------------------------------------------------------
// analysis
//------------------------------------------------------------------------------
integer i, h;
real    re, im, p1, ph_sum, pwr, thd, a1;
real    f_meas, ppm, f_clk, d_clk, f_soc, d_soc;

task check;
    input        ok;
    input [8*40-1:0] name;
    begin
        if (ok) $display("  PASS  %0s", name);
        else begin
            $display("  FAIL  %0s", name);
            err_cnt = err_cnt + 1;
        end
    end
endtask

initial begin
    // 625 SOC samples + margin for crossings
    #(NPT * 1000.0 + 100000.0);

    // DFT at harmonic bins
    ph_sum = 0.0;
    for (h = 1; h <= NH; h = h + 1) begin
        re = 0.0; im = 0.0;
        for (i = 0; i < NPT; i = i + 1) begin
            re = re + smp[i] * $cos(2.0 * PI * h * NCY * i / NPT);
            im = im + smp[i] * $sin(2.0 * PI * h * NCY * i / NPT);
        end
        pwr = re * re + im * im;
        if (h == 1) p1 = pwr; else ph_sum = ph_sum + pwr;
    end
    a1  = 2.0 * $sqrt(p1) / NPT;
    thd = 10.0 * $log10(ph_sum / p1);

    f_meas = 1.0e9 * (nx - 1) / (t_x1 - t_x0);
    ppm    = (f_meas - 11.2e3) / 11.2e3 * 1.0e6;

    f_clk  = 1.0e3 * (clk_nr - 1) / (clk_r1 - clk_r0);
    d_clk  = 100.0 * clk_hi / (clk_nr * 1.0e3 / f_clk);
    f_soc  = 1.0e3 * (soc_nr - 1) / (soc_r1 - soc_r0);
    d_soc  = 100.0 * soc_hi / (soc_nr * 1.0e3 / f_soc);

    $display("");
    $display("==================== result ====================");
    $display("XADC_CH0 min      : %0.6f V (%0.5f*VDDA)", vmin, vmin / VDDA);
    $display("XADC_CH0 max      : %0.6f V (%0.5f*VDDA)", vmax, vmax / VDDA);
    $display("XADC_CH0 freq     : %0.4f Hz (%0.3f ppm, %0d cycles)", f_meas, ppm, nx - 1);
    $display("XADC_CH0 amp      : %0.6f V", a1);
    $display("XADC_CH0 THD      : %0.2f dB (H2..H%0d)", thd, NH);
    $display("XTR0 ADC_CLK      : %0.6f MHz, duty %0.3f%%", f_clk, d_clk);
    $display("XTR1 ADC_SOC      : %0.6f MHz, duty %0.3f%%", f_soc, d_soc);
    $display("------------------------------------------------");

    check((vmin / VDDA > 0.0089) && (vmin / VDDA < 0.0091), "sine min 0.009*VDDA");
    check((vmax / VDDA > 0.8909) && (vmax / VDDA < 0.8911), "sine max 0.891*VDDA");
    check((ppm < 100.0) && (ppm > -100.0),                  "sine freq 11.2KHz +/-100ppm");
    check(thd < -62.0,                                      "sine THD < -62dB");
    check((f_clk > 10.999) && (f_clk < 11.001),             "ADC_CLK 11MHz");
    check((d_clk > 49.9) && (d_clk < 50.1),                 "ADC_CLK duty 50%");
    check((f_soc > 0.9999) && (f_soc < 1.0001),             "ADC_SOC 1MHz");
    check((d_soc > 49.9) && (d_soc < 50.1),                 "ADC_SOC duty 50%");

    if (err_cnt == 0) $display("TEST PASSED");
    else              $display("TEST FAILED (%0d errors)", err_cnt);
    $finish;
end

endmodule
