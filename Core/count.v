
`timescale 1ns / 1ps

module count  #(  
 parameter stride = 2,
 parameter ic_para = 8,
 parameter pixel_para = 4,
 parameter oc_para = 8
)
(input               clk,
 input               rst,
 input [15:0]        channel,
 input [15:0]        pixel_h,
 input [15:0]        pixel_w,
 input [15:0]        filter_n,
 input [2:0]  kernel_h,
 input [2:0]  kernel_w,
 output [6-1:0]      x,
 output reg [15:0]   location_h,
 output reg [15:0]   location_w,

 output [15:0]   cnt_phw_input_addr,
 output [15:0]       cnt_phw_offset, 
 output [15:0]       cnt_fn,
 input               acc_start_signal,       

 input [3:0]         pad_h,
 input [3:0]         pad_w,
 input padding_left  ,
 input padding_right 
);

wire x1,x4;
wire [1:0] x22,x33;
wire [15:0] cnt_chan;
wire [15:0] cnt_khw;
wire [15:0] tile_cnt_h;
wire [15:0] tile_cnt_w;
wire [15:0] tile_sub_cnt_h;
wire [15:0] tile_sub_cnt_w;
wire ct1,ct2,ct3,ct4;

reg conv_run_stage;
reg conv_run_stage_delay1;
reg conv_run_stage_delay2;
reg x_reset;

always @(posedge clk) begin
   location_h <=  tile_cnt_h + tile_sub_cnt_h;
end

always @(posedge clk) begin
   location_w <=  (tile_cnt_w * pixel_para) + tile_sub_cnt_w;
end

countloop count_channel(
.clk(clk),
.rst(rst),
.loop_dimen(channel/ic_para),
.cnt(cnt_chan),
.x(x1),
.ct(ct1),

.conv_run_stage(conv_run_stage),
.x_reset(x_reset)
);


 countloop_khw  count_kernelhw(
.clk(ct1),
.rst(rst),
.k_h(kernel_h),
.k_w(kernel_w),
.cnt_hw(cnt_khw),
.cnt_h(tile_sub_cnt_w), 
.cnt_w(tile_sub_cnt_h),
.x(x22),
.ct(ct2),

.conv_run_stage(conv_run_stage),
.x_reset(x_reset)
);


 countloop_phw #(
.stride(stride),
.pixel_para(pixel_para)
) count_pixelhw(
.clk(ct2),
.rst(rst),
.k_h(kernel_h),
.k_w(kernel_w),
.p_h(pixel_h), 
.p_w(pixel_w),
.cnt_hw_input_addr(cnt_phw_input_addr),
.cnt_hw_offset(cnt_phw_offset), 
.cnt_h(tile_cnt_w),
.cnt_w(tile_cnt_h), 
.x(x33),
.ct(ct3),

.conv_run_stage(conv_run_stage),
.x_reset(x_reset)
);

 countloop count_filt(
.clk(ct3),
.rst(rst),
.loop_dimen(filter_n/ic_para), 
.cnt(cnt_fn),
.x(x4),
.ct(ct4),

.conv_run_stage(conv_run_stage),
.x_reset(x_reset)
);

assign x = {x1,x22,x33,x4};

always@(posedge clk)begin
   if(!rst)begin
      conv_run_stage <= 1'b0;
   end else if(acc_start_signal)begin
      conv_run_stage <= 1'b1;
   end else if(x==6'b11_1111)begin
      conv_run_stage <= 1'b0;
   end else begin
      conv_run_stage <= conv_run_stage;
   end
end
always@(posedge clk)begin
   if(x == 6'b11_1111)begin
      x_reset <= 1'b1;
   end else begin
      x_reset <= 1'b0;
   end
end

endmodule




module countloop_khw  
(input clk,
 input rst,
 input [2:0]  k_h,
 input [2:0]  k_w,
 output [15:0]cnt_hw,
 output [15:0]cnt_h,
 output [15:0]cnt_w,
 output [2-1:0]x,
 output ct,

 input conv_run_stage,
 input x_reset
 );

wire x1;
wire x2;
wire ct1;



countloop count_channel(
.clk(clk),
.rst(rst),
.loop_dimen({29'b0, k_h}),
.cnt(cnt_h),
.x(x1),
.ct(ct1),
.conv_run_stage(conv_run_stage),
.x_reset(x_reset)
);


 countloop count_kernelhw(
.clk(ct1),
.rst(rst),
.loop_dimen({29'b0, k_w}),
.cnt(cnt_w),
.x(x2),
.ct(ct),
.conv_run_stage(conv_run_stage),
.x_reset(x_reset)
);

assign x = {x1,x2};
assign cnt_hw = k_h * cnt_w + cnt_h;
endmodule



// pixel level count
module countloop_phw  #(  
 parameter stride = 1,
 parameter pixel_para = 4
)
(input clk,
 input rst,
 input [15:0] p_h,
 input [15:0] p_w,
 input [2:0]  k_h,
 input [2:0]  k_w,
//  output [10:0]cnt_hw,
 output [15:0]cnt_hw_input_addr,
 output [15:0]cnt_hw_offset, 
 output [15:0]cnt_h,
 output [15:0]cnt_w,
 output [2-1:0]x,
 output ct,
 
 input conv_run_stage,
 input x_reset
 );

wire x1;
wire x2;
wire ct1;

countloop count_channel(
.clk(clk),
.rst(rst),
.loop_dimen(((p_h - k_h)/stride + 1) / pixel_para),   
.cnt(cnt_h),
.x(x1),
.ct(ct1),
.conv_run_stage(conv_run_stage),
.x_reset(x_reset)
);

 countloop count_pixelhw(
.clk(ct1),
.rst(rst),
.loop_dimen((p_w -k_w)/stride +1),
.cnt(cnt_w),
.x(x2),
.ct(ct),
.conv_run_stage(conv_run_stage),
.x_reset(x_reset)
);
assign x = {x1,x2};
assign cnt_hw_offset = ((p_h -k_h)/stride + 1) * cnt_w + (cnt_h * pixel_para);   
assign cnt_hw_input_addr = (p_h * cnt_w + (cnt_h * pixel_para)) * stride;        
endmodule








module countloop(
input clk,
input rst,
input [31:0] loop_dimen,
output reg [15:0]cnt,
output reg x,
output ct,
input conv_run_stage,
input x_reset
);

reg ct1;

always @(posedge clk)begin
   if(!rst) begin
      cnt <= 0;
      ct1 <= 1;
   end else if(conv_run_stage) begin
      if(cnt == (loop_dimen - 1)) begin
         cnt <= 0;
         ct1 <= 1;
      end else begin
         cnt <= cnt + 1;
         ct1 <= 0; 
      end
   end else begin
      cnt <= 0;
      ct1 <= 1;
   end     
end 

always@(*)begin
   if(x_reset)begin
      x <= 0;
   end else if(conv_run_stage)begin
      if(cnt == (loop_dimen - 1))begin
         x <= 1;
      end else begin
         x <= 0;
      end
   end else begin
      x <= 0;
   end
end


assign ct =( ((cnt==(loop_dimen-1))&(cnt ==0))  ) ? clk: ct1 ;
endmodule
