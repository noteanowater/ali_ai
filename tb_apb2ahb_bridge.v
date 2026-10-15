`timescale 1ns/1ps
//==============================================================================
// Testbench for apb2ahb_bridge
//   - APB master BFM (tasks apb_write / apb_read)
//   - AHB-Lite slave model: 256-word memory, random wait states,
//     two-cycle ERROR response for addresses >= 32'h0000_F000
//==============================================================================
module tb_apb2ahb_bridge;

reg         clk;
reg         rst_n;

reg         psel, penable, pwrite;
reg  [31:0] paddr, pwdata;
reg  [3:0]  pstrb;
reg  [2:0]  pprot;
wire [31:0] prdata;
wire        pready, pslverr;

wire [31:0] haddr;
wire [1:0]  htrans;
wire        hwrite;
wire [2:0]  hsize, hburst;
wire [3:0]  hprot;
wire        hmastlock;
wire [31:0] hwdata;
wire [3:0]  hwstrb;
reg  [31:0] hrdata;
reg         hready;
reg         hresp;

integer     errors;

apb2ahb_bridge u_dut (
    .clk(clk), .rst_n(rst_n),
    .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr),
    .pwdata(pwdata), .pstrb(pstrb), .pprot(pprot),
    .prdata(prdata), .pready(pready), .pslverr(pslverr),
    .haddr(haddr), .htrans(htrans), .hwrite(hwrite), .hsize(hsize),
    .hburst(hburst), .hprot(hprot), .hmastlock(hmastlock),
    .hwdata(hwdata), .hwstrb(hwstrb), .hrdata(hrdata),
    .hready(hready), .hresp(hresp)
);

initial clk = 1'b0;
always #5 clk = ~clk;

//------------------------------------------------------------------------------
// AHB-Lite slave model
//------------------------------------------------------------------------------
reg  [31:0] mem [0:255];
reg         dp_valid, dp_write, dp_err;
reg  [7:0]  dp_idx;
reg  [3:0]  dp_strb;
integer     wait_cnt;
integer     i;

always @ (posedge clk or negedge rst_n)
    if (!rst_n) begin
        dp_valid <= 1'b0;
        hready   <= 1'b1;
        hresp    <= 1'b0;
        hrdata   <= 32'h0;
        wait_cnt <= 0;
    end
    else begin
        // ---- data phase ----
        if (dp_valid && (!hready || hresp)) begin
            if (dp_err) begin
                if (!hready) begin          // 2nd cycle of ERROR
                    hready   <= 1'b1;
                    dp_valid <= 1'b0;
                end
                else hresp <= 1'b0;
            end
            else if (wait_cnt > 0) begin
                wait_cnt <= wait_cnt - 1;
            end
            else begin
                if (dp_write) begin
                    for (i = 0; i < 4; i = i + 1)
                        if (dp_strb[i]) mem[dp_idx][i*8 +: 8] <= hwdata[i*8 +: 8];
                end
                else hrdata <= mem[dp_idx];
                hready   <= 1'b1;
                dp_valid <= 1'b0;
            end
        end
        else if (hresp) begin
            hresp <= 1'b0;
        end
        else begin
            dp_valid <= 1'b0;
        end

        // ---- address phase sampled ----
        if (hready && htrans[1]) begin
            dp_valid <= 1'b1;
            dp_write <= hwrite;
            dp_idx   <= haddr[9:2];
            dp_strb  <= hwstrb;
            dp_err   <= (haddr >= 32'h0000_F000);
            if (haddr >= 32'h0000_F000) begin
                hready <= 1'b0;             // 1st cycle of ERROR
                hresp  <= 1'b1;
            end
            else begin
                hready   <= 1'b0;
                wait_cnt <= $random & 3;    // 0..3 extra wait states
            end
        end
    end

// protocol checks
always @ (posedge clk)
    if (rst_n && htrans == 2'b10) begin
        if (hsize != 3'b010 || hburst != 3'b000 || hmastlock) begin
            $display("ERROR: bad AHB control at %0t", $time);
            errors = errors + 1;
        end
    end

//------------------------------------------------------------------------------
// APB master BFM
//------------------------------------------------------------------------------
task apb_write;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  strb;
    output       err;
    begin
        @(posedge clk);
        psel <= 1'b1; penable <= 1'b0; pwrite <= 1'b1;
        paddr <= addr; pwdata <= data; pstrb <= strb;
        @(posedge clk);
        penable <= 1'b1;
        @(posedge clk);
        while (!pready) @(posedge clk);
        err = pslverr;
        psel <= 1'b0; penable <= 1'b0;
    end
endtask

task apb_read;
    input  [31:0] addr;
    output [31:0] data;
    output        err;
    begin
        @(posedge clk);
        psel <= 1'b1; penable <= 1'b0; pwrite <= 1'b0;
        paddr <= addr; pstrb <= 4'h0;
        @(posedge clk);
        penable <= 1'b1;
        @(posedge clk);
        while (!pready) @(posedge clk);
        data = prdata;
        err  = pslverr;
        psel <= 1'b0; penable <= 1'b0;
    end
endtask

//------------------------------------------------------------------------------
// Stimulus
//------------------------------------------------------------------------------
reg  [31:0] rd;
reg         er;
reg  [31:0] exp [0:15];
integer     k;

initial begin
    errors = 0;
    rst_n = 1'b0; psel = 0; penable = 0; pwrite = 0;
    paddr = 0; pwdata = 0; pstrb = 0; pprot = 3'b000;
    for (k = 0; k < 256; k = k + 1) mem[k] = 32'h0;
    repeat (3) @(posedge clk);
    rst_n <= 1'b1;

    // full-word writes then reads
    for (k = 0; k < 16; k = k + 1) begin
        exp[k] = $random;
        apb_write(k*4, exp[k], 4'hF, er);
        if (er) begin $display("ERROR: unexpected PSLVERR on write %0d", k); errors = errors + 1; end
    end
    for (k = 0; k < 16; k = k + 1) begin
        apb_read(k*4, rd, er);
        if (er || rd !== exp[k]) begin
            $display("ERROR: read addr %h got %h exp %h err %b", k*4, rd, exp[k], er);
            errors = errors + 1;
        end
    end

    // byte-strobe write
    apb_write(32'h0, 32'hAABBCCDD, 4'b0101, er);
    apb_read (32'h0, rd, er);
    if (rd !== {exp[0][31:24], 8'hBB, exp[0][15:8], 8'hDD}) begin
        $display("ERROR: strobe write got %h", rd); errors = errors + 1;
    end

    // error response
    apb_write(32'h0000_F000, 32'h1234_5678, 4'hF, er);
    if (!er) begin $display("ERROR: PSLVERR missing on write"); errors = errors + 1; end
    apb_read (32'h0000_F004, rd, er);
    if (!er) begin $display("ERROR: PSLVERR missing on read"); errors = errors + 1; end

    // normal access after error
    apb_read(32'h4, rd, er);
    if (er || rd !== exp[1]) begin $display("ERROR: read after error"); errors = errors + 1; end

    repeat (5) @(posedge clk);
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED, %0d errors", errors);
    $finish;
end

initial begin
    #100000;
    $display("ERROR: timeout");
    $finish;
end

endmodule
