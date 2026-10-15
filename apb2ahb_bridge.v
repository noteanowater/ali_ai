`timescale 1ns/1ps
//==============================================================================
// Module      : apb2ahb_bridge
// Description : APB to AHB-Lite bridge.
//               - APB side : slave port of the bridge, driven by an APB master
//                            (APB3/APB4 compatible: PREADY, PSLVERR, PPROT, PSTRB)
//               - AHB side : master port of the bridge, drives an AHB-Lite slave
//
//               Each APB transfer is converted into one AHB SINGLE / NONSEQ
//               transfer. HSIZE is fixed to the APB data width (word access).
//               PSTRB is forwarded on HWSTRB (AHB5 style, optional for the slave).
//               HRESP = ERROR is reported back as PSLVERR.
//
// Timing      :
//   APB  : | SETUP | ACCESS ......................... | ACCESS(PREADY=1) |
//   AHB  : | (latch)| ADDR (NONSEQ) | DATA (wait HREADY) |
//
// Clock       : PCLK and HCLK must be the same clock (synchronous bridge).
//==============================================================================
module apb2ahb_bridge (
                clk,
                rst_n,

                // APB slave interface (connected to APB master)
                psel,
                penable,
                pwrite,
                paddr,
                pwdata,
                pstrb,
                pprot,
                prdata,
                pready,
                pslverr,

                // AHB-Lite master interface (connected to AHB slave)
                haddr,
                htrans,
                hwrite,
                hsize,
                hburst,
                hprot,
                hmastlock,
                hwdata,
                hwstrb,
                hrdata,
                hready,
                hresp
                );

parameter ADDR_WIDTH = 32;
parameter DATA_WIDTH = 32;              // 32 or 64

localparam STRB_WIDTH = DATA_WIDTH/8;

// AHB HTRANS encoding
localparam HTRANS_IDLE   = 2'b00;
localparam HTRANS_NONSEQ = 2'b10;

// AHB HSIZE for a full data-bus access
localparam HSIZE_FULL = (DATA_WIDTH == 64) ? 3'b011 : 3'b010;

// FSM states
localparam ST_IDLE = 2'b00;             // wait APB SETUP phase
localparam ST_ADDR = 2'b01;             // AHB address phase
localparam ST_DATA = 2'b10;             // AHB data phase
localparam ST_RESP = 2'b11;             // APB ACCESS phase completes (PREADY=1)

input                       clk;
input                       rst_n;

input                       psel;
input                       penable;
input                       pwrite;
input  [ADDR_WIDTH-1:0]     paddr;
input  [DATA_WIDTH-1:0]     pwdata;
input  [STRB_WIDTH-1:0]     pstrb;
input  [2:0]                pprot;
output [DATA_WIDTH-1:0]     prdata;
output                      pready;
output                      pslverr;

output [ADDR_WIDTH-1:0]     haddr;
output [1:0]                htrans;
output                      hwrite;
output [2:0]                hsize;
output [2:0]                hburst;
output [3:0]                hprot;
output                      hmastlock;
output [DATA_WIDTH-1:0]     hwdata;
output [STRB_WIDTH-1:0]     hwstrb;
input  [DATA_WIDTH-1:0]     hrdata;
input                       hready;
input                       hresp;

reg  [1:0]                  state;

reg  [ADDR_WIDTH-1:0]       haddr_r;
reg                         hwrite_r;
reg  [3:0]                  hprot_r;
reg  [DATA_WIDTH-1:0]       hwdata_r;
reg  [STRB_WIDTH-1:0]       hwstrb_r;

reg  [DATA_WIDTH-1:0]       prdata_r;
reg                         pslverr_r;

wire                        apb_setup;

//-----------------part 1 APB setup phase detect ------------------------------
assign apb_setup = psel & ~penable;

//-----------------part 2 bridge FSM ------------------------------------------
always @ (posedge clk or negedge rst_n)
    if (!rst_n)
        state <= #1 ST_IDLE;
    else
        case (state)
        ST_IDLE : if (apb_setup)    state <= #1 ST_ADDR;
        ST_ADDR : if (hready)       state <= #1 ST_DATA;   // address accepted
        ST_DATA : if (hready)       state <= #1 ST_RESP;   // data phase done
        ST_RESP :                   state <= #1 ST_IDLE;   // APB ACCESS ends
        default :                   state <= #1 ST_IDLE;
        endcase

//-----------------part 3 latch APB control/data in SETUP phase ---------------
// PPROT[0]: privileged, PPROT[1]: non-secure, PPROT[2]: instruction
// HPROT[0]: data,       HPROT[1]: privileged, HPROT[2]: bufferable, HPROT[3]: cacheable
always @ (posedge clk or negedge rst_n)
    if (!rst_n) begin
        haddr_r  <= #1 {ADDR_WIDTH{1'b0}};
        hwrite_r <= #1 1'b0;
        hprot_r  <= #1 4'b0011;
        hwdata_r <= #1 {DATA_WIDTH{1'b0}};
        hwstrb_r <= #1 {STRB_WIDTH{1'b0}};
    end
    else if ((state == ST_IDLE) && apb_setup) begin
        haddr_r  <= #1 paddr;
        hwrite_r <= #1 pwrite;
        hprot_r  <= #1 {2'b00, pprot[0], ~pprot[2]};
        hwdata_r <= #1 pwdata;
        hwstrb_r <= #1 pwrite ? pstrb : {STRB_WIDTH{1'b0}};
    end

//-----------------part 4 capture AHB response --------------------------------
always @ (posedge clk or negedge rst_n)
    if (!rst_n) begin
        prdata_r  <= #1 {DATA_WIDTH{1'b0}};
        pslverr_r <= #1 1'b0;
    end
    else if ((state == ST_DATA) && hready) begin
        prdata_r  <= #1 hwrite_r ? {DATA_WIDTH{1'b0}} : hrdata;
        pslverr_r <= #1 hresp;
    end
    else if (state == ST_RESP) begin
        pslverr_r <= #1 1'b0;
    end

//-----------------part 5 outputs ---------------------------------------------
// AHB
assign haddr     = haddr_r;
assign htrans    = (state == ST_ADDR) ? HTRANS_NONSEQ : HTRANS_IDLE;
assign hwrite    = hwrite_r;
assign hsize     = HSIZE_FULL;
assign hburst    = 3'b000;              // SINGLE
assign hprot     = hprot_r;
assign hmastlock = 1'b0;
assign hwdata    = hwdata_r;
assign hwstrb    = hwstrb_r;

// APB
assign pready    = (state == ST_RESP);
assign pslverr   = (state == ST_RESP) & pslverr_r;
assign prdata    = prdata_r;

endmodule
