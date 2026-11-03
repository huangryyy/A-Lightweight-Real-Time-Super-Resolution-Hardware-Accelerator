`timescale 1ns / 1ps
// Four original C0 samples per 512-bit feature word, retained across all layers.
// 16384 words cover the 14400 words of a 320x180 input frame.
module global_residual_store #(
    parameter ADDR_WIDTH = 16,
    parameter MEM_ADDR_WIDTH = 14
)(
    input wire clk,
    input wire write_enable,
    input wire [ADDR_WIDTH-1:0] write_addr,
    input wire [511:0] input_word,
    input wire read_enable,
    input wire [ADDR_WIDTH-1:0] read_addr,
    output reg [31:0] residual_word
);
(* ram_style = "block" *) reg [31:0] mem [0:(1<<MEM_ADDR_WIDTH)-1];
always @(posedge clk) begin
    if (write_enable)
        mem[write_addr[MEM_ADDR_WIDTH-1:0]] <=
            {input_word[511:504],input_word[383:376],input_word[255:248],input_word[127:120]};
    if (read_enable)
        residual_word <= mem[read_addr[MEM_ADDR_WIDTH-1:0]];
end
`ifndef SYNTHESIS
always @(posedge clk) begin
    if (write_enable && (write_addr >> MEM_ADDR_WIDTH))
        $fatal(1,"Global residual write exceeds frame memory");
    if (read_enable && (read_addr >> MEM_ADDR_WIDTH))
        $fatal(1,"Global residual read exceeds frame memory");
end
`endif
endmodule
