`timescale 1ns / 1ps

module ddr_wt_core_conv(   
    input                    I_sys_clk                    ,   
    input                    I_sys_rst_n                  ,      
    input [63:0]             s_axis_wconfig_data          ,   
    input                    s_axis_wconfig_valid         ,   
    input                    s_axis_wconfig_last          ,   
    output reg               s_axis_wconfig_ready         =1'b1,     
    input [511:0]            S_axis_ddr_wdata             ,   
    input                    S_axis_ddr_wvalid            ,   
    input                    S_axis_ddr_wlast             ,   
    output                   S_axis_ddr_wready            ,      
    output [31:0]            M_axis_ddr_awdata            ,   
    output [7:0]             M_axis_ddr_awlen             ,   
    output reg               M_axis_ddr_awvalid           =1'b0,   
    input                    M_axis_ddr_awready           ,   
    
    output  [511:0]          M_axis_ddr_wdata             ,   
    output                   M_axis_ddr_wvalid            ,   
    output  reg              M_axis_ddr_wlast             ,   
    input                    M_axis_ddr_wready            ,
	output	reg				 O_wr_finish
    );
  
parameter P_BRUST_LEN        =    64     ;
parameter P_DDR_ADDR_SHIFT   =    4096   ;    

parameter S_IDLE        =    4'd0   ; 
parameter S_CONFIG      =    4'd1   ; 
parameter S_LEN_JDG     =    4'd2   ; 
parameter S_ADDR_GEN    =    4'd3   ; 
parameter S_ADDR_APP    =    4'd4   ; 

reg [3:0]                       r_state                             = 4'd0;  
reg [3:0]                       r_state_d                           ;   
reg [31:0]                      r_ddr_wt_len_reg                    =16'd0;
  

reg                             S_axis_ddr_wvalid_delay             ;
reg                             S_axis_ddr_wready_delay             ;
always@(posedge I_sys_clk)begin
    S_axis_ddr_wvalid_delay <= S_axis_ddr_wvalid;
    S_axis_ddr_wready_delay <= S_axis_ddr_wready;
end
  
always@(posedge I_sys_clk)  r_state_d <= r_state;

always@(posedge I_sys_clk)
begin
    if(~I_sys_rst_n)begin
        r_state          <= S_IDLE ;   
    end else case(r_state)
        S_IDLE:begin  
            r_state <= S_CONFIG ;   
        end 
        S_CONFIG:begin  
            if (s_axis_wconfig_ready && s_axis_wconfig_valid && s_axis_wconfig_last)begin      
                r_state <= S_LEN_JDG ;
            end else begin
                r_state <= S_CONFIG ;
            end
        end 
        S_LEN_JDG:begin
            if (r_ddr_wt_len_reg == 0)begin
                r_state <= S_CONFIG ;   
            end else begin
                r_state <= S_ADDR_GEN ;   
            end
        end 
        S_ADDR_GEN:begin
            if (M_axis_ddr_awvalid && M_axis_ddr_awready)begin
                r_state   <= S_ADDR_APP ;
            end else begin
                r_state <= S_ADDR_GEN;
            end
        end 
        S_ADDR_APP:begin
            if(M_axis_ddr_wvalid && M_axis_ddr_wready && M_axis_ddr_wlast)begin
                r_state <= S_LEN_JDG ;
            end else begin
                r_state <= S_ADDR_APP;
            end
        end
        default:begin
            r_state <= S_IDLE ;   
        end 
    endcase
end

always@(posedge I_sys_clk)begin
	case(r_state)
		S_LEN_JDG:begin
			if(r_ddr_wt_len_reg == 0)begin
                O_wr_finish <= 1'b1;   
            end else begin
                O_wr_finish <= 1'b0;
            end
		end
		default:begin
            O_wr_finish <= 1'b0;
        end
	endcase
end
////////////////////////////////////////////////////////////////////////////////
always@(posedge I_sys_clk)begin 
	case(r_state)
        S_CONFIG:begin 
             if (s_axis_wconfig_ready & s_axis_wconfig_valid & s_axis_wconfig_last)begin 
                r_ddr_wt_len_reg <= s_axis_wconfig_data[31:0];
             end
        end 
        S_ADDR_GEN:begin
            if(M_axis_ddr_awvalid & M_axis_ddr_awready)begin
                if(r_ddr_wt_len_reg <= P_BRUST_LEN)begin
                    r_ddr_wt_len_reg <= 32'd0;
                end else begin
                    r_ddr_wt_len_reg <= r_ddr_wt_len_reg - P_BRUST_LEN;
                end
            end
        end
        default: begin
			r_ddr_wt_len_reg <= r_ddr_wt_len_reg;
        end
    endcase
end

always@(posedge I_sys_clk)begin
	if(r_state == S_CONFIG)begin
        if(s_axis_wconfig_ready & s_axis_wconfig_valid & s_axis_wconfig_last)begin
            s_axis_wconfig_ready <= 1'b0;         
        end else begin
            s_axis_wconfig_ready <= 1'b1;         
        end 
    end else begin
        s_axis_wconfig_ready <= 1'b0;         
    end
end
////////////////////////////////////////////////////////////////////////////////
reg [31:0]                      r_ddr_addr_data                     =32'd0;   
reg [7:0]                       r_ddr_addr_len                      =8'd0;   

////////////////////////////////////////////////////////////////////////////////
always@(posedge I_sys_clk)begin
	if(r_state == S_CONFIG)begin
        r_ddr_addr_data <= s_axis_wconfig_data[63:32];   
    end else if(r_state == S_ADDR_GEN & (M_axis_ddr_awvalid & M_axis_ddr_awready))begin
        r_ddr_addr_data <= r_ddr_addr_data + P_DDR_ADDR_SHIFT;   
    end else begin
        r_ddr_addr_data <= r_ddr_addr_data;
    end
end
////////////////////////////////////////////////////////////////////////////////
always@(posedge I_sys_clk)begin
	if(r_state == S_ADDR_GEN && r_state_d !=r_state)begin
        if(r_ddr_wt_len_reg <= P_BRUST_LEN)begin
            r_ddr_addr_len <= r_ddr_wt_len_reg[7:0] - 8'd1;
        end else begin
            r_ddr_addr_len <= P_BRUST_LEN[7:0] - 8'd1;
        end
    end else begin
        r_ddr_addr_len <= r_ddr_addr_len  ;   
    end
end
////////////////////////////////////////////////////////////////////////////////
reg	[31:0]	data_unconfig_cnt	= 32'b0; 
always@(posedge I_sys_clk)	begin
	if(S_axis_ddr_wvalid_delay & S_axis_ddr_wready_delay & M_axis_ddr_awvalid & M_axis_ddr_awready)	data_unconfig_cnt <= data_unconfig_cnt - (r_ddr_addr_len+8'd1) +  32'd1;
	else if(M_axis_ddr_awvalid & M_axis_ddr_awready)	data_unconfig_cnt <= data_unconfig_cnt - (r_ddr_addr_len+8'd1);
	else if(S_axis_ddr_wvalid_delay & S_axis_ddr_wready_delay)	data_unconfig_cnt <= data_unconfig_cnt + 32'd1;
	else data_unconfig_cnt <= data_unconfig_cnt;
end

always @(posedge I_sys_clk)begin
	if(r_state == S_ADDR_GEN && r_state_d == r_state)begin
        if (M_axis_ddr_awvalid & M_axis_ddr_awready)begin
            M_axis_ddr_awvalid <= 1'b0;
        end else if(data_unconfig_cnt >= (r_ddr_addr_len+8'b1)) begin
            M_axis_ddr_awvalid <= 1'b1;
        end else begin
            M_axis_ddr_awvalid <= 1'b0;   
        end
    end else begin
        M_axis_ddr_awvalid <= 1'b0;
    end
end

assign M_axis_ddr_awdata       =   r_ddr_addr_data   ;   
assign M_axis_ddr_awlen        =   r_ddr_addr_len    ;


reg	valid_ctrl;
always@(posedge I_sys_clk)begin
	case(r_state)
		S_ADDR_APP:begin	
			if(M_axis_ddr_wvalid & M_axis_ddr_wready & M_axis_ddr_wlast) valid_ctrl <= 1'b0;
			else valid_ctrl <= 1'b1;
		end
		default:begin
            valid_ctrl	<= 1'b0;
        end
	endcase
end

wire                            w_ddr_wt_data_fifo_prg              ;   
wire [259:0]                    w_ddr_wt_data_dout                  ;   
wire							fifo_valid							;

fifo_512din_512dout_512d inst_ddr_wt_data_fifo_conv (
    .srst                                 (~I_sys_rst_n                                     ),  
    .clk                              	  (I_sys_clk                                        ),  // input wire rd_clk
    .din                                  (S_axis_ddr_wdata                                 ),  // input wire [511 : 0] din
    .wr_en                                (S_axis_ddr_wvalid_delay & S_axis_ddr_wready_delay),  // input wire wr_en
    .rd_en                                (M_axis_ddr_wready & M_axis_ddr_wvalid            ), 
	.dout                                 (M_axis_ddr_wdata                   	            ),  // output wire [511 : 0] dout
    .full                                 (                                                 ),  // output wire full
    .empty                                (                                                 ),  // output wire empty
    .valid                                (fifo_valid		                                ),
    .prog_full                            (w_ddr_wt_data_fifo_prg                           )   // output wire prog_full
);
assign	M_axis_ddr_wvalid = valid_ctrl & fifo_valid;

reg [15:0]	fifo_out_count = 16'b0;
always@(posedge I_sys_clk)begin
	if(M_axis_ddr_wready && M_axis_ddr_wvalid && fifo_out_count == M_axis_ddr_awlen)	fifo_out_count <= 16'b0;
	else if(M_axis_ddr_wready && M_axis_ddr_wvalid)	fifo_out_count <= fifo_out_count + 16'b1;
	else	fifo_out_count <= fifo_out_count;
end

always@(posedge I_sys_clk)begin
	if(M_axis_ddr_wready && M_axis_ddr_wvalid && fifo_out_count == M_axis_ddr_awlen - 16'd1)	M_axis_ddr_wlast <= 1'b1;
	else if(M_axis_ddr_wready && M_axis_ddr_wvalid && fifo_out_count == M_axis_ddr_awlen)	M_axis_ddr_wlast <= 1'b0;
	else if(fifo_out_count == M_axis_ddr_awlen)	M_axis_ddr_wlast <= 1'b1;
	else	M_axis_ddr_wlast <= 1'b0;
end

reg r_ddr_data_in_enable=1'b0;
always@(posedge I_sys_clk)begin
	if (S_axis_ddr_wvalid & S_axis_ddr_wready & S_axis_ddr_wlast) begin
	    r_ddr_data_in_enable <= 1'b0;
	end else if (r_state == S_CONFIG & s_axis_wconfig_ready & s_axis_wconfig_valid & s_axis_wconfig_last) begin
	    r_ddr_data_in_enable  <= 1'b1;
	end 
end

assign	S_axis_ddr_wready = r_ddr_data_in_enable?~w_ddr_wt_data_fifo_prg:1'b0;

endmodule
