
`timescale 1ns / 1ps
module Processing_group #(
    parameter depth_inp  = 2048,
    parameter addr_bit_inp = 11,
    parameter depth_bias = 64,
    parameter addr_bit_bias = 128,
    parameter depth_out  = 2048,
    parameter addr_bit_out = 11,
    parameter pixel_para = 4,
    parameter number_add = 8,
    parameter bits_input  = 8, 
    parameter bits_weight = 8,
    parameter bits_bias   = 16,
    parameter bits_eleout = 20,
    parameter bits_addout = 23,
    parameter bits_macout = 18,
    parameter bits_quantout = 8,
    parameter ic_para = 8,
    parameter oc_para = 8,
    parameter PIX_W = ic_para * bits_input
)(
    input clk,
    input rst,
    input ReLU_enable,
    input first_layer,
    input last_layer,
    input done_re,
    input mac_reset,
    input [15:0] channel,
    input [15:0] pixel_h,
    input [15:0] pixel_w,
    input [pixel_para*ic_para*bits_input-1:0] wData_inp,
    input [addr_bit_inp-1:0] wAddr_inp, rAddr_inp,
    input  wEn_inp, rEn_inp,

    input [oc_para*bits_bias-1:0] wData_bias,
    input [addr_bit_bias-1:0] wAddr_bias, rAddr_bias,
    input  wEn_bias, rEn_bias,
    input [15:0]  location_h,
    input [15:0]  location_w,

    input [addr_bit_out-1:0] wAddr_out, rAddr_out,
    input  wEn_out, rEn_out,

    input [ic_para*oc_para*bits_weight-1:0] mac_mul_wei,
    output  [pixel_para*oc_para*bits_quantout-1:0] rData_out,

    input [15:0] quantization_scale,

    input padding_left  ,
    input padding_right ,
    input [3:0]         pad_h,
    input [3:0]         pad_w
);

wire [ic_para*bits_input-1:0] share_mac_in_act;
wire [oc_para*bits_bias-1:0] mac_add_bias;
wire [oc_para*bits_macout-1:0] mac_out;
wire [oc_para*bits_macout-1:0] relu_out;
wire [2*oc_para*bits_macout-1:0] quant_mac_out;
wire [oc_para*bits_macout-1:0] quant_clip_out;
wire [oc_para-1:0] carry_bit;

wire [addr_bit_inp-1:0] rAddr_inp_offset;

wire [addr_bit_inp-1:0] stride_padding =  (location_h*2*pad_h)+pad_h;
assign rAddr_inp_offset = padding_left ? ((stride_padding+(pixel_h*pad_w))*(channel/ic_para)) : (stride_padding*(channel/ic_para));

wire signed [addr_bit_inp+1:0] signed_true_addr = $signed({2'b0, rAddr_inp}) - $signed({2'b0, rAddr_inp_offset});
wire signed [addr_bit_inp+1:0] signed_word_A = signed_true_addr >>> 2;
wire signed [addr_bit_inp+1:0] signed_word_B = signed_word_A + 1;

wire ena_input = rEn_inp | wEn_inp;
wire wea_input = wEn_inp;

wire [addr_bit_inp-1:0] Addr_input_A = wea_input ? wAddr_inp : 
                                       (signed_word_A < 0 ? {addr_bit_inp{1'b0}} : signed_word_A[addr_bit_inp-1:0]);
wire [addr_bit_inp-1:0] Addr_input_B = (signed_word_B < 0 ? {addr_bit_inp{1'b0}} : signed_word_B[addr_bit_inp-1:0]);

reg [1:0]  unaligned_offset_d1;
reg [15:0] location_w_d1;
reg [addr_bit_inp-1:0] Addr_input_A_d1;
reg [15:0] location_h_d1;

always @(posedge clk) begin
    unaligned_offset_d1 <= signed_true_addr[1:0]; 
    location_w_d1       <= location_w;               
    location_h_d1       <= location_h;                 
    Addr_input_A_d1     <= Addr_input_A;
end

wire [pixel_para*ic_para*bits_input-1:0] raw_douta_A;
wire [pixel_para*ic_para*bits_input-1:0] raw_doutb_B;

blk_mem_gen_input sram_input (
  .clka   (clk),         
  .ena    (ena_input), 
  .wea    (wea_input),   
  .addra  (Addr_input_A), 
  .dina   (wData_inp),   
  .douta  (raw_douta_A),
  
  .clkb   (clk),         
  .enb    (rEn_inp), 
  .web    (1'b0),        
  .addrb  (Addr_input_B), 
  .dinb   ({(pixel_para*ic_para*bits_input){1'b0}}), 
  .doutb  (raw_doutb_B)
);

wire [2*pixel_para*ic_para*bits_input-1:0] wide_read = {raw_douta_A, raw_doutb_B} ;
reg  [pixel_para*ic_para*bits_input-1:0]   share_mac_in_act_aligned;

always @(*) begin
    case(unaligned_offset_d1) 
        2'd0: share_mac_in_act_aligned = wide_read[8*PIX_W-1 : 4*PIX_W];
        2'd1: share_mac_in_act_aligned = wide_read[7*PIX_W-1 : 3*PIX_W];
        2'd2: share_mac_in_act_aligned = wide_read[6*PIX_W-1 : 2*PIX_W];
        2'd3: share_mac_in_act_aligned = wide_read[5*PIX_W-1 : 1*PIX_W];
    endcase
end

// The first 256-bit beat contains all sixteen signed 16-bit biases.
reg [oc_para*bits_bias-1:0] bias_reg [0:1];
reg [oc_para*bits_bias-1:0] bias_read;
always @(posedge clk) begin
    if (wEn_bias && wAddr_bias < 2) bias_reg[wAddr_bias] <= wData_bias;
    if (rEn_bias) bias_read <= (rAddr_bias < 2) ? bias_reg[rAddr_bias] : 0;
end
assign mac_add_bias = bias_read;

wire [31:0] global_residual;
global_residual_store #(.ADDR_WIDTH(addr_bit_inp)) residual_store (
    .clk(clk), .write_enable(wEn_inp && first_layer),
    .write_addr(wAddr_inp), .input_word(wData_inp),
    .read_enable(wEn_out && last_layer), .read_addr(wAddr_out),
    .residual_word(global_residual)
);

wire [pixel_para*oc_para*bits_quantout-1:0] wData_out;

genvar p;
generate
    for(p=0; p<pixel_para; p=p+1) begin : parallel_lanes
        
        wire [15:0] cur_loc_w = location_w_d1 + p; 
        wire is_pad_lane = (padding_left && (location_h_d1 < pad_w)) || 
                           (padding_right && (location_h_d1 >= pixel_w + pad_w)) || 
                           (cur_loc_w < pad_h) || 
                           (cur_loc_w >= pixel_h + pad_h);

        wire [ic_para*bits_input-1:0] lane_in = share_mac_in_act_aligned[(pixel_para-p)*PIX_W-1 -: PIX_W];
        wire [ic_para*bits_input-1:0] masked_in = is_pad_lane ? {(PIX_W){1'b0}} : lane_in;

        wire [oc_para*bits_macout-1:0] mac_out;

        Mac_8x8 #(
            .number_ew(ic_para), 
            .number_eg(oc_para), 
            .bits_input(bits_input),
            .bits_weight(bits_weight), 
            .bits_bias(bits_bias), 
            .bits_eleout(bits_eleout),
            .bits_addout(bits_addout), 
            .bits_macout(bits_macout)
        ) Mac_8x8_ins (
            .clk(clk), 
            .rst(rst), 
            .done_re(done_re), 
            .mac_reset(mac_reset),
            .share_mac_in_act(masked_in), 
            .mac_mul_wei(mac_mul_wei), 
            .mac_add_bias(mac_add_bias),
            .mac_out(mac_out)
        );

        wire [oc_para*bits_macout-1:0] relu_out;
        genvar k;
        for(k=0; k<oc_para; k=k+1) begin : relu_inst
            ReLU #(.bits_ReLU(bits_macout)
            ) inst_ReLU (
                .ReLU_enable(ReLU_enable),
                .ReLU_in(mac_out[(oc_para*bits_macout)-(k*bits_macout)-1-:bits_macout]),
                .ReLU_out(relu_out[(oc_para*bits_macout)-(k*bits_macout)-1-:bits_macout])
            );
        end

        localparam P_WIDTH = bits_macout + 16;
        wire [oc_para*P_WIDTH-1:0] quant_mac_out;
        genvar i;
        for(i=0; i<oc_para; i=i+1) begin : quantize
            mult_quantization_scale inst_mult_quant (
                .CLK(clk), 
                .A(relu_out[(oc_para*bits_macout)-(i*bits_macout)-1-:bits_macout]), // Width = 18
                .B(quantization_scale),                                             // Width = 16
                .P(quant_mac_out[(oc_para*P_WIDTH)-(i*P_WIDTH)-1-:P_WIDTH])         // Width = 34
            );
        end

        wire [oc_para-1:0] carry_bit;
        wire [oc_para*bits_macout-1:0] quant_clip_out;
        genvar j, m;
        for(j=0; j<oc_para; j=j+1) begin : carry_logic
            wire [P_WIDTH-1:0] p_val = quant_mac_out[(oc_para*P_WIDTH)-(j*P_WIDTH)-1-:P_WIDTH];
            assign carry_bit[j] = p_val[P_WIDTH-1] ? (p_val[15] & (|p_val[14:0])) :  ((|p_val[14:0]) ? p_val[15] : (p_val[16] & p_val[15])); 
        end
        for(m=0; m<oc_para; m=m+1) begin : clip_logic
            wire [P_WIDTH-1:0] p_val = quant_mac_out[(oc_para*P_WIDTH)-(m*P_WIDTH)-1-:P_WIDTH];
            assign quant_clip_out[(oc_para*bits_macout)-(m*bits_macout)-1-:bits_macout] = p_val[P_WIDTH-1 : 16] + carry_bit[m]; 
        end

        // One extra pipeline cycle aligns quantized values with the synchronous
        // residual RAM read. Output write enable AND address are delayed below.
        reg [oc_para*bits_macout-1:0] quant_clip_out_d1;
        always @(posedge clk) quant_clip_out_d1 <= quant_clip_out;
        genvar n;
        for(n=0; n<oc_para; n=n+1) begin : quant_logic_assign
            residual_add_saturate #(.QUANT_BITS(bits_macout)) add_clip (
                .quantized(quant_clip_out_d1[(oc_para-n)*bits_macout-1 -: bits_macout]),
                .residual(global_residual[(pixel_para-p)*8-1 -: 8]),
                .last_layer(last_layer),
                .value(wData_out[(pixel_para-p)*oc_para*bits_quantout-n*bits_quantout-1 -: bits_quantout])
            );
        end
    end
endgenerate

reg wEn_out_d1;
reg [addr_bit_out-1:0] wAddr_out_d1;
always @(posedge clk) begin
    if (!rst) begin wEn_out_d1 <= 0; wAddr_out_d1 <= 0; end
    else begin wEn_out_d1 <= wEn_out; wAddr_out_d1 <= wAddr_out; end
end
wire ena_output = rEn_out | wEn_out_d1;
wire wea_output = wEn_out_d1;
wire [addr_bit_out-1:0] Addr_output = wea_output ? wAddr_out_d1 : rAddr_out;

blk_mem_gen_output sram_output (
  .clka   (clk), 
  .ena    (ena_output), 
  .wea    (wea_output),
  .addra  (Addr_output), 
  .dina   (wData_out), 
  .douta  (rData_out)
);

endmodule