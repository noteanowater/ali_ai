//==============================================================================
// tb_adc_smic : adc_stim_model driving the (unmodified) SMIC S40NLLAD2G_8MUX
//               digital model
//
//   iverilog -g2001 -o tb_smic.vvp tb_adc_smic.v adc_stim_model.v \
//            <path>/S40NLLAD2G_8MUX.v && vvp tb_smic.vvp
//   (iverilog cannot parse the bit-select specify paths of the SMIC model,
//    so run it without -gspecify; VCS/Xcelium can use the specify block)
//
// Connection:
//   XTR0 (ADC_CLK 11MHz) -> CLK
//   XTR1 (ADC_SOC 1MHz)  -> SOC
//   XADC_CH0_DIG         -> CH[0]   (the SMIC model's CH pin is a 1-bit wire,
//                                    it cannot carry a real voltage)
//   S = 0, PD = 0 after reset
//
// Checks:
//   - SOC rise/fall vs CLK rise meets Ts=0 / Th=10ns of the SMIC model
//   - one EOC per SOC period (1us)
//   - every conversion result B == {10{CH[0] at the sampling edge}}
//   - B follows the 11.2KHz input: frequency and 50% duty
//==============================================================================
`timescale 1ns/1fs

module tb_adc_smic;

parameter real VDDA_V = 1.8;
parameter real TS     = 0.0;     // SMIC $setup(posedge SOC, posedge CLK)
parameter real TH     = 10.0;    // SMIC $hold (posedge CLK, negedge SOC)

wire [63:0] XADC_CH0;
wire        XADC_CH0_DIG;
wire        XTR0;
wire        XTR1;

reg         PD;
wire [9:0]  B;
wire        EOC;

supply1 vdd;
supply0 vss;

adc_stim_model #(.VDDA(VDDA_V)) u_stim (
    .XADC_CH0      (XADC_CH0),
    .XADC_CH0_CODE (),
    .XADC_CH0_DIG  (XADC_CH0_DIG),
    .XTR0          (XTR0),
    .XTR1          (XTR1)
);

S40NLLAD2G_8MUX u_adc (
    .CLK  (XTR0),
    .PD   (PD),
    .SOC  (XTR1),
    .S    (3'd0),
    .CH   ({7'd0, XADC_CH0_DIG}),
    .VREF (vdd),
    .EOC  (EOC),
    .B    (B),
    .VDDD (vdd),
    .VSSD (vss),
    .VDDA (vdd),
    .VSSA (vss)
);

integer err_cnt;
initial begin
    err_cnt = 0;
    PD      = 1'b1;
    #5 PD   = 1'b0;          // release power down before the first CLK edge
end

//------------------------------------------------------------------------------
// SOC setup / hold vs CLK
//------------------------------------------------------------------------------
real    t_clk_last, t_soc_rise, min_setup, min_hold;
reg     setup_pend;
initial begin
    t_clk_last = -1.0e9; setup_pend = 1'b0;
    min_setup  = 1.0e9;  min_hold   = 1.0e9;
end
always @(posedge XTR0) begin
    if (setup_pend) begin
        if ($realtime - t_soc_rise < min_setup) min_setup = $realtime - t_soc_rise;
        setup_pend = 1'b0;
    end
    t_clk_last = $realtime;
end
always @(posedge XTR1) begin
    t_soc_rise = $realtime;
    setup_pend = 1'b1;
end
always @(negedge XTR1)
    if ($realtime - t_clk_last < min_hold) min_hold = $realtime - t_clk_last;

//------------------------------------------------------------------------------
// conversion data check
//   the SMIC model samples CH[S] on the CLK edge where counter==1 and
//   presents {10{bit}} on B together with EOC
//------------------------------------------------------------------------------
reg     exp_bit;
reg     exp_vld;
integer n_eoc, n_ok;
real    t_eoc0, t_eoc1;
initial begin exp_vld = 1'b0; n_eoc = 0; n_ok = 0; end

always @(posedge XTR0)
    if (!PD && u_adc.counter == 5'd1) begin
        exp_bit = XADC_CH0_DIG;
        exp_vld = 1'b1;
    end

always @(posedge EOC) begin
    if (n_eoc == 0) t_eoc0 = $realtime;
    t_eoc1 = $realtime;
    n_eoc  = n_eoc + 1;
    #1;
    if (exp_vld && B === {10{exp_bit}})
        n_ok = n_ok + 1;
    else if (exp_vld) begin
        if (err_cnt < 10)
            $display("  ERROR @%0t: B=%h expected %h", $realtime, B, {10{exp_bit}});
        err_cnt = err_cnt + 1;
    end
end

//------------------------------------------------------------------------------
// B waveform: frequency / duty of the 11.2KHz content
//------------------------------------------------------------------------------
//   high time is summed over complete cycles only (rise .. next rise)
real    t_br0, t_br1, t_b_lr, b_hi, b_hi_last;
integer n_br;
initial begin n_br = 0; b_hi = 0.0; b_hi_last = 0.0; end
always @(posedge B[9]) begin
    if (n_br == 0) t_br0 = $realtime;
    else           b_hi  = b_hi + b_hi_last;
    t_br1 = $realtime; t_b_lr = $realtime; n_br = n_br + 1;
end
always @(negedge B[9])
    if (n_br > 0) b_hi_last = $realtime - t_b_lr;

//------------------------------------------------------------------------------
// result
//------------------------------------------------------------------------------
real f_b, d_b, f_eoc;

task check;
    input            ok;
    input [8*48-1:0] name;
    begin
        if (ok) $display("  PASS  %0s", name);
        else begin
            $display("  FAIL  %0s", name);
            err_cnt = err_cnt + 1;
        end
    end
endtask

initial begin
    #(8.0 / 11.2e3 * 1.0e9 + 50000.0);       // > 8 sine cycles

    f_eoc = 1.0e3 * (n_eoc - 1) / (t_eoc1 - t_eoc0);
    f_b   = 1.0e9 * (n_br - 1) / (t_br1 - t_br0);
    d_b   = 100.0 * b_hi / (t_br1 - t_br0);

    $display("");
    $display("============== stim -> S40NLLAD2G_8MUX ==============");
    $display("SOC setup to CLK  : min %0.3f ns (Ts=%0.1f)", min_setup, TS);
    $display("SOC hold from CLK : min %0.3f ns (Th=%0.1f)", min_hold, TH);
    $display("EOC               : %0d, %0.6f MHz", n_eoc, f_eoc);
    $display("B data            : %0d / %0d match", n_ok, n_eoc);
    $display("B[9] waveform     : %0.2f Hz, duty %0.2f%% (%0d cycles)",
             f_b, d_b, n_br - 1);
    $display("-----------------------------------------------------");

    check(min_setup > TS,                       "SOC setup  (posedge SOC -> posedge CLK)");
    check(min_hold  >= TH,                      "SOC hold   (posedge CLK -> negedge SOC)");
    check((f_eoc > 0.9999) && (f_eoc < 1.0001), "EOC rate 1MHz");
    check(n_ok == n_eoc && n_ok > 0,        "B == {10{CH[0]}} for every EOC");
    check((f_b > 11.2e3 * 0.99) && (f_b < 11.2e3 * 1.01),
                                                "B follows 11.2KHz input");
    check((d_b > 48.0) && (d_b < 52.0),         "B duty ~50%");

    if (err_cnt == 0) $display("TEST PASSED");
    else              $display("TEST FAILED (%0d errors)", err_cnt);
    $finish;
end

endmodule
