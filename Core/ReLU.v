module ReLU #(
    parameter bits_ReLU = 16
)(
    input   ReLU_enable,
    input [bits_ReLU-1:0] ReLU_in,
    output [bits_ReLU-1:0] ReLU_out
);

	assign ReLU_out = ReLU_enable?((ReLU_in[bits_ReLU-1] == 1'b0)?ReLU_in:16'd0):ReLU_in;
endmodule