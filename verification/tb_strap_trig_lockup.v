`timescale 1ns/1ps
module tb_strap2;

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

reg [31:0] rd; integer gap; integer stuck_cnt; integer poll;

initial begin
    $display("");
    $display("### 同一 TRIG 位在清除窗口内被重写  (PCLK 200MHz, STRAP_CLK 50MHz)");
    $display("### gap = 两次写 TRIG[3] 之间插入的等待时间");
    stuck_cnt = 0;
    for (gap = 0; gap <= 60; gap = gap + 2) begin
        // 复位
        PRESETN=0; STRAP_RSTJ=0; SRC_RSTJ=0; #50;
        PRESETN=1; STRAP_RSTJ=1; SRC_RSTJ=1; #50;

        apb_write(32'h00, 32'h8);     // 数据
        apb_write(32'h0C, 32'h8);     // 第一次触发
        #(gap);
        apb_write(32'h0C, 32'h8);     // 第二次触发, 可能撞上清除脉冲

        poll = 0; rd = 32'hFFFF_FFFF;
        while (rd[3] !== 1'b0 && poll < 60) begin apb_read(32'h0C, rd); poll = poll + 1; end

        if (rd[3] !== 1'b0) begin
            stuck_cnt = stuck_cnt + 1;
            $display("  gap=%0dns  -> TRIG[3] 卡死 (轮询 %0d 次仍为 1)", gap, poll);
        end
    end
    $display("");
    if (stuck_cnt == 0) $display("  [PASS] 扫描 31 个 gap 值, 未复现卡死");
    else                $display("  [FAIL] 31 个 gap 值中有 %0d 个导致 TRIG[3] 永久卡死", stuck_cnt);
    $display("");
    $finish;
end
endmodule
