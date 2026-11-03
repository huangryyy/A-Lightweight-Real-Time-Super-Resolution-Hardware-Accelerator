module ddr_wr_wrapper1#(
	parameter	RAM_LATENCY	=	2,
	parameter	RAM_ADDR_WIDTH = 13
)(
	input				I_clk					,
	input				I_rst_n					,
	input		[31:0]	I_addr_offset			,
	input		[31:0]	I_wr_lenth				,
	input				I_offset_valid			,
	input				I_conv_start_signal		,
	output				O_wr_finish_signal		,
	output	reg	[RAM_ADDR_WIDTH-1:0]  O_ram_addr,
	output	reg			O_rd_en					,
	input		[511:0]	I_ram_data				,		
	output	reg	[3:0]	M_AXI_AWID		=4'd0	,
	output		[31:0]	M_AXI_AWADDR			,
	output		[7:0]	M_AXI_AWLEN				,
	output	reg	[2:0]	M_AXI_AWSIZE	=3'b110,
	output	reg	[1:0]	M_AXI_AWBURST	=2'b01	,
	output	reg			M_AXI_AWLOCK	=1'b0	,
	output	reg	[3:0]	M_AXI_AWCACHE	=4'b0011,
	output	reg	[2:0]	M_AXI_AWPROT	=3'b000	,
	output	reg	[3:0]	M_AXI_AWQOS		=4'b000	,
	output				M_AXI_AWVALID			,
	input				M_AXI_AWREADY			,
	//wr_data
	output		[511:0]	M_AXI_WDATA						,
	output	reg	[63:0]	M_AXI_WSTRB		=64'hffffffffffffffff	,
	output				M_AXI_WVALID					,
	output				M_AXI_WLAST						,
	input				M_AXI_WREADY					,
	input		[3:0]	M_AXI_BID				,
	input		[1:0]	M_AXI_BRESP				,
	input				M_AXI_BVALID			,
	output	reg			M_AXI_BREADY	=1'b1			
);
localparam	S_IDLE		=	2'd0;
localparam	S_CONFIG	=	2'd1;
localparam	S_WRITE		=	2'd2;
localparam	S_WR_JDG	=	2'd3;

reg		[1:0]	r_state				     		;
wire	[63:0]	w_axis_wconfig_data				;
reg				r_axis_wconfig_valid	= 1'd0	;
reg				r_axis_wconfig_last	=	1'b1	;
wire			w_axis_wconfig_ready			;
reg		[31:0]	r_rd_out_num			= 32'd0	;

wire			w_axis_ddr_wready				;
reg				r_axis_ddr_wlast				;

reg		[31:0]	r_addr_offset					;
reg		[31:0]	r_wr_lenth						;
reg				r_offset_valid_delay1			;
reg				r_offset_valid_delay2			;
reg				r_conv_start_signal_delay1		;
reg				r_conv_start_signal_delay2		;

always@(posedge I_clk)begin
	if(!I_rst_n)begin
		r_offset_valid_delay1	<= 1'b0;
		r_offset_valid_delay2	<= 1'b0;
	end	else begin
		r_offset_valid_delay1	<= I_offset_valid;
		r_offset_valid_delay2	<= r_offset_valid_delay1;
	end
end

always@(posedge I_clk)begin
	if(!I_rst_n)begin
		r_conv_start_signal_delay1 <= 1'b0;
		r_conv_start_signal_delay2 <= 1'b0;
	end else begin
		r_conv_start_signal_delay1 <= I_conv_start_signal;
		r_conv_start_signal_delay2 <= r_conv_start_signal_delay1;
	end
end

always@(posedge I_clk)begin
	if(!I_rst_n)	r_state	<=	S_IDLE;
	else case(r_state)
		S_IDLE:begin
			if(r_offset_valid_delay2)	r_state	<=	S_CONFIG;
		end
		S_CONFIG:begin
			if(r_axis_wconfig_valid && w_axis_wconfig_ready)	r_state <= S_WRITE;
		end
		S_WRITE:begin
			if(O_wr_finish_signal)	r_state	<=	S_IDLE;
		end
		default:	r_state	<=	S_IDLE;
	endcase
end

ddr_wt_core_conv ddr_wt_core_out_inst( 
    .I_sys_clk                    (I_clk						),   
    .I_sys_rst_n                  (I_rst_n						),   
    .s_axis_wconfig_data          (w_axis_wconfig_data			),   
    .s_axis_wconfig_valid         (r_axis_wconfig_valid			),   
    .s_axis_wconfig_last          (r_axis_wconfig_last			),   
    .s_axis_wconfig_ready         (w_axis_wconfig_ready			),     
    .S_axis_ddr_wdata             (I_ram_data					),
    .S_axis_ddr_wvalid            (O_rd_en						),   
    .S_axis_ddr_wlast             (r_axis_ddr_wlast				),   
    .S_axis_ddr_wready            (w_axis_ddr_wready			),   
    .M_axis_ddr_awdata            (M_AXI_AWADDR					),   
    .M_axis_ddr_awlen             (M_AXI_AWLEN					),   
    .M_axis_ddr_awvalid           (M_AXI_AWVALID				),   
    .M_axis_ddr_awready           (M_AXI_AWREADY				),   
    .M_axis_ddr_wdata             (M_AXI_WDATA					),   
    .M_axis_ddr_wvalid            (M_AXI_WVALID					),   
    .M_axis_ddr_wlast             (M_AXI_WLAST					),   
    .M_axis_ddr_wready            (M_AXI_WREADY					),
	.O_wr_finish				  (O_wr_finish_signal			)
);

always@(posedge I_clk)begin
	if(r_conv_start_signal_delay2)begin
		r_addr_offset <= I_addr_offset	;
		r_wr_lenth	<=	I_wr_lenth		;
	end
end

assign	w_axis_wconfig_data = {r_addr_offset,r_wr_lenth};

always@(posedge I_clk)begin
	case(r_state)
		S_CONFIG:begin
			if(r_axis_wconfig_valid && w_axis_wconfig_ready)	r_axis_wconfig_valid <= 1'b0;
			else	r_axis_wconfig_valid <= 1'b1;
		end
		default:	r_axis_wconfig_valid <= 1'b0;
	endcase
end

always@(posedge I_clk)begin
	if(r_state == S_WRITE	&& w_axis_ddr_wready && O_rd_en && r_axis_ddr_wlast)	O_rd_en <= 1'b0;
	else if(r_state == S_WRITE && r_rd_out_num == r_wr_lenth - 32'd1)	O_rd_en <= 1'b0;
	else if(r_state == S_WRITE && w_axis_ddr_wready)	O_rd_en <= 1'b1;
	else	O_rd_en  <= O_rd_en;
end

always@(posedge I_clk)begin
	case(r_state)
		S_CONFIG:begin
			O_ram_addr	<= 13'd0;
		end
		S_WRITE:begin
			if(O_rd_en && w_axis_ddr_wready)	O_ram_addr <= O_ram_addr + 13'd1;
		end
		default:	O_ram_addr <= 13'd0;
	endcase
end

always@(posedge I_clk)begin
	case(r_state)
		S_WRITE:begin
			if(O_rd_en && w_axis_ddr_wready)	r_rd_out_num <= r_rd_out_num + 32'd1;
		end
		default:	r_rd_out_num <= 32'd0;
	endcase
end

always@(posedge I_clk)begin
	case(r_state)
		S_WRITE:begin
			if(O_rd_en && w_axis_ddr_wready && r_rd_out_num == r_wr_lenth - 32'd2)	r_axis_ddr_wlast <= 1'b1;
			else if(O_rd_en && w_axis_ddr_wready && r_axis_ddr_wlast)	r_axis_ddr_wlast <= 1'b0;
			else	r_axis_ddr_wlast  <= r_axis_ddr_wlast;
		end
		default:	r_axis_ddr_wlast <= 1'b0;
	endcase
end

endmodule