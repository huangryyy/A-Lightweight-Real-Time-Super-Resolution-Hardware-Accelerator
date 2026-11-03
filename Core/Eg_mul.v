

`timescale 1ns / 1ps
module Eg_mul_8#(
parameter bits_in = 12,
parameter bits_weight = 8,
parameter bits_out = 20,
parameter number_mul = 8
)(
input clk,
input rst,
input [(number_mul*bits_in)-1:0] I,
input [(number_mul*bits_weight)-1:0] H,
output wire [(number_mul*bits_out)-1:0] M
);

wire [bits_in-1:0] I_unsigned [0:number_mul-1];
wire signed [bits_in:0] I_signed [0:number_mul-1];
wire signed [bits_weight-1:0] Hsigned [0:number_mul-1];
wire signed [bits_out-1:0] Msigned [0:number_mul-1];

generate
    genvar i;
    for(i=0;i<number_mul;i=i+1) begin: in_name
        assign I_unsigned[number_mul-1-i] = I [(number_mul*bits_in)-(i*bits_in)-1-:bits_in];
    end
endgenerate

generate
    genvar j;
    for(j=0;j<number_mul;j=j+1) begin: wei_name
        assign Hsigned[number_mul-1-j] = H [(number_mul*bits_weight)-(j*bits_weight)-1-:bits_weight];
    end
endgenerate

generate
    genvar k;
    for(k=0;k<number_mul;k=k+1) begin: out_name
        assign M [(number_mul*bits_out)-(k*bits_out)-1-:bits_out] = Msigned [number_mul-1-k];
    end
endgenerate

genvar q;
generate
    for(q=0; q<number_mul; q=q+1)begin:multiplier
        Hsigned_mult_Isigned Hsigned_mult_Isigned_inst (
        .CLK(clk),   
        .A(Hsigned[q]),       
        .B(I_unsigned[q]),       
        .P(Msigned[q])      
        );
    end
endgenerate

endmodule 
