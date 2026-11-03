`timescale 1ns / 1ps
module acc_1x8#(
    parameter bits_input = 22,
    parameter bits_bias = 8,
    parameter bits_out = 12 ,  
    parameter number_add = 8
)(
    input   wire                                clk,
    input   wire                                rst,
    input   wire                                done_re,
    input   wire                                mac_reset,
    input   wire    [bits_input*number_add-1: 0]              Data_i,
    input   wire    [bits_bias*number_add-1: 0]              Bias,
    output  wire    [bits_out*number_add-1: 0]             Result_o
);

genvar q;
generate
    for (q=0;q<number_add;q=q+1) begin: acc_gen
        Acc_1 #(
            .bits_input(bits_input),
            .bits_bias(bits_bias),
            .bits_out(bits_out)   
        ) acc_q (
            .clk(clk),
            .rst(rst),
            .done_re(done_re),
            .mac_reset(mac_reset),
            .Data_i(Data_i[bits_input*(number_add-q)-1-:bits_input]),
            .Bias(Bias[bits_bias*(number_add-q)-1-:bits_bias]),
            .Result_o(Result_o[bits_out*(number_add-q)-1-:bits_out])
        );
    end
endgenerate

endmodule

