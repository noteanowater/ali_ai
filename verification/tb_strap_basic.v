`timescale 1ns/1ps
module tb_strap;

reg PCLK=0, PRESETN=0;
reg STRAP_CLK=0, STRAP_RSTJ=0;
reg SRC_CLK=0, SRC_RSTJ=0;

reg PSEL=0, PENABLE=0, PWRITE=0;
reg [31:0] PADDR=0, PWDATA=0;
wire [31:0] PRDATA;
wire PREADY, PSLVERR;

// strap pins: 缺省 BOOT 全 0 (NOR Flash), CLK_PLL_OSC=1, FUNC_MODE=1, WORK_MODE=111
reg BOOT_USB_DEV_IN=0, BOOT_UART_IN=0, BOOT_NOR_NAND_IN=0, BOOT_EMMC_IN=0;
reg CLK_PLL_OSC_IN=1, SCAN_MODE_IN=0, FUNC_MODE_IN=1;
reg WORK_MODE0_IN=1, WORK_MODE1_IN=1, WORK_MODE2_IN=1;

wire STR_SCAN_MODE, FUNC_MODE, CLK_PLL_OSC;
wire [2:0] WORK_MODE;
wire BOOT_EMMC, BOOT_NOR_NAND, BOOT_UART, BOOT_USB_DEV;

`ifndef PCLK_HALF
 `define PCLK_HALF 2.5
`endif
localparam STRAP_HALF = 10.0;   // STRAP_CLK / SRC_CLK = 50 MHz
localparam PCLK_HALF  = `PCLK_HALF;

always #(PCLK_HALF)   PCLK      = ~PCLK;
always #(STRAP_HALF)  STRAP_CLK = ~STRAP_CLK;
always #(STRAP_HALF)  SRC_CLK   = ~SRC_CLK;

STRAP_PIN_SHELL U_DUT (
    .PCLK(PCLK), .PRESETN(PRESETN),
    .STRAP_CLK(STRAP_CLK), .STRAP_RSTJ(STRAP_RSTJ),
    .SRC_CLK(SRC_CLK), .SRC_RSTJ(SRC_RSTJ),
    .PSEL(PSEL), .PENABLE(PENABLE), .PWRITE(PWRITE),
    .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA),
    .PREADY(PREADY), .PSLVERR(PSLVERR),
    .BOOT_USB_DEV_IN(BOOT_USB_DEV_IN), .BOOT_UART_IN(BOOT_UART_IN),
    .BOOT_NOR_NAND_IN(BOOT_NOR_NAND_IN), .BOOT_EMMC_IN(BOOT_EMMC_IN),
    .CLK_PLL_OSC_IN(CLK_PLL_OSC_IN), .SCAN_MODE_IN(SCAN_MODE_IN),
    .FUNC_MODE_IN(FUNC_MODE_IN),
    .WORK_MODE0_IN(WORK_MODE0_IN), .WORK_MODE1_IN(WORK_MODE1_IN), .WORK_MODE2_IN(WORK_MODE2_IN),
    .STR_SCAN_MODE(STR_SCAN_MODE), .FUNC_MODE(FUNC_MODE), .WORK_MODE(WORK_MODE),
    .CLK_PLL_OSC(CLK_PLL_OSC), .BOOT_EMMC(BOOT_EMMC), .BOOT_NOR_NAND(BOOT_NOR_NAND),
    .BOOT_UART(BOOT_UART), .BOOT_USB_DEV(BOOT_USB_DEV)
);

task apb_write(input [31:0] a, input [31:0] d);
begin
    @(posedge PCLK); #0.1; PSEL=1; PENABLE=0; PWRITE=1; PADDR=a; PWDATA=d;
    @(posedge PCLK); #0.1; PENABLE=1;
    @(posedge PCLK); #0.1;                      // PREADY 在此拍拉高
    @(posedge PCLK); #0.1; PSEL=0; PENABLE=0; PWRITE=0;   // 写在此沿提交
end
endtask

task apb_read(input [31:0] a, output [31:0] d);
begin
    @(posedge PCLK); #0.1; PSEL=1; PENABLE=0; PWRITE=0; PADDR=a;
    @(posedge PCLK); #0.1; PENABLE=1;
    @(posedge PCLK); #0.1;
    d = PRDATA;
    @(posedge PCLK); #0.1; PSEL=0; PENABLE=0;
end
endtask

reg [31:0] rd;
integer poll;

initial begin
    #1;
    $display("");
    $display("### PCLK = %0.1f MHz , STRAP_CLK = %0.1f MHz",
             1000.0/(2*PCLK_HALF), 1000.0/(2*STRAP_HALF));

    #200; PRESETN=1; STRAP_RSTJ=1; SRC_RSTJ=1;
    #200;

    $display("复位后引脚采样值: BOOT_RPT[3:0]=%b%b%b%b  CLK_PLL_OSC=%b  FUNC_MODE=%b  WORK_MODE=%b",
             BOOT_EMMC, BOOT_NOR_NAND, BOOT_UART, BOOT_USB_DEV, CLK_PLL_OSC, FUNC_MODE, WORK_MODE);

    // ---- 软件重配置: 切到 eMMC 启动 ----
    apb_write(32'h00, 32'h8);       // BOOT_REG bit3 = BOOT_EMMC
    apb_write(32'h0C, 32'h8);       // TRIG bit3
    $display("已写 TRIG[3], 开始轮询自清 ...");

    poll = 0;
    rd = 32'hFFFF_FFFF;
    while (rd[3] !== 1'b0 && poll < 200) begin
        apb_read(32'h0C, rd);
        poll = poll + 1;
    end

    if (rd[3] === 1'b0)
        $display("  [PASS] TRIG[3] 在第 %0d 次轮询后自清", poll);
    else
        $display("  [FAIL] TRIG[3] 轮询 %0d 次仍为 1 -- 清除脉冲丢失, 该位永久卡死", poll);

    apb_read(32'h10, rd);
    $display("  BOOT_RPT = 0x%0h  (期望 0x8)  -> BOOT_EMMC=%b", rd, BOOT_EMMC);
    if (rd[3] === 1'b1) $display("  [PASS] 重配置生效");
    else                $display("  [FAIL] 重配置未生效");

    $display("");
    $finish;
end

endmodule
