`timescale 1ns / 1ps
// Addition MUST precede clipping: e.g. 200 + (-100) = 100, not 27.
module residual_add_saturate #(
    parameter QUANT_BITS = 18
)(
    input wire signed [QUANT_BITS-1:0] quantized,
    input wire signed [7:0] residual,
    input wire last_layer,
    output wire [7:0] value
);
wire signed [QUANT_BITS:0] q_ext = {quantized[QUANT_BITS-1],quantized};
wire signed [QUANT_BITS:0] r_ext = {{(QUANT_BITS-7){residual[7]}},residual};
wire signed [QUANT_BITS:0] sum = q_ext + (last_layer ? r_ext : {(QUANT_BITS+1){1'b0}});
assign value = last_layer ? ((sum > 127) ? 8'h7f : (sum < -128) ? 8'h80 : sum[7:0]) :
                            ((sum > 255) ? 8'hff : (sum < 0) ? 8'h00 : sum[7:0]);
endmodule
