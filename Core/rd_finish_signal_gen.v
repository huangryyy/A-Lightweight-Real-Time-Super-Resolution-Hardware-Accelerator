module rd_finish_signal_gen(
	input		I_clk,
	input		I_rst_n,
	input		rd_finish_signal1,
	input		rd_finish_signal2,
	input		rd_finish_signal3,
	input		rd_tile_finish_signal,
	output		rd_finish_signal
);
reg	r_signal1_last = 1'b0;
reg	r_signal2_last = 1'b0;
reg	r_signal3_last = 1'b0;
reg r_tile_signal_last = 1'b0;
reg r_finish_signal = 1'b0;
reg	r_finish_signal_delay = 1'b0;
reg r_tile_finish_signal = 1'b0;
reg	r_tile_finish_signal_delay = 1'b0;
wire	tile_finish_signal;
always@(posedge I_clk)begin
	if(!I_rst_n)	r_signal1_last <= 1'b0;
	else if(rd_finish_signal)	r_signal1_last <= 1'b0;
	else if(rd_finish_signal1)	r_signal1_last <= 1'b1;
	else	r_signal1_last <= r_signal1_last;
end

always@(posedge I_clk)begin
	if(!I_rst_n)	r_signal2_last <= 1'b0;
	else if(tile_finish_signal)	r_signal2_last <= 1'b0;
	else if(rd_finish_signal2)	r_signal2_last <= 1'b1;
	else	r_signal2_last <= r_signal2_last;
end

always@(posedge I_clk)begin
	if(!I_rst_n)	r_signal3_last <= 1'b0;
	else if(tile_finish_signal)	r_signal3_last <= 1'b0;
	else if(rd_finish_signal3)	r_signal3_last <= 1'b1;
	else	r_signal3_last <= r_signal3_last;
end

always@(posedge I_clk)begin
	if(!I_rst_n)	r_tile_signal_last <= 1'b0;
	else if(tile_finish_signal)	r_tile_signal_last <= 1'b0;
	else if(rd_tile_finish_signal)	r_tile_signal_last <= 1'b1;
	else	r_tile_signal_last <= r_tile_signal_last;
end

always@(posedge I_clk)begin
	r_finish_signal <= r_signal1_last & r_signal2_last & r_signal3_last;
end
always@(posedge I_clk)begin
	r_finish_signal_delay <= r_finish_signal;
end
assign rd_finish_signal = r_finish_signal | r_finish_signal_delay;

always@(posedge I_clk)begin
	r_tile_finish_signal <= r_signal2_last & r_signal3_last & r_tile_signal_last;
end
always@(posedge I_clk)begin
	r_tile_finish_signal_delay <= r_tile_finish_signal;
end
assign tile_finish_signal = r_tile_finish_signal | r_tile_finish_signal_delay;

endmodule