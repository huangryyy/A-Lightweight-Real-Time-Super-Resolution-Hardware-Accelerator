`timescale 1ns/1ps
module fifo_top_controller(input srst,clk,input[511:0]din,input wr_en,rd_en,output reg[511:0]dout);
reg[511:0]mem[0:63];integer wp=0,rp=0;
always@(posedge clk)if(srst)begin wp<=0;rp<=0;dout<=0;end else begin
 if(wr_en)begin mem[wp]<=din;wp<=wp+1;end
 if(rd_en)begin dout<=mem[rp];rp<=rp+1;end
end
endmodule
module fifo_512din_512dout_512d(input srst,clk,input[511:0]din,input wr_en,rd_en,
 output[511:0]dout,output full,empty,valid,prog_full);
reg[511:0]mem[0:63];integer wp=0,rp=0;
always@(posedge clk)if(srst)begin wp<=0;rp<=0;end else begin
 if(wr_en)begin mem[wp]<=din;wp<=wp+1;end
 if(rd_en)rp<=rp+1;
end
assign dout=mem[rp];assign empty=(wp==rp);assign valid=!empty;
assign full=(wp-rp==64);assign prog_full=(wp-rp>=60);
endmodule
