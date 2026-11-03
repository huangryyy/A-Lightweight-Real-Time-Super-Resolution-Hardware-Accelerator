
module FSM_state  #(  
 parameter stride = 1,
 parameter ic_para = 16,
 parameter pixel_para = 4,
 parameter oc_para = 16
)
(input clk,
 input rst,
 input [15:0] channel,
 input [15:0] pixel_h,
 input [15:0] pixel_w,
 input [15:0] filter_n,
 input [2:0]  kernel_h,
 input [2:0]  kernel_w,
 output [7-1:0] done,
 output [15:0]  location_h,
 output [15:0]  location_w,
 output [15:0]  cnt_phw_input_addr, 
 output [15:0]  cnt_fn,
 input	acc_start_signal,		
 output reg acc_finish_signal,		

 input [3:0]         pad_h,
 input [3:0]         pad_w,
 input padding_left,
 input padding_right
);

wire  [6-1:0] x;
wire acc_finish_signal_0;
reg acc_finish_signal_1;
reg acc_finish_signal_2;
reg acc_finish_signal_3;
always@(posedge clk)begin
	acc_finish_signal_1 <= acc_finish_signal_0;
	acc_finish_signal_2 <= acc_finish_signal_1;
	acc_finish_signal_3 <= acc_finish_signal_2;
	acc_finish_signal   <= acc_finish_signal_3;
end

count #(
.stride	         (stride),
.ic_para         (ic_para),
.pixel_para		 (pixel_para),
.oc_para         (oc_para)
)count_ins1(
.clk                 (clk),
.rst                 (rst),
.kernel_h        (kernel_h),
.kernel_w        (kernel_w),
.channel         	 (channel),
.pixel_h         	 (pixel_h),
.pixel_w         	 (pixel_w),
.filter_n        	 (filter_n),
.x                   (x),
.padding_left       (padding_left),
.padding_right      (padding_right),
.location_h			 (location_h),
.location_w          (location_w),
.cnt_phw_input_addr(cnt_phw_input_addr), 
.cnt_phw_offset(), 
.cnt_fn             (cnt_fn),
.acc_start_signal	(acc_start_signal),		
.pad_h              (pad_h),
.pad_w              (pad_w)
);


FSM  FSM_ins1(
.clk                 (clk),
.rst                 (rst),
.x_in                (x),
.done                (done),
.acc_start_signal	 (acc_start_signal), 
.acc_finish_signal	 (acc_finish_signal_0)	
);
endmodule




module FSM 
(input clk,
 input rst,
 input  [6-1:0] x_in,
 output reg [7-1:0] done,
 input acc_start_signal,		
 output reg acc_finish_signal	
);


localparam s_idle      = 7'b0000000 ;
localparam s1          = 7'b0000001 ;
localparam s21         = 7'b0000011 ;
localparam s22         = 7'b0000111 ;
localparam s31         = 7'b0001111 ;
localparam s32         = 7'b0011111 ;
localparam s4          = 7'b0111111 ;
localparam s_end       = 7'b1111111 ;
localparam s_wrong     = 7'b1100011 ;  

reg [7-1:0] current_state;
reg [7-1:0] next_state;

always @(posedge clk)
 begin
	if(!rst)
		begin
			current_state <= s_idle;
		end
	else
		begin
			current_state <= next_state;
		end
end

always @(*)
begin
	case(current_state)	
		s_idle: begin
                          if (!rst)
                                next_state = s_idle;
					  else if (!acc_start_signal)
					  		next_state = s_idle;
	                  else if  (x_in == 6'b00_0000) 
	                        next_state = s1;  

                          else if  (x_in == 6'b11_1111)
	                        next_state = s_end;
		          else if  (x_in == 6'b11_1110)
                                next_state = s4;
		          else if  (x_in[5:2] == 6'b11_11)
                                next_state = s32;
                          else if  (x_in[5:3] == 6'b11_1)
                                next_state = s31;
                          else if  (x_in[5:4] == 6'b11)
                                next_state = s22;
	                  else if  (x_in[5] == 6'b1)
	                        next_state = s21;
                          else
                                next_state = s_idle;
		        end
		s1:     begin
                          if       (x_in == 6'b11_1111)
	                        next_state = s_end;
		          else if  (x_in == 6'b11_1110)
                                next_state = s4;
		          else if  (x_in[5:2] == 6'b11_11)
                                next_state = s32;
                          else if  (x_in[5:3] == 6'b11_1)
                                next_state = s31;
                          else if  (x_in[5:4] == 6'b11)
                                next_state = s22;
	                  else if  (x_in[5] == 6'b1)
	                        next_state = s21;
                          else
                                next_state = s1;
		        end
			
		s21:     begin
                          if       (x_in == 6'b11_1111)
	                        next_state = s_end;
		          else if  (x_in == 6'b11_1110)
                                next_state = s4;
		          else if  (x_in[5:2] == 6'b11_11)
                                next_state = s32;
                          else if  (x_in[5:3] == 6'b11_1)
                                next_state = s31;
                          else if  (x_in[5:4] == 6'b11)
                                next_state = s22;
	                  else if  (x_in[5] == 6'b1)
	                        next_state = s21;
                          else
                                next_state = s1;

			end 


		s22:     begin
                          if       (x_in == 6'b11_1111)
	                        next_state = s_end;
		          else if  (x_in == 6'b11_1110)
                                next_state = s4;
		          else if  (x_in[5:2] == 6'b11_11)
                                next_state = s32;
                          else if  (x_in[5:3] == 6'b11_1)
                                next_state = s31;
                          else if  (x_in[5:4] == 6'b11)
                                next_state = s22;
	                  else if  (x_in[5] == 6'b1)
	                        next_state = s21;
                          else
                                next_state = s1;

			end 

		s31:     begin
                          if       (x_in == 6'b11_1111)
	                        next_state = s_end;
		          else if  (x_in == 6'b11_1110)
                                next_state = s4;
		          else if  (x_in[5:2] == 6'b11_11)
                                next_state = s32;
                          else if  (x_in[5:3] == 6'b11_1)
                                next_state = s31;
                          else if  (x_in[5:4] == 6'b11)
                                next_state = s22;
	                  else if  (x_in[5] == 6'b1)
	                        next_state = s21;
                          else
                                next_state = s1;

			end 

		s32:     begin
                          if       (x_in == 6'b11_1111)
	                        next_state = s_end;
		          else if  (x_in == 6'b11_1110)
                                next_state = s4;
		          else if  (x_in[5:2] == 6'b11_11)
                                next_state = s32;
                          else if  (x_in[5:3] == 6'b11_1)
                                next_state = s31;
                          else if  (x_in[5:4] == 6'b11)
                                next_state = s22;
	                  else if  (x_in[5] == 6'b1)
	                        next_state = s21;
                          else
                                next_state = s1;

			end 

		s4:     begin
                          if       (x_in == 6'b11_1111)
	                        next_state = s_end;
		          else if  (x_in == 6'b11_1110)
                                next_state = s4;
		          else if  (x_in[5:2] == 6'b11_11)
                                next_state = s32;
                          else if  (x_in[5:3] == 6'b11_1)
                                next_state = s31;
                          else if  (x_in[5:4] == 6'b11)
                                next_state = s22;
	                  else if  (x_in[5] == 6'b1)
	                        next_state = s21;
                          else
                                next_state = s1;

			end 
 
	        s_end:	begin
			        next_state = s_idle;		
	                end  
		default:
			begin
				next_state = s_wrong;
			end
		
	endcase
end

//modify 2023.8.16
always @(posedge clk)
 begin
	case(next_state)
			s_idle:
				begin
					done <= 0;
					acc_finish_signal <= 0;
				end	

			s1:
				begin
					done <= 1;
					acc_finish_signal <= 0;
				end	
			
			s21:
				begin
					done <= 20;
					acc_finish_signal <= 0;
				end
				
			s22:
				begin
					done <= 21;
					acc_finish_signal <= 0;
				end

			s31:
				begin
					done <= 30;
					acc_finish_signal <= 0;
				end
				
			s32:
				begin
					done <= 31;
					acc_finish_signal <= 0;
				end

			s4:
				begin
					done <= 4;
					acc_finish_signal <= 0;
				end	
			s_end:
				begin
					done <= 5;
					acc_finish_signal <= 1;
				end	
				
			default:
				begin
					done <= 0;	//???
					acc_finish_signal <= 0;
				end
			endcase
	
end 
endmodule