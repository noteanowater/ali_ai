//==============================================================================
// spi2apb_bridge
//------------------------------------------------------------------------------
// ES (Engineering Sample) mode debug path: an external SPI master (tester,
// FTDI/MCU board, ATE) replaces the CPU and drives the on-chip APB bus, so APB
// IPs can be configured/read back to check that the silicon is alive.
//
// SPI  : slave, Mode 0 (CPOL=0, CPHA=0), MSB first, cs_n active low.
//        sclk/cs_n/mosi are oversampled in the pclk domain (single clock
//        domain design, no async FIFO).  Requirement: f_pclk >= 8 * f_sclk.
//
// APB  : APB3 master (psel/penable/pwrite/paddr/pwdata/prdata/pready/pslverr),
//        with a pready timeout so a hung slave can not lock the bridge.
//
// Frame formats (one frame per cs_n low period):
//   WRITE  0x02 : MOSI  [CMD 8][ADDR 32][WDATA 32]                 = 72 sclk
//                 APB write is launched after the last WDATA bit.
//   READ   0x03 : MOSI  [CMD 8][ADDR 32][DUMMY 8][xxxx 32]         = 80 sclk
//                 MISO                           [RDATA 32]
//                 APB read is launched after the last ADDR bit and must be
//                 finished within the 8 dummy cycles (else STATUS.rd_late=1
//                 and RDATA returns 0).
//   STATUS 0x05 : MOSI  [CMD 8][xxxx 8]                            = 16 sclk
//                 MISO       [STATUS 8]
//                 STATUS = {3'b0, drop, rd_late, timeout, slverr, busy}
//                 Sticky flags (bit4..1) are cleared by reading STATUS.
//   ID     0x9F : MOSI  [CMD 8][xxxx 32]                           = 40 sclk
//                 MISO       [BRIDGE_ID 32]
//                 Pure SPI loopback check, does not touch APB.
//==============================================================================
module spi2apb_bridge #(
    parameter [31:0] BRIDGE_ID      = 32'h5A50_4931,  // "ZPI1"
    parameter        TIMEOUT_CYCLES = 1024            // pready timeout (pclk)
)(
    input             pclk,
    input             presetn,
    input             es_mode,       // 1: bridge enabled

    // SPI slave pins
    input             spi_sclk,
    input             spi_cs_n,
    input             spi_mosi,
    output            spi_miso,
    output            spi_miso_oe,   // tri-state enable for the MISO pad

    // APB3 master
    output reg [31:0] paddr,
    output reg        psel,
    output reg        penable,
    output reg        pwrite,
    output reg [31:0] pwdata,
    input      [31:0] prdata,
    input             pready,
    input             pslverr
);

localparam [7:0] CMD_WRITE  = 8'h02;
localparam [7:0] CMD_READ   = 8'h03;
localparam [7:0] CMD_STATUS = 8'h05;
localparam [7:0] CMD_ID     = 8'h9F;

// last bit index (0 based) of each field
localparam [6:0] BIT_CMD_END   = 7'd7;
localparam [6:0] BIT_ADDR_END  = 7'd39;
localparam [6:0] BIT_DUMMY_END = 7'd47;
localparam [6:0] BIT_WDATA_END = 7'd71;

//------------------------------------------------------------------------------
// part 1 : synchronize SPI pins into pclk domain, detect sclk edges
//------------------------------------------------------------------------------
reg [2:0] sclk_sync;
reg [1:0] cs_n_sync;
reg [1:0] mosi_sync;

always @(posedge pclk or negedge presetn)
    if (!presetn) begin
        sclk_sync <= 3'b000;
        cs_n_sync <= 2'b11;
        mosi_sync <= 2'b00;
    end
    else begin
        sclk_sync <= {sclk_sync[1:0], spi_sclk};
        cs_n_sync <= {cs_n_sync[0],   spi_cs_n};
        mosi_sync <= {mosi_sync[0],   spi_mosi};
    end

wire mosi_s    = mosi_sync[1];                  // aligned with sclk_sync[1]
wire cs_act    = es_mode & ~cs_n_sync[1];
wire sclk_rise = cs_act &  sclk_sync[1] & ~sclk_sync[2];
wire sclk_fall = cs_act & ~sclk_sync[1] &  sclk_sync[2];

//------------------------------------------------------------------------------
// part 2 : SPI receive shifter / frame decode
//------------------------------------------------------------------------------
reg  [6:0]  bit_cnt;     // index of the bit being received
reg  [31:0] rx_shift;
reg  [7:0]  cmd;
reg  [31:0] addr;

wire [31:0] rx_word = {rx_shift[30:0], mosi_s};

always @(posedge pclk or negedge presetn)
    if (!presetn) begin
        bit_cnt  <= 7'd0;
        rx_shift <= 32'd0;
        cmd      <= 8'd0;
        addr     <= 32'd0;
    end
    else if (!cs_act) begin
        bit_cnt  <= 7'd0;
        cmd      <= 8'd0;
    end
    else if (sclk_rise) begin
        rx_shift <= rx_word;
        if (bit_cnt != 7'h7f)
            bit_cnt <= bit_cnt + 7'd1;
        if (bit_cnt == BIT_CMD_END)  cmd  <= rx_word[7:0];
        if (bit_cnt == BIT_ADDR_END) addr <= rx_word;
    end

// single-cycle requests towards the APB master
wire wr_req     = sclk_rise & (bit_cnt == BIT_WDATA_END) & (cmd == CMD_WRITE);
wire rd_req     = sclk_rise & (bit_cnt == BIT_ADDR_END)  & (cmd == CMD_READ);
wire rd_load    = sclk_rise & (bit_cnt == BIT_DUMMY_END) & (cmd == CMD_READ);
wire cmd_done   = sclk_rise & (bit_cnt == BIT_CMD_END);
wire status_rd  = cmd_done  & (rx_word[7:0] == CMD_STATUS);
wire id_rd      = cmd_done  & (rx_word[7:0] == CMD_ID);

//------------------------------------------------------------------------------
// part 3 : APB3 master FSM + status flags
//------------------------------------------------------------------------------
localparam [1:0] ST_IDLE   = 2'd0;
localparam [1:0] ST_SETUP  = 2'd1;
localparam [1:0] ST_ACCESS = 2'd2;

reg [1:0]  apb_st;
reg [15:0] to_cnt;
reg [31:0] rdata_r;
reg        rdata_vld;
reg        slverr_f, timeout_f, rd_late_f, drop_f;

wire busy     = (apb_st != ST_IDLE);
wire apb_req  = wr_req | rd_req;
wire [7:0] status = {3'b000, drop_f, rd_late_f, timeout_f, slverr_f, busy};

always @(posedge pclk or negedge presetn)
    if (!presetn) begin
        apb_st    <= ST_IDLE;
        psel      <= 1'b0;
        penable   <= 1'b0;
        pwrite    <= 1'b0;
        paddr     <= 32'd0;
        pwdata    <= 32'd0;
        to_cnt    <= 16'd0;
        rdata_r   <= 32'd0;
        rdata_vld <= 1'b0;
    end
    else begin
        case (apb_st)
        ST_IDLE:
            if (apb_req) begin
                psel   <= 1'b1;
                pwrite <= wr_req;
                paddr  <= wr_req ? addr : rx_word;   // read addr = word just received
                pwdata <= rx_word;                   // only meaningful for write
                if (rd_req) rdata_vld <= 1'b0;
                apb_st <= ST_SETUP;
            end
        ST_SETUP: begin
            penable <= 1'b1;
            to_cnt  <= 16'd0;
            apb_st  <= ST_ACCESS;
        end
        ST_ACCESS:
            if (pready) begin
                psel    <= 1'b0;
                penable <= 1'b0;
                if (!pwrite) begin
                    rdata_r   <= prdata;
                    rdata_vld <= 1'b1;
                end
                apb_st  <= ST_IDLE;
            end
            else if (to_cnt == TIMEOUT_CYCLES - 1) begin
                psel    <= 1'b0;
                penable <= 1'b0;
                apb_st  <= ST_IDLE;
            end
            else
                to_cnt <= to_cnt + 16'd1;
        default:
            apb_st <= ST_IDLE;
        endcase
    end

// sticky flags: set has priority over clear (clear = STATUS command)
wire set_slverr  = (apb_st == ST_ACCESS) & pready & pslverr;
wire set_timeout = (apb_st == ST_ACCESS) & ~pready & (to_cnt == TIMEOUT_CYCLES - 1);
wire set_rd_late = rd_load & ~rdata_vld;
wire set_drop    = apb_req & busy;

always @(posedge pclk or negedge presetn)
    if (!presetn) begin
        slverr_f  <= 1'b0;
        timeout_f <= 1'b0;
        rd_late_f <= 1'b0;
        drop_f    <= 1'b0;
    end
    else begin
        slverr_f  <= set_slverr  | (slverr_f  & ~status_rd);
        timeout_f <= set_timeout | (timeout_f & ~status_rd);
        rd_late_f <= set_rd_late | (rd_late_f & ~status_rd);
        drop_f    <= set_drop    | (drop_f    & ~status_rd);
    end

//------------------------------------------------------------------------------
// part 4 : SPI transmit shifter (MISO changes on sclk falling edge, Mode 0)
//------------------------------------------------------------------------------
reg [31:0] tx_shift;
reg        miso_r;

always @(posedge pclk or negedge presetn)
    if (!presetn) begin
        tx_shift <= 32'd0;
        miso_r   <= 1'b0;
    end
    else if (!cs_act) begin
        tx_shift <= 32'd0;
        miso_r   <= 1'b0;
    end
    else if (status_rd)
        tx_shift <= {status, 24'd0};
    else if (id_rd)
        tx_shift <= BRIDGE_ID;
    else if (rd_load)
        tx_shift <= rdata_vld ? rdata_r : 32'd0;
    else if (sclk_fall) begin
        miso_r   <= tx_shift[31];
        tx_shift <= {tx_shift[30:0], 1'b0};
    end

assign spi_miso    = miso_r;
assign spi_miso_oe = cs_act;

endmodule
