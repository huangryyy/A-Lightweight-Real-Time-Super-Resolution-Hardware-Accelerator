module ddr_rd_wrapper2#(
	parameter	RAM_LATENCY	=	2,
	parameter	RAM_ADDR_WIDTH = 13
)(
	input				I_clk					,
	input				I_rst_n					,
	input		[31:0]	I_addr_offset			,
	input		[31:0]	I_rd_lenth				,
	input				I_offset_valid			,
	output	reg			O_rd_finish_signal		,
	output	reg	[RAM_ADDR_WIDTH-1:0]	O_ram_addr				,
	output	    		O_wr_en					,
	output		[2047:0]	O_ram_data			,
	output	reg	[3:0]	M_AXI_ARID		=4'd0	,
	output		[31:0]	M_AXI_ARADDR			,
	output		[7:0]	M_AXI_ARLEN				,
	output	reg	[2:0]	M_AXI_ARSIZE	=3'b110 , // ARSIZE为一个突发中单个数据包的传输位宽，3bits的值分别对应1，2，4，8，16，32，64，128字节
	output	reg	[1:0]	M_AXI_ARBURST	=2'b01	,
	output	reg			M_AXI_ARLOCK	=1'b0	,
	output	reg	[3:0]	M_AXI_ARCACHE	=4'b0011,
	output	reg	[2:0]	M_AXI_ARPROT	=3'b000	,
	output	reg	[3:0]	M_AXI_ARQOS		=4'b000	,
	output				M_AXI_ARVALID			,
	input				M_AXI_ARREADY			,
	input		[3:0]	M_AXI_RID				,		
	input		[511:0]	M_AXI_RDATA				,
	input		[1:0]	M_AXI_RRESP				,
	input				M_AXI_RVALID			,
	input				M_AXI_RLAST				,
	output				M_AXI_RREADY					
);
localparam	S_IDLE		=	2'd0;
localparam	S_CONFIG	=	2'd1;
localparam	S_RD		=	2'd2;

reg		[1:0]	r_state							;
wire	[63:0]	w_axis_rconfig_data				;
reg				r_axis_rconfig_valid			;
reg				r_axis_rconfig_last		=	1'b1;
wire			w_axis_rconfig_ready			;

reg		[31:0]	r_addr_offset					;
reg		[31:0]	r_rd_lenth						;
reg		[31:0]	r_rd_out_num					;
reg				r_offset_valid_delay1			;
reg				r_offset_valid_delay2			;
always@(posedge I_clk)begin
	if(!I_rst_n)begin
		r_offset_valid_delay1	<= 1'b0;
		r_offset_valid_delay2	<= 1'b0;
	end	else begin
		r_offset_valid_delay1	<= I_offset_valid;
		r_offset_valid_delay2	<= r_offset_valid_delay1;
	end
end

//fsm
always@(posedge I_clk)begin
	if(!I_rst_n)	r_state	<=	S_IDLE;
	else case(r_state)
		S_IDLE:begin
			if(r_offset_valid_delay2)	r_state	<=	S_CONFIG;
		end
		S_CONFIG:begin
			if(r_axis_rconfig_valid && w_axis_rconfig_ready)	r_state <= S_RD;
		end
		S_RD:begin
			if(r_rd_out_num == (r_rd_lenth>>2))	r_state	<=	S_IDLE;		// 2048/512=4
		end
		default:	r_state	<=	S_IDLE;
	endcase
end

ddr_rd_core_conv_weight ddr_rd_core_conv_weight_inst(   
    .I_sys_clk                    (I_clk),   
    .I_sys_rst_n                  (I_rst_n),      
    .s_axis_rconfig_data          (w_axis_rconfig_data),   
    .s_axis_rconfig_valid         (r_axis_rconfig_valid),   
    .s_axis_rconfig_last          (r_axis_rconfig_last),   
    .s_axis_rconfig_ready         (w_axis_rconfig_ready),   
    .M_axis_ddr_rdata             (O_ram_data),   
    .M_axis_ddr_rvalid            (O_wr_en),      
    .M_axis_ddr_rready            (1'b1),    
    .M_axis_ddr_ardata            (M_AXI_ARADDR),   
    .M_axis_ddr_arlen             (M_AXI_ARLEN),   
    .M_axis_ddr_arvalid           (M_AXI_ARVALID),   
    .M_axis_ddr_arready           (M_AXI_ARREADY),   
    .S_axis_ddr_rdata             (M_AXI_RDATA),   
    .S_axis_ddr_rvalid            (M_AXI_RVALID),   
    .S_axis_ddr_rready            (M_AXI_RREADY),
	.S_axis_ddr_rlast			  (M_AXI_RLAST)
);

always@(posedge I_clk)begin
	if(r_offset_valid_delay2)begin
		r_addr_offset <= I_addr_offset	;
		r_rd_lenth	<=	I_rd_lenth		;
	end
end

assign	w_axis_rconfig_data = {r_addr_offset,r_rd_lenth};

always@(posedge I_clk)begin
	case(r_state)
		S_CONFIG:begin
			if(r_axis_rconfig_valid && w_axis_rconfig_ready)	r_axis_rconfig_valid <= 1'b0;
			else	r_axis_rconfig_valid <= 1'b1;
		end
		default:	r_axis_rconfig_valid <= 1'b0;
	endcase
end

always@(posedge I_clk)begin
	case(r_state)
		S_CONFIG:begin
			O_ram_addr	<= 13'd0;
		end
		S_RD:begin
			if(O_wr_en)	O_ram_addr <= O_ram_addr + 13'd1;
		end
		default:	O_ram_addr <= 13'd0;
	endcase
end

always@(posedge I_clk)begin
	case(r_state)
		S_RD:begin
			if(O_wr_en)	r_rd_out_num <= r_rd_out_num + 32'd1;
		end
		default:	r_rd_out_num <= 32'd0;
	endcase
end

always@(posedge I_clk)begin
	case(r_state)
		S_RD:begin
			if(r_rd_out_num == (r_rd_lenth>>2))	O_rd_finish_signal <= 1'b1;	
			else	O_rd_finish_signal  <= 1'b0;
		end
		default:	O_rd_finish_signal <= 32'd0;
	endcase
end

endmodule