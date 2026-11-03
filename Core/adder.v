`timescale 1ns / 1ps
module adder#(
    parameter bits_input = 20,
    parameter bits_out = 23 ,  
    parameter number_add = 8
)(
    input   wire    [bits_input*number_add-1: 0]   Data_i ,
    output  wire    [bits_out-1: 0]             Result_o 
);


wire [bits_input-1:0]  Data [0:number_add-1];

genvar i; 
generate 
    for(i=0; i < number_add; i=i+1) begin
        assign Data[i] = Data_i[bits_input*number_add-i*bits_input-1-:bits_input];
   end
endgenerate 

wire [bits_input:0] Result_17;
wire [bits_input+1:0] Result_18;
wire [bits_input+2:0] Result_19;
wire [bits_input+3:0] Result_20;
wire [bits_input+4:0] Result_21;
wire [bits_input+5:0] Result_22;
wire [bits_input+6:0] Result_23;
wire [bits_input+7:0] Result_24;
wire [bits_input+8:0] Result_25;
wire [bits_input+9:0] Result_26;
wire [bits_input+10:0] Result_27;
wire [bits_input+11:0] Result_28;
wire [bits_input+12:0] Result_29;
wire [bits_input+13:0] Result_30;

assign Result_17 = {Data[0][bits_input-1],Data[0]} + {Data[1][bits_input-1],Data[1]};
assign Result_18 = {Result_17[bits_input],Result_17} + {{2{Data[2][bits_input-1]}},Data[2]};
assign Result_19 = {Result_18[bits_input+1],Result_18} + {{3{Data[3][bits_input-1]}},Data[3]};
assign Result_20 = {Result_19[bits_input+2],Result_19} + {{4{Data[4][bits_input-1]}},Data[4]};
assign Result_21 = {Result_20[bits_input+3],Result_20} + {{5{Data[5][bits_input-1]}},Data[5]};
assign Result_22 = {Result_21[bits_input+4],Result_21} + {{6{Data[6][bits_input-1]}},Data[6]};
assign Result_23 = {Result_22[bits_input+5],Result_22} + {{7{Data[7][bits_input-1]}},Data[7]};
assign Result_24 = {Result_23[bits_input+6],Result_23} + {{8{Data[8][bits_input-1]}},Data[8]};
assign Result_25 = {Result_24[bits_input+7],Result_24} + {{9{Data[9][bits_input-1]}},Data[9]};
assign Result_26 = {Result_25[bits_input+8],Result_25} + {{10{Data[10][bits_input-1]}},Data[10]};
assign Result_27 = {Result_26[bits_input+9],Result_26} + {{11{Data[11][bits_input-1]}},Data[11]};
assign Result_28 = {Result_27[bits_input+10],Result_27} + {{12{Data[12][bits_input-1]}},Data[12]};
assign Result_29 = {Result_28[bits_input+11],Result_28} + {{13{Data[13][bits_input-1]}},Data[13]};
assign Result_30 = {Result_29[bits_input+12],Result_29} + {{14{Data[14][bits_input-1]}},Data[14]};
assign Result_o  = {Result_30[bits_input+13],Result_30} + {{15{Data[15][bits_input-1]}},Data[15]};


// assign  Result_o = Data[0] + Data[1] + Data[2] + Data[3] + Data[4] + Data[5] + Data[6]+ Data[7] + Data[8] + Data[9] + Data[10] + Data[11] + Data[12] + Data[13] + Data[14] + Data[15]; 

endmodule 