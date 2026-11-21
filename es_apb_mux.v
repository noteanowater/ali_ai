//==============================================================================
// es_apb_mux
//------------------------------------------------------------------------------
// Selects the APB master that owns the APB bus:
//   es_mode = 0 : CPU (normal function mode)
//   es_mode = 1 : spi2apb_bridge (ES test mode, SPI replaces CPU)
//
// es_mode is expected to be a static strap / test pin (stable after reset),
// so a plain combinational mux is used.  While es_mode = 1 the CPU port is
// answered with pready=1 / pslverr=1 so a running CPU can not hang on the bus.
//==============================================================================
module es_apb_mux (
    input             es_mode,

    // master 0 : CPU
    input      [31:0] cpu_paddr,
    input             cpu_psel,
    input             cpu_penable,
    input             cpu_pwrite,
    input      [31:0] cpu_pwdata,
    output     [31:0] cpu_prdata,
    output            cpu_pready,
    output            cpu_pslverr,

    // master 1 : SPI bridge
    input      [31:0] spi_paddr,
    input             spi_psel,
    input             spi_penable,
    input             spi_pwrite,
    input      [31:0] spi_pwdata,
    output     [31:0] spi_prdata,
    output            spi_pready,
    output            spi_pslverr,

    // to APB interconnect / decoder
    output     [31:0] m_paddr,
    output            m_psel,
    output            m_penable,
    output            m_pwrite,
    output     [31:0] m_pwdata,
    input      [31:0] m_prdata,
    input             m_pready,
    input             m_pslverr
);

assign m_paddr     = es_mode ? spi_paddr   : cpu_paddr;
assign m_psel      = es_mode ? spi_psel    : cpu_psel;
assign m_penable   = es_mode ? spi_penable : cpu_penable;
assign m_pwrite    = es_mode ? spi_pwrite  : cpu_pwrite;
assign m_pwdata    = es_mode ? spi_pwdata  : cpu_pwdata;

assign spi_prdata  = es_mode ? m_prdata  : 32'd0;
assign spi_pready  = es_mode ? m_pready  : 1'b1;
assign spi_pslverr = es_mode ? m_pslverr : 1'b1;

assign cpu_prdata  = es_mode ? 32'd0 : m_prdata;
assign cpu_pready  = es_mode ? 1'b1  : m_pready;
assign cpu_pslverr = es_mode ? 1'b1  : m_pslverr;

endmodule
