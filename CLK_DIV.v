//==============================================================================
// CLK_DIV : 整数时钟分频器（只使用 posedge 触发器，无负沿触发器）
//
//   div = 0      : clk_o = clk (bypass)
//   div = 1~2^n-1: clk_o = clk / (div+1)，奇偶分频均为 50% 占空比
//
//   时钟路径：clk_o = clk_p | ICG(clk, gen_en)
//     偶数分频 : gen_en 恒 0，clk_o = clk_p
//     奇数分频 : ICG 补出 clk_p 之后的半个周期（在 clk 下降沿结束）
//     bypass   : clk_p 恒 0，gen_en 恒 1，clk_o = clk
//
//   后端/STA 注意：
//     1. 对 U_CLKDIV_OR2 做 clock gating check：奇数分频时 clk_p 的下降沿
//        必须晚于 ICG 输出的上升沿（hold），否则会有毛刺
//     2. U_CLKDIV_ICG / U_CLKDIV_OR2 设置 dont_touch
//     3. DFT：ICG 的 SE 由 DFT 插入时连接；clk_o 需要 DFT autofix（测试 mux）
//==============================================================================
module CLK_DIV(
      clk  ,
      rstn ,
      div  ,
      clk_o
);

parameter div_width = 4;

input  wire                 clk   ;
input  wire                 rstn  ;
input  wire [div_width-1:0] div   ;
output wire                 clk_o ;

`ifdef FPGA
assign clk_o = clk;
`else

reg  [div_width-1:0] div_sync_1 ;
reg  [div_width-1:0] div_sync_2 ;
reg  [div_width-1:0] div_sync   ;
reg  [div_width-1:0] div_reg    ;
reg  [div_width-1:0] cnt_p      ;
reg                  clk_p      ;   // 分频主时钟
reg                  gen_en     ;   // ICG 使能

wire [div_width-1:0] half_div   ;   // = (div_reg+1)>>1，无溢出写法
wire                 clk_gate   ;

assign half_div = (div_reg >> 1) + {{(div_width-1){1'b0}}, div_reg[0]};

//------------------------------------------------------------
// div 同步
//------------------------------------------------------------
always@(posedge clk or negedge rstn) begin
  if (~rstn)
    div_sync_1 <= {div_width{1'b1}};
  else
    div_sync_1 <= div;
end

always@(posedge clk or negedge rstn) begin
  if (~rstn)
    div_sync_2 <= {div_width{1'b1}};
  else
    div_sync_2 <= div_sync_1;
end

always@(posedge clk or negedge rstn) begin
  if (~rstn)
    div_sync <= {div_width{1'b1}};
  else if (div_sync_1 == div_sync_2)
    div_sync <= div_sync_2;
end

//------------------------------------------------------------
// 分频比更新：只在一个分频周期结束时更新
//------------------------------------------------------------
always@(posedge clk or negedge rstn) begin
  if (~rstn)
    div_reg <= {div_width{1'b1}};
  else if (cnt_p == div_reg)
    div_reg <= div_sync;
end

//------------------------------------------------------------
// 计数器：0 ~ div_reg
//------------------------------------------------------------
always@(posedge clk or negedge rstn) begin
  if (~rstn)
    cnt_p <= {div_width{1'b0}};
  else if (cnt_p == div_reg)
    cnt_p <= {div_width{1'b0}};
  else
    cnt_p <= cnt_p + 1'b1;
end

//------------------------------------------------------------
// clk_p：cnt_p==0 后置 1，cnt_p==half_div 后清 0（清零优先）
//   高电平占 half_div 个 clk 周期
//   div_reg==0 时 half_div==0，清零恒优先 -> clk_p 恒 0
//------------------------------------------------------------
always@(posedge clk or negedge rstn) begin
  if (~rstn)
    clk_p <= 1'b0;
  else if (cnt_p == half_div)
    clk_p <= 1'b0;
  else if (cnt_p == {div_width{1'b0}})
    clk_p <= 1'b1;
end

//------------------------------------------------------------
// gen_en：ICG 使能
//   周期结束时，下一配置为 bypass(div=0) 或奇数分频(div 为偶数)，
//   即 div_sync[0]==0 时置 1；cnt_p==half_div 后清 0
//   bypass   ：每拍都是周期结束 -> 恒 1
//   奇数分频 ：比 clk_p 早一拍置 1、晚一拍清 0
//   偶数分频 ：恒 0
//------------------------------------------------------------
always@(posedge clk or negedge rstn) begin
  if (~rstn)
    gen_en <= 1'b0;
  else if (cnt_p == div_reg)
    gen_en <= (div_sync[0] == 1'b0);
  else if (cnt_p == half_div)
    gen_en <= 1'b0;
end

//------------------------------------------------------------
// 时钟路径：clk_o = clk_p | ICG(clk, gen_en)
//------------------------------------------------------------
P_CLK_GATE U_CLKDIV_ICG (
    .CLK   (clk     ),
    .EN    (gen_en  ),
    .SE    (1'b0    ),   // DFT 插入时自动连接
    .YGCLK (clk_gate)
);

OR2V2_8TR40 U_CLKDIV_OR2 (
    .A1 (clk_p   ),
    .A2 (clk_gate),
    .Z  (clk_o   )
);

`endif
endmodule
