//==========================================================================
// FILE    : pll_ddr_dfs_task.v
// PURPOSE : PLL_DDR 调频 (DFS) pattern
//           通过 a45_io_write32b 配置 SCU 寄存器，按 PLL_Config_Calculator 表格
//           依次切换 PLL_DDR 频点，检查：
//             1) CFG_EN 上升沿是否产生 CFG_PULSE，SHELL 寄存器是否载入正确值
//             2) pd 后 LOCK 是否拉低，重新上电后 LOCK 是否在超时内拉高（记录锁定时间）
//             3) CLK_EN=0 期间门控输出 F400/F300 无毛刺
//             4) 锁定后 clko0 (F400, DDR) / clko1 (F300, IP) 实测频率与理论值比对
//             5) TEST_DIV1/2 观测时钟实测频率（打印分频比，供 MFP 管脚测量参考）
//             6) 总线读 SCU 0x28 LOCK 状态位
//
// USAGE   : 在 test_chip_top 模块内部 `include "pll_ddr_dfs_task.v"
//           initial 里调用 chip_top_task;
//           （假定 `timescale 1ns/1ps，时间单位按 ns 计算频率）
//
// 频点表 (Fref = OSC 24MHz, 来源 PLL_Config_Calculator_10.xlsx)
// +-----+----------+-----+---+--------+-----------+-----------+--------------+--------------+
// | idx | 名称     | NI  | M | Fvco   | clko0     | clko1     | SCU 0x70     | SCU 0x6C(on) |
// +-----+----------+-----+---+--------+-----------+-----------+--------------+--------------+
// |  0  | DDR-1600 | 100 | 1 | 2400   | /6   =400 | /8   =300 | 32'h0075_3064| 32'hA100_0000|
// |  1  | DDR-1500 | 125 | 1 | 3000   | /8   =375 | /5x2 =300 | 32'h1047_307D| 32'hA100_0000|
// |  2  | DDR-1440 |  75 | 1 | 1800   | /5   =360 | /6   =300 | 32'h0054_304B| 32'hA100_0000|
// |  3  | DDR-1400 | 175 | 2 | 2100   | /6   =350 | /7   =300 | 32'h0065_30AF| 32'hA200_0000|
// |  4  | DDR-1333 | 125 | 1 | 3000   | /3x3 =333.3| /5x2=300 | 32'h1242_307D| 32'hA100_0000|
// |  5  | DDR-1050 | 175 | 2 | 2100   | /8   =262.5| /7  =300 | 32'h0067_30AF| 32'hA200_0000|
// +-----+----------+-----+---+--------+-----------+-----------+--------------+--------------+
// SCU 0x74 (CFG_2) 固定 32'h0169_0000 : divval=1 cpi=3 cpp=2 gvco=1, SSC off
// 0x6C power-down 版本 : bit31=0 -> 32'h2100_0000 (M=1) / 32'h2200_0000 (M=2)
//
// SCU (base 32'ha000_c400) 相关寄存器
//   0x10 [1]     PLL_GATE[1]  ddr_clk_on   -> SHELL PLL_DDR_CLK_EN  ([0] mfp_clk_on 保持 1)
//   0x28 [2]     DDR_PLL_LOCK (RO)
//   0x6C         PLL_DDR_CFG_0 : [31]pd(1=power on) [30]testen [29]disable_sscg [28:24]M [23:0]frac
//   0x70         PLL_DDR_CFG_1 : [31]sel_extwave [30:28]postdiv1_1 [26:24]postdiv1_0
//                                [22:20]postdiv0_1 [18:16]postdiv0_0 [15:14]testsel
//                                [13]dsmpd [12]dacpd [11:0]fbdiv
//                                (注意: SCU 内 postdiv 位置与 SHELL CFG_1 打包位置不同，按 SCU 位置写)
//   0x74         PLL_DDR_CFG_2
//   0x78 [7:0]   DIV_DDR1 -> SHELL PLL_DDR_CLK_DIV2 (TEST_DIV2, 源 F300)
//   0x7C [2]     PLL_DDR_CONFIG2_EN -> SHELL PLL_DDR_CFG_EN (上升沿载入全部字段)
//   0x84 [7:0]   DIV_DDR0 -> SHELL PLL_DDR_CLK_DIV1 (TEST_DIV1, 源 F400)
//==========================================================================

//------------------------------------------------------------------
// 可调参数
//------------------------------------------------------------------
`define PLLDDR              test_chip_top.chip_top.core_ddr_wrap.u_core_ddr.U_PLL_DDR_CLK_TOP_SHELL.U_PLL_DDR_SHELL
`define SCU_BASE            32'ha000_c400

`define SCU_PLL_GATE        32'h10
`define SCU_PLL_LOCK        32'h28
`define SCU_PLLDDR_CFG0     32'h6c
`define SCU_PLLDDR_CFG1     32'h70
`define SCU_PLLDDR_CFG2     32'h74
`define SCU_PLL_DIV_SEL     32'h78
`define SCU_PLL_CFG_EN      32'h7c
`define SCU_DIV_DDR0        32'h84

`define PLLDDR_PD_ON        1'b1          // SCU pd 位: 1 = power on (见 SHELL 复位值 / PLL_PD_GEN 注释)
`define PLLDDR_PD_OFF       1'b0
`define PLLDDR_FREF_MHZ     24.0
`define PLL_LOCK_TIMEOUT    500000        // ns, 等 LOCK 超时
`define PLL_PD_HOLD         2000          // ns, 新参数载入后保持 power down 的时间 (>=1us)
`define PLL_MEAS_TIMEOUT    200000        // ns, 测频超时 (时钟不翻转)
`define PLL_FREQ_TOL_PPM    1000.0        // 频率容差 1000ppm = 0.1%

//------------------------------------------------------------------
// 全局变量 / 监控
//------------------------------------------------------------------
integer pll_ddr_err_cnt;
integer pll_ddr_f400_edge_cnt;
integer pll_ddr_f300_edge_cnt;
reg     pll_ddr_lock_mon_en;
reg [1:0] pll_ddr_meas_sel;

initial begin
    pll_ddr_err_cnt       = 0;
    pll_ddr_f400_edge_cnt = 0;
    pll_ddr_f300_edge_cnt = 0;
    pll_ddr_lock_mon_en   = 1'b0;
    pll_ddr_meas_sel      = 2'd0;
end

// 门控后输出时钟沿计数 (用于 CLK_EN=0 期间毛刺检查)
always @(posedge `PLLDDR.PLL_DDR_F400_CLK) pll_ddr_f400_edge_cnt = pll_ddr_f400_edge_cnt + 1;
always @(posedge `PLLDDR.PLL_DDR_F300_CLK) pll_ddr_f300_edge_cnt = pll_ddr_f300_edge_cnt + 1;

// LOCK 变化记录
always @(`PLLDDR.PLL_DDR_LOCK)
    $display("[%0t] PLL_DDR_INFO : PLL_DDR_LOCK -> %b", $realtime, `PLLDDR.PLL_DDR_LOCK);

// 稳定工作期间 LOCK 不允许掉
always @(negedge `PLLDDR.PLL_DDR_LOCK)
    if (pll_ddr_lock_mon_en) begin
        pll_ddr_err_cnt = pll_ddr_err_cnt + 1;
        $display("[%0t] PLL_DDR_ERROR : LOCK dropped unexpectedly during stable phase", $realtime);
    end

// 测频时钟选择
wire pll_ddr_meas_clk = (pll_ddr_meas_sel == 2'd0) ? `PLLDDR.PLL_DDR_F400_CLK      :
                        (pll_ddr_meas_sel == 2'd1) ? `PLLDDR.PLL_DDR_F300_CLK      :
                        (pll_ddr_meas_sel == 2'd2) ? `PLLDDR.PLL_DDR_TEST_DIV1_CLK :
                                                     `PLLDDR.PLL_DDR_TEST_DIV2_CLK ;

//------------------------------------------------------------------
// SCU 读写封装 (如 task 名/参数顺序不同，只需改这里)
//------------------------------------------------------------------
task scu_wr;
    input [31:0] off;
    input [31:0] data;
    begin
        a45_io_write32b(`SCU_BASE, off, data);
        $display("[%0t] PLL_DDR_INFO : SCU WR [0x%h] = 0x%h", $realtime, `SCU_BASE + off, data);
    end
endtask

task scu_rd;
    input [31:0] off;
    input [31:0] exp;
    input [31:0] mask;
    begin
        a45_io_read32b(`SCU_BASE, off, exp, mask);
    end
endtask

task pll_ddr_error;
    input [8*64-1:0] msg;
    begin
        pll_ddr_err_cnt = pll_ddr_err_cnt + 1;
        $display("[%0t] PLL_DDR_ERROR : %0s", $realtime, msg);
    end
endtask

//------------------------------------------------------------------
// 频点表
//   postdiv 为寄存器编码 = 实际分频值 - 1
//   clko0 = Fvco / ((p00+1)*(p10+1)) , clko1 = Fvco / ((p01+1)*(p11+1))
//------------------------------------------------------------------
task pll_ddr_point;
    input  integer     idx;
    output [8*12-1:0]  name;
    output [11:0]      fb;
    output [4:0]       m;
    output [23:0]      frac;
    output [2:0]       p00;
    output [2:0]       p10;
    output [2:0]       p01;
    output [2:0]       p11;
    begin
        case (idx)
          0: begin name = "DDR-1600"; fb = 12'd100; m = 5'd1; frac = 24'h0; p00 = 3'd5; p10 = 3'd0; p01 = 3'd7; p11 = 3'd0; end // 2400/6=400   2400/8=300
          1: begin name = "DDR-1500"; fb = 12'd125; m = 5'd1; frac = 24'h0; p00 = 3'd7; p10 = 3'd0; p01 = 3'd4; p11 = 3'd1; end // 3000/8=375   3000/10=300
          2: begin name = "DDR-1440"; fb = 12'd75 ; m = 5'd1; frac = 24'h0; p00 = 3'd4; p10 = 3'd0; p01 = 3'd5; p11 = 3'd0; end // 1800/5=360   1800/6=300
          3: begin name = "DDR-1400"; fb = 12'd175; m = 5'd2; frac = 24'h0; p00 = 3'd5; p10 = 3'd0; p01 = 3'd6; p11 = 3'd0; end // 2100/6=350   2100/7=300
          4: begin name = "DDR-1333"; fb = 12'd125; m = 5'd1; frac = 24'h0; p00 = 3'd2; p10 = 3'd2; p01 = 3'd4; p11 = 3'd1; end // 3000/9=333.3 3000/10=300
          5: begin name = "DDR-1050"; fb = 12'd175; m = 5'd2; frac = 24'h0; p00 = 3'd7; p10 = 3'd0; p01 = 3'd6; p11 = 3'd0; end // 2100/8=262.5 2100/7=300
          default: begin
              name = "INVALID"; fb = 12'd100; m = 5'd1; frac = 24'h0; p00 = 3'd5; p10 = 3'd0; p01 = 3'd7; p11 = 3'd0;
              pll_ddr_error("pll_ddr_point : invalid index");
          end
        endcase
    end
endtask

//------------------------------------------------------------------
// CFG_EN 脉冲 : 0x7C[2] 0->1->0，检查 SHELL 内 CFG_PULSE 产生
//------------------------------------------------------------------
task pll_ddr_cfg_load;
    reg seen;
    begin
        seen = 1'b0;
        fork
            begin : PLL_DDR_PULSE_WAIT
                @(posedge `PLLDDR.PLL_DDR_CFG_PULSE);
                seen = 1'b1;
            end
            begin
                scu_wr(`SCU_PLL_CFG_EN, 32'h0000_0004);
                repeat (8) @(posedge `PLLDDR.PLL_DDR_CLK);     // 2 级同步 + 边沿检测，保持 >=3 拍
                scu_wr(`SCU_PLL_CFG_EN, 32'h0000_0000);
                repeat (4) @(posedge `PLLDDR.PLL_DDR_CLK);
                disable PLL_DDR_PULSE_WAIT;
            end
        join
        if (!seen) pll_ddr_error("CFG_EN rising edge did not generate PLL_DDR_CFG_PULSE");
        else       $display("[%0t] PLL_DDR_INFO : CFG_PULSE seen, config loaded", $realtime);
    end
endtask

//------------------------------------------------------------------
// 等 LOCK 到指定值，带超时
//------------------------------------------------------------------
task pll_ddr_wait_lock;
    input       val;
    output real t_used;
    output      ok;
    real t0;
    begin
        ok = 1'b0;
        t0 = $realtime;
        fork : PLL_DDR_WL
            begin
                wait (`PLLDDR.PLL_DDR_LOCK === val);
                ok = 1'b1;
                disable PLL_DDR_WL;
            end
            begin
                #(`PLL_LOCK_TIMEOUT);
                disable PLL_DDR_WL;
            end
        join
        t_used = $realtime - t0;
    end
endtask

//------------------------------------------------------------------
// 测频 : sel 0=F400 1=F300 2=TEST_DIV1 3=TEST_DIV2
//   f_exp > 0 时与理论值比对；f_exp = 0 只打印
//------------------------------------------------------------------
task pll_ddr_meas;
    input  [1:0]       sel;
    input  integer     n;
    input  real        f_exp;
    input  [8*16-1:0]  tag;
    output real        f_meas;
    real    t0, t1, ppm;
    reg     timeout;
    begin
        pll_ddr_meas_sel = sel;
        timeout = 1'b0;
        t0 = 0.0; t1 = 0.0;
        #1;
        fork : PLL_DDR_MEAS
            begin
                repeat (8) @(posedge pll_ddr_meas_clk);
                t0 = $realtime;
                repeat (n) @(posedge pll_ddr_meas_clk);
                t1 = $realtime;
                disable PLL_DDR_MEAS;
            end
            begin
                #(`PLL_MEAS_TIMEOUT);
                timeout = 1'b1;
                disable PLL_DDR_MEAS;
            end
        join

        if (timeout || (t1 <= t0)) begin
            f_meas = 0.0;
            pll_ddr_error({tag, " : clock not toggling (measure timeout)"});
        end
        else begin
            f_meas = n * 1000.0 / (t1 - t0);                 // MHz (时间单位 ns)
            if (f_exp > 0.0) begin
                ppm = (f_meas - f_exp) / f_exp * 1.0e6;
                if (ppm < 0.0) ppm = -ppm;
                if (ppm > `PLL_FREQ_TOL_PPM) begin
                    pll_ddr_err_cnt = pll_ddr_err_cnt + 1;
                    $display("[%0t] PLL_DDR_ERROR : %0s freq = %f MHz, expect %f MHz, err %f ppm",
                             $realtime, tag, f_meas, f_exp, ppm);
                end
                else
                    $display("[%0t] PLL_DDR_PASS  : %0s freq = %f MHz, expect %f MHz, err %f ppm",
                             $realtime, tag, f_meas, f_exp, ppm);
            end
            else
                $display("[%0t] PLL_DDR_INFO  : %0s freq = %f MHz", $realtime, tag, f_meas);
        end
    end
endtask

//------------------------------------------------------------------
// 检查 SHELL 内寄存器已载入期望值
//------------------------------------------------------------------
task pll_ddr_chk_shell;
    input [11:0] fb;
    input [4:0]  m;
    input [23:0] frac;
    input [2:0]  p00;
    input [2:0]  p10;
    input [2:0]  p01;
    input [2:0]  p11;
    input        pd;
    begin
        if (`PLLDDR.PLL_DDR_FBDIV_REG      !== fb  ) pll_ddr_error("SHELL FBDIV_REG mismatch");
        if (`PLLDDR.PLL_DDR_PREDIV_REG     !== m   ) pll_ddr_error("SHELL PREDIV_REG mismatch");
        if (`PLLDDR.PLL_DDR_FRAC_REG       !== frac) pll_ddr_error("SHELL FRAC_REG mismatch");
        if (`PLLDDR.PLL_DDR_POSTDIV0_0_REG !== p00 ) pll_ddr_error("SHELL POSTDIV0_0_REG mismatch");
        if (`PLLDDR.PLL_DDR_POSTDIV1_0_REG !== p10 ) pll_ddr_error("SHELL POSTDIV1_0_REG mismatch");
        if (`PLLDDR.PLL_DDR_POSTDIV0_1_REG !== p01 ) pll_ddr_error("SHELL POSTDIV0_1_REG mismatch");
        if (`PLLDDR.PLL_DDR_POSTDIV1_1_REG !== p11 ) pll_ddr_error("SHELL POSTDIV1_1_REG mismatch");
        if (`PLLDDR.PLL_DDR_PD_REG         !== pd  ) pll_ddr_error("SHELL PD_REG mismatch");
        // DFT mux 之后送 PLL 的值
        if (`PLLDDR.PLL_DDR_FBDIV          !== fb  ) pll_ddr_error("PLL fbdiv pin mismatch (DFT_MODE?)");
        if (`PLLDDR.PLL_DDR_PREDIV         !== m   ) pll_ddr_error("PLL prediv pin mismatch (DFT_MODE?)");
        $display("[%0t] PLL_DDR_INFO : SHELL reg check done : fbdiv=%0d M=%0d frac=0x%h pd0_0=%0d pd1_0=%0d pd0_1=%0d pd1_1=%0d pd=%b",
                 $realtime, `PLLDDR.PLL_DDR_FBDIV_REG, `PLLDDR.PLL_DDR_PREDIV_REG, `PLLDDR.PLL_DDR_FRAC_REG,
                 `PLLDDR.PLL_DDR_POSTDIV0_0_REG, `PLLDDR.PLL_DDR_POSTDIV1_0_REG,
                 `PLLDDR.PLL_DDR_POSTDIV0_1_REG, `PLLDDR.PLL_DDR_POSTDIV1_1_REG, `PLLDDR.PLL_DDR_PD_REG);
    end
endtask

//------------------------------------------------------------------
// 锁定后测频 (F400 / F300 比对理论值, TEST_DIV 打印)
//------------------------------------------------------------------
task pll_ddr_freq_check;
    input real f0_exp;
    input real f1_exp;
    real f0, f1, fd1, fd2;
    begin
        pll_ddr_meas(2'd0, 400, f0_exp, "clko0 F400(DDR)", f0);
        pll_ddr_meas(2'd1, 400, f1_exp, "clko1 F300(IP) ", f1);
        pll_ddr_meas(2'd2, 20 , 0.0   , "TEST_DIV1      ", fd1);
        pll_ddr_meas(2'd3, 20 , 0.0   , "TEST_DIV2      ", fd2);
        if (fd1 > 0.0) $display("[%0t] PLL_DDR_INFO  : TEST_DIV1 ratio F400/DIV1 = %f (DIV_DDR0=0x%h)", $realtime, f0/fd1, `PLLDDR.PLL_DDR_CLK_DIV1_REG);
        if (fd2 > 0.0) $display("[%0t] PLL_DDR_INFO  : TEST_DIV2 ratio F300/DIV2 = %f (DIV_DDR1=0x%h)", $realtime, f1/fd2, `PLLDDR.PLL_DDR_CLK_DIV2_REG);
    end
endtask

//------------------------------------------------------------------
// 复位默认值检查 (DDR-1600)
//------------------------------------------------------------------
task pll_ddr_init_check;
    real t; reg ok;
    begin
        $display("\n[%0t] PLL_DDR_INFO : ===== reset default check (DDR-1600) =====", $realtime);
        if (`PLLDDR.DFT_MODE !== 1'b0) pll_ddr_error("DFT_MODE=1 : CFG_EN is blocked, DFS can not run");

        // SCU 复位值
        scu_rd(`SCU_PLLDDR_CFG0, 32'hA100_0000, 32'hFFFF_FFFF);
        scu_rd(`SCU_PLLDDR_CFG1, 32'h0075_3064, 32'hFFFF_FFFF);
        scu_rd(`SCU_PLLDDR_CFG2, 32'h0169_0000, 32'hFFFF_FFFF);

        pll_ddr_wait_lock(1'b1, t, ok);
        if (!ok) pll_ddr_error("reset : PLL_DDR_LOCK not asserted");
        else     $display("[%0t] PLL_DDR_INFO : reset lock ok", $realtime);

        pll_ddr_chk_shell(12'd100, 5'd1, 24'h0, 3'd5, 3'd0, 3'd7, 3'd0, `PLLDDR_PD_ON);
        pll_ddr_lock_mon_en = 1'b1;
        pll_ddr_freq_check(400.0, 300.0);
        pll_ddr_lock_mon_en = 1'b0;
    end
endtask

//------------------------------------------------------------------
// 一次调频
//------------------------------------------------------------------
task pll_ddr_dfs;
    input integer idx;
    reg [8*12-1:0] name;
    reg [11:0]     fb;
    reg [4:0]      m;
    reg [23:0]     frac;
    reg [2:0]      p00, p10, p01, p11;
    reg            dacpd, dsmpd, ok;
    reg [31:0]     cfg0_old_off, cfg0_off, cfg0_on, cfg1, cfg2;
    real           fpfd, fvco, f0_exp, f1_exp, t_lock;
    integer        e400, e300;
    begin
        pll_ddr_point(idx, name, fb, m, frac, p00, p10, p01, p11);

        dacpd  = (frac == 24'h0) ? 1'b1 : 1'b0;      // 整数模式 1 / 小数模式 0
        dsmpd  = dacpd;
        fpfd   = `PLLDDR_FREF_MHZ / m;
        fvco   = `PLLDDR_FREF_MHZ * (fb + frac / 16777216.0) / m;
        f0_exp = fvco / ((p00 + 1) * (p10 + 1));
        f1_exp = fvco / ((p01 + 1) * (p11 + 1));

        $display("\n[%0t] PLL_DDR_INFO : ===== DFS -> %0s : NI=%0d M=%0d frac=0x%h Fpfd=%f Fvco=%f clko0=%f clko1=%f =====",
                 $realtime, name, fb, m, frac, fpfd, fvco, f0_exp, f1_exp);

        // 规格检查
        if (fpfd < 10.0  || fpfd > 100.0 ) pll_ddr_error("Fpfd out of range 10~100MHz");
        if (fvco < 1000.0|| fvco > 3200.0) pll_ddr_error("Fvco out of range 1~3.2GHz");
        if (fb == 12'd11 || fb < 12'd8   ) pll_ddr_error("NI illegal (8,9,10,12~4095)");

        //                 pd             testen disable_sscg M  frac
        cfg0_off     = {`PLLDDR_PD_OFF, 1'b0,  1'b1,        m, frac};
        cfg0_on      = {`PLLDDR_PD_ON , 1'b0,  1'b1,        m, frac};
        cfg0_old_off = {`PLLDDR_PD_OFF, `PLLDDR.PLL_DDR_TESTEN_REG, `PLLDDR.PLL_DDR_DIS_SSCG_REG,
                        `PLLDDR.PLL_DDR_PREDIV_REG, `PLLDDR.PLL_DDR_FRAC_REG};
        //                sel_ext       pd1_1      pd1_0      pd0_1      pd0_0  testsel dsmpd dacpd fbdiv
        cfg1         = {1'b0, p11, 1'b0, p10, 1'b0, p01, 1'b0, p00, 2'b00, dsmpd, dacpd, fb};
        //                downspread spread divval cpi   cpp   gvco  extwaveval ext_maxaddr
        cfg2         = {1'b0,      3'd0,  4'd1,  3'd3, 3'd2, 2'd1, 8'h00,     8'h00};

        //--- step1 : 关输出时钟门控 CLK_EN=0 ------------------------------
        $display("[%0t] PLL_DDR_INFO : step1 gate off output clock", $realtime);
        scu_wr(`SCU_PLL_GATE, 32'h0000_0001);           // [1]ddr_clk_on=0 , [0]mfp_clk_on=1 保持
        pll_ddr_cfg_load;
        if (`PLLDDR.PLL_DDR_CLK_EN_REG !== 1'b0) pll_ddr_error("step1 : CLK_EN_REG not 0");
        #50;
        e400 = pll_ddr_f400_edge_cnt;
        e300 = pll_ddr_f300_edge_cnt;

        //--- step2 : PLL power down (旧参数) ------------------------------
        $display("[%0t] PLL_DDR_INFO : step2 PLL power down", $realtime);
        scu_wr(`SCU_PLLDDR_CFG0, cfg0_old_off);
        pll_ddr_cfg_load;
        pll_ddr_wait_lock(1'b0, t_lock, ok);
        if (!ok) pll_ddr_error("step2 : LOCK not deasserted after power down");
        else     $display("[%0t] PLL_DDR_INFO : LOCK deasserted %f ns after pd", $realtime, t_lock);

        //--- step3 : 写新参数 (保持 power down) ----------------------------
        $display("[%0t] PLL_DDR_INFO : step3 load new divider (pd keep off)", $realtime);
        scu_wr(`SCU_PLLDDR_CFG2, cfg2);
        scu_wr(`SCU_PLLDDR_CFG1, cfg1);
        scu_wr(`SCU_PLLDDR_CFG0, cfg0_off);
        scu_rd(`SCU_PLLDDR_CFG2, cfg2    , 32'hFFFF_FFFF);
        scu_rd(`SCU_PLLDDR_CFG1, cfg1    , 32'hFFFF_FFFF);
        scu_rd(`SCU_PLLDDR_CFG0, cfg0_off, 32'hFFFF_FFFF);
        pll_ddr_cfg_load;
        pll_ddr_chk_shell(fb, m, frac, p00, p10, p01, p11, `PLLDDR_PD_OFF);
        #(`PLL_PD_HOLD);

        //--- step4 : power on, 等 LOCK -------------------------------------
        $display("[%0t] PLL_DDR_INFO : step4 PLL power on, wait lock", $realtime);
        scu_wr(`SCU_PLLDDR_CFG0, cfg0_on);
        pll_ddr_cfg_load;
        pll_ddr_wait_lock(1'b1, t_lock, ok);
        if (!ok) pll_ddr_error("step4 : LOCK timeout after power on");
        else     $display("[%0t] PLL_DDR_INFO : %0s LOCK time = %f ns (from CFG pulse)", $realtime, name, t_lock);
        pll_ddr_chk_shell(fb, m, frac, p00, p10, p01, p11, `PLLDDR_PD_ON);
        scu_rd(`SCU_PLL_LOCK, 32'h0000_0004, 32'h0000_0004);   // 总线读 LOCK 状态位

        //--- step5 : 门控期间无毛刺检查, 打开输出 -------------------------
        if (pll_ddr_f400_edge_cnt != e400) pll_ddr_error("F400_CLK toggled while CLK_EN=0 (glitch)");
        if (pll_ddr_f300_edge_cnt != e300) pll_ddr_error("F300_CLK toggled while CLK_EN=0 (glitch)");
        $display("[%0t] PLL_DDR_INFO : step5 gate on output clock", $realtime);
        scu_wr(`SCU_PLL_GATE, 32'h0000_0003);
        pll_ddr_cfg_load;
        if (`PLLDDR.PLL_DDR_CLK_EN_REG !== 1'b1) pll_ddr_error("step5 : CLK_EN_REG not 1");

        //--- step6 : 测频比对 ---------------------------------------------
        pll_ddr_lock_mon_en = 1'b1;
        pll_ddr_freq_check(f0_exp, f1_exp);
        pll_ddr_lock_mon_en = 1'b0;

        $display("[%0t] PLL_DDR_INFO : ===== DFS -> %0s done, err_cnt = %0d =====", $realtime, name, pll_ddr_err_cnt);
    end
endtask

//------------------------------------------------------------------
// 结果汇总
//------------------------------------------------------------------
task pll_ddr_report;
    begin
        $display("\n==============================================================");
        if (pll_ddr_err_cnt == 0) $display("  PLL_DDR DFS TEST PASS");
        else                      $display("  PLL_DDR DFS TEST FAIL : %0d error(s)", pll_ddr_err_cnt);
        $display("==============================================================\n");
    end
endtask

//------------------------------------------------------------------
// 顶层 pattern
//------------------------------------------------------------------
task chip_top_task;
begin
    pll_ddr_init_check;          // 复位默认 DDR-1600

    pll_ddr_dfs(1);              // 1600 -> 1500
    pll_ddr_dfs(2);              // 1500 -> 1440
    pll_ddr_dfs(3);              // 1440 -> 1400 (M=2)
    pll_ddr_dfs(4);              // 1400 -> 1333 (postdiv1 级联)
    pll_ddr_dfs(5);              // 1333 -> 1050
    pll_ddr_dfs(0);              // 1050 -> 1600 (大跨度升频)
    pll_ddr_dfs(5);              // 1600 -> 1050 (大跨度降频)
    pll_ddr_dfs(0);              // 回到默认 1600

    pll_ddr_report;
#2000;
end
endtask
