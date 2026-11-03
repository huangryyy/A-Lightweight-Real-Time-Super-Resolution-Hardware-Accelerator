module top_controller #(
	parameter	PARAM_SIZE = 4,
    parameter NUM_LAYERS = 8
)
(
	input				I_clk				  ,
	input				I_rst_n				  ,
	input		[31:0]	S_AXI_AWADDR		  ,
	input		[2:0]	S_AXI_AWPROT		  ,
	input				S_AXI_AWVALID		  ,
	output	reg			S_AXI_AWREADY		  ,
	input		[31:0]	S_AXI_WDATA			  ,
	input		[3:0]	S_AXI_WSTRB			  ,
	input				S_AXI_WVALID		  ,
	output	reg			S_AXI_WREADY		  ,
	output	reg	[1:0]	S_AXI_BRESP	= 2'b0    ,
	output	reg			S_AXI_BVALID		  ,
	input				S_AXI_BREADY		  ,
	input		[31:0]	S_AXI_ARADDR		  ,
	input		[2:0]	S_AXI_ARPROT		  ,
	input				S_AXI_ARVALID 		  ,
	output	reg			S_AXI_ARREADY		  ,
	output	reg	[31:0]	S_AXI_RDATA			  ,
	output	reg	[1:0]	S_AXI_RRESP	= 2'b0	  ,
	output	reg			S_AXI_RVALID		  ,
	input				S_AXI_RREADY		  ,
	output		[319:0]	O_conv_config_data	  ,
	output	reg			O_conv_start_signal	  ,
	input				I_conv_finish_signal  ,
    input [31:0] I_debug_status,
	output	reg			O_ReLU_enable,
	output reg first_layer,
	output  reg 		last_layer
);
localparam	S_WR_IDLE	=	3'd0	;
localparam	S_WR_DATA	=	3'd1	;
localparam	S_WR_RESP	=	3'd2	;

localparam	S_RD_IDLE	=	3'd0	;
localparam	S_RD_DATA	=	3'd1	;

localparam	S_IDLE							 =	4'd0	;
localparam	S_CONFIG						 =	4'd1	;
localparam	S_CONV_CONFIG					 =	4'd2	;
localparam	S_CONV_CONFIG_WAIT				 =	4'd3	;
localparam	S_LAYER_WAIT						 =	4'd4	;
localparam	S_WAIT							 =	4'd5	;

reg	[2:0]	r_wr_state	=	3'd0	;
reg	[2:0]	r_rd_state	=	3'd0	;

reg	[28:0]	r_rd_data_addr	=	29'd0;
reg	[28:0]	r_wr_data_addr	= 	29'd0;
reg [31:0]  r_reg_grp [2**PARAM_SIZE-1:0];
reg	[31:0]	r_pl_state;

reg	[9:0]	r_write_cnt	=	10'd0;
reg r_fifo_wr_en;
reg [511:0] r_fifo_payload;
wire [511:0]	w_fifo_dout;


reg	[7:0]	r_conv_cal_cnt	;

reg	r_conv_start_signal	=1'd0;
reg	r_conv_start_signal_delay1 = 1'd0;
reg	r_conv_start_signal_delay2 = 1'd0;

reg r_conv_finish_signal_delay1;
reg r_conv_finish_signal_delay2;

reg [5:0] r_layer_scale_cnt = 6'd0;
reg	[3:0]	r_state	= 4'd0;
reg [3:0]	r_wait_cnt;
always@(posedge I_clk)begin
	r_conv_finish_signal_delay1 <= I_conv_finish_signal;
	r_conv_finish_signal_delay2 <= r_conv_finish_signal_delay1;
end

//AXI-Lite wr control logic
always@(posedge I_clk)begin
	if(!I_rst_n)	r_wr_state <= S_WR_IDLE;
	else case(r_wr_state)
		S_WR_IDLE:begin
			if(S_AXI_AWVALID && S_AXI_AWREADY)	r_wr_state <= S_WR_DATA;
			else	r_wr_state <= r_wr_state;
		end
		S_WR_DATA:begin
			if(S_AXI_WVALID && S_AXI_WREADY)	r_wr_state <= S_WR_RESP;
			else	r_wr_state <= r_wr_state;
		end
		S_WR_RESP:begin
			if(S_AXI_BVALID && S_AXI_BREADY)	r_wr_state <= S_WR_IDLE;
			else	r_wr_state <= r_wr_state;
		end
		default:	r_wr_state <= S_WR_IDLE;
	endcase
end

//AXI AW signal
//S_AXI_AWREADY
always@(posedge I_clk)begin
	case(r_wr_state)
		S_WR_IDLE:begin
			if(S_AXI_AWVALID && S_AXI_AWREADY)	S_AXI_AWREADY <= 1'b0;
			else	S_AXI_AWREADY <= 1'b1;
		end
		S_WR_DATA,S_WR_RESP:begin
			S_AXI_AWREADY <= 1'b0;
		end
		default:	S_AXI_AWREADY <= 1'b0;
	endcase
end

//r_wr_data_addr
always@(posedge I_clk)begin
	if(S_AXI_AWVALID && S_AXI_AWREADY)	r_wr_data_addr <= S_AXI_AWADDR>>2;
	else	r_wr_data_addr <= r_wr_data_addr;
end

//AXI W signal
//S_AXI_WREADY
always@(posedge I_clk)begin
	case(r_wr_state)
		S_WR_IDLE,S_WR_RESP:begin
			S_AXI_WREADY <= 1'b0;
		end
		S_WR_DATA:begin
			if(S_AXI_WVALID && S_AXI_WREADY)	S_AXI_WREADY <= 1'b0;
			else	S_AXI_WREADY <= 1'b1;
		end
		default:	S_AXI_WREADY <= 1'b0;
	endcase
end


always@(posedge I_clk)begin
	case(r_wr_state)
		S_WR_DATA:begin
			if(S_AXI_WVALID && S_AXI_WREADY)begin
				r_reg_grp[r_wr_data_addr] <= S_AXI_WDATA;
			end
		end
	endcase
end

//write response to host
//S_AXI_BVALID
always@(posedge I_clk)begin
	if(!I_rst_n)	S_AXI_BVALID <= 1'b0;
	case(r_wr_state)
		S_WR_RESP:begin
			if(S_AXI_BVALID && S_AXI_BREADY)	S_AXI_BVALID <= 1'b0;
			else	S_AXI_BVALID <= 1'b1;
		end
		default:	S_AXI_BVALID <= 1'b0;
	endcase
end

//AXI-Lite rd control logic
always@(posedge I_clk)begin
	if(!I_rst_n)	r_rd_state <= S_RD_IDLE;
	else case(r_rd_state)
		S_RD_IDLE:begin
			if(S_AXI_ARVALID && S_AXI_ARREADY)	r_rd_state <= S_RD_DATA;
			else	r_rd_state <= r_rd_state;
		end
		S_RD_DATA:begin
			if(S_AXI_RVALID && S_AXI_RREADY)	r_rd_state <= S_RD_IDLE;
			else	r_rd_state <= r_rd_state;
		end
		default:	r_rd_state <= S_RD_IDLE;
	endcase
end

//AXI AR signal
//S_AXI_ARREADY
always@(posedge I_clk)begin
	case(r_rd_state)
		S_RD_IDLE:begin
			if(S_AXI_ARVALID && S_AXI_ARREADY)	S_AXI_ARREADY <= 1'b0;
			else	S_AXI_ARREADY <= 1'b1;
		end
		S_RD_DATA:begin
			S_AXI_ARREADY <= 1'b0;
		end
		default:	S_AXI_ARREADY <= 1'b0;
	endcase
end

//r_rd_data_addr
always@(posedge I_clk)begin
	if(S_AXI_ARVALID && S_AXI_ARREADY)	r_rd_data_addr <= S_AXI_ARADDR>>2;
	else	r_rd_data_addr <= r_rd_data_addr;
end

//AXI RD signal
//S_AXI_RVALID
always@(posedge I_clk)begin
	case(r_rd_state)
		S_RD_IDLE:begin
			S_AXI_RVALID <= 1'b0;
		end
		S_RD_DATA:begin
			if(S_AXI_RVALID && S_AXI_RREADY)	S_AXI_RVALID <= 1'b0;
			else	S_AXI_RVALID <= 1'b1;
		end
		default:	S_AXI_RVALID <= 1'b0;
	endcase
end

//S_AXI_RDATA
always@(posedge I_clk)begin
	if(!I_rst_n)	S_AXI_RDATA <= 32'd0;
	case(r_rd_state)
		S_RD_DATA:begin
			if(r_rd_data_addr == 17)begin
                S_AXI_RDATA <= 32'h38475231; // 8GR1: eight layers, 16-bit bias, global residual
            end
            else if(r_rd_data_addr == 18)begin
                S_AXI_RDATA <= {3'b0,r_fifo_wr_en,r_write_cnt[3:0],2'b0,r_layer_scale_cnt,r_conv_cal_cnt,1'b0,r_wr_state,r_state};
            end
            else if(r_rd_data_addr == 19) S_AXI_RDATA <= I_debug_status;
            else if(r_rd_data_addr == 20) S_AXI_RDATA <= r_fifo_payload[31:0];
            else if(r_rd_data_addr == 21) S_AXI_RDATA <= 32'd2;
            else if(r_rd_data_addr == 22) S_AXI_RDATA <= O_conv_config_data[31:0];
            else if(r_rd_data_addr == 23) S_AXI_RDATA <= O_conv_config_data[287:256];
            else if(r_rd_data_addr == 24) S_AXI_RDATA <= O_conv_config_data[319:288];
            else if(r_rd_data_addr == 2**PARAM_SIZE)begin
				S_AXI_RDATA <= r_pl_state;
			end
			else begin
				S_AXI_RDATA <= r_reg_grp[r_rd_data_addr];
			end
		end
		default:	S_AXI_RDATA <= 32'd0;
	endcase
end

fifo_top_controller inst_fifo_512din_512dout (					
    .srst     (~I_rst_n                   ), 
    .clk      (I_clk                      ), 
	.din      (r_fifo_payload),
    .wr_en    (r_fifo_wr_en				  ), 
	.rd_en    (r_conv_start_signal_delay2), 
    .dout     (w_fifo_dout	  			  )
);

always@(posedge I_clk)begin
	if(!I_rst_n) r_write_cnt <= 10'd0;
	else if (S_AXI_WVALID && S_AXI_WREADY && r_wr_data_addr < 10) begin
        // A packet starts at offset0 and must visit offsets0,4,...,36 in order.
        // Ignore unrelated partial UART/diagnostic accesses before our driver binds.
        if (r_wr_data_addr == 0) r_write_cnt <= 1;
        else if (r_wr_data_addr == r_write_cnt)
            r_write_cnt <= (r_write_cnt == 9) ? 0 : r_write_cnt+1;
        else r_write_cnt <= 0;
    end
	else	r_write_cnt <= r_write_cnt;
end

always@(posedge I_clk)begin
    if (!I_rst_n) begin
        r_fifo_wr_en <= 1'b0;
        r_fifo_payload <= 0;
    end else begin
        r_fifo_wr_en <= 1'b0;
        if(S_AXI_WVALID && S_AXI_WREADY && r_write_cnt == 10'd9 && r_wr_data_addr == 9) begin
            r_fifo_payload <= {192'd0,r_reg_grp[0],r_reg_grp[1],r_reg_grp[2],r_reg_grp[3],r_reg_grp[4],r_reg_grp[5],r_reg_grp[6],r_reg_grp[7],r_reg_grp[8],S_AXI_WDATA};
            r_fifo_wr_en <= 1'b1;
        end
    end
end

always@(posedge I_clk)begin
	if(!I_rst_n)	r_state <= S_IDLE	;
	else case(r_state)
		S_IDLE:begin
			if(r_reg_grp[2**PARAM_SIZE-1] == 32'd1)	r_state <= S_CONFIG;
			else	r_state <= r_state;
		end
		S_CONFIG:begin
			r_state <= S_CONV_CONFIG;
		end
		S_CONV_CONFIG:begin
			r_state <=	S_CONV_CONFIG_WAIT;
		end
		S_CONV_CONFIG_WAIT:begin
			if(r_wait_cnt == 4'd9)	r_state <=	S_LAYER_WAIT;
			else r_state <=	r_state;
		end
		S_LAYER_WAIT:begin
			if(r_conv_finish_signal_delay2 && r_conv_cal_cnt == NUM_LAYERS-1)	r_state <= S_WAIT;
			else if(r_conv_finish_signal_delay2)	r_state <= S_CONV_CONFIG;
			else	r_state	<= r_state;
		end
		S_WAIT:begin
			if(r_reg_grp[2**PARAM_SIZE-1] == 32'd2 && r_pl_state == 32'd1)begin
				r_state <= S_IDLE;
			end
			else	r_state <= S_WAIT;
		end
		default:	r_state <= r_state;
	endcase
end

// r_wait_cnt
always@(posedge I_clk)begin
	case(r_state)
		S_CONV_CONFIG_WAIT:begin
			if(r_wait_cnt == 4'd9)begin
				r_wait_cnt <= 4'd0;
			end else begin
				r_wait_cnt <= r_wait_cnt + 4'd1;
			end
		end
		default:begin
			r_wait_cnt <= 4'd0;
		end
	endcase
end

//r_pl_state
always@(posedge I_clk)begin
	if(!I_rst_n)	r_pl_state <= 32'd0;
	else case(r_state)
		S_LAYER_WAIT:begin
			if(r_conv_finish_signal_delay2 && r_conv_cal_cnt == NUM_LAYERS-1)	r_pl_state <= 32'd1;
			else	r_pl_state <= r_pl_state;
		end
		S_WAIT:begin
			if(r_reg_grp[2**PARAM_SIZE-1] == 32'd2)	r_pl_state <= 32'd0;
			else	r_pl_state <= r_pl_state;
		end
		default:	r_pl_state <= r_pl_state;
	endcase
end

//Conv
//r_conv_start_signal
always@(posedge I_clk)begin
	case(r_state)
		S_CONV_CONFIG:begin
			r_conv_start_signal <= 1'd1;
		end
		default:	r_conv_start_signal <= 1'd0;
	endcase
end

always@(posedge I_clk)begin
	r_conv_start_signal_delay1 <= r_conv_start_signal;
	r_conv_start_signal_delay2 <= r_conv_start_signal_delay1;
end

always@(posedge I_clk)begin
	if(!I_rst_n)	O_conv_start_signal <= 1'b0;
	else O_conv_start_signal <= r_conv_start_signal_delay2 | r_conv_start_signal_delay1 | r_conv_start_signal;
end

// //O_conv_config_data
assign O_conv_config_data = w_fifo_dout[319:0];

//r_conv_cal_cnt
always@(posedge I_clk)begin
	if(!I_rst_n)	r_conv_cal_cnt <= 8'd0;	
	else case(r_state)
		S_LAYER_WAIT:begin
			if(r_conv_finish_signal_delay2 && r_conv_cal_cnt == NUM_LAYERS-1)	r_conv_cal_cnt <= 8'd0;
			else if(r_conv_finish_signal_delay2)	r_conv_cal_cnt <= r_conv_cal_cnt + 8'd1;
			else	r_conv_cal_cnt <= r_conv_cal_cnt;
		end
		default:	r_conv_cal_cnt <= r_conv_cal_cnt;
	endcase
end

//r_layer_scale_cnt
always@(posedge I_clk)begin
	case(r_state)
		S_IDLE:begin
			r_layer_scale_cnt <= 6'd0;
		end
		S_CONV_CONFIG:begin
			r_layer_scale_cnt <= r_layer_scale_cnt + 6'd1;
		end
		S_WAIT:begin
			r_layer_scale_cnt <= 6'd0;
		end
		default:begin
			r_layer_scale_cnt <= r_layer_scale_cnt;
		end
	endcase
end

// First/last flags remain stable while the corresponding layer's DMA runs.
always @(posedge I_clk) begin
    if (!I_rst_n) begin
        O_ReLU_enable <= 1'b0;
        first_layer <= 1'b0;
        last_layer <= 1'b0;
    end else begin
        first_layer <= (r_layer_scale_cnt == 1);
        last_layer <= (r_layer_scale_cnt == NUM_LAYERS);
        O_ReLU_enable <= (r_layer_scale_cnt != NUM_LAYERS);
    end
end
endmodule
