module DFT_MODE_CTRL (
    input  wire  DFT_MODE_IN , //From Strap Pin
    output wire  DFT_MODE    ,

    input  wire  SRC_CLK     ,
    input  wire  SRC_RSTJ   
);

reg DFT_MODE_REG ;
always @ (posedge SRC_CLK )begin 
    if(!SRC_RSTJ )begin 
        DFT_MODE_REG <= DFT_MODE_IN ;
    end 
end 

P_CLK_BUF DFT_MODE_BUF (.A (DFT_MODE_REG), .Y(DFT_MODE) );

endmodule
