module STRAP_PIN_SHELL (
  input   wire             PCLK             ,
  input   wire             PRESETN          ,

  input   wire             STRAP_CLK        ,
  input   wire             STRAP_RSTJ       ,

  input   wire             SRC_CLK          ,
  input   wire             SRC_RSTJ         ,

  input   wire             PSEL             ,
  input   wire             PENABLE          ,
  input   wire             PWRITE           ,
  input   wire   [31:0]    PADDR            ,
  input   wire   [31:0]    PWDATA           ,
  output  wire   [31:0]    PRDATA           ,
  output  wire             PREADY           ,
  output  wire             PSLVERR          ,

  input   wire             BOOT_USB_DEV_IN  ,
  input   wire             BOOT_UART_IN     ,
  input   wire             BOOT_NOR_NAND_IN ,
  input   wire             BOOT_EMMC_IN     ,
  input   wire             CLK_PLL_OSC_IN   ,
  input   wire             SCAN_MODE_IN     ,
  input   wire             FUNC_MODE_IN     ,
  input   wire             WORK_MODE0_IN    ,
  input   wire             WORK_MODE1_IN    ,
  input   wire             WORK_MODE2_IN    ,

  output  wire             STR_SCAN_MODE    ,
  output  wire             FUNC_MODE        ,
  output  wire  [2:0]      WORK_MODE        ,
  output  wire             CLK_PLL_OSC      ,
  output  wire             BOOT_EMMC        ,
  output  wire             BOOT_NOR_NAND    ,
  output  wire             BOOT_UART        ,
  output  wire             BOOT_USB_DEV     

);

localparam STRAP_WIDTH   = 10 ;
localparam TRIG_WIDTH    = 8  ;

wire [STRAP_WIDTH-1:0]      STRAP_PIN_REG      ;
wire [TRIG_WIDTH-1:0]       STRAP_PIN_TRIG     ;
wire [TRIG_WIDTH-1:0]       STRAP_PIN_CLEAR    ;
wire [STRAP_WIDTH-1:0]      ALL_STRAP_PIN_RPT  ;

assign  WORK_MODE     = ALL_STRAP_PIN_RPT[9:7];
assign  FUNC_MODE     = ALL_STRAP_PIN_RPT[6]  ;
//assign  TEST_MODE     = ALL_STRAP_PIN_RPT[5]  ;
assign  CLK_PLL_OSC   = ALL_STRAP_PIN_RPT[4]  ;
assign  BOOT_EMMC     = ALL_STRAP_PIN_RPT[3]  ;
assign  BOOT_NOR_NAND = ALL_STRAP_PIN_RPT[2]  ;
assign  BOOT_UART     = ALL_STRAP_PIN_RPT[1]  ;
assign  BOOT_USB_DEV  = ALL_STRAP_PIN_RPT[0]  ;

STRAP_SYS_REG #(
    .DATA_WIDTH          (32                   ),
    .ADDR_WIDTH          (32                   ),
    .STRAP_WIDTH         (STRAP_WIDTH          ),
    .TRIG_WIDTH          (TRIG_WIDTH           )
)U_STRAP_SYS_REG(
    .PCLK                (PCLK                 ),
    //.PRESETn            ( PRESETN              ),
    .PRESETN             (PRESETN              ),

    .PSEL                (PSEL                 ),
    .PENABLE             (PENABLE              ),
    .PWRITE              (PWRITE               ),
    .PADDR               (PADDR                ),
    .PWDATA              (PWDATA               ),
    .PRDATA              (PRDATA               ),
    .PREADY              (PREADY               ),
    .PSLVERR             (PSLVERR              ),

    .STRAP_PIN_REG       (STRAP_PIN_REG        ),
    .STRAP_PIN_TRIG      (STRAP_PIN_TRIG       ),
    .STRAP_PIN_CLEAR     (STRAP_PIN_CLEAR      ),
    .ALL_STRAP_PIN_RPT   (ALL_STRAP_PIN_RPT    )
);


PAD_STRAP #(
    .STRAP_WIDTH         (STRAP_WIDTH         ),
    .TRIG_WIDTH          (TRIG_WIDTH          )
)U_PAD_STRAP(
    .STRAP_CLK           (STRAP_CLK           ),
    .STRAP_RSTJ          (STRAP_RSTJ          ),

    .BOOT_USB_DEV_IN     (BOOT_USB_DEV_IN     ), // BOOT_USB_DEV
    .BOOT_UART_IN        (BOOT_UART_IN        ), // BOOT_UART
    .BOOT_NOR_NAND_IN    (BOOT_NOR_NAND_IN    ), // BOOT_NOR_NAND
    .BOOT_EMMC_IN        (BOOT_EMMC_IN        ), // BOOT_EMMC
    .CLK_PLL_OSC_IN      (CLK_PLL_OSC_IN      ), // CLK_PLL_OSC
    .FUNC_MODE_IN        (FUNC_MODE_IN        ), // FUNC_MODE
    .WORK_MODE0_IN       (WORK_MODE0_IN       ), // WORK_MODE[0]
    .WORK_MODE1_IN       (WORK_MODE1_IN       ), // WORK_MODE[1]
    .WORK_MODE2_IN       (WORK_MODE2_IN       ), // WORK_MODE[2]

    .SCAN_MODE           (STR_SCAN_MODE       ),
//    .FUNC_MODE           (STR_FUNC_MODE       ),

    .STRAP_PIN_REG       (STRAP_PIN_REG       ),
    .STRAP_PIN_TRIG      (STRAP_PIN_TRIG      ),
    .STRAP_PIN_CLEAR     (STRAP_PIN_CLEAR     ),
    .ALL_STRAP_PIN_RPT   (ALL_STRAP_PIN_RPT   )
);


//FUNC_MODE_CTRL U_FUNC_MODE_CTRL(
//    .FUNC_MODE_IN (FUNC_MODE_IN ), //From Strap Pin
//    .FUNC_MODE    (STR_FUNC_MODE),
//
//    .SRC_CLK      (SRC_CLK      ),
//    .SRC_RSTJ     (SRC_RSTJ     ) 
//);
//

DFT_MODE_CTRL U_DFT_MODE_CTRL(
   .DFT_MODE_IN  (SCAN_MODE_IN   ),   
   .DFT_MODE     (STR_SCAN_MODE  ),
   .SRC_CLK      (SRC_CLK        ),
   .SRC_RSTJ     (SRC_RSTJ       )
);


endmodule
