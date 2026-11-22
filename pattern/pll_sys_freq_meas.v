//==========================================================================
// FILE    : pll_sys_freq_meas.v
// PURPOSE : PLL_SYS frequency measure task
//           clko0 : A45_CPU , clko1 : BUS/IP
//           (frequency is calculated assuming 1ns time unit)
//
// PLL_SYS frequency table (Fref=24MHz, from PLL_Config_Calculator)
//   SEL=2'b00 : NI=83  frac=555555 Fvco=2000 clko0 /4 = 500   clko1 /5 = 400
//   SEL=2'b01 : NI=116 frac=AAAAAB Fvco=2800 clko0 /5 = 560   clko1 /7 = 400
//   SEL=2'b10 : NI=100 frac=0      Fvco=2400 clko0 /4 = 600   clko1 /6 = 400
//   SEL=2'b11 : NI=133 frac=555555 Fvco=3200 clko0 /7 = 457.14 clko1 /8 = 400
//
// USAGE : pll_sys_freq_meas(500.0, 400.0);
//==========================================================================

// TODO : replace with the real PLL_SYS_SHELL hierarchy and output clock names
`define PLLSYS        test_chip_top.chip_top.core_main.PLL_SYS
`define PLLSYS_CLKO0  PLL_SYS_CPU_CLK      // clko0 : A45_CPU
`define PLLSYS_CLKO1  PLL_SYS_BUS_CLK      // clko1 : BUS/IP

integer pll_sys_err_cnt;
initial pll_sys_err_cnt = 0;

//------------------------------------------------------------------
// Frequency measure : measure n cycles of clko0 / clko1, compare with expected (tolerance 0.1%)
//------------------------------------------------------------------
task pll_sys_freq_meas;
    input real fcpu_exp;     // MHz , clko0
    input real fbus_exp;     // MHz , clko1
    real    t0, t1, fcpu, fbus, err;
    integer n;
    begin
        n = 1000;

        // clko0 : CPU
        repeat (8) @(posedge `PLLSYS.`PLLSYS_CLKO0);
        t0 = $realtime;
        repeat (n) @(posedge `PLLSYS.`PLLSYS_CLKO0);
        t1 = $realtime;
        fcpu = n * 1000.0 / (t1 - t0);
        err  = (fcpu - fcpu_exp) / fcpu_exp * 100.0;
        if (err < 0.0) err = -err;
        if (err > 0.1) begin
            pll_sys_err_cnt = pll_sys_err_cnt + 1;
            $display("[%0t] PLL_SYS_ERROR : CPU = %f MHz , expect %f MHz , err %f %%", $realtime, fcpu, fcpu_exp, err);
        end
        else
            $display("[%0t] PLL_SYS_PASS  : CPU = %f MHz , expect %f MHz , err %f %%", $realtime, fcpu, fcpu_exp, err);

        // clko1 : BUS
        repeat (8) @(posedge `PLLSYS.`PLLSYS_CLKO1);
        t0 = $realtime;
        repeat (n) @(posedge `PLLSYS.`PLLSYS_CLKO1);
        t1 = $realtime;
        fbus = n * 1000.0 / (t1 - t0);
        err  = (fbus - fbus_exp) / fbus_exp * 100.0;
        if (err < 0.0) err = -err;
        if (err > 0.1) begin
            pll_sys_err_cnt = pll_sys_err_cnt + 1;
            $display("[%0t] PLL_SYS_ERROR : BUS = %f MHz , expect %f MHz , err %f %%", $realtime, fbus, fbus_exp, err);
        end
        else
            $display("[%0t] PLL_SYS_PASS  : BUS = %f MHz , expect %f MHz , err %f %%", $realtime, fbus, fbus_exp, err);
    end
endtask

//------------------------------------------------------------------
// pattern : PLL_SYS is set by strap SEL (SCU 0x54/0x58 are read only),
//           so only wait lock and measure
//------------------------------------------------------------------
task chip_top_task;
begin
    $display("[%0t] ===== PLL_SYS =====", $realtime);
    a45_io_wait32b (32'ha000_c400, 32'h28 , 32'h0000_0002 , 32'h0000_0002 );   // wait SCU 0x28[1] SYS_PLL_LOCK = 1
    $display("[%0t] PLL_SYS_INFO : PLL_SYS locked", $realtime);

    // CPU frequency selected by `define CPU_SPEED_SEL0 / CPU_SPEED_SEL1
`ifdef CPU_SPEED_SEL0
  `ifdef CPU_SPEED_SEL1
    // SEL=2'b11 : NI=133 frac=555555 Fvco=3200 , /7 , /8
    $display("[%0t] PLL_SYS_INFO : CPU_SPEED_SEL1=1 CPU_SPEED_SEL0=1 , running CPU = 457.14 MHz , BUS = 400 MHz", $realtime);
    pll_sys_freq_meas(457.142857, 400.0);
  `else
    // SEL=2'b01 : NI=116 frac=AAAAAB Fvco=2800 , /5 , /7
    $display("[%0t] PLL_SYS_INFO : CPU_SPEED_SEL1=0 CPU_SPEED_SEL0=1 , running CPU = 560 MHz , BUS = 400 MHz", $realtime);
    pll_sys_freq_meas(560.0, 400.0);
  `endif
`else
  `ifdef CPU_SPEED_SEL1
    // SEL=2'b10 : NI=100 frac=0 Fvco=2400 , /4 , /6
    $display("[%0t] PLL_SYS_INFO : CPU_SPEED_SEL1=1 CPU_SPEED_SEL0=0 , running CPU = 600 MHz , BUS = 400 MHz", $realtime);
    pll_sys_freq_meas(600.0, 400.0);
  `else
    // SEL=2'b00 : NI=83 frac=555555 Fvco=2000 , /4 , /5
    $display("[%0t] PLL_SYS_INFO : CPU_SPEED_SEL1=0 CPU_SPEED_SEL0=0 , running CPU = 500 MHz , BUS = 400 MHz", $realtime);
    pll_sys_freq_meas(500.0, 400.0);
  `endif
`endif

    if (pll_sys_err_cnt == 0) $display("===== PLL_SYS TEST PASS =====");
    else                      $display("===== PLL_SYS TEST FAIL : %0d error(s) =====", pll_sys_err_cnt);
#2000;
end
endtask
