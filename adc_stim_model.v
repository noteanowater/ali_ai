//==============================================================================
// adc_stim_model : behavioral stimulus model for ADC test (Verilog-2001 only)
//
//   XADC_CH[0] : 11.2KHz sinewave, 0.009*VDDA ~ 0.891*VDDA
//                THD < -62dB, frequency accuracy 100ppm
//   XTR0       : ADC_CLK, 11MHz, duty 50%
//   XTR1       : ADC_SOC, 1MHz,  duty 50%
//
// Analog value transport (pure Verilog has no real-type ports):
//   XADC_CH0 is a 64-bit bus carrying an IEEE-754 double (unit: Volt).
//   Receiver side:   real v;  always @(XADC_CH0) v = $bitstoreal(XADC_CH0);
//   Hierarchical access is also possible: <inst>.xadc_ch0_v
//
// XADC_CH0_CODE is the ideal N-bit quantization of the input (reference only,
// for comparing against the ADC output).
//
// All clock edges are computed from absolute time (n*T), so there is no
// accumulated rounding drift; ADC_CLK and ADC_SOC are coherent (11:1).
//==============================================================================
`timescale 1ns/1fs

module adc_stim_model (
    XADC_CH0,
    XADC_CH0_CODE,
    XTR0,
    XTR1
);

//------------------------------------------------------------------------------
// parameters
//------------------------------------------------------------------------------
// analog supply
parameter real    VDDA        = 1.8;

// sine source
parameter real    SIN_FREQ    = 11.2e3;   // Hz
parameter real    SIN_PPM     = 0.0;      // frequency error, spec |ppm| <= 100
parameter real    SIN_VMIN_R  = 0.009;    // min voltage, ratio of VDDA
parameter real    SIN_VMAX_R  = 0.891;    // max voltage, ratio of VDDA
parameter real    SIN_PHASE   = 0.0;      // initial phase, degree
parameter real    SIN_STEP    = 1.0;      // output update step, ns
parameter real    HD2_DBC     = -75.0;    // 2nd harmonic, dBc
parameter real    HD3_DBC     = -70.0;    // 3rd harmonic, dBc
                                          // THD = -68.8dB (< -62dB)

// ADC_CLK (XTR0)
parameter real    CLK_FREQ    = 11.0e6;   // Hz
parameter real    CLK_PPM     = 0.0;
parameter real    CLK_DUTY    = 50.0;     // %
parameter real    CLK_DELAY   = 0.0;      // first rising edge, ns

// ADC_SOC (XTR1)
parameter real    SOC_FREQ    = 1.0e6;    // Hz
parameter real    SOC_PPM     = 0.0;
parameter real    SOC_DUTY    = 50.0;     // %
parameter real    SOC_DELAY   = 0.0;      // first rising edge, ns

// ideal reference code width
parameter integer CODE_BITS   = 12;

localparam real   PI          = 3.14159265358979323846;

//------------------------------------------------------------------------------
// ports
//------------------------------------------------------------------------------
output [63:0]           XADC_CH0;
output [CODE_BITS-1:0]  XADC_CH0_CODE;
output                  XTR0;
output                  XTR1;

reg    [63:0]           XADC_CH0;
reg    [CODE_BITS-1:0]  XADC_CH0_CODE;
reg                     XTR0;
reg                     XTR1;

//------------------------------------------------------------------------------
// derived values
//------------------------------------------------------------------------------
real sin_f;        // actual sine frequency, Hz
real sin_off;      // DC offset, V
real sin_amp;      // fundamental amplitude, V
real hd2_a;        // harmonic amplitude ratio
real hd3_a;
real thd_db;
real wmin, wmax;   // min/max of normalized waveform (with harmonics)
real wph, wv;
integer wi;

real clk_t;        // ADC_CLK period, ns
real soc_t;        // ADC_SOC period, ns

real xadc_ch0_v;   // current analog value, V (hierarchical access)

initial begin
    sin_f   = SIN_FREQ * (1.0 + SIN_PPM * 1.0e-6);
    hd2_a   = 10.0 ** (HD2_DBC / 20.0);
    hd3_a   = 10.0 ** (HD3_DBC / 20.0);

    // harmonics shift the peaks slightly: scan one cycle and rescale so the
    // composite waveform spans exactly VMIN ~ VMAX
    wmin = 1.0e9; wmax = -1.0e9;
    for (wi = 0; wi < 100000; wi = wi + 1) begin
        wph = 2.0 * PI * wi / 100000.0;
        wv  = $sin(wph) + hd2_a * $sin(2.0 * wph) + hd3_a * $sin(3.0 * wph);
        if (wv < wmin) wmin = wv;
        if (wv > wmax) wmax = wv;
    end
    sin_amp = VDDA * (SIN_VMAX_R - SIN_VMIN_R) / (wmax - wmin);
    sin_off = VDDA * SIN_VMIN_R - sin_amp * wmin;
    thd_db  = 10.0 * $log10(hd2_a * hd2_a + hd3_a * hd3_a + 1.0e-30);

    clk_t   = 1.0e9 / (CLK_FREQ * (1.0 + CLK_PPM * 1.0e-6));
    soc_t   = 1.0e9 / (SOC_FREQ * (1.0 + SOC_PPM * 1.0e-6));

    $display("[adc_stim_model] VDDA=%0.4fV  sine %0.6fHz  %0.6fV ~ %0.6fV  THD(set)=%0.2fdB",
             VDDA, sin_f, sin_off + sin_amp * wmin, sin_off + sin_amp * wmax, thd_db);
    $display("[adc_stim_model] ADC_CLK %0.6fMHz duty %0.1f%%,  ADC_SOC %0.6fMHz duty %0.1f%%",
             1.0e3 / clk_t, CLK_DUTY, 1.0e3 / soc_t, SOC_DUTY);

    if (SIN_PPM > 100.0 || SIN_PPM < -100.0)
        $display("[adc_stim_model] WARNING: SIN_PPM=%0.2f exceeds 100ppm spec", SIN_PPM);
    if (thd_db >= -62.0)
        $display("[adc_stim_model] WARNING: THD=%0.2fdB does not meet < -62dB spec", thd_db);
    if (CLK_DUTY <= 0.0 || CLK_DUTY >= 100.0 || SOC_DUTY <= 0.0 || SOC_DUTY >= 100.0)
        $display("[adc_stim_model] ERROR: duty cycle must be within (0,100)%%");
end

//------------------------------------------------------------------------------
// XADC_CH[0] : sinewave
//   phase is computed from absolute time each step (no accumulated error)
//------------------------------------------------------------------------------
real    t_s;
real    cyc;
real    ph;
real    v;
integer code;

initial begin
    XADC_CH0      = 64'd0;
    XADC_CH0_CODE = {CODE_BITS{1'b0}};
    #0;
    forever begin
        t_s = $realtime * 1.0e-9;
        cyc = sin_f * t_s + SIN_PHASE / 360.0;
        cyc = cyc - $floor(cyc);                 // wrap to [0,1)
        ph  = 2.0 * PI * cyc;

        v   = sin_off + sin_amp * ( $sin(ph)
                                  + hd2_a * $sin(2.0 * ph)
                                  + hd3_a * $sin(3.0 * ph) );
        if (v < 0.0)  v = 0.0;
        if (v > VDDA) v = VDDA;

        xadc_ch0_v = v;
        XADC_CH0   = $realtobits(v);

        code = $rtoi($floor(v / VDDA * (2.0 ** CODE_BITS)));
        if (code > (1 << CODE_BITS) - 1) code = (1 << CODE_BITS) - 1;
        if (code < 0)                    code = 0;
        XADC_CH0_CODE = code;

        #(SIN_STEP);
    end
end

//------------------------------------------------------------------------------
// XTR0 : ADC_CLK  (rise at CLK_DELAY + n*T, fall at rise + DUTY*T)
//------------------------------------------------------------------------------
integer clk_n;
real    clk_rise;

initial begin
    XTR0  = 1'b0;
    clk_n = 0;
    #0;
    forever begin
        clk_rise = CLK_DELAY + clk_n * clk_t;
        #(clk_rise - $realtime)                          XTR0 = 1'b1;
        #(clk_rise + clk_t * CLK_DUTY / 100.0 - $realtime) XTR0 = 1'b0;
        clk_n = clk_n + 1;
    end
end

//------------------------------------------------------------------------------
// XTR1 : ADC_SOC
//------------------------------------------------------------------------------
integer soc_n;
real    soc_rise;

initial begin
    XTR1  = 1'b0;
    soc_n = 0;
    #0;
    forever begin
        soc_rise = SOC_DELAY + soc_n * soc_t;
        #(soc_rise - $realtime)                          XTR1 = 1'b1;
        #(soc_rise + soc_t * SOC_DUTY / 100.0 - $realtime) XTR1 = 1'b0;
        soc_n = soc_n + 1;
    end
end

endmodule
