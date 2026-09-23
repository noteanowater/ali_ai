`timescale 1ns/1ps
module tb_strap3;

reg PCLK=0, PRESETN=0, STRAP_CLK=0, STRAP_RSTJ=0, SRC_CLK=0, SRC_RSTJ=0;
reg PSEL=0, PENABLE=0, PWRITE=0;
reg [31:0] PADDR=0, PWDATA=0;
wire [31:0] PRDATA; wire PREADY, PSLVERR;

reg BOOT_USB_DEV_IN=0, BOOT_UART_IN=0, BOOT_NOR_NAND_IN=0, BOOT_EMMC_IN=0;
reg CLK_PLL_OSC_IN=1, SCAN_MODE_IN=0, FUNC_MODE_IN=1;
reg WORK_MODE0_IN=1, WORK_MODE1_IN=1, WORK_MODE2_IN=1;
wire STR_SCAN_MODE, FUNC_MODE, CLK_PLL_OSC; wire [2:0] WORK_MODE;
wire BOOT_EMMC, BOOT_NOR_NAND, BOOT_UART, BOOT_USB_DEV;

always #2.5 PCLK      = ~PCLK;      // 200 MHz
always #10  STRAP_CLK = ~STRAP_CLK; // 50 MHz
always #10  SRC_CLK   = ~SRC_CLK;

STRAP_PIN_SHELL U_DUT (
    .PCLK(PCLK),.PRESETN(PRESETN),.STRAP_CLK(STRAP_CLK),.STRAP_RSTJ(STRAP_RSTJ),
    .SRC_CLK(SRC_CLK),.SRC_RSTJ(SRC_RSTJ),
    .PSEL(PSEL),.PENABLE(PENABLE),.PWRITE(PWRITE),.PADDR(PADDR),.PWDATA(PWDATA),
    .PRDATA(PRDATA),.PREADY(PREADY),.PSLVERR(PSLVERR),
    .BOOT_USB_DEV_IN(BOOT_USB_DEV_IN),.BOOT_UART_IN(BOOT_UART_IN),
    .BOOT_NOR_NAND_IN(BOOT_NOR_NAND_IN),.BOOT_EMMC_IN(BOOT_EMMC_IN),
    .CLK_PLL_OSC_IN(CLK_PLL_OSC_IN),.SCAN_MODE_IN(SCAN_MODE_IN),.FUNC_MODE_IN(FUNC_MODE_IN),
    .WORK_MODE0_IN(WORK_MODE0_IN),.WORK_MODE1_IN(WORK_MODE1_IN),.WORK_MODE2_IN(WORK_MODE2_IN),
    .STR_SCAN_MODE(STR_SCAN_MODE),.FUNC_MODE(FUNC_MODE),.WORK_MODE(WORK_MODE),
    .CLK_PLL_OSC(CLK_PLL_OSC),.BOOT_EMMC(BOOT_EMMC),.BOOT_NOR_NAND(BOOT_NOR_NAND),
    .BOOT_UART(BOOT_UART),.BOOT_USB_DEV(BOOT_USB_DEV));

task apb_write(input [31:0] a, input [31:0] d);
begin
    @(posedge PCLK); #0.1; PSEL=1; PENABLE=0; PWRITE=1; PADDR=a; PWDATA=d;
    @(posedge PCLK); #0.1; PENABLE=1;
    @(posedge PCLK); #0.1;
    @(posedge PCLK); #0.1; PSEL=0; PENABLE=0; PWRITE=0;
end
endtask

task apb_read(input [31:0] a, output [31:0] d);
begin
    @(posedge PCLK); #0.1; PSEL=1; PENABLE=0; PWRITE=0; PADDR=a;
    @(posedge PCLK); #0.1; PENABLE=1;
    @(posedge PCLK); #0.1; d = PRDATA;
    @(posedge PCLK); #0.1; PSEL=0; PENABLE=0;
end
endtask

reg [31:0] rd;

initial begin
    $display("");
    $display("### 软件改写 FUNC_MODE 测试");
    PRESETN=0; STRAP_RSTJ=0; SRC_RSTJ=0; #50;
    PRESETN=1; STRAP_RSTJ=1; SRC_RSTJ=1; #50;

    $display("  复位后 (引脚 FUNC_MODE_IN=1): FUNC_MODE=%b  TEST_MODE/SCAN=%b", FUNC_MODE, STR_SCAN_MODE);

    // 只写 TRIG[6], 不写 MODE_REG -- 复现"写序颠倒"危害
    apb_write(32'h0C, 32'h40);
    #400;
    $display("  仅写 TRIG[6] 未写数据后:   FUNC_MODE=%b   <- 加载到 MODE_REG[1] 的复位值 0", FUNC_MODE);
    apb_read(32'h18, rd);
    $display("  MODE_RPT = 0x%0h  (bit0=SCAN_MODE, bit1=FUNC_MODE)", rd);

    // 尝试用软件置 TEST_MODE
    apb_write(32'h08, 32'h1);       // MODE_REG[0] = TEST_MODE = 1
    apb_write(32'h0C, 32'h20);      // TRIG[5]
    #400;
    apb_read(32'h18, rd);
    $display("  写 MODE_REG[0]=1 + TRIG[5] 后: SCAN_MODE=%b  MODE_RPT=0x%0h", STR_SCAN_MODE, rd);
    if (STR_SCAN_MODE === 1'b0) $display("  [PASS] 软件无法置位 TEST_MODE");
    else                        $display("  [FAIL] 软件置位了 TEST_MODE !");
    apb_read(32'h0C, rd);
    $display("  TRIG = 0x%0h  (bit5 应已自清)", rd);
    $display("");
    $finish;
end
endmodule
