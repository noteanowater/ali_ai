//+FHDR----------------------------------------------------------
//(C) Copyright Company, ALi
//All Right Reserved
//--------------------------------------------------------------
//FILE NAME: PAD_STRAP.v
//AUTHOR: roy.deng
//CONTACT INFORMATION: roy.deng@alitech.com
//--------------------------------------------------------------
//RELEASE VERSION: V1.0
//RELEASE HISTORY:
// VERSION 1.0
//--------------------------------------------------------------
//RELEASE DATE:
//--------------------------------------------------------------
//PURPOSE: Strap pin register module with system register override
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

module PAD_STRAP #(
    parameter STRAP_WIDTH   = 10 ,
    parameter TRIG_WIDTH    = 8
)(
    input   wire                        STRAP_CLK           ,
    input   wire                        STRAP_RSTJ          ,

    input   wire                        SCAN_MODE            ,

    input   wire                        BOOT_USB_DEV_IN     , // BOOT_USB_DEV
    input   wire                        BOOT_UART_IN        , // BOOT_UART
    input   wire                        BOOT_NOR_NAND_IN    , // BOOT_NOR_NAND
    input   wire                        BOOT_EMMC_IN        , // BOOT_EMMC
    input   wire                        CLK_PLL_OSC_IN      , // CLK_PLL_OSC
//    input   wire                        TEST_MODE_IN        , // TEST_MODE
    input   wire                        FUNC_MODE_IN        , // FUNC_MODE
    input   wire                        WORK_MODE0_IN       , // WORK_MODE[0]
    input   wire                        WORK_MODE1_IN       , // WORK_MODE[1]
    input   wire                        WORK_MODE2_IN       , // WORK_MODE[2]

//    output  wire                        FUNC_MODE           ,

    input   wire [STRAP_WIDTH-1:0]      STRAP_PIN_REG       ,
    input   wire [TRIG_WIDTH-1:0]       STRAP_PIN_TRIG      ,
    output  wire [TRIG_WIDTH-1:0]       STRAP_PIN_CLEAR     ,
    output  wire [STRAP_WIDTH-1:0]      ALL_STRAP_PIN_RPT   
);

parameter udly = 1'h1;

//wire STRAP_CLK = STRAP_CLK;

//--------------------------------------------------------------
// Pad alias
//--------------------------------------------------------------
wire                    BOOT_USB_DEV  = BOOT_USB_DEV_IN                                 ;
wire                    BOOT_UART     = BOOT_UART_IN                                    ;
wire                    BOOT_NOR_NAND = BOOT_NOR_NAND_IN                                ;
wire                    BOOT_EMMC     = BOOT_EMMC_IN                                    ;
wire                    CLK_PLL_OSC   = CLK_PLL_OSC_IN                                  ;
//wire                    PAD_TEST_MODE = TEST_MODE_IN                                    ;
wire                    FUNC_MODE     = FUNC_MODE_IN                                    ;
wire [2:0]              WORK_MODE     = {WORK_MODE2_IN, WORK_MODE1_IN, WORK_MODE0_IN}   ;

//--------------------------------------------------------------
// TRIG sync and rising edge detect
//--------------------------------------------------------------
reg [TRIG_WIDTH-1:0] trig_d1;
reg [TRIG_WIDTH-1:0] trig_d2;
wire [TRIG_WIDTH-1:0] trig_posedge = trig_d1 & (~trig_d2);

always @(posedge STRAP_CLK or negedge STRAP_RSTJ) begin
    if (!STRAP_RSTJ) begin
        trig_d1 <= #udly {TRIG_WIDTH{1'b0}};
        trig_d2 <= #udly {TRIG_WIDTH{1'b0}};
    end else begin
        trig_d1 <= #udly STRAP_PIN_TRIG;
        trig_d2 <= #udly trig_d1;
    end
end

//--------------------------------------------------------------
// Strap config registers
//--------------------------------------------------------------
reg                     r_boot_usb_dev_cfg  ;
reg                     r_boot_uart_cfg     ;
reg                     r_boot_nor_nand_cfg ;
reg                     r_boot_emmc_cfg     ;
reg                     r_clk_pll_osc_cfg   ;
reg                     r_test_mode_cfg     ;
reg                     r_func_mode_cfg     ;
reg [2:0]               r_work_mode_cfg     ;

//always @(posedge STRAP_CLK or negedge STRAP_RSTJ) begin
always @(posedge STRAP_CLK )begin 
    if (!STRAP_RSTJ) begin
        r_boot_usb_dev_cfg  <= #udly BOOT_USB_DEV  ;
        r_boot_uart_cfg     <= #udly BOOT_UART     ;
        r_boot_nor_nand_cfg <= #udly BOOT_NOR_NAND ;
        r_boot_emmc_cfg     <= #udly BOOT_EMMC     ;
        r_clk_pll_osc_cfg   <= #udly CLK_PLL_OSC   ;
        r_func_mode_cfg     <= #udly FUNC_MODE     ;
        r_work_mode_cfg     <= #udly WORK_MODE     ;
    end else begin
        if (trig_posedge[0]) r_boot_usb_dev_cfg  <= #udly STRAP_PIN_REG[0];
        if (trig_posedge[1]) r_boot_uart_cfg     <= #udly STRAP_PIN_REG[1];
        if (trig_posedge[2]) r_boot_nor_nand_cfg <= #udly STRAP_PIN_REG[2];
        if (trig_posedge[3]) r_boot_emmc_cfg     <= #udly STRAP_PIN_REG[3];
        if (trig_posedge[4]) r_clk_pll_osc_cfg   <= #udly STRAP_PIN_REG[4];
        if (trig_posedge[6]) r_func_mode_cfg     <= #udly STRAP_PIN_REG[6];
        if (trig_posedge[7]) r_work_mode_cfg     <= #udly STRAP_PIN_REG[9:7];
    end
end

//--------------------------------------------------------------
// Output
//--------------------------------------------------------------
assign STRAP_PIN_CLEAR = trig_posedge;

assign ALL_STRAP_PIN_RPT = {r_work_mode_cfg     ,
                            r_func_mode_cfg, //FUNC_MODE           ,
                            SCAN_MODE           , //r_test_mode_cfg,
                            r_clk_pll_osc_cfg   ,
                            r_boot_emmc_cfg     ,
                            r_boot_nor_nand_cfg ,
                            r_boot_uart_cfg     ,
                            r_boot_usb_dev_cfg  };

endmodule
