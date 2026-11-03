
`timescale 1ns / 1ps

module PG_sram #(
    parameter depth_inp  = 2048, //bit_width_inp = number_ew*bits_input
    parameter addr_bit_inp = 11,

    parameter depth_weight  = 1024,// bit_width_weight =number_ew*number_eg*bits_weight
    parameter addr_bit_weight = 8,

    parameter depth_bias  = 64,
    parameter addr_bit_bias = 6,

    parameter depth_out  = 2048,// bit_width_out =number_eg*bits_quantout
    parameter addr_bit_out = 11,

    parameter number_add = 8,
    parameter bits_input  = 12, 
    parameter bits_weight = 8,
    parameter bits_bias = 8,
    parameter bits_eleout = 20,
    parameter bits_addout = 23,
    parameter bits_macout = 12,
    parameter bits_quantout = 8,

    parameter stride   = 1,
    parameter pixel_para = 4,
    parameter ic_para = 16,
    parameter oc_para = 16
)(
    input clk,
    input rst,
    input [15:0] channel,
    input [15:0] pixel_h,
    input [15:0] pixel_w,
    input [15:0] filter_n,
    input [2:0]  kernel_h,
    input [2:0]  kernel_w,
    input ReLU_enable,
    input first_layer,
    input last_layer,
    input wEn_inp,
    input padding_left,
    input padding_right,
    input [addr_bit_inp-1:0] wAddr_inp,
    input [pixel_para*ic_para*bits_input-1:0] wData_inp,
    input wEn_weight,
    input [addr_bit_weight-1:0] wAddr_weight,
    input [oc_para*ic_para*bits_weight-1:0] wData_weight,
    input wEn_bias,
    input [addr_bit_bias-1:0] wAddr_bias,
    input [oc_para*bits_bias-1:0] wData_bias,
    input rEn_out,
    input [addr_bit_out-1:0] rAddr_out,
    output [pixel_para*oc_para*bits_quantout-1:0] rData_out,
    input [15:0]  quantization_scale,
    
    input acc_start_signal,    
    output acc_finish_signal,   

    input [3:0]         pad_h,
    input [3:0]         pad_w       
);

wire [7-1:0] done;
wire [15:0]  cnt_phw_input_addr;
wire [15:0]  cnt_fn;
reg  [addr_bit_out-1:0] wAddr_out;
reg acc_clean;
wire mac_reset;
wire [addr_bit_inp-1:0] rAddr_inp;
wire rEn_inp;
wire [addr_bit_bias-1:0] rAddr_bias;
wire rEn_bias;

wire wEn_out_0;
reg wEn_out_1;
reg  wEn_out;
always @(posedge clk)
  begin
   wEn_out_1 <= wEn_out_0;	
  end
always @(posedge clk)
  begin
   wEn_out <= wEn_out_1;	
  end

//add two cycles delay ;
wire [addr_bit_out-1:0] wAddr_out_0;
reg [addr_bit_out-1:0] wAddr_out_1;
always @(posedge clk)
  begin
   wAddr_out_1 <= wAddr_out_0;	
  end
always @(posedge clk)
  begin
   wAddr_out <= wAddr_out_1;	
  end

//add two cycles delay ;
wire  acc_clean_0;
reg  acc_clean_1;
always @(posedge clk)
  begin
   acc_clean_1 <= acc_clean_0;	
   acc_clean <= acc_clean_1;	
  end

wire [15:0]  pixel_w_padding, pixel_h_padding;
wire [15:0]  location_h;
wire [15:0]  location_w;
wire rEn_weight;
wire [addr_bit_weight-1:0] rAddr_weight;
wire [oc_para*ic_para*bits_weight-1:0] mac_mul_wei;

assign pixel_w_padding = (padding_left | padding_right) ? ((padding_left & padding_right) ? (pixel_w + pad_w + pad_w) : (pixel_w + pad_w)) : pixel_w; 
assign pixel_h_padding = pixel_h + pad_h + pad_h;

wire ena_weight;
wire wea_weight;
wire [addr_bit_weight-1:0] Addr_weight;
assign ena_weight = rEn_weight | wEn_weight;
assign wea_weight = wEn_weight;
assign Addr_weight = wea_weight?wAddr_weight:rAddr_weight;
blk_mem_gen_weight sram_weight (
  .clka   (clk),    // input wire clka
  .ena    (ena_weight),      // input wire ena
  .wea    (wea_weight),      // input wire [0 : 0] wea
  .addra  (Addr_weight),  // input wire [10 : 0] addra
  .dina   (wData_weight),    // input wire [2047 : 0] dina
  .douta  (mac_mul_wei)  // output wire [2047 : 0] douta
);


FSM_state #(
.stride          (stride),
.ic_para         (ic_para),
.pixel_para      (pixel_para),
.oc_para         (oc_para)
)FSM_state_ins1(
.clk                 (clk),
.rst                 (rst),
.channel             (channel),
.pixel_h             (pixel_h_padding),
.pixel_w             (pixel_w_padding),
.kernel_h        (kernel_h),
.kernel_w        (kernel_w),
.filter_n            (filter_n),
.done                (done),
.location_h			 (location_h),
.location_w          (location_w),
.cnt_phw_input_addr  (cnt_phw_input_addr), 
.cnt_fn              (cnt_fn),
.acc_start_signal    (acc_start_signal),   
.acc_finish_signal   (acc_finish_signal),   

.padding_left       (padding_left),
.padding_right      (padding_right),
.pad_h               (pad_h),
.pad_w               (pad_w)
);


Control_sram_addr  #(  
.addr_bit_inp    (addr_bit_inp),
.addr_bit_weight (addr_bit_weight),
.addr_bit_bias   (addr_bit_bias),
.addr_bit_out    (addr_bit_out),
.ic_para         (ic_para),
.oc_para         (oc_para)
) Control_sram_addr_insl (
.clk             (clk),
.rst             (rst),
.channel         (channel),
.pixel_h         (pixel_h_padding),
.pixel_w         (pixel_w_padding),
.kernel_h        (kernel_h),
.kernel_w        (kernel_w),
.filter_n        (filter_n),
.done            (done),
.cnt_phw_input_addr  (cnt_phw_input_addr), 
.cnt_fn          (cnt_fn),
.inp_raddr       (rAddr_inp),
.rEn_inp         (rEn_inp),
.weight_raddr    (rAddr_weight),
.rEn_weight      (rEn_weight),
.bias_raddr      (rAddr_bias),
.rEn_bias        (rEn_bias),
.acc_clean       (acc_clean_0),
.mac_reset       (mac_reset),
.output_waddr    (wAddr_out_0),
.wEn_out         (wEn_out_0)
);


Processing_group #(
.depth_inp       (depth_inp),
.addr_bit_inp    (addr_bit_inp),
.depth_bias      (depth_bias),
.addr_bit_bias   (addr_bit_bias),
.depth_out       (depth_out),
.addr_bit_out    (addr_bit_out),

.bits_input      (bits_input), 
.bits_weight     (bits_weight),
.bits_eleout     (bits_eleout),
.bits_addout     (bits_addout),
.bits_macout     (bits_macout),
.bits_quantout   (bits_quantout),
.ic_para         (ic_para),
.oc_para         (oc_para)
)Processing_group_insl(
.clk             (clk),
.rst             (rst),
.pixel_h         (pixel_h),
.pixel_w         (pixel_w),
.channel         (channel),
.ReLU_enable     (ReLU_enable),
.first_layer (first_layer),
.last_layer      (last_layer),
.done_re         (acc_clean),
.mac_reset       (mac_reset),
.wData_inp       (wData_inp),
.wAddr_inp       (wAddr_inp), 
.rAddr_inp       (rAddr_inp),
.wEn_inp         (wEn_inp), 
.rEn_inp         (rEn_inp),

.wData_bias      (wData_bias),
.wAddr_bias      (wAddr_bias), 
.rAddr_bias      (rAddr_bias),
.wEn_bias        (wEn_bias), 
.rEn_bias        (rEn_bias),

.wAddr_out       (wAddr_out), 
.rAddr_out       (rAddr_out),
.wEn_out         (wEn_out), 
.rEn_out         (rEn_out),

.mac_mul_wei     (mac_mul_wei),
.rData_out       (rData_out),

.quantization_scale(quantization_scale),

.padding_left       (padding_left),
.padding_right      (padding_right),
.location_h			 (location_h),
.location_w          (location_w),
.pad_h               (pad_h),
.pad_w               (pad_w)
);

endmodule


