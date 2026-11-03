
`timescale 1ns / 1ps

module Control_sram_addr  #( 
 parameter addr_bit_inp = 11,
//  parameter addr_bit_off = 13,
 parameter addr_bit_weight = 8,
 parameter addr_bit_bias = 6,
 parameter addr_bit_out = 11, 
 parameter ic_para = 8,
 parameter oc_para = 8
)
(
  input                                      clk, rst,
  input             [15:0]                   channel,
  input             [15:0]                   pixel_h,
  input             [15:0]                   pixel_w,
  input [2:0]  kernel_h,
  input [2:0]  kernel_w,
  input             [15:0]                   filter_n,
  input             [7-1:0]                  done,
  input             [15:0]                   cnt_phw_input_addr,
  input             [15:0]                   cnt_fn,
  output  reg       [addr_bit_inp-1:0]       inp_raddr,
  output  reg                                rEn_inp,
  output  reg       [addr_bit_weight-1:0]    weight_raddr,
  output  reg                                rEn_weight,
  output  reg       [addr_bit_bias-1:0]      bias_raddr,
  output  reg                                rEn_bias,
  output  reg                                acc_clean,
  output  reg                                mac_reset,
  output  reg       [addr_bit_out-1:0]       output_waddr,
  output  reg                                wEn_out
);

reg [addr_bit_bias-1:0] bias_raddr_0;
reg [addr_bit_bias-1:0] bias_raddr_1;
reg [addr_bit_bias-1:0] bias_raddr_2;
reg [addr_bit_bias-1:0] bias_raddr_3;
reg rEn_bias_0;
reg rEn_bias_1;
reg rEn_bias_2;
reg rEn_bias_3;
reg [addr_bit_out-1:0] output_waddr_0;
reg [addr_bit_out-1:0] output_waddr_1;
reg [addr_bit_out-1:0] output_waddr_2;
reg [addr_bit_out-1:0] output_waddr_3;
reg [addr_bit_out-1:0] output_waddr_4;
reg wEn_out_0;
reg wEn_out_1;
reg wEn_out_2;
reg wEn_out_3;
reg wEn_out_4;
reg acc_clean_0;
reg acc_clean_1;
reg mac_reset_0;
reg mac_reset_1;
reg mac_reset_2;
reg mac_reset_3;

reg change_channel;


always @ (posedge clk)  begin
    if(!rst)   begin
          inp_raddr       <= -1   ;   
          weight_raddr    <= -1   ;
          bias_raddr_0    <= -1   ;
          output_waddr_0  <= -(filter_n/oc_para) ;
 
          acc_clean_0     <= 0    ;
          change_channel  <= 0    ;
          mac_reset_0     <= 1    ;
 
          rEn_inp         <= 0    ;
          rEn_weight      <= 0    ;
          rEn_bias_0      <= 0    ;
          wEn_out_0       <= 0    ;
          end
     else begin
     case(done) 
     0:   begin 
          inp_raddr       <= -1   ;   
          weight_raddr    <= -1   ;
          bias_raddr_0    <= 0    ;
          output_waddr_0  <= -(filter_n/oc_para);

          acc_clean_0     <= 1    ;
          change_channel  <= 0    ;
          mac_reset_0     <= 1    ;

          rEn_inp         <= 0    ;
          rEn_weight      <= 0    ;
          rEn_bias_0      <= 0    ;
          wEn_out_0       <= 0    ;
          end


     1:   begin 
          inp_raddr       <= inp_raddr    + 1   ;   
          weight_raddr    <= weight_raddr + 1   ;
          bias_raddr_0    <= bias_raddr_0       ;
          output_waddr_0  <= output_waddr_0     ;

          acc_clean_0     <= 0    ;
          change_channel  <= change_channel    ;
          mac_reset_0     <= 0    ;

          rEn_inp         <= 1    ;
          rEn_weight      <= 1    ;
          rEn_bias_0      <= 1    ;
          wEn_out_0       <= 0    ;
          end

     
     20:  begin 
          inp_raddr       <= inp_raddr    + 1   ;   
          weight_raddr    <= weight_raddr + 1   ;
          bias_raddr_0    <= bias_raddr_0       ;
          output_waddr_0  <= output_waddr_0     ;

          acc_clean_0     <= 0    ;
          change_channel  <= change_channel    ;
          mac_reset_0     <= 0    ;

          rEn_inp         <= 1    ;
          rEn_weight      <= 1    ;
          rEn_bias_0      <= 1    ;
          wEn_out_0       <= 0    ;
          end

     21:  begin 
          inp_raddr       <= inp_raddr    + (pixel_h)*(channel/ic_para) -(kernel_h)*(channel/ic_para)+1  ;   
          weight_raddr    <= weight_raddr + 1 ;
          bias_raddr_0    <= bias_raddr_0     ;
          output_waddr_0  <= output_waddr_0 ;

          acc_clean_0     <= 0    ;
          change_channel  <= change_channel    ;
          mac_reset_0     <= 0    ;

          rEn_inp         <= 1    ;
          rEn_weight      <= 1    ;
          rEn_bias_0      <= 1    ;
          wEn_out_0       <= 0    ;
          end


     30:  begin 
          inp_raddr       <= cnt_phw_input_addr*(channel/ic_para)  ;   //cnt_phw 2 cnt_phw_input_addr 
          weight_raddr    <= cnt_fn *(channel/ic_para*kernel_h*kernel_w) ; //modified 2-17,from 0 to cnt_fn *(channel/ic_para*kernel_h*kernel_w)
          bias_raddr_0    <= bias_raddr_0;
          output_waddr_0  <= change_channel?cnt_fn:output_waddr_0 + (filter_n/oc_para)   ;

          acc_clean_0     <= 1    ;
          change_channel  <= 0    ;
          mac_reset_0     <= 0    ;

          rEn_inp         <= 1    ;
          rEn_weight      <= 1    ;
          rEn_bias_0      <= 1    ;
          wEn_out_0       <= 1    ;
          end


     31:  begin 
          inp_raddr       <= cnt_phw_input_addr * (channel/ic_para)  ;   //cnt_phw 2 cnt_phw_input_addr 
          weight_raddr    <= cnt_fn *(channel/ic_para*kernel_h*kernel_w) ; //modified 2-17,from 0 to cnt_fn *(channel/ic_para*kernel_h*kernel_w)
          bias_raddr_0    <= bias_raddr_0 ;
          output_waddr_0  <= output_waddr_0 +(filter_n/oc_para)  ;

          acc_clean_0     <= 1    ;
          change_channel  <= 0    ;
          mac_reset_0     <= 0    ;

          rEn_inp         <= 1    ;
          rEn_weight      <= 1    ;
          rEn_bias_0      <= 1    ;
          wEn_out_0       <= 1    ;
          end


     4:  begin 
          inp_raddr       <= 0    ;   
          weight_raddr    <= cnt_fn *(channel/ic_para*kernel_h*kernel_w) ;
          bias_raddr_0    <= bias_raddr_0 + 1;
          output_waddr_0  <= output_waddr_0 +(filter_n/oc_para) ;

          acc_clean_0     <= 1    ;
          change_channel  <= 1    ;
          mac_reset_0     <= 0    ;

          rEn_inp         <= 1    ;
          rEn_weight      <= 1    ;
          rEn_bias_0      <= 1    ;
          wEn_out_0       <= 1    ;
          end


     5:  begin 
          inp_raddr       <= 0    ;   
          weight_raddr    <= 0    ;
          bias_raddr_0    <= bias_raddr_0 ;
          output_waddr_0  <= output_waddr_0 +(filter_n/oc_para) ;

          acc_clean_0     <= 1    ;
          change_channel  <= 1    ;
          mac_reset_0     <= 0    ;

          rEn_inp         <= 0    ;
          rEn_weight      <= 0    ;
          rEn_bias_0      <= 1    ;
          wEn_out_0       <= 1    ;
          end
          endcase
     end
end


always@(posedge clk)begin
     bias_raddr_1 <= bias_raddr_0;
     bias_raddr_2 <= bias_raddr_1;
     bias_raddr_3 <= bias_raddr_2;
     bias_raddr   <= bias_raddr_3;
end
always@(posedge clk)begin
     rEn_bias_1 <= rEn_bias_0;
     rEn_bias_2 <= rEn_bias_1;
     rEn_bias_3 <= rEn_bias_2;
     rEn_bias   <= rEn_bias_3;
end
always@(posedge clk)begin
     output_waddr_1 <= output_waddr_0;
     output_waddr_2 <= output_waddr_1;
     output_waddr_3 <= output_waddr_2;
     output_waddr_4 <= output_waddr_3;
     output_waddr <= output_waddr_4;
end
always@(posedge clk)begin
     wEn_out_1 <= wEn_out_0;
     wEn_out_2 <= wEn_out_1;
     wEn_out_3 <= wEn_out_2;
     wEn_out_4 <= wEn_out_3;
     wEn_out <= wEn_out_4;
end
always@(posedge clk)begin
     acc_clean_1 <= acc_clean_0;
     acc_clean <= acc_clean_1;
end
always@(posedge clk)begin
     mac_reset_1 <= mac_reset_0;
     mac_reset_2 <= mac_reset_1;
     mac_reset_3 <= mac_reset_2;
     mac_reset <= mac_reset_3;
end



endmodule













