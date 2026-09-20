module clk_switch_2to1 (
                test_mode,
                test_se,
                rst_n,
                clka,
                clkb,

                select,
                sel_clk,

                clk_o
                );
input test_mode;
input test_se;
input rst_n;
input clka,clkb;
input select;
input sel_clk;
output clk_o;


reg sel_clka_d0,sel_clka_d1;
reg sel_clka_dly1,sel_clka_dly2,sel_clka_dly3;

reg sel_clkb_d0,sel_clkb_d1;
reg sel_clkb_dly1,sel_clkb_dly2,sel_clkb_dly3;

reg sel_clka,sel_clkb;

wire clka_g,clkb_g;

//-----------------part 1 genarate each clock select and latch to DFF ---------------------

always @ (posedge sel_clk or negedge rst_n)
    if (!rst_n)
        sel_clka <= #1 1'b0;
    else if (select==1'b0)
        sel_clka <= #1 1'b1;
    else
        sel_clka <= #1 1'b0;


always @ (posedge sel_clk or negedge rst_n)
    if (!rst_n)
        sel_clkb <= #1 1'b0;
    else if (select==1'b1)
        sel_clkb <= #1 1'b1;
    else
        sel_clkb <= #1 1'b0;


//-----------------part 2 generate  each clock gate enable control---------------------
always @ (posedge clka or negedge rst_n)
begin
    if (!rst_n) begin
        sel_clka_d0 <= 1'b0;
        sel_clka_d1 <= 1'b0;
    end
    else begin
        sel_clka_d0 <= sel_clka & (~sel_clkb_dly3);
        sel_clka_d1 <= sel_clka_d0 ;
    end
end


always @ (posedge clka or negedge rst_n)
begin
    if (!rst_n) begin
        sel_clka_dly1 <= 1'b0;
        sel_clka_dly2 <= 1'b0;
        sel_clka_dly3 <= 1'b0;
    end
    else begin
        sel_clka_dly1 <= sel_clka_d1;
        sel_clka_dly2 <= sel_clka_dly1 ;
        sel_clka_dly3 <= sel_clka_dly2 ;
    end
end

//-----------------part 2 generate  each clock gate enable control---------------------
always @ (posedge clkb or negedge rst_n)
begin
    if (!rst_n) begin
        sel_clkb_d0 <= 1'b0;
        sel_clkb_d1 <= 1'b0;
    end
    else begin
        sel_clkb_d0 <= sel_clkb & (~sel_clka_dly3);
        sel_clkb_d1 <= sel_clkb_d0 ;
    end
end


always @ (posedge clkb or negedge rst_n)
begin
    if (!rst_n) begin
        sel_clkb_dly1 <= 1'b0;
        sel_clkb_dly2 <= 1'b0;
        sel_clkb_dly3 <= 1'b0;
    end
    else begin
        sel_clkb_dly1 <= sel_clkb_d1   ;
        sel_clkb_dly2 <= sel_clkb_dly1 ;
        sel_clkb_dly3 <= sel_clkb_dly2 ;
    end
end


//-----------------part 3 each clk have its own gated clk---------------------

wire CLK_GATE_EN_A =  test_mode ? 1: sel_clka_dly3;
wire CLK_GATE_EN_B =  test_mode ? 1: sel_clkb_dly3;

P1_CLK_GATE I_P1_CLK_GATE_a (
                        .CLK      (clka          ),
                        .EN       (CLK_GATE_EN_A ),
                        .SE       (test_se       ),
                        .YGCLK    (clka_g   )
                        );


P1_CLK_GATE I_P1_CLK_GATE_b (
                        .CLK      (clkb          ),
                        .EN       (CLK_GATE_EN_B ),
                        .SE       (test_se       ),
                        .YGCLK    (clkb_g   )
                        );

//-----------------part 4 output the final muxed and gated clk---------------------
//assign clk_o = clka_g | clkb_g;

OR2_X6B_A7PP140ZTL_C35 U_CLOCK_OR2_1 (.A(clka_g),.B(clkb_g),.Y(clk_o));


endmodule
