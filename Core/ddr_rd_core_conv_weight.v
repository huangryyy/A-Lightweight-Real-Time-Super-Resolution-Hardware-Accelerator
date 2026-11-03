`timescale 1ns / 1ps

module ddr_rd_core_conv_weight( 
    input                    I_sys_clk                    ,   
    input                    I_sys_rst_n                  ,    
    input [63:0]             s_axis_rconfig_data          ,   
    input                    s_axis_rconfig_valid         ,   
    input                    s_axis_rconfig_last          ,   
    output reg               s_axis_rconfig_ready         =1'b1,     
    output reg [2047:0]      M_axis_ddr_rdata             ,   
    output reg               M_axis_ddr_rvalid            ,      
    input                    M_axis_ddr_rready            ,      
    output [31:0]            M_axis_ddr_ardata            ,   
    output [7:0]             M_axis_ddr_arlen             ,   
    output reg               M_axis_ddr_arvalid           =1'b0,   
    input                    M_axis_ddr_arready           ,   
    
    input  [511:0]           S_axis_ddr_rdata             ,   
    input                    S_axis_ddr_rvalid            ,   
    input                    S_axis_ddr_rlast             ,
	output					 M_fifo_empty				  ,
    output 	                 S_axis_ddr_rready               
);
  
parameter P_BRUST_LEN        =    64    ;
parameter P_DDR_ADDR_SHIFT   =    4096   ;  

parameter S_IDLE        =    4'd0   ; 
parameter S_CONFIG      =    4'd1   ; 
parameter S_LEN_JDG     =    4'd2   ; 
parameter S_ADDR_GEN    =    4'd3   ; 
parameter S_ADDR_APP    =    4'd4   ; 

reg [3:0]                       r_state                             ;  
reg [31:0]                      r_ddr_rd_len_reg                    =32'd0;

wire [511:0] r_axis_ddr_rdata;
wire         r_axis_ddr_rvalid;
reg [15:0] rvalid_cnt;
always @(posedge I_sys_clk)
begin
    if (~I_sys_rst_n) begin
        r_state          <= S_IDLE ;   
    end else case (r_state)
        S_IDLE        :  begin  
            r_state          <= S_CONFIG ;   
        end 
        S_CONFIG     :  begin  
            if (s_axis_rconfig_ready & s_axis_rconfig_valid & s_axis_rconfig_last) begin      
                r_state          <= S_LEN_JDG ;
            end   
        end 
        S_LEN_JDG :  begin
            if (r_ddr_rd_len_reg == 0) begin
                r_state   <= S_CONFIG ;   
            end else begin
                r_state   <= S_ADDR_GEN  ;   
            end
        end 
        S_ADDR_GEN    :  begin
            if (M_axis_ddr_arvalid & M_axis_ddr_arready) begin
                r_state   <= S_ADDR_APP ;
            end 
        end 
        S_ADDR_APP    :  begin
            if (S_axis_ddr_rvalid & S_axis_ddr_rready & S_axis_ddr_rlast) begin
                r_state   <= S_LEN_JDG ;
            end   
        end 
       
        default       :  begin
            r_state   <= S_IDLE ;   
        end 
    endcase
end
////////////////////////////////////////////////////////////////////////////////
always @(posedge I_sys_clk)
begin
    // if (~I_sys_rst_n) begin
        // r_ddr_rd_len_reg <= 32'd0;
    // end else 
	case (r_state)
        S_CONFIG : begin 
             if (s_axis_rconfig_ready & s_axis_rconfig_valid & s_axis_rconfig_last) begin
                 r_ddr_rd_len_reg <= s_axis_rconfig_data[31:0]; //相对取M_axis_ddr_rdata(512bit)的次数，取S_axis_ddr_rdata（512bit）的次数是其1倍（即不移动）
             end
        end 
        S_ADDR_GEN : begin
            if (M_axis_ddr_arvalid & M_axis_ddr_arready) begin
                if (r_ddr_rd_len_reg <= P_BRUST_LEN) begin
                     r_ddr_rd_len_reg <= 32'd0;
                end else begin
                     r_ddr_rd_len_reg <= r_ddr_rd_len_reg - P_BRUST_LEN;
                end
            end
        end
        default: begin
			r_ddr_rd_len_reg <= r_ddr_rd_len_reg;
        end
    endcase
end

always @(posedge I_sys_clk)
begin
	if (r_state == S_CONFIG) begin
        if (s_axis_rconfig_ready & s_axis_rconfig_valid & s_axis_rconfig_last) begin
            s_axis_rconfig_ready  <= 1'b0;         
        end else begin
            s_axis_rconfig_ready  <= 1'b1;         
        end 
    end else begin
        s_axis_rconfig_ready  <= 1'b0;         
    end
end
////////////////////////////////////////////////////////////////////////////////
reg [31:0]                      r_ddr_addr_data                     =32'd0;   
reg [7:0]                       r_ddr_addr_len                      =8'd0;   
reg                             r_ddr_addr_valid                    ;   
////////////////////////////////////////////////////////////////////////////////
always@ (posedge I_sys_clk)
begin
	if (r_state == S_CONFIG) begin
        r_ddr_addr_data    <=   s_axis_rconfig_data[63:32];   
    end else if (r_state == S_ADDR_GEN & (M_axis_ddr_arvalid & M_axis_ddr_arready)) begin
        r_ddr_addr_data    <=   r_ddr_addr_data + P_DDR_ADDR_SHIFT;   
    end
end
////////////////////////////////////////////////////////////////////////////////
always@ (posedge I_sys_clk)
begin
	if (r_state == S_ADDR_GEN) begin
         if (r_ddr_rd_len_reg <= P_BRUST_LEN) begin
             r_ddr_addr_len <= r_ddr_rd_len_reg - 1;
         end else begin
             r_ddr_addr_len <= P_BRUST_LEN - 1;
         end
     end 
end
////////////////////////////////////////////////////////////////////////////////
always @(posedge I_sys_clk)
begin
	if(r_state == S_ADDR_GEN) begin
        if (M_axis_ddr_arvalid & M_axis_ddr_arready) begin
            M_axis_ddr_arvalid        <= 1'b0;
        end else begin
            M_axis_ddr_arvalid        <= 1'b1;
        end   
    end
end

assign M_axis_ddr_ardata       =   r_ddr_addr_data   ;   
assign M_axis_ddr_arlen        =   r_ddr_addr_len    ;

////////////////////////////////////////////////////////////////////////////////
reg [511:0]                     r_ddr_rdata_data                   =0;   
reg                             r_ddr_rdata_wren                   =0;   
wire                            w_ddr_rd_data_fifo_prg              ;   

fifo_512din_512dout_512d inst_fifo_512din_512dout_512d (
    .srst                                 (~I_sys_rst_n                         ),          // input wire rst
    .clk                               	  (I_sys_clk                            ),          // input wire clk         // input wire clk
    //.din                                 (r_ddr_rdata_data                     ),
	.din                                  (S_axis_ddr_rdata                     ),          // input wire [511 : 0] din
    .wr_en                                (S_axis_ddr_rvalid & S_axis_ddr_rready),          // input wire wr_en
    //.wr_en                              (r_ddr_rdata_wren                     ),
	.rd_en                                (M_axis_ddr_rready & r_axis_ddr_rvalid),          // input wire rd_en
    .dout                                 (r_axis_ddr_rdata  					),          // output wire [256 : 0] dout
    .full                                 (                                     ),          // output wire full
    .empty                                (M_fifo_empty                         ),          // output wire empty
    .valid                                (r_axis_ddr_rvalid                    ),          // output wire valid
    .prog_full                            (w_ddr_rd_data_fifo_prg               )  
	// output wire prog_full
);
always@(posedge I_sys_clk)begin
    if(!I_sys_rst_n)begin
        rvalid_cnt <= 16'd0;
    end else if(r_axis_ddr_rvalid && rvalid_cnt == 16'd3)begin
        rvalid_cnt <= 16'd0;
    end else if(r_axis_ddr_rvalid)begin
        rvalid_cnt <= rvalid_cnt + 16'd1;
    end else begin
        rvalid_cnt <= rvalid_cnt;
    end
end
always@(posedge I_sys_clk)begin
    if(!I_sys_rst_n)begin
        M_axis_ddr_rvalid <= 1'b0;
    end else if(r_axis_ddr_rvalid && rvalid_cnt == 'd3)begin
        M_axis_ddr_rvalid <= 1'b1;
    end else begin
        M_axis_ddr_rvalid <= 1'b0;
    end
end
always@(posedge I_sys_clk)begin
    if(!I_sys_rst_n)begin
        M_axis_ddr_rdata <= 'd0;
    end else if(r_axis_ddr_rvalid)begin
        M_axis_ddr_rdata <= {M_axis_ddr_rdata[1535:0], r_axis_ddr_rdata};
    end else begin
        M_axis_ddr_rdata <= M_axis_ddr_rdata;
    end
end

assign S_axis_ddr_rready = !w_ddr_rd_data_fifo_prg;

reg [15:0]	fifo_out_count = 16'b0;
always@(posedge I_sys_clk)begin
	if(S_axis_ddr_rvalid && S_axis_ddr_rready)	fifo_out_count <= fifo_out_count + 16'b1;
	else	fifo_out_count <= fifo_out_count;
end

endmodule
