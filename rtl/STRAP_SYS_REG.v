//+FHDR----------------------------------------------------------
//(C) Copyright Company, ALi
//All Right Reserved
//--------------------------------------------------------------
//FILE NAME: STRAP_SYS_REG.v
//AUTHOR: roy.deng
//CONTACT INFORMATION: roy.deng@alitech.com
//--------------------------------------------------------------
//RELEASE VERSION: V1.0
//RELEASE HISTORY:
// VERSION 1.0
//--------------------------------------------------------------
//RELEASE DATE:
//--------------------------------------------------------------
//PURPOSE:APB slave for strap pin system registers
//--------------------------------------------------------------
//--------------------------------------------------------------
//REUSE ISSUES:
//Reset Strategy: async reset
//Clock Strategy: clock
//Critical Timing: no
//Test Feature: DFT
//Asynchronous Interface: YES
//Scan Methodology: DFT
//-FHDR----------------------------------------------------------

module STRAP_SYS_REG #(
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 32,
    parameter STRAP_WIDTH   = 10,
    parameter TRIG_WIDTH    = 8
)(
    input   wire                        PCLK                ,
    input   wire                        PRESETN             ,

    input   wire                        PSEL                ,
    input   wire                        PENABLE             ,
    input   wire                        PWRITE              ,
    input   wire [ADDR_WIDTH-1:0]       PADDR               ,
    input   wire [DATA_WIDTH-1:0]       PWDATA              ,
    output  reg  [DATA_WIDTH-1:0]       PRDATA              ,
    output  reg                         PREADY              ,
    output  wire                        PSLVERR             ,

    output  reg  [STRAP_WIDTH-1:0]      STRAP_PIN_REG       ,
    output  reg  [TRIG_WIDTH-1:0]       STRAP_PIN_TRIG      ,
    input   wire [TRIG_WIDTH-1:0]       STRAP_PIN_CLEAR     ,
    input   wire [STRAP_WIDTH-1:0]      ALL_STRAP_PIN_RPT
);

parameter UDLY = 1'h1;

assign PSLVERR = 1'h0;

localparam ADDR_BOOT_REG  = {{(ADDR_WIDTH-5){1'b0}}, 5'h00};
localparam ADDR_CLK_REG   = {{(ADDR_WIDTH-5){1'b0}}, 5'h04};
localparam ADDR_MODE_REG  = {{(ADDR_WIDTH-5){1'b0}}, 5'h08};
localparam ADDR_TRIG      = {{(ADDR_WIDTH-5){1'b0}}, 5'h0C};
localparam ADDR_BOOT_RPT  = {{(ADDR_WIDTH-5){1'b0}}, 5'h10};
localparam ADDR_CLK_RPT   = {{(ADDR_WIDTH-5){1'b0}}, 5'h14};
localparam ADDR_MODE_RPT  = {{(ADDR_WIDTH-5){1'b0}}, 5'h18};

// assign PREADY = 1'b1;
always @(posedge PCLK or negedge PRESETN) begin
    if (!PRESETN)
        PREADY <= #UDLY 1'b0;
    else if (PREADY)
        PREADY <= #UDLY 1'b0;
    else if (PSEL & PENABLE)
        PREADY <= #UDLY 1'b1;
end

wire APB_WR    = PSEL & PENABLE & PREADY & PWRITE;
wire WR_00H    = APB_WR & (PADDR == ADDR_BOOT_REG);
wire WR_04H    = APB_WR & (PADDR == ADDR_CLK_REG);
wire WR_08H    = APB_WR & (PADDR == ADDR_MODE_REG);
wire WR_0CH    = APB_WR & (PADDR == ADDR_TRIG);

//--------------------------------------------------------------
// BOOT_REG[0] - BOOT_USB_DEV  (RW, offset 0x00)
// BOOT_REG[1] - BOOT_UART
// BOOT_REG[2] - BOOT_NOR_NAND
// BOOT_REG[3] - BOOT_EMMC
//--------------------------------------------------------------
always @(posedge PCLK or negedge PRESETN) begin
    if (!PRESETN) begin
        STRAP_PIN_REG[0] <= #UDLY 1'b0;
        STRAP_PIN_REG[1] <= #UDLY 1'b0;
        STRAP_PIN_REG[2] <= #UDLY 1'b0;
        STRAP_PIN_REG[3] <= #UDLY 1'b0;
    end
    else if (WR_00H) begin
        STRAP_PIN_REG[0] <= #UDLY PWDATA[0];
        STRAP_PIN_REG[1] <= #UDLY PWDATA[1];
        STRAP_PIN_REG[2] <= #UDLY PWDATA[2];
        STRAP_PIN_REG[3] <= #UDLY PWDATA[3];
    end
end

//--------------------------------------------------------------
// CLK_REG[0] - CLK_PLL_OSC    (RW, offset 0x04)
//--------------------------------------------------------------
always @(posedge PCLK or negedge PRESETN) begin
    if (!PRESETN) begin
        STRAP_PIN_REG[4] <= #UDLY 1'b0;
    end
    else if (WR_04H) begin
        STRAP_PIN_REG[4] <= #UDLY PWDATA[0];
    end
end

//--------------------------------------------------------------
// MODE_REG[0] - TEST_MODE     (RW, offset 0x08)
// MODE_REG[1] - FUNC_MODE
// MODE_REG[4:2] - WORK_MODE[2:0]
//--------------------------------------------------------------
always @(posedge PCLK or negedge PRESETN) begin
    if (!PRESETN) begin
        STRAP_PIN_REG[5] <= #UDLY 1'b0;
        STRAP_PIN_REG[6] <= #UDLY 1'b0;
        STRAP_PIN_REG[9:7] <= #UDLY 3'h0;
    end
    else if (WR_08H) begin
        STRAP_PIN_REG[5] <= #UDLY PWDATA[0];
        STRAP_PIN_REG[6] <= #UDLY PWDATA[1];
        STRAP_PIN_REG[9:7] <= #UDLY PWDATA[4:2];
    end
end



//--------------------------------------------------------------
// STRAP_PIN_TRIG[0] - BOOT_USB_DEV  (W1S, hw clear)
//--------------------------------------------------------------
always @(posedge PCLK or negedge PRESETN) begin
    if (!PRESETN)
        STRAP_PIN_TRIG[0] <= #UDLY 1'b0;
    else if (WR_0CH && PWDATA[0])
        STRAP_PIN_TRIG[0] <= #UDLY 1'b1;
    else if (STRAP_PIN_CLEAR[0])
        STRAP_PIN_TRIG[0] <= #UDLY 1'b0;
end

//--------------------------------------------------------------
// STRAP_PIN_TRIG[1] - BOOT_UART     (W1S, hw clear)
//--------------------------------------------------------------
always @(posedge PCLK or negedge PRESETN) begin
    if (!PRESETN)
        STRAP_PIN_TRIG[1] <= #UDLY 1'b0;
    else if (WR_0CH && PWDATA[1])
        STRAP_PIN_TRIG[1] <= #UDLY 1'b1;
    else if (STRAP_PIN_CLEAR[1])
        STRAP_PIN_TRIG[1] <= #UDLY 1'b0;
end

//--------------------------------------------------------------
// STRAP_PIN_TRIG[2] - BOOT_NOR_NAND (W1S, hw clear)
//--------------------------------------------------------------
always @(posedge PCLK or negedge PRESETN) begin
    if (!PRESETN)
        STRAP_PIN_TRIG[2] <= #UDLY 1'b0;
    else if (WR_0CH && PWDATA[2])
        STRAP_PIN_TRIG[2] <= #UDLY 1'b1;
    else if (STRAP_PIN_CLEAR[2])
        STRAP_PIN_TRIG[2] <= #UDLY 1'b0;
end

//--------------------------------------------------------------
// STRAP_PIN_TRIG[3] - BOOT_EMMC (W1S, hw clear)
//--------------------------------------------------------------
always @(posedge PCLK or negedge PRESETN) begin
    if (!PRESETN)
        STRAP_PIN_TRIG[3] <= #UDLY 1'b0;
    else if (WR_0CH && PWDATA[3])
        STRAP_PIN_TRIG[3] <= #UDLY 1'b1;
    else if (STRAP_PIN_CLEAR[3])
        STRAP_PIN_TRIG[3] <= #UDLY 1'b0;
end

//--------------------------------------------------------------
// STRAP_PIN_TRIG[4] - CLK_PLL_OSC   (W1S, hw clear)
//--------------------------------------------------------------
always @(posedge PCLK or negedge PRESETN) begin
    if (!PRESETN)
        STRAP_PIN_TRIG[4] <= #UDLY 1'b0;
    else if (WR_0CH && PWDATA[4])
        STRAP_PIN_TRIG[4] <= #UDLY 1'b1;
    else if (STRAP_PIN_CLEAR[4])
        STRAP_PIN_TRIG[4] <= #UDLY 1'b0;
end

//--------------------------------------------------------------
// STRAP_PIN_TRIG[5] - TEST_MODE     (W1S, hw clear)
//--------------------------------------------------------------
always @(posedge PCLK or negedge PRESETN) begin
    if (!PRESETN)
        STRAP_PIN_TRIG[5] <= #UDLY 1'b0;
    else if (WR_0CH && PWDATA[5])
        STRAP_PIN_TRIG[5] <= #UDLY 1'b1;
    else if (STRAP_PIN_CLEAR[5])
        STRAP_PIN_TRIG[5] <= #UDLY 1'b0;
end

//--------------------------------------------------------------
// STRAP_PIN_TRIG[6] - FUNC_MODE     (W1S, hw clear)
//--------------------------------------------------------------
always @(posedge PCLK or negedge PRESETN) begin
    if (!PRESETN)
        STRAP_PIN_TRIG[6] <= #UDLY 1'b0;
    else if (WR_0CH && PWDATA[6])
        STRAP_PIN_TRIG[6] <= #UDLY 1'b1;
    else if (STRAP_PIN_CLEAR[6])
        STRAP_PIN_TRIG[6] <= #UDLY 1'b0;
end

//--------------------------------------------------------------
// STRAP_PIN_TRIG[7] - WORK_MODE     (W1S, hw clear)
//--------------------------------------------------------------
always @(posedge PCLK or negedge PRESETN) begin
    if (!PRESETN)
        STRAP_PIN_TRIG[7] <= #UDLY 1'b0;
    else if (WR_0CH && PWDATA[7])
        STRAP_PIN_TRIG[7] <= #UDLY 1'b1;
    else if (STRAP_PIN_CLEAR[7])
        STRAP_PIN_TRIG[7] <= #UDLY 1'b0;
end

//--------------------------------------------------------------
// Read mux
//--------------------------------------------------------------
always @(*) begin
    PRDATA = {DATA_WIDTH{1'b0}};
    case (PADDR)
        ADDR_BOOT_REG : PRDATA[3:0] = STRAP_PIN_REG[3:0];
        ADDR_CLK_REG  : PRDATA[0]   = STRAP_PIN_REG[4];
        ADDR_MODE_REG : PRDATA[4:0] = STRAP_PIN_REG[9:5];
        ADDR_TRIG     : PRDATA[TRIG_WIDTH-1:0] = STRAP_PIN_TRIG;
        ADDR_BOOT_RPT : PRDATA[3:0] = ALL_STRAP_PIN_RPT[3:0];
        ADDR_CLK_RPT  : PRDATA[0]   = ALL_STRAP_PIN_RPT[4];
        ADDR_MODE_RPT : PRDATA[4:0] = ALL_STRAP_PIN_RPT[9:5];
        default       : PRDATA = {DATA_WIDTH{1'b0}};
    endcase
end

endmodule
