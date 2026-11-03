`timescale 1ns / 1ps
module Acc_1#(
    parameter bits_input = 22,
    parameter bits_bias = 8,
    parameter bits_out = 18   
)   (
    input   wire                                clk,
    input   wire                                rst,
    input   wire                                done_re,      
    input   wire                                mac_reset,      
    input   wire    [bits_input-1: 0]           Data_i,
    input   wire    [bits_bias-1: 0]            Bias,
    output  wire    [bits_out-1: 0]             Result_o
);

localparam extra_width = 3;

reg signed [bits_input+extra_width-1: 0] Data_temp_reg;
wire signed [bits_input+extra_width+1-1: 0] Data_add_bias;

wire signed [bits_input+extra_width-1: 0] Data_i_ext ;
assign Data_i_ext = {{extra_width{Data_i[bits_input-1]}},Data_i};

wire signed [bits_input+extra_width:0] Bias_ext;
assign Bias_ext = {{(bits_input+extra_width+1-bits_bias){Bias[bits_bias-1]}},Bias};

always @(posedge clk or negedge rst) begin
    if(!rst)begin
        Data_temp_reg <= 'b0;
    end
    else begin
        if(mac_reset)
            Data_temp_reg <= 'd0;
        else if(done_re)
            Data_temp_reg <= Data_i_ext;
        else 
            Data_temp_reg <= Data_temp_reg + Data_i_ext; 
    end
end

assign Data_add_bias = {Data_temp_reg[bits_input+extra_width-1], Data_temp_reg} + Bias_ext;

wire signed [bits_out-1:0] max_val = (1 << (bits_out-1)) - 1;
wire signed [bits_out-1:0] min_val = ~(max_val);
assign Result_o = ($signed(Data_add_bias) < min_val) ? min_val : 
                  (($signed(Data_add_bias) > max_val) ? max_val : Data_add_bias[bits_out-1:0]);

endmodule