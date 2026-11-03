`timescale 1ns / 1ps

module Mac_8x8 #(
    parameter number_ew = 8,
    parameter number_eg = 8,
    parameter bits_input  = 12, 
    parameter bits_weight = 8,
    parameter bits_bias   = 8,
    parameter bits_eleout = 20,
    parameter bits_addout = 23,
    parameter bits_macout = 12
)(
    input clk,
    input rst,
    input done_re,
    input mac_reset,
    input [number_ew*bits_input-1:0] share_mac_in_act,
    input [number_ew*number_eg*bits_weight-1:0] mac_mul_wei,
    input [number_eg*bits_bias-1:0] mac_add_bias,
    output  [number_eg*bits_macout-1:0] mac_out
    );

wire [bits_weight*number_ew-1:0]  eg_wei [0:number_eg-1];
wire [bits_eleout*number_ew-1:0]  ele_out [0:number_eg-1];
wire [bits_addout*number_eg-1:0]  add_out_gather;
wire [bits_addout-1:0]  add_out [0:number_eg-1];

genvar i; 
generate 
    for(i=0; i < number_eg; i=i+1) begin
        assign eg_wei[i] = mac_mul_wei[(number_ew*bits_weight*number_eg)-(i*bits_weight*number_ew)-1-:bits_weight*number_ew];
   end
endgenerate 

genvar r;
generate 
    for(r=0; r < number_eg; r=r+1) begin
        assign add_out_gather[(number_eg*bits_addout)-(r*bits_addout)-1-:bits_addout] = add_out[r];
   end
endgenerate 

genvar j;
generate
    for(j=0; j < number_eg; j=j+1) begin: gen_eg
        Eg_mul_8 #(
    .bits_in(bits_input),
    .bits_weight(bits_weight),
    .bits_out(bits_eleout),
    .number_mul(number_ew)
   )Eg_mul_8_insi(
    .clk(clk),
    .rst(rst),
    .I(share_mac_in_act),
    .H(eg_wei[j]),
    .M(ele_out[j])
); 

    end
endgenerate



genvar q;
generate
    for(q=0; q < number_eg; q=q+1) begin: gen_add
        adder #(
    .bits_input(bits_eleout),
    .bits_out(bits_addout),
    .number_add(number_ew) 
   )adder_insi(
    .Data_i(ele_out[q]),
    .Result_o(add_out[q])
); 

    end
endgenerate

acc_1x8 #(
    .bits_input(bits_addout),
    .bits_bias(bits_bias),
    .bits_out(bits_macout),
    .number_add(number_eg)
)acc_1x8_insi(
    .clk(clk),
    .rst(rst),
    .done_re(done_re),
    .mac_reset(mac_reset),
    .Data_i(add_out_gather),
    .Bias(mac_add_bias),
    .Result_o(mac_out)
); 

endmodule
