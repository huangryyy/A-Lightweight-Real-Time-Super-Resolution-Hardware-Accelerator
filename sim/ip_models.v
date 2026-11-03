`timescale 1ns/1ps
// Test-only models: BRAM read latency=1; both multiplier pipelines=3 cycles,
// matching the existing Vivado XCI settings. Not synthesis sources.
module blk_mem_gen_input(input clka,ena,wea,input [15:0] addra,input [511:0] dina,output reg[511:0] douta,
 input clkb,enb,web,input[15:0]addrb,input[511:0]dinb,output reg[511:0]doutb);
reg[511:0]mem[0:16383];
always@(posedge clka)if(ena)begin if(wea)mem[addra]<=dina;else douta<=mem[addra];end
always@(posedge clkb)if(enb)begin if(web)mem[addrb]<=dinb;else doutb<=mem[addrb];end
endmodule
module blk_mem_gen_weight(input clka,ena,wea,input[7:0]addra,input[2047:0]dina,output reg[2047:0]douta);
reg[2047:0]mem[0:255];
always@(posedge clka)if(ena)begin if(wea)mem[addra]<=dina;else douta<=mem[addra];end
endmodule
module blk_mem_gen_output(input clka,ena,wea,input[15:0]addra,input[511:0]dina,output reg[511:0]douta);
reg[511:0]mem[0:16383];
always@(posedge clka)if(ena)begin if(wea)mem[addra]<=dina;else douta<=mem[addra];end
endmodule
module Hsigned_mult_Isigned(input CLK,input signed[7:0]A,input[7:0]B,output reg signed[15:0]P);
reg signed[7:0]a;reg[7:0]b;reg signed[15:0]m;
always@(posedge CLK)begin a<=A;b<=B;m<=a*$signed({1'b0,b});P<=m;end
endmodule
module mult_quantization_scale(input CLK,input signed[17:0]A,input signed[15:0]B,output reg signed[33:0]P);
reg signed[17:0]a;reg signed[15:0]b;reg signed[33:0]m;
always@(posedge CLK)begin a<=A;b<=B;m<=a*b;P<=m;end
endmodule
