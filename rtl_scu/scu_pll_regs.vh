//==========================================================================
// SCU PLL registers (0x54 ~ 0x74)
//   PLLxxx_PWRON [31] : PLL power on, 1 = on (default), 0 = off
//                       (goes through PLL_PD_GEN : ~4.2us delay before the
//                        PLL pd pin is released ; off is immediate)
//   PLL_SYS divider fields are RO (strap CPU_SPEED_SEL, read back from shell)
//
//   Default : 0x54 = 0xA155_5555 (strap 2'b00)  0x58 = 0x0043_0053  0x5C = 0x0169_0000
//             0x60 = 0xA100_0000                0x64 = 0x0052_307D  0x68 = 0x0169_0000
//             0x6C = 0xA100_0000                0x70 = 0x0075_3064  0x74 = 0x0169_0000
//==========================================================================

//=============================== IO REG 0X54H BEGIN =============================//
reg            pllsys_disable_sscg_reg;
reg            pllsys_testen_reg      ;
reg            pllsys_pwron_reg       ;

assign PLLSYS_DISABLE_SSCG           = pllsys_disable_sscg_reg; //0X54[29]
assign PLLSYS_TESTEN                 = pllsys_testen_reg      ; //0X54[30]
assign PLLSYS_PWRON                  = pllsys_pwron_reg       ; //0X54[31]

wire   [31:00]  DATA_0X54H = {
                             pllsys_pwron_reg                 ,//[31]
                             pllsys_testen_reg                ,//[30]
                             pllsys_disable_sscg_reg          ,//[29]
                             PLLSYS_PREDIV[4:0]               ,//[28:24], RO
                             PLLSYS_FRAC[23:0]                 //[23:0],  RO
                             };

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllsys_disable_sscg_reg           <= #udly 1'b1;
    else if (WR_0X54H & WR_BE3)
        pllsys_disable_sscg_reg           <= #udly SCU_REG_IHB_WDATA[29];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllsys_testen_reg                 <= #udly 1'b0;
    else if (WR_0X54H & WR_BE3)
        pllsys_testen_reg                 <= #udly SCU_REG_IHB_WDATA[30];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllsys_pwron_reg                  <= #udly 1'b1;    // 1 = PLL on
    else if (WR_0X54H & WR_BE3)
        pllsys_pwron_reg                  <= #udly SCU_REG_IHB_WDATA[31];

//=============================== IO REG 0X54H END ===============================//

//=============================== IO REG 0X58H BEGIN =============================//
reg  [1:0]     pllsys_testsel_reg    ;
reg            pllsys_sel_extwave_reg;

assign PLLSYS_TESTSEL[1:0]          = pllsys_testsel_reg    ; //0X58[15:14]
assign PLLSYS_SEL_EXTWAVE           = pllsys_sel_extwave_reg; //0X58[31]

wire   [31:00]  DATA_0X58H = {
                             pllsys_sel_extwave_reg          ,//[31]
                             PLLSYS_POSTDIV1_1[2:0]          ,//[30:28], RO
                             1'b0                            ,//[27]
                             PLLSYS_POSTDIV1_0[2:0]          ,//[26:24], RO
                             1'b0                            ,//[23]
                             PLLSYS_POSTDIV0_1[2:0]          ,//[22:20], RO
                             1'b0                            ,//[19]
                             PLLSYS_POSTDIV0_0[2:0]          ,//[18:16], RO
                             pllsys_testsel_reg[1:0]         ,//[15:14]
                             PLLSYS_DSMPD                    ,//[13],    RO
                             PLLSYS_DACPD                    ,//[12],    RO
                             PLLSYS_FBDIV[11:0]               //[11:0],  RO
                             };

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllsys_testsel_reg[1:0]          <= #udly 2'h0;
    else if (WR_0X58H & WR_BE1)
        pllsys_testsel_reg[1:0]          <= #udly SCU_REG_IHB_WDATA[15:14];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllsys_sel_extwave_reg           <= #udly 1'b0;
    else if (WR_0X58H & WR_BE3)
        pllsys_sel_extwave_reg           <= #udly SCU_REG_IHB_WDATA[31];

//=============================== IO REG 0X58H END ===============================//

//=============================== IO REG 0X5CH BEGIN =============================//
reg  [7:0]     pllsys_ext_maxaddr_reg;
reg  [7:0]     pllsys_extwaveval_reg ;
reg  [1:0]     pllsys_gvco_bias_reg  ;
reg  [2:0]     pllsys_cpp_bias_reg   ;
reg  [2:0]     pllsys_cpi_bias_reg   ;
reg  [3:0]     pllsys_divval_reg     ;
reg  [2:0]     pllsys_spread_reg     ;
reg            pllsys_downspread_reg ;

assign PLLSYS_EXT_MAXADDR[7:0]      = pllsys_ext_maxaddr_reg; //0X5C[7:0]
assign PLLSYS_EXTWAVEVAL[7:0]       = pllsys_extwaveval_reg ; //0X5C[15:8]
assign PLLSYS_GVCO_BIAS[1:0]        = pllsys_gvco_bias_reg  ; //0X5C[17:16]
assign PLLSYS_CPP_BIAS[2:0]         = pllsys_cpp_bias_reg   ; //0X5C[20:18]
assign PLLSYS_CPI_BIAS[2:0]         = pllsys_cpi_bias_reg   ; //0X5C[23:21]
assign PLLSYS_DIVVAL[3:0]           = pllsys_divval_reg     ; //0X5C[27:24]
assign PLLSYS_SPREAD[2:0]           = pllsys_spread_reg     ; //0X5C[30:28]
assign PLLSYS_DOWNSPREAD            = pllsys_downspread_reg ; //0X5C[31]

wire   [31:00]  DATA_0X5CH = {
                             pllsys_downspread_reg           ,//[31]
                             pllsys_spread_reg[2:0]          ,//[30:28]
                             pllsys_divval_reg[3:0]          ,//[27:24]
                             pllsys_cpi_bias_reg[2:0]        ,//[23:21]
                             pllsys_cpp_bias_reg[2:0]        ,//[20:18]
                             pllsys_gvco_bias_reg[1:0]       ,//[17:16]
                             pllsys_extwaveval_reg[7:0]      ,//[15:8]
                             pllsys_ext_maxaddr_reg[7:0]      //[7:0]
                             };

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllsys_ext_maxaddr_reg[7:0]      <= #udly 8'h0;
    else if (WR_0X5CH & WR_BE0)
        pllsys_ext_maxaddr_reg[7:0]      <= #udly SCU_REG_IHB_WDATA[7:0];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllsys_extwaveval_reg[7:0]       <= #udly 8'h0;
    else if (WR_0X5CH & WR_BE1)
        pllsys_extwaveval_reg[7:0]       <= #udly SCU_REG_IHB_WDATA[15:8];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllsys_gvco_bias_reg[1:0]        <= #udly 2'h1;
    else if (WR_0X5CH & WR_BE2)
        pllsys_gvco_bias_reg[1:0]        <= #udly SCU_REG_IHB_WDATA[17:16];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllsys_cpp_bias_reg[2:0]         <= #udly 3'h2;
    else if (WR_0X5CH & WR_BE2)
        pllsys_cpp_bias_reg[2:0]         <= #udly SCU_REG_IHB_WDATA[20:18];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllsys_cpi_bias_reg[2:0]         <= #udly 3'h3;
    else if (WR_0X5CH & WR_BE2)
        pllsys_cpi_bias_reg[2:0]         <= #udly SCU_REG_IHB_WDATA[23:21];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllsys_divval_reg[3:0]           <= #udly 4'h1;
    else if (WR_0X5CH & WR_BE3)
        pllsys_divval_reg[3:0]           <= #udly SCU_REG_IHB_WDATA[27:24];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllsys_spread_reg[2:0]           <= #udly 3'h0;
    else if (WR_0X5CH & WR_BE3)
        pllsys_spread_reg[2:0]           <= #udly SCU_REG_IHB_WDATA[30:28];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllsys_downspread_reg            <= #udly 1'b0;
    else if (WR_0X5CH & WR_BE3)
        pllsys_downspread_reg            <= #udly SCU_REG_IHB_WDATA[31];

//=============================== IO REG 0X5CH END ===============================//

//=============================== IO REG 0X60H BEGIN =============================//
reg  [23:0]    pllmfp_frac_reg        ;
reg  [4:0]     pllmfp_prediv_reg      ;
reg            pllmfp_disable_sscg_reg;
reg            pllmfp_testen_reg      ;
reg            pllmfp_pwron_reg       ;

assign PLL_MFP_CFG_0[23:0]     = pllmfp_frac_reg        ; //0X60[23:0]
assign PLL_MFP_CFG_0[28:24]    = pllmfp_prediv_reg      ; //0X60[28:24]
assign PLL_MFP_CFG_0[29]       = pllmfp_disable_sscg_reg; //0X60[29]
assign PLL_MFP_CFG_0[30]       = pllmfp_testen_reg      ; //0X60[30]
assign PLL_MFP_CFG_0[31]       = pllmfp_pwron_reg       ; //0X60[31]

wire   [31:00]  DATA_0X60H = {
                             pllmfp_pwron_reg                 ,//[31]
                             pllmfp_testen_reg                ,//[30]
                             pllmfp_disable_sscg_reg          ,//[29]
                             pllmfp_prediv_reg[4:0]           ,//[28:24]
                             pllmfp_frac_reg[23:0]             //[23:0]
                             };

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_frac_reg[23:0]             <= #udly 24'h0;
    else if (WR_0X60H)
    begin
      if (WR_BE2)
        pllmfp_frac_reg[23:16]            <= #udly SCU_REG_IHB_WDATA[23:16];
      if (WR_BE1)
        pllmfp_frac_reg[15:8]             <= #udly SCU_REG_IHB_WDATA[15:8];
      if (WR_BE0)
        pllmfp_frac_reg[7:0]              <= #udly SCU_REG_IHB_WDATA[7:0];
    end

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_prediv_reg[4:0]            <= #udly 5'h1;
    else if (WR_0X60H & WR_BE3)
        pllmfp_prediv_reg[4:0]            <= #udly SCU_REG_IHB_WDATA[28:24];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_disable_sscg_reg           <= #udly 1'b1;
    else if (WR_0X60H & WR_BE3)
        pllmfp_disable_sscg_reg           <= #udly SCU_REG_IHB_WDATA[29];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_testen_reg                 <= #udly 1'b0;
    else if (WR_0X60H & WR_BE3)
        pllmfp_testen_reg                 <= #udly SCU_REG_IHB_WDATA[30];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_pwron_reg                  <= #udly 1'b1;    // 1 = PLL on
    else if (WR_0X60H & WR_BE3)
        pllmfp_pwron_reg                  <= #udly SCU_REG_IHB_WDATA[31];

//=============================== IO REG 0X60H END ===============================//

//=============================== IO REG 0X64H BEGIN =============================//
reg  [11:0]    pllmfp_fbdiv_reg      ;
reg            pllmfp_dacpd_reg      ;
reg            pllmfp_dsmpd_reg      ;
reg  [1:0]     pllmfp_testsel_reg    ;
reg  [2:0]     pllmfp_postdiv0_0_reg ;
reg  [2:0]     pllmfp_postdiv0_1_reg ;
reg  [2:0]     pllmfp_postdiv1_0_reg ;
reg  [2:0]     pllmfp_postdiv1_1_reg ;
reg            pllmfp_sel_extwave_reg;

assign PLL_MFP_CFG_1[11:0]     = pllmfp_fbdiv_reg      ; //0X64[11:0]
assign PLL_MFP_CFG_1[12]       = pllmfp_dacpd_reg      ; //0X64[12]
assign PLL_MFP_CFG_1[13]       = pllmfp_dsmpd_reg      ; //0X64[13]
assign PLL_MFP_CFG_1[15:14]    = pllmfp_testsel_reg    ; //0X64[15:14]
assign PLL_MFP_CFG_1[18:16]    = pllmfp_postdiv0_0_reg ; //0X64[18:16]
assign PLL_MFP_CFG_1[21:19]    = pllmfp_postdiv0_1_reg ; //0X64[22:20]
assign PLL_MFP_CFG_1[24:22]    = pllmfp_postdiv1_0_reg ; //0X64[26:24]
assign PLL_MFP_CFG_1[27:25]    = pllmfp_postdiv1_1_reg ; //0X64[30:28]
assign PLL_MFP_CFG_1[28]       = pllmfp_sel_extwave_reg; //0X64[31]

wire   [31:00]  DATA_0X64H = {
                             pllmfp_sel_extwave_reg          ,//[31]
                             pllmfp_postdiv1_1_reg[2:0]      ,//[30:28]
                             1'b0                            ,//[27]
                             pllmfp_postdiv1_0_reg[2:0]      ,//[26:24]
                             1'b0                            ,//[23]
                             pllmfp_postdiv0_1_reg[2:0]      ,//[22:20]
                             1'b0                            ,//[19]
                             pllmfp_postdiv0_0_reg[2:0]      ,//[18:16]
                             pllmfp_testsel_reg[1:0]         ,//[15:14]
                             pllmfp_dsmpd_reg                ,//[13]
                             pllmfp_dacpd_reg                ,//[12]
                             pllmfp_fbdiv_reg[11:0]           //[11:0]
                             };

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_fbdiv_reg[11:0]           <= #udly 12'h07D;
    else if (WR_0X64H)
    begin
      if (WR_BE1)
        pllmfp_fbdiv_reg[11:8]           <= #udly SCU_REG_IHB_WDATA[11:8];
      if (WR_BE0)
        pllmfp_fbdiv_reg[7:0]            <= #udly SCU_REG_IHB_WDATA[7:0];
    end

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_dacpd_reg                 <= #udly 1'b1;
    else if (WR_0X64H & WR_BE1)
        pllmfp_dacpd_reg                 <= #udly SCU_REG_IHB_WDATA[12];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_dsmpd_reg                 <= #udly 1'b1;
    else if (WR_0X64H & WR_BE1)
        pllmfp_dsmpd_reg                 <= #udly SCU_REG_IHB_WDATA[13];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_testsel_reg[1:0]          <= #udly 2'h0;
    else if (WR_0X64H & WR_BE1)
        pllmfp_testsel_reg[1:0]          <= #udly SCU_REG_IHB_WDATA[15:14];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_postdiv0_0_reg[2:0]       <= #udly 3'h2;
    else if (WR_0X64H & WR_BE2)
        pllmfp_postdiv0_0_reg[2:0]       <= #udly SCU_REG_IHB_WDATA[18:16];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_postdiv0_1_reg[2:0]       <= #udly 3'h5;
    else if (WR_0X64H & WR_BE2)
        pllmfp_postdiv0_1_reg[2:0]       <= #udly SCU_REG_IHB_WDATA[22:20];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_postdiv1_0_reg[2:0]       <= #udly 3'h0;
    else if (WR_0X64H & WR_BE3)
        pllmfp_postdiv1_0_reg[2:0]       <= #udly SCU_REG_IHB_WDATA[26:24];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_postdiv1_1_reg[2:0]       <= #udly 3'h0;
    else if (WR_0X64H & WR_BE3)
        pllmfp_postdiv1_1_reg[2:0]       <= #udly SCU_REG_IHB_WDATA[30:28];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_sel_extwave_reg           <= #udly 1'b0;
    else if (WR_0X64H & WR_BE3)
        pllmfp_sel_extwave_reg           <= #udly SCU_REG_IHB_WDATA[31];

//=============================== IO REG 0X64H END ===============================//

//=============================== IO REG 0X68H BEGIN =============================//
reg  [7:0]     pllmfp_ext_maxaddr_reg;
reg  [7:0]     pllmfp_extwaveval_reg ;
reg  [1:0]     pllmfp_gvco_bias_reg  ;
reg  [2:0]     pllmfp_cpp_bias_reg   ;
reg  [2:0]     pllmfp_cpi_bias_reg   ;
reg  [3:0]     pllmfp_divval_reg     ;
reg  [2:0]     pllmfp_spread_reg     ;
reg            pllmfp_downspread_reg ;

assign PLL_MFP_CFG_2[7:0]      = pllmfp_ext_maxaddr_reg; //0X68[7:0]
assign PLL_MFP_CFG_2[15:8]     = pllmfp_extwaveval_reg ; //0X68[15:8]
assign PLL_MFP_CFG_2[17:16]    = pllmfp_gvco_bias_reg  ; //0X68[17:16]
assign PLL_MFP_CFG_2[20:18]    = pllmfp_cpp_bias_reg   ; //0X68[20:18]
assign PLL_MFP_CFG_2[23:21]    = pllmfp_cpi_bias_reg   ; //0X68[23:21]
assign PLL_MFP_CFG_2[27:24]    = pllmfp_divval_reg     ; //0X68[27:24]
assign PLL_MFP_CFG_2[30:28]    = pllmfp_spread_reg     ; //0X68[30:28]
assign PLL_MFP_CFG_2[31]       = pllmfp_downspread_reg ; //0X68[31]

wire   [31:00]  DATA_0X68H = {
                             pllmfp_downspread_reg           ,//[31]
                             pllmfp_spread_reg[2:0]          ,//[30:28]
                             pllmfp_divval_reg[3:0]          ,//[27:24]
                             pllmfp_cpi_bias_reg[2:0]        ,//[23:21]
                             pllmfp_cpp_bias_reg[2:0]        ,//[20:18]
                             pllmfp_gvco_bias_reg[1:0]       ,//[17:16]
                             pllmfp_extwaveval_reg[7:0]      ,//[15:8]
                             pllmfp_ext_maxaddr_reg[7:0]      //[7:0]
                             };

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_ext_maxaddr_reg[7:0]      <= #udly 8'h0;
    else if (WR_0X68H & WR_BE0)
        pllmfp_ext_maxaddr_reg[7:0]      <= #udly SCU_REG_IHB_WDATA[7:0];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_extwaveval_reg[7:0]       <= #udly 8'h0;
    else if (WR_0X68H & WR_BE1)
        pllmfp_extwaveval_reg[7:0]       <= #udly SCU_REG_IHB_WDATA[15:8];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_gvco_bias_reg[1:0]        <= #udly 2'h1;
    else if (WR_0X68H & WR_BE2)
        pllmfp_gvco_bias_reg[1:0]        <= #udly SCU_REG_IHB_WDATA[17:16];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_cpp_bias_reg[2:0]         <= #udly 3'h2;
    else if (WR_0X68H & WR_BE2)
        pllmfp_cpp_bias_reg[2:0]         <= #udly SCU_REG_IHB_WDATA[20:18];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_cpi_bias_reg[2:0]         <= #udly 3'h3;
    else if (WR_0X68H & WR_BE2)
        pllmfp_cpi_bias_reg[2:0]         <= #udly SCU_REG_IHB_WDATA[23:21];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_divval_reg[3:0]           <= #udly 4'h1;
    else if (WR_0X68H & WR_BE3)
        pllmfp_divval_reg[3:0]           <= #udly SCU_REG_IHB_WDATA[27:24];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_spread_reg[2:0]           <= #udly 3'h0;
    else if (WR_0X68H & WR_BE3)
        pllmfp_spread_reg[2:0]           <= #udly SCU_REG_IHB_WDATA[30:28];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllmfp_downspread_reg            <= #udly 1'b0;
    else if (WR_0X68H & WR_BE3)
        pllmfp_downspread_reg            <= #udly SCU_REG_IHB_WDATA[31];

//=============================== IO REG 0X68H END ===============================//

//=============================== IO REG 0X6CH BEGIN =============================//
reg  [23:0]    pllddr_frac_reg        ;
reg  [4:0]     pllddr_prediv_reg      ;
reg            pllddr_disable_sscg_reg;
reg            pllddr_testen_reg      ;
reg            pllddr_pwron_reg       ;

assign PLL_DDR_CFG_0[23:0]     = pllddr_frac_reg        ; //0X6C[23:0]
assign PLL_DDR_CFG_0[28:24]    = pllddr_prediv_reg      ; //0X6C[28:24]
assign PLL_DDR_CFG_0[29]       = pllddr_disable_sscg_reg; //0X6C[29]
assign PLL_DDR_CFG_0[30]       = pllddr_testen_reg      ; //0X6C[30]
assign PLL_DDR_CFG_0[31]       = pllddr_pwron_reg       ; //0X6C[31]

wire   [31:00]  DATA_0X6CH = {
                             pllddr_pwron_reg                 ,//[31]
                             pllddr_testen_reg                ,//[30]
                             pllddr_disable_sscg_reg          ,//[29]
                             pllddr_prediv_reg[4:0]           ,//[28:24]
                             pllddr_frac_reg[23:0]             //[23:0]
                             };

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_frac_reg[23:0]             <= #udly 24'h0;
    else if (WR_0X6CH)
    begin
      if (WR_BE2)
        pllddr_frac_reg[23:16]            <= #udly SCU_REG_IHB_WDATA[23:16];
      if (WR_BE1)
        pllddr_frac_reg[15:8]             <= #udly SCU_REG_IHB_WDATA[15:8];
      if (WR_BE0)
        pllddr_frac_reg[7:0]              <= #udly SCU_REG_IHB_WDATA[7:0];
    end

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_prediv_reg[4:0]            <= #udly 5'h1;
    else if (WR_0X6CH & WR_BE3)
        pllddr_prediv_reg[4:0]            <= #udly SCU_REG_IHB_WDATA[28:24];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_disable_sscg_reg           <= #udly 1'b1;
    else if (WR_0X6CH & WR_BE3)
        pllddr_disable_sscg_reg           <= #udly SCU_REG_IHB_WDATA[29];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_testen_reg                 <= #udly 1'b0;
    else if (WR_0X6CH & WR_BE3)
        pllddr_testen_reg                 <= #udly SCU_REG_IHB_WDATA[30];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_pwron_reg                  <= #udly 1'b1;    // 1 = PLL on
    else if (WR_0X6CH & WR_BE3)
        pllddr_pwron_reg                  <= #udly SCU_REG_IHB_WDATA[31];

//=============================== IO REG 0X6CH END ===============================//

//=============================== IO REG 0X70H BEGIN =============================//
reg  [11:0]    pllddr_fbdiv_reg      ;
reg            pllddr_dacpd_reg      ;
reg            pllddr_dsmpd_reg      ;
reg  [1:0]     pllddr_testsel_reg    ;
reg  [2:0]     pllddr_postdiv0_0_reg ;
reg  [2:0]     pllddr_postdiv0_1_reg ;
reg  [2:0]     pllddr_postdiv1_0_reg ;
reg  [2:0]     pllddr_postdiv1_1_reg ;
reg            pllddr_sel_extwave_reg;

assign PLL_DDR_CFG_1[11:0]     = pllddr_fbdiv_reg      ; //0X70[11:0]
assign PLL_DDR_CFG_1[12]       = pllddr_dacpd_reg      ; //0X70[12]
assign PLL_DDR_CFG_1[13]       = pllddr_dsmpd_reg      ; //0X70[13]
assign PLL_DDR_CFG_1[15:14]    = pllddr_testsel_reg    ; //0X70[15:14]
assign PLL_DDR_CFG_1[18:16]    = pllddr_postdiv0_0_reg ; //0X70[18:16]
assign PLL_DDR_CFG_1[21:19]    = pllddr_postdiv0_1_reg ; //0X70[22:20]
assign PLL_DDR_CFG_1[24:22]    = pllddr_postdiv1_0_reg ; //0X70[26:24]
assign PLL_DDR_CFG_1[27:25]    = pllddr_postdiv1_1_reg ; //0X70[30:28]
assign PLL_DDR_CFG_1[28]       = pllddr_sel_extwave_reg; //0X70[31]

wire   [31:00]  DATA_0X70H = {
                             pllddr_sel_extwave_reg          ,//[31]
                             pllddr_postdiv1_1_reg[2:0]      ,//[30:28]
                             1'b0                            ,//[27]
                             pllddr_postdiv1_0_reg[2:0]      ,//[26:24]
                             1'b0                            ,//[23]
                             pllddr_postdiv0_1_reg[2:0]      ,//[22:20]
                             1'b0                            ,//[19]
                             pllddr_postdiv0_0_reg[2:0]      ,//[18:16]
                             pllddr_testsel_reg[1:0]         ,//[15:14]
                             pllddr_dsmpd_reg                ,//[13]
                             pllddr_dacpd_reg                ,//[12]
                             pllddr_fbdiv_reg[11:0]           //[11:0]
                             };

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_fbdiv_reg[11:0]           <= #udly 12'h064;
    else if (WR_0X70H)
    begin
      if (WR_BE1)
        pllddr_fbdiv_reg[11:8]           <= #udly SCU_REG_IHB_WDATA[11:8];
      if (WR_BE0)
        pllddr_fbdiv_reg[7:0]            <= #udly SCU_REG_IHB_WDATA[7:0];
    end

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_dacpd_reg                 <= #udly 1'b1;
    else if (WR_0X70H & WR_BE1)
        pllddr_dacpd_reg                 <= #udly SCU_REG_IHB_WDATA[12];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_dsmpd_reg                 <= #udly 1'b1;
    else if (WR_0X70H & WR_BE1)
        pllddr_dsmpd_reg                 <= #udly SCU_REG_IHB_WDATA[13];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_testsel_reg[1:0]          <= #udly 2'h0;
    else if (WR_0X70H & WR_BE1)
        pllddr_testsel_reg[1:0]          <= #udly SCU_REG_IHB_WDATA[15:14];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_postdiv0_0_reg[2:0]       <= #udly 3'h5;
    else if (WR_0X70H & WR_BE2)
        pllddr_postdiv0_0_reg[2:0]       <= #udly SCU_REG_IHB_WDATA[18:16];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_postdiv0_1_reg[2:0]       <= #udly 3'h7;
    else if (WR_0X70H & WR_BE2)
        pllddr_postdiv0_1_reg[2:0]       <= #udly SCU_REG_IHB_WDATA[22:20];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_postdiv1_0_reg[2:0]       <= #udly 3'h0;
    else if (WR_0X70H & WR_BE3)
        pllddr_postdiv1_0_reg[2:0]       <= #udly SCU_REG_IHB_WDATA[26:24];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_postdiv1_1_reg[2:0]       <= #udly 3'h0;
    else if (WR_0X70H & WR_BE3)
        pllddr_postdiv1_1_reg[2:0]       <= #udly SCU_REG_IHB_WDATA[30:28];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_sel_extwave_reg           <= #udly 1'b0;
    else if (WR_0X70H & WR_BE3)
        pllddr_sel_extwave_reg           <= #udly SCU_REG_IHB_WDATA[31];

//=============================== IO REG 0X70H END ===============================//

//=============================== IO REG 0X74H BEGIN =============================//
reg  [7:0]     pllddr_ext_maxaddr_reg;
reg  [7:0]     pllddr_extwaveval_reg ;
reg  [1:0]     pllddr_gvco_bias_reg  ;
reg  [2:0]     pllddr_cpp_bias_reg   ;
reg  [2:0]     pllddr_cpi_bias_reg   ;
reg  [3:0]     pllddr_divval_reg     ;
reg  [2:0]     pllddr_spread_reg     ;
reg            pllddr_downspread_reg ;

assign PLL_DDR_CFG_2[7:0]      = pllddr_ext_maxaddr_reg; //0X74[7:0]
assign PLL_DDR_CFG_2[15:8]     = pllddr_extwaveval_reg ; //0X74[15:8]
assign PLL_DDR_CFG_2[17:16]    = pllddr_gvco_bias_reg  ; //0X74[17:16]
assign PLL_DDR_CFG_2[20:18]    = pllddr_cpp_bias_reg   ; //0X74[20:18]
assign PLL_DDR_CFG_2[23:21]    = pllddr_cpi_bias_reg   ; //0X74[23:21]
assign PLL_DDR_CFG_2[27:24]    = pllddr_divval_reg     ; //0X74[27:24]
assign PLL_DDR_CFG_2[30:28]    = pllddr_spread_reg     ; //0X74[30:28]
assign PLL_DDR_CFG_2[31]       = pllddr_downspread_reg ; //0X74[31]

wire   [31:00]  DATA_0X74H = {
                             pllddr_downspread_reg           ,//[31]
                             pllddr_spread_reg[2:0]          ,//[30:28]
                             pllddr_divval_reg[3:0]          ,//[27:24]
                             pllddr_cpi_bias_reg[2:0]        ,//[23:21]
                             pllddr_cpp_bias_reg[2:0]        ,//[20:18]
                             pllddr_gvco_bias_reg[1:0]       ,//[17:16]
                             pllddr_extwaveval_reg[7:0]      ,//[15:8]
                             pllddr_ext_maxaddr_reg[7:0]      //[7:0]
                             };

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_ext_maxaddr_reg[7:0]      <= #udly 8'h0;
    else if (WR_0X74H & WR_BE0)
        pllddr_ext_maxaddr_reg[7:0]      <= #udly SCU_REG_IHB_WDATA[7:0];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_extwaveval_reg[7:0]       <= #udly 8'h0;
    else if (WR_0X74H & WR_BE1)
        pllddr_extwaveval_reg[7:0]       <= #udly SCU_REG_IHB_WDATA[15:8];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_gvco_bias_reg[1:0]        <= #udly 2'h1;
    else if (WR_0X74H & WR_BE2)
        pllddr_gvco_bias_reg[1:0]        <= #udly SCU_REG_IHB_WDATA[17:16];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_cpp_bias_reg[2:0]         <= #udly 3'h2;
    else if (WR_0X74H & WR_BE2)
        pllddr_cpp_bias_reg[2:0]         <= #udly SCU_REG_IHB_WDATA[20:18];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_cpi_bias_reg[2:0]         <= #udly 3'h3;
    else if (WR_0X74H & WR_BE2)
        pllddr_cpi_bias_reg[2:0]         <= #udly SCU_REG_IHB_WDATA[23:21];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_divval_reg[3:0]           <= #udly 4'h1;
    else if (WR_0X74H & WR_BE3)
        pllddr_divval_reg[3:0]           <= #udly SCU_REG_IHB_WDATA[27:24];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_spread_reg[2:0]           <= #udly 3'h0;
    else if (WR_0X74H & WR_BE3)
        pllddr_spread_reg[2:0]           <= #udly SCU_REG_IHB_WDATA[30:28];

 always @(posedge SCU_REG_CLK or negedge SCU_REG_RSTJ)
    if (!SCU_REG_RSTJ)
        pllddr_downspread_reg            <= #udly 1'b0;
    else if (WR_0X74H & WR_BE3)
        pllddr_downspread_reg            <= #udly SCU_REG_IHB_WDATA[31];

//=============================== IO REG 0X74H END ===============================//
