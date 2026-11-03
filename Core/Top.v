module Top#(
	parameter RAM_LATENCY = 2,
    parameter PARAM_SIZE = 4,
    parameter depth_inp = 65536,      
    parameter addr_bit_inp = 16,  
    parameter depth_weight = 256,      
    parameter addr_bit_weight = 8,   
    parameter depth_bias = 16,      
    parameter addr_bit_bias = 4,   
    parameter depth_out = 65536,      
    parameter addr_bit_out = 16,  
    parameter bits_input  = 8,        
    parameter bits_weight = 8,      
    parameter bits_bias   = 16,    
    parameter bits_eleout = 16,       
    parameter bits_addout = 31,       
    parameter bits_macout = 18,
    parameter bits_quantout = 8,
    parameter stride = 1,    
    parameter pixel_para = 4,   
    parameter ic_para = 16,           
    parameter oc_para = 16           
)(
    // ddr4
    output [16 : 0] ddr4_adr,
    output [1 : 0]  ddr4_ba,
    output [0 : 0]  ddr4_cke,
    output [0 : 0]  ddr4_cs_n,
    inout [7 : 0]   ddr4_dm_dbi_n,
    inout [63 : 0]  ddr4_dq,
    inout [7 : 0]   ddr4_dqs_c,
    inout [7 : 0]   ddr4_dqs_t,
    output [0 : 0]  ddr4_odt,
    output [0 : 0]  ddr4_bg,
    output          ddr4_reset_n,
    output          ddr4_act_n,
    output [0:0]    ddr4_ck_c,
    output [0:0]    ddr4_ck_t,
    input           ddr4_sys_clk_p,        
    input           ddr4_sys_clk_n,
	input  [15:0]	pcie_mgt_rxn,
	input  [15:0]	pcie_mgt_rxp,
	output [15:0]	pcie_mgt_txn,
	output [15:0]	pcie_mgt_txp,
	input			pcie_resetn,
	input  [0:0]	pcie_sys_clk_p,        
	input  [0:0]	pcie_sys_clk_n
);
wire	[3:0]	S00_AXI_ARID;
wire	[31:0]	S00_AXI_ARADDR;
wire	[7:0]	S00_AXI_ARLEN;
wire	[2:0]	S00_AXI_ARSIZE;
wire	[1:0]	S00_AXI_ARBURST;
wire			S00_AXI_ARLOCK;
wire	[3:0]	S00_AXI_ARCACHE;
wire	[2:0]	S00_AXI_ARPROT;
wire	[3:0]	S00_AXI_ARQOS;
wire			S00_AXI_ARVALID;
wire			S00_AXI_ARREADY;
wire	[3:0]	S00_AXI_RID;
wire	[511:0]	S00_AXI_RDATA;
wire	[1:0]	S00_AXI_RRESP;
wire	       	S00_AXI_RVALID;
wire			S00_AXI_RLAST;
wire			S00_AXI_RREADY;	
wire	[3:0]	S00_AXI_AWID;
wire	[31:0]	S00_AXI_AWADDR;
wire	[7:0]	S00_AXI_AWLEN;
wire	[2:0]	S00_AXI_AWSIZE;
wire	[1:0]	S00_AXI_AWBURST;
wire			S00_AXI_AWLOCK;
wire	[3:0]	S00_AXI_AWCACHE;
wire	[2:0]	S00_AXI_AWPROT;
wire	[3:0]	S00_AXI_AWQOS;
wire			S00_AXI_AWVALID;
wire			S00_AXI_AWREADY;
wire	[511:0]	S00_AXI_WDATA;
wire	[63:0]	S00_AXI_WSTRB;
wire			S00_AXI_WVALID;
wire			S00_AXI_WLAST;
wire			S00_AXI_WREADY;
wire	[3:0]	S00_AXI_BID;
wire	[1:0]	S00_AXI_BRESP;
wire			S00_AXI_BVALID;
wire			S00_AXI_BREADY;	

wire	[3:0]	S01_AXI_ARID;
wire	[31:0]	S01_AXI_ARADDR;
wire	[7:0]	S01_AXI_ARLEN;
wire	[2:0]	S01_AXI_ARSIZE;
wire	[1:0]	S01_AXI_ARBURST;
wire			S01_AXI_ARLOCK;
wire	[3:0]	S01_AXI_ARCACHE;
wire	[2:0]	S01_AXI_ARPROT;
wire	[3:0]	S01_AXI_ARQOS;
wire			S01_AXI_ARVALID;
wire			S01_AXI_ARREADY;
wire	[3:0]	S01_AXI_RID;
wire	[511:0]	S01_AXI_RDATA;
wire	[1:0]	S01_AXI_RRESP;
wire	       	S01_AXI_RVALID;
wire			S01_AXI_RLAST;
wire			S01_AXI_RREADY;	
// wire	[3:0]	S01_AXI_AWID;
// wire	[31:0]	S01_AXI_AWADDR;
// wire	[7:0]	S01_AXI_AWLEN;
// wire	[2:0]	S01_AXI_AWSIZE;
// wire	[1:0]	S01_AXI_AWBURST;
// wire			S01_AXI_AWLOCK;
// wire	[3:0]	S01_AXI_AWCACHE;
// wire	[2:0]	S01_AXI_AWPROT;
// wire	[3:0]	S01_AXI_AWQOS;
// wire			S01_AXI_AWVALID;
// wire			S01_AXI_AWREADY;
// wire	[511:0]	S01_AXI_WDATA;
// wire	[63:0]	S01_AXI_WSTRB;
// wire			S01_AXI_WVALID;
// wire			S01_AXI_WLAST;
// wire			S01_AXI_WREADY;
// wire	[3:0]	S01_AXI_BID;
// wire	[1:0]	S01_AXI_BRESP;
// wire			S01_AXI_BVALID;
// wire			S01_AXI_BREADY;	

wire	[3:0]	S02_AXI_ARID;
wire	[31:0]	S02_AXI_ARADDR;
wire	[7:0]	S02_AXI_ARLEN;
wire	[2:0]	S02_AXI_ARSIZE;
wire	[1:0]	S02_AXI_ARBURST;
wire			S02_AXI_ARLOCK;
wire	[3:0]	S02_AXI_ARCACHE;
wire	[2:0]	S02_AXI_ARPROT;
wire	[3:0]	S02_AXI_ARQOS;
wire			S02_AXI_ARVALID;
wire			S02_AXI_ARREADY;
wire	[3:0]	S02_AXI_RID;
wire	[511:0]	S02_AXI_RDATA;
wire	[1:0]	S02_AXI_RRESP;
wire	       	S02_AXI_RVALID;
wire			S02_AXI_RLAST;
wire			S02_AXI_RREADY;	
// wire	[3:0]	S02_AXI_AWID;
// wire	[31:0]	S02_AXI_AWADDR;
// wire	[7:0]	S02_AXI_AWLEN;
// wire	[2:0]	S02_AXI_AWSIZE;
// wire	[1:0]	S02_AXI_AWBURST;
// wire			S02_AXI_AWLOCK;
// wire	[3:0]	S02_AXI_AWCACHE;
// wire	[2:0]	S02_AXI_AWPROT;
// wire	[3:0]	S02_AXI_AWQOS;
// wire			S02_AXI_AWVALID;
// wire			S02_AXI_AWREADY;
// wire	[511:0]	S02_AXI_WDATA;
// wire	[63:0]	S02_AXI_WSTRB;
// wire			S02_AXI_WVALID;
// wire			S02_AXI_WLAST;
// wire			S02_AXI_WREADY;
// wire	[3:0]	S02_AXI_BID;
// wire	[1:0]	S02_AXI_BRESP;
// wire			S02_AXI_BVALID;
// wire			S02_AXI_BREADY;	

//PCIE XMDA
wire	[3:0]	S03_AXI_ARID;
wire	[63:0]	S03_AXI_ARADDR;
wire	[7:0]	S03_AXI_ARLEN;
wire	[2:0]	S03_AXI_ARSIZE;
wire	[1:0]	S03_AXI_ARBURST;
wire			S03_AXI_ARLOCK;
wire	[3:0]	S03_AXI_ARCACHE;
wire	[2:0]	S03_AXI_ARPROT;
wire	[3:0]	S03_AXI_ARQOS;
wire			S03_AXI_ARVALID;
wire			S03_AXI_ARREADY;
wire	[3:0]	S03_AXI_RID;
wire	[511:0]	S03_AXI_RDATA;
wire	[1:0]	S03_AXI_RRESP;
wire	       	S03_AXI_RVALID;
wire			S03_AXI_RLAST;
wire			S03_AXI_RREADY;	
wire	[3:0]	S03_AXI_AWID;
wire	[63:0]	S03_AXI_AWADDR;
wire	[7:0]	S03_AXI_AWLEN;
wire	[2:0]	S03_AXI_AWSIZE;
wire	[1:0]	S03_AXI_AWBURST;
wire			S03_AXI_AWLOCK;
wire	[3:0]	S03_AXI_AWCACHE;
wire	[2:0]	S03_AXI_AWPROT;
wire	[3:0]	S03_AXI_AWQOS;
wire			S03_AXI_AWVALID;
wire			S03_AXI_AWREADY;
wire	[511:0]	S03_AXI_WDATA;
wire	[63:0]	S03_AXI_WSTRB;
wire			S03_AXI_WVALID;
wire			S03_AXI_WLAST;
wire			S03_AXI_WREADY;
wire	[3:0]	S03_AXI_BID;
wire	[1:0]	S03_AXI_BRESP;
wire			S03_AXI_BVALID;
wire			S03_AXI_BREADY;	

wire	[7:0]	M00_axi_awid	        ;
wire	[31:0]	M00_axi_awaddr	        ;
wire	[7:0]	M00_axi_awlen	        ;
wire	[2:0]	M00_axi_awsize	        ;
wire	[1:0]	M00_axi_awburst         ;
wire			M00_axi_awlock	        ;
wire	[3:0]	M00_axi_awcache         ;
wire	[2:0]	M00_axi_awprot	        ;
wire	[3:0]	M00_axi_awqos	        ;
wire			M00_axi_awvalid         ;
wire			M00_axi_awready         ;
wire	[511:0]	M00_axi_wdata	        ;
wire	[63:0]	M00_axi_wstrb	        ;
wire			M00_axi_wlast	        ;
wire			M00_axi_wvalid	        ;
wire			M00_axi_wready	        ;
wire			M00_axi_bready	        ;
wire	[7:0]	M00_axi_bid	            ;
wire	[1:0]	M00_axi_bresp	        ;
wire			M00_axi_bvalid	        ;
wire	[7:0]	M00_axi_arid	        ;
wire	[31:0]	M00_axi_araddr	        ;
wire	[7:0]	M00_axi_arlen	        ;
wire	[2:0]	M00_axi_arsize	        ;
wire	[1:0]	M00_axi_arburst         ;
wire			M00_axi_arlock	        ;
wire	[3:0]	M00_axi_arcache         ;
wire	[2:0]	M00_axi_arprot	        ;
wire	[3:0]	M00_axi_arqos	        ;
wire			M00_axi_arvalid         ;
wire			M00_axi_arready         ;
wire			M00_axi_rready	        ;
wire	[7:0]	M00_axi_rid	            ;
wire	[511:0]	M00_axi_rdata	        ;
wire	[1:0]	M00_axi_rresp	        ;
wire			M00_axi_rlast	        ;
wire			M00_axi_rvalid			;


wire	[31:0]	m_axil_awaddr			;  
wire	[2:0]	m_axil_awprot           ;
wire			m_axil_awvalid          ;
wire			m_axil_awready          ;
wire	[31:0]	m_axil_wdata            ;
wire	[3:0]	m_axil_wstrb            ;
wire			m_axil_wvalid           ;
wire			m_axil_wready           ;
wire			m_axil_bvalid           ;
wire	[1:0]	m_axil_bresp            ;
wire			m_axil_bready           ;
wire	[31:0]	m_axil_araddr           ;
wire	[2:0]	m_axil_arprot           ;
wire			m_axil_arvalid          ;
wire			m_axil_arready          ;
wire	[31:0]	m_axil_rdata            ;
wire	[1:0]	m_axil_rresp            ;
wire			m_axil_rvalid           ;
wire			m_axil_rready	        ;

wire			clk_out1				;
wire			dcm_locked				;

wire            clk_out2                ;

wire			peripheral_aresetn0		;
wire			peripheral_aresetn1		;

wire			ui_clk					;   
wire			ui_clk_sync_rst			;
wire            init_calib_complete     ;
wire            sys_rst                 ;

wire            pcie_sys_clk_gt         ;   
wire			pcie_sys_clk			;   
wire			pcie_aclk				;	
wire			pcie_aresetn			;
wire            user_lnk_up             ;


wire [319:0]	O_conv_config_data	    ;
wire 		    O_conv_start_signal	    ;
wire 		    I_conv_finish_signal    ;

wire [2:0]      O_kernel_h              ;
wire [2:0]      O_kernel_w              ;
wire            O_ReLU_enable           ;
wire O_first_layer;
wire            O_last_layer            ;

wire			conv_rd_finish_signal	;
wire			O_rd_finish_signal1		;
wire			O_rd_finish_signal2		;
wire			O_rd_finish_signal3		;
wire			O_wr_start_signal		;

wire            O_wr_tile_finish_signal ;
wire            O_rd_tile_finish_signal ;

wire [16:0]     O_feature_length        ;

wire			                            O_wr_en1				;
wire	[addr_bit_inp-1:0]	                O_wr_ram_addr1			;
wire	[pixel_para*bits_input*ic_para-1:0]	        O_wr_ram_data1			;
wire			                            O_wr_en2				;
wire	[addr_bit_weight-1:0]	            O_wr_ram_addr2			;
wire	[bits_weight*ic_para*oc_para-1:0]	O_wr_ram_data2			;
wire			                            O_wr_en3				;
wire	[addr_bit_bias-1:0]	                O_wr_ram_addr3			;
wire	[bits_bias*oc_para-1:0]	            O_wr_ram_data3			;
wire			                            O_rd_en1				;
wire	[addr_bit_out-1:0]	                O_rd_ram_addr1			;
wire	[pixel_para*bits_quantout*oc_para-1:0]	        O_rd_ram_data1  		;

wire [3:0]         pad_h ;
wire [3:0]         pad_w ;     

reg [17:0] stage_debug;
wire [31:0] core_debug_status = {dcm_locked,peripheral_aresetn0,init_calib_complete,pcie_aresetn,10'b0,stage_debug};
always @(posedge clk_out1) begin
    if (!peripheral_aresetn0 || O_conv_start_signal) stage_debug <= 0;
    else begin
        stage_debug[0] <= stage_debug[0] | O_rd_finish_signal1;
        stage_debug[1] <= stage_debug[1] | O_rd_finish_signal2;
        stage_debug[2] <= stage_debug[2] | O_rd_finish_signal3;
        stage_debug[3] <= stage_debug[3] | conv_rd_finish_signal;
        stage_debug[4] <= stage_debug[4] | O_wr_start_signal;
        stage_debug[5] <= stage_debug[5] | I_conv_finish_signal;
        stage_debug[6] <= stage_debug[6] | O_wr_en1;
        stage_debug[7] <= stage_debug[7] | O_wr_en2;
        stage_debug[8] <= stage_debug[8] | O_wr_en3;
        stage_debug[9] <= stage_debug[9] | O_rd_en1;
        stage_debug[10] <= stage_debug[10] | (S00_AXI_AWVALID && S00_AXI_AWREADY);
        stage_debug[11] <= stage_debug[11] | (S00_AXI_WVALID && S00_AXI_WREADY);
        stage_debug[12] <= stage_debug[12] | (S01_AXI_ARVALID && S01_AXI_ARREADY);
        stage_debug[13] <= stage_debug[13] | (S02_AXI_ARVALID && S02_AXI_ARREADY);
        stage_debug[14] <= stage_debug[14] | (S00_AXI_ARVALID && S00_AXI_ARREADY);
        stage_debug[15] <= stage_debug[15] | S01_AXI_RVALID;
        stage_debug[16] <= stage_debug[16] | S02_AXI_RVALID;
        stage_debug[17] <= stage_debug[17] | S00_AXI_RVALID;
    end
end

// clk setting
clk_wiz_0	inst_clk_wiz_0
   (.clk_out1(clk_out1),
    .reset(!pcie_resetn),
    .locked(dcm_locked),
    .clk_in1(pcie_aclk));

clk_wiz_1 inst_clk_wiz_1
   (
    .clk_out1(),   
    .locked(sys_rst),     
    .clk_in1(clk_out2)     
);

proc_sys_reset_0 inst_proc_sys_reset_0
   (.slowest_sync_clk(clk_out1),
    .ext_reset_in(pcie_resetn),
	.aux_reset_in(1'd1),
    .mb_debug_sys_rst(1'd0),
    .dcm_locked(dcm_locked),
    .peripheral_aresetn(peripheral_aresetn0)
);

proc_sys_reset_ddr inst_proc_sys_reset_ddr
   (.slowest_sync_clk(ui_clk),
    .ext_reset_in(ui_clk_sync_rst),
	.aux_reset_in(1'b0),
	.mb_debug_sys_rst(1'b0),
    .dcm_locked(1'b1),
    .peripheral_aresetn(peripheral_aresetn1)
);

//axi cross_bar instance
axi_interconnect_0 inst_axi_interconnect(
  .INTERCONNECT_ACLK        (clk_out1            ),  // input wire INTERCONNECT_ACLK
  .INTERCONNECT_ARESETN     (peripheral_aresetn0 ),  // input wire INTERCONNECT_ARESETN
  .S00_AXI_ARESET_OUT_N     (                    ),  // output wire S00_AXI_ARESET_OUT_N
  .S00_AXI_ACLK             (clk_out1            ),  // input wire S00_AXI_ACLK
  .S00_AXI_AWID             (S00_AXI_AWID  	     ),  // input wire [3 : 0] S00_AXI_AWID
  .S00_AXI_AWADDR           (S00_AXI_AWADDR	     ),  // input wire [31 : 0] S00_AXI_AWADDR
  .S00_AXI_AWLEN            (S00_AXI_AWLEN	     ),  // input wire [7 : 0] S00_AXI_AWLEN
  .S00_AXI_AWSIZE           (S00_AXI_AWSIZE	     ),  // input wire [2 : 0] S00_AXI_AWSIZE
  .S00_AXI_AWBURST          (S00_AXI_AWBURST     ),  // input wire [1 : 0] S00_AXI_AWBURST
  .S00_AXI_AWLOCK           (S00_AXI_AWLOCK	     ),  // input wire S00_AXI_AWLOCK
  .S00_AXI_AWCACHE          (S00_AXI_AWCACHE     ),  // input wire [3 : 0] S00_AXI_AWCACHE
  .S00_AXI_AWPROT           (S00_AXI_AWPROT	     ),  // input wire [2 : 0] S00_AXI_AWPROT
  .S00_AXI_AWQOS            (S00_AXI_AWQOS	     ),  // input wire [3 : 0] S00_AXI_AWQOS
  .S00_AXI_AWVALID          (S00_AXI_AWVALID     ),  // input wire S00_AXI_AWVALID
  .S00_AXI_AWREADY          (S00_AXI_AWREADY     ),  // output wire S00_AXI_AWREADY
  .S00_AXI_WDATA            (S00_AXI_WDATA	     ),  // input wire [511 : 0] S00_AXI_WDATA
  .S00_AXI_WSTRB            (S00_AXI_WSTRB	     ),  // input wire [63 : 0] S00_AXI_WSTRB
  .S00_AXI_WLAST            (S00_AXI_WLAST	     ),  // input wire S00_AXI_WLAST
  .S00_AXI_WVALID           (S00_AXI_WVALID	     ),  // input wire S00_AXI_WVALID
  .S00_AXI_WREADY           (S00_AXI_WREADY	     ),  // output wire S00_AXI_WREADY
  .S00_AXI_BID              (S00_AXI_BID	     ),  // output wire [3 : 0] S00_AXI_BID
  .S00_AXI_BRESP            (S00_AXI_BRESP	     ),  // output wire [1 : 0] S00_AXI_BRESP
  .S00_AXI_BVALID           (S00_AXI_BVALID	     ),  // output wire S00_AXI_BVALID
  .S00_AXI_BREADY           (S00_AXI_BREADY	     ),  // input wire S00_AXI_BREADY
  .S00_AXI_ARID             (S00_AXI_ARID	     ),  // input wire [3 : 0] S00_AXI_ARID
  .S00_AXI_ARADDR           (S00_AXI_ARADDR	     ),  // input wire [31 : 0] S00_AXI_ARADDR
  .S00_AXI_ARLEN            (S00_AXI_ARLEN	     ),  // input wire [7 : 0] S00_AXI_ARLEN
  .S00_AXI_ARSIZE           (S00_AXI_ARSIZE	     ),  // input wire [2 : 0] S00_AXI_ARSIZE
  .S00_AXI_ARBURST          (S00_AXI_ARBURST     ),  // input wire [1 : 0] S00_AXI_ARBURST
  .S00_AXI_ARLOCK           (S00_AXI_ARLOCK	     ),  // input wire S00_AXI_ARLOCK
  .S00_AXI_ARCACHE          (S00_AXI_ARCACHE     ),  // input wire [3 : 0] S00_AXI_ARCACHE
  .S00_AXI_ARPROT           (S00_AXI_ARPROT	     ),  // input wire [2 : 0] S00_AXI_ARPROT
  .S00_AXI_ARQOS            (S00_AXI_ARQOS	     ),  // input wire [3 : 0] S00_AXI_ARQOS
  .S00_AXI_ARVALID          (S00_AXI_ARVALID     ),  // input wire S00_AXI_ARVALID
  .S00_AXI_ARREADY          (S00_AXI_ARREADY     ),  // output wire S00_AXI_ARREADY
  .S00_AXI_RID              (S00_AXI_RID	     ),  // output wire [3 : 0] S00_AXI_RID
  .S00_AXI_RDATA            (S00_AXI_RDATA	     ),  // output wire [511 : 0] S00_AXI_RDATA
  .S00_AXI_RRESP            (S00_AXI_RRESP	     ),  // output wire [1 : 0] S00_AXI_RRESP
  .S00_AXI_RLAST            (S00_AXI_RLAST	     ),  // output wire S00_AXI_RLAST
  .S00_AXI_RVALID           (S00_AXI_RVALID	     ),  // output wire S00_AXI_RVALID
  .S00_AXI_RREADY           (S00_AXI_RREADY	     ),  // input wire S00_AXI_RREADY
  .S01_AXI_ARESET_OUT_N     (                    ),  // output wire S01_AXI_ARESET_OUT_N
  .S01_AXI_ACLK             (clk_out1            ),  // input wire S01_AXI_ACLK
  .S01_AXI_AWID             (1'b0         	     ),  // input wire [3 : 0] S01_AXI_AWID
  .S01_AXI_AWADDR           (32'b0      	     ),  // input wire [31 : 0] S01_AXI_AWADDR
  .S01_AXI_AWLEN            (8'b0          	     ),  // input wire [7 : 0] S01_AXI_AWLEN
  .S01_AXI_AWSIZE           (3'b0       	     ),  // input wire [2 : 0] S01_AXI_AWSIZE
  .S01_AXI_AWBURST          (2'b0                ),  // input wire [1 : 0] S01_AXI_AWBURST
  .S01_AXI_AWLOCK           (1'b0       	     ),  // input wire S01_AXI_AWLOCK
  .S01_AXI_AWCACHE          (4'b0                ),  // input wire [3 : 0] S01_AXI_AWCACHE
  .S01_AXI_AWPROT           (3'b0       	     ),  // input wire [2 : 0] S01_AXI_AWPROT
  .S01_AXI_AWQOS            (4'b0       	     ),  // input wire [3 : 0] S01_AXI_AWQOS
  .S01_AXI_AWVALID          (1'b0                ),  // input wire S01_AXI_AWVALID
  .S01_AXI_AWREADY          (                    ),  // output wire S01_AXI_AWREADY
  .S01_AXI_WDATA            (512'b0     	     ),  // input wire [511 : 0] S01_AXI_WDATA
  .S01_AXI_WSTRB            (64'b0      	     ),  // input wire [63 : 0] S01_AXI_WSTRB
  .S01_AXI_WLAST            (1'b0       	     ),  // input wire S01_AXI_WLAST
  .S01_AXI_WVALID           (1'b0       	     ),  // input wire S01_AXI_WVALID
  .S01_AXI_WREADY           (           	     ),  // output wire S01_AXI_WREADY
  .S01_AXI_BID              (           	     ),  // output wire [3 : 0] S01_AXI_BID
  .S01_AXI_BRESP            (           	     ),  // output wire [1 : 0] S01_AXI_BRESP
  .S01_AXI_BVALID           (           	     ),  // output wire S01_AXI_BVALID
  .S01_AXI_BREADY           (1'b0           	 ),  // input wire S01_AXI_BREADY
  .S01_AXI_ARID             (S01_AXI_ARID	     ),  // input wire [3 : 0] S01_AXI_ARID
  .S01_AXI_ARADDR           (S01_AXI_ARADDR	     ),  // input wire [31 : 0] S01_AXI_ARADDR
  .S01_AXI_ARLEN            (S01_AXI_ARLEN	     ),  // input wire [7 : 0] S01_AXI_ARLEN
  .S01_AXI_ARSIZE           (S01_AXI_ARSIZE	     ),  // input wire [2 : 0] S01_AXI_ARSIZE
  .S01_AXI_ARBURST          (S01_AXI_ARBURST     ),  // input wire [1 : 0] S01_AXI_ARBURST
  .S01_AXI_ARLOCK           (S01_AXI_ARLOCK	     ),  // input wire S01_AXI_ARLOCK
  .S01_AXI_ARCACHE          (S01_AXI_ARCACHE     ),  // input wire [3 : 0] S01_AXI_ARCACHE
  .S01_AXI_ARPROT           (S01_AXI_ARPROT	     ),  // input wire [2 : 0] S01_AXI_ARPROT
  .S01_AXI_ARQOS            (S01_AXI_ARQOS	     ),  // input wire [3 : 0] S01_AXI_ARQOS
  .S01_AXI_ARVALID          (S01_AXI_ARVALID     ),  // input wire S01_AXI_ARVALID
  .S01_AXI_ARREADY          (S01_AXI_ARREADY     ),  // output wire S01_AXI_ARREADY
  .S01_AXI_RID              (S01_AXI_RID	     ),  // output wire [3 : 0] S01_AXI_RID
  .S01_AXI_RDATA            (S01_AXI_RDATA	     ),  // output wire [511 : 0] S01_AXI_RDATA
  .S01_AXI_RRESP            (S01_AXI_RRESP	     ),  // output wire [1 : 0] S01_AXI_RRESP
  .S01_AXI_RLAST            (S01_AXI_RLAST	     ),  // output wire S01_AXI_RLAST
  .S01_AXI_RVALID           (S01_AXI_RVALID	     ),  // output wire S01_AXI_RVALID
  .S01_AXI_RREADY           (S01_AXI_RREADY	     ),  // input wire S01_AXI_RREADY
  .S02_AXI_ARESET_OUT_N     (                    ),  // output wire S02_AXI_ARESET_OUT_N
  .S02_AXI_ACLK             (clk_out1            ),  // input wire S02_AXI_ACLK
  .S02_AXI_AWID             (1'b0         	     ),  // input wire [3 : 0] S02_AXI_AWID
  .S02_AXI_AWADDR           (32'b0      	     ),  // input wire [31 : 0] S02_AXI_AWADDR
  .S02_AXI_AWLEN            (8'b0          	     ),  // input wire [7 : 0] S02_AXI_AWLEN
  .S02_AXI_AWSIZE           (3'b0       	     ),  // input wire [2 : 0] S02_AXI_AWSIZE
  .S02_AXI_AWBURST          (2'b0                ),  // input wire [1 : 0] S02_AXI_AWBURST
  .S02_AXI_AWLOCK           (1'b0       	     ),  // input wire S02_AXI_AWLOCK
  .S02_AXI_AWCACHE          (4'b0                ),  // input wire [3 : 0] S02_AXI_AWCACHE
  .S02_AXI_AWPROT           (3'b0       	     ),  // input wire [2 : 0] S02_AXI_AWPROT
  .S02_AXI_AWQOS            (4'b0       	     ),  // input wire [3 : 0] S02_AXI_AWQOS
  .S02_AXI_AWVALID          (1'b0                ),  // input wire S02_AXI_AWVALID
  .S02_AXI_AWREADY          (                    ),  // output wire S02_AXI_AWREADY
  .S02_AXI_WDATA            (512'b0     	     ),  // input wire [511 : 0] S02_AXI_WDATA
  .S02_AXI_WSTRB            (64'b0      	     ),  // input wire [63 : 0] S02_AXI_WSTRB
  .S02_AXI_WLAST            (1'b0       	     ),  // input wire S02_AXI_WLAST
  .S02_AXI_WVALID           (1'b0       	     ),  // input wire S02_AXI_WVALID
  .S02_AXI_WREADY           (           	     ),  // output wire S02_AXI_WREADY
  .S02_AXI_BID              (           	     ),  // output wire [3 : 0] S02_AXI_BID
  .S02_AXI_BRESP            (           	     ),  // output wire [1 : 0] S02_AXI_BRESP
  .S02_AXI_BVALID           (           	     ),  // output wire S02_AXI_BVALID
  .S02_AXI_BREADY           (1'b0           	 ),  // input wire S02_AXI_BREADY
  .S02_AXI_ARID             (S02_AXI_ARID	     ),  // input wire [3 : 0] S02_AXI_ARID
  .S02_AXI_ARADDR           (S02_AXI_ARADDR	     ),  // input wire [31 : 0] S02_AXI_ARADDR
  .S02_AXI_ARLEN            (S02_AXI_ARLEN	     ),  // input wire [7 : 0] S02_AXI_ARLEN
  .S02_AXI_ARSIZE           (S02_AXI_ARSIZE	     ),  // input wire [2 : 0] S02_AXI_ARSIZE
  .S02_AXI_ARBURST          (S02_AXI_ARBURST     ),  // input wire [1 : 0] S02_AXI_ARBURST
  .S02_AXI_ARLOCK           (S02_AXI_ARLOCK	     ),  // input wire S02_AXI_ARLOCK
  .S02_AXI_ARCACHE          (S02_AXI_ARCACHE     ),  // input wire [3 : 0] S02_AXI_ARCACHE
  .S02_AXI_ARPROT           (S02_AXI_ARPROT	     ),  // input wire [2 : 0] S02_AXI_ARPROT
  .S02_AXI_ARQOS            (S02_AXI_ARQOS	     ),  // input wire [3 : 0] S02_AXI_ARQOS
  .S02_AXI_ARVALID          (S02_AXI_ARVALID     ),  // input wire S02_AXI_ARVALID
  .S02_AXI_ARREADY          (S02_AXI_ARREADY     ),  // output wire S02_AXI_ARREADY
  .S02_AXI_RID              (S02_AXI_RID	     ),  // output wire [3 : 0] S02_AXI_RID
  .S02_AXI_RDATA            (S02_AXI_RDATA	     ),  // output wire [511 : 0] S02_AXI_RDATA
  .S02_AXI_RRESP            (S02_AXI_RRESP	     ),  // output wire [1 : 0] S02_AXI_RRESP
  .S02_AXI_RLAST            (S02_AXI_RLAST	     ),  // output wire S02_AXI_RLAST
  .S02_AXI_RVALID           (S02_AXI_RVALID	     ),  // output wire S02_AXI_RVALID
  .S02_AXI_RREADY           (S02_AXI_RREADY	     ),  // input wire S02_AXI_RREADY

  .S03_AXI_ARESET_OUT_N     (                    ),  // output wire S03_AXI_ARESET_OUT_N
  .S03_AXI_ACLK             (pcie_aclk           ),  // input wire S03_AXI_ACLK
  .S03_AXI_AWID             (S03_AXI_AWID        ),  // input wire [3 : 0] S03_AXI_AWID
  .S03_AXI_AWADDR           (S03_AXI_AWADDR[31:0]),  // input wire [31 : 0] S03_AXI_AWADDR
  .S03_AXI_AWLEN            (S03_AXI_AWLEN	     ),  // input wire [7 : 0] S03_AXI_AWLEN
  .S03_AXI_AWSIZE           (S03_AXI_AWSIZE	     ),  // input wire [2 : 0] S03_AXI_AWSIZE
  .S03_AXI_AWBURST          (S03_AXI_AWBURST     ),  // input wire [1 : 0] S03_AXI_AWBURST
  .S03_AXI_AWLOCK           (S03_AXI_AWLOCK	     ),  // input wire S03_AXI_AWLOCK
  .S03_AXI_AWCACHE          (S03_AXI_AWCACHE     ),  // input wire [3 : 0] S03_AXI_AWCACHE
  .S03_AXI_AWPROT           (S03_AXI_AWPROT	     ),  // input wire [2 : 0] S03_AXI_AWPROT
  .S03_AXI_AWQOS            (4'b0			     ),  // input wire [3 : 0] S03_AXI_AWQOS
  .S03_AXI_AWVALID          (S03_AXI_AWVALID     ),  // input wire S03_AXI_AWVALID
  .S03_AXI_AWREADY          (S03_AXI_AWREADY     ),  // output wire S03_AXI_AWREADY
  .S03_AXI_WDATA            (S03_AXI_WDATA	     ),  // input wire [511 : 0] S03_AXI_WDATA
  .S03_AXI_WSTRB            (S03_AXI_WSTRB	     ),  // input wire [63 : 0] S03_AXI_WSTRB
  .S03_AXI_WLAST            (S03_AXI_WLAST	     ),  // input wire S03_AXI_WLAST
  .S03_AXI_WVALID           (S03_AXI_WVALID	     ),  // input wire S03_AXI_WVALID
  .S03_AXI_WREADY           (S03_AXI_WREADY	     ),  // output wire S03_AXI_WREADY
  .S03_AXI_BID              (S03_AXI_BID	     ),  // output wire [3 : 0] S03_AXI_BID
  .S03_AXI_BRESP            (S03_AXI_BRESP	     ),  // output wire [1 : 0] S03_AXI_BRESP
  .S03_AXI_BVALID           (S03_AXI_BVALID	     ),  // output wire S03_AXI_BVALID
  .S03_AXI_BREADY           (S03_AXI_BREADY	     ),  // input wire S03_AXI_BREADY
  .S03_AXI_ARID             (S03_AXI_ARID	     ),  // input wire [3 : 0] S03_AXI_ARID
  .S03_AXI_ARADDR           (S03_AXI_ARADDR[31:0]),  // input wire [31 : 0] S03_AXI_ARADDR
  .S03_AXI_ARLEN            (S03_AXI_ARLEN	     ),  // input wire [7 : 0] S03_AXI_ARLEN
  .S03_AXI_ARSIZE           (S03_AXI_ARSIZE	     ),  // input wire [2 : 0] S03_AXI_ARSIZE
  .S03_AXI_ARBURST          (S03_AXI_ARBURST     ),  // input wire [1 : 0] S03_AXI_ARBURST
  .S03_AXI_ARLOCK           (S03_AXI_ARLOCK	     ),  // input wire S03_AXI_ARLOCK
  .S03_AXI_ARCACHE          (S03_AXI_ARCACHE     ),  // input wire [3 : 0] S03_AXI_ARCACHE
  .S03_AXI_ARPROT           (S03_AXI_ARPROT	     ),  // input wire [2 : 0] S03_AXI_ARPROT
  .S03_AXI_ARQOS            (4'b0			     ),  // input wire [3 : 0] S03_AXI_ARQOS
  .S03_AXI_ARVALID          (S03_AXI_ARVALID     ),  // input wire S03_AXI_ARVALID
  .S03_AXI_ARREADY          (S03_AXI_ARREADY     ),  // output wire S03_AXI_ARREADY
  .S03_AXI_RID              (S03_AXI_RID	     ),  // output wire [3 : 0] S03_AXI_RID
  .S03_AXI_RDATA            (S03_AXI_RDATA	     ),  // output wire [511 : 0] S03_AXI_RDATA
  .S03_AXI_RRESP            (S03_AXI_RRESP	     ),  // output wire [1 : 0] S03_AXI_RRESP
  .S03_AXI_RLAST            (S03_AXI_RLAST	     ),  // output wire S03_AXI_RLAST
  .S03_AXI_RVALID           (S03_AXI_RVALID	     ),  // output wire S03_AXI_RVALID
  .S03_AXI_RREADY           (S03_AXI_RREADY	     ),  // input wire S03_AXI_RREADY
  .M00_AXI_ARESET_OUT_N     (                    ),  // output wire M00_AXI_ARESET_OUT_N
  .M00_AXI_ACLK             (ui_clk              ),  // input wire M00_AXI_ACLK
  .M00_AXI_AWID             (M00_axi_awid	     ),  // output wire [7 : 0] M00_AXI_AWID
  .M00_AXI_AWADDR           (M00_axi_awaddr	     ),  // output wire [31 : 0] M00_AXI_AWADDR
  .M00_AXI_AWLEN            (M00_axi_awlen	     ),  // output wire [7 : 0] M00_AXI_AWLEN
  .M00_AXI_AWSIZE           (M00_axi_awsize	     ),  // output wire [2 : 0] M00_AXI_AWSIZE
  .M00_AXI_AWBURST          (M00_axi_awburst     ),  // output wire [1 : 0] M00_AXI_AWBURST
  .M00_AXI_AWLOCK           (M00_axi_awlock	     ),  // output wire M00_AXI_AWLOCK
  .M00_AXI_AWCACHE          (M00_axi_awcache     ),  // output wire [3 : 0] M00_AXI_AWCACHE
  .M00_AXI_AWPROT           (M00_axi_awprot	     ),  // output wire [2 : 0] M00_AXI_AWPROT
  .M00_AXI_AWQOS            (M00_axi_awqos	     ),  // output wire [3 : 0] M00_AXI_AWQOS
  .M00_AXI_AWVALID          (M00_axi_awvalid     ),  // output wire M00_AXI_AWVALID
  .M00_AXI_AWREADY          (M00_axi_awready     ),  // input wire M00_AXI_AWREADY
  .M00_AXI_WDATA            (M00_axi_wdata	     ),  // output wire [511 : 0] M00_AXI_WDATA
  .M00_AXI_WSTRB            (M00_axi_wstrb	     ),  // output wire [63 : 0] M00_AXI_WSTRB
  .M00_AXI_WLAST            (M00_axi_wlast	     ),  // output wire M00_AXI_WLAST
  .M00_AXI_WVALID           (M00_axi_wvalid	     ),  // output wire M00_AXI_WVALID
  .M00_AXI_WREADY           (M00_axi_wready	     ),  // input wire M00_AXI_WREADY
  .M00_AXI_BID              (M00_axi_bid	     ),  // input wire [7 : 0] M00_AXI_BID
  .M00_AXI_BRESP            (M00_axi_bresp	     ),  // input wire [1 : 0] M00_AXI_BRESP
  .M00_AXI_BVALID           (M00_axi_bvalid	     ),  // input wire M00_AXI_BVALID
  .M00_AXI_BREADY           (M00_axi_bready	     ),  // output wire M00_AXI_BREADY
  .M00_AXI_ARID             (M00_axi_arid	     ),  // output wire [7 : 0] M00_AXI_ARID
  .M00_AXI_ARADDR           (M00_axi_araddr	     ),  // output wire [31 : 0] M00_AXI_ARADDR
  .M00_AXI_ARLEN            (M00_axi_arlen	     ),  // output wire [7 : 0] M00_AXI_ARLEN
  .M00_AXI_ARSIZE           (M00_axi_arsize	     ),  // output wire [2 : 0] M00_AXI_ARSIZE
  .M00_AXI_ARBURST          (M00_axi_arburst     ),  // output wire [1 : 0] M00_AXI_ARBURST
  .M00_AXI_ARLOCK           (M00_axi_arlock	     ),  // output wire M00_AXI_ARLOCK
  .M00_AXI_ARCACHE          (M00_axi_arcache     ),  // output wire [3 : 0] M00_AXI_ARCACHE
  .M00_AXI_ARPROT           (M00_axi_arprot	     ),  // output wire [2 : 0] M00_AXI_ARPROT
  .M00_AXI_ARQOS            (M00_axi_arqos	     ),  // output wire [3 : 0] M00_AXI_ARQOS
  .M00_AXI_ARVALID          (M00_axi_arvalid     ),  // output wire M00_AXI_ARVALID
  .M00_AXI_ARREADY          (M00_axi_arready     ),  // input wire M00_AXI_ARREADY
  .M00_AXI_RID              (M00_axi_rid	     ),  // input wire [7 : 0] M00_AXI_RID
  .M00_AXI_RDATA            (M00_axi_rdata	     ),  // input wire [511 : 0] M00_AXI_RDATA
  .M00_AXI_RRESP            (M00_axi_rresp	     ),  // input wire [1 : 0] M00_AXI_RRESP
  .M00_AXI_RLAST            (M00_axi_rlast	     ),  // input wire M00_AXI_RLAST
  .M00_AXI_RVALID           (M00_axi_rvalid	     ),  // input wire M00_AXI_RVALID
  .M00_AXI_RREADY           (M00_axi_rready	     )   // output wire M00_AXI_RREADY
);

//conv_input_ddr_rd_wrapper instance
ddr_rd_wrapper1#(
	.RAM_LATENCY            (RAM_LATENCY),
    .RAM_ADDR_WIDTH         (addr_bit_inp)
)inp_ddr_rd_wrapper
(
	.I_clk					(clk_out1),
	.I_rst_n				(peripheral_aresetn0),
	.I_addr_offset			(O_conv_config_data[319:288]),
	.I_rd_lenth				(O_conv_config_data[287:256]),
	.I_offset_valid			(O_conv_start_signal),
	.O_rd_finish_signal		(O_rd_finish_signal1),
	.O_ram_addr				(O_wr_ram_addr1),
	.O_wr_en				(O_wr_en1),
	.O_ram_data				(O_wr_ram_data1),
	.M_AXI_ARID				(S00_AXI_ARID),
	.M_AXI_ARADDR			(S00_AXI_ARADDR),
	.M_AXI_ARLEN			(S00_AXI_ARLEN),
	.M_AXI_ARSIZE			(S00_AXI_ARSIZE),
	.M_AXI_ARBURST			(S00_AXI_ARBURST),
	.M_AXI_ARLOCK			(S00_AXI_ARLOCK),
	.M_AXI_ARCACHE			(S00_AXI_ARCACHE),
	.M_AXI_ARPROT			(S00_AXI_ARPROT),
	.M_AXI_ARQOS			(S00_AXI_ARQOS),
	.M_AXI_ARVALID			(S00_AXI_ARVALID),
	.M_AXI_ARREADY			(S00_AXI_ARREADY),
	.M_AXI_RID				(S00_AXI_RID),
	.M_AXI_RDATA			(S00_AXI_RDATA),
	.M_AXI_RRESP			(S00_AXI_RRESP),
	.M_AXI_RVALID			(S00_AXI_RVALID),
	.M_AXI_RLAST			(S00_AXI_RLAST),
	.M_AXI_RREADY			(S00_AXI_RREADY)		
);
//conv_weight_ddr_rd_wrapper instance
ddr_rd_wrapper2#(
	.RAM_LATENCY            (RAM_LATENCY),
    .RAM_ADDR_WIDTH         (addr_bit_weight)
)weight_ddr_rd_wrapper
(
	.I_clk					(clk_out1),
	.I_rst_n				(peripheral_aresetn0),
	.I_addr_offset			(O_conv_config_data[255:224]),
	.I_rd_lenth				(O_conv_config_data[223:192]),
	.I_offset_valid			(O_conv_start_signal),
	.O_rd_finish_signal		(O_rd_finish_signal2),
	.O_ram_addr				(O_wr_ram_addr2),
	.O_wr_en				(O_wr_en2),
	.O_ram_data				(O_wr_ram_data2),
	.M_AXI_ARID				(S01_AXI_ARID),
	.M_AXI_ARADDR			(S01_AXI_ARADDR),
	.M_AXI_ARLEN			(S01_AXI_ARLEN),
	.M_AXI_ARSIZE			(S01_AXI_ARSIZE),
	.M_AXI_ARBURST			(S01_AXI_ARBURST),
	.M_AXI_ARLOCK			(S01_AXI_ARLOCK),
	.M_AXI_ARCACHE			(S01_AXI_ARCACHE),
	.M_AXI_ARPROT		    (S01_AXI_ARPROT),
	.M_AXI_ARQOS			(S01_AXI_ARQOS),
	.M_AXI_ARVALID			(S01_AXI_ARVALID),
	.M_AXI_ARREADY			(S01_AXI_ARREADY),
	.M_AXI_RID				(S01_AXI_RID),
	.M_AXI_RDATA			(S01_AXI_RDATA),
	.M_AXI_RRESP			(S01_AXI_RRESP),
	.M_AXI_RVALID			(S01_AXI_RVALID),
	.M_AXI_RLAST			(S01_AXI_RLAST),
	.M_AXI_RREADY			(S01_AXI_RREADY)		
);
//conv_bias_ddr_rd_wrapper instance
ddr_rd_wrapper3#(
	.RAM_LATENCY            (RAM_LATENCY),
    .RAM_ADDR_WIDTH         (addr_bit_bias)
)bias_ddr_rd_wrapper
(
	.I_clk					(clk_out1),
	.I_rst_n				(peripheral_aresetn0),
	.I_addr_offset			(O_conv_config_data[191:160]),
	.I_rd_lenth				({2'b0, O_conv_config_data[159:130]}),
	.I_offset_valid			(O_conv_start_signal),
	.O_rd_finish_signal		(O_rd_finish_signal3),
	.O_ram_addr				(O_wr_ram_addr3),
	.O_wr_en				(O_wr_en3),
	.O_ram_data				(O_wr_ram_data3),
	.M_AXI_ARID				(S02_AXI_ARID),
	.M_AXI_ARADDR			(S02_AXI_ARADDR),
	.M_AXI_ARLEN			(S02_AXI_ARLEN),
	.M_AXI_ARSIZE			(S02_AXI_ARSIZE),
	.M_AXI_ARBURST			(S02_AXI_ARBURST),
	.M_AXI_ARLOCK			(S02_AXI_ARLOCK),
	.M_AXI_ARCACHE			(S02_AXI_ARCACHE),
	.M_AXI_ARPROT		    (S02_AXI_ARPROT),
	.M_AXI_ARQOS			(S02_AXI_ARQOS),
	.M_AXI_ARVALID			(S02_AXI_ARVALID),
	.M_AXI_ARREADY			(S02_AXI_ARREADY),
	.M_AXI_RID				(S02_AXI_RID),
	.M_AXI_RDATA			(S02_AXI_RDATA),
	.M_AXI_RRESP			(S02_AXI_RRESP),
	.M_AXI_RVALID			(S02_AXI_RVALID),
	.M_AXI_RLAST			(S02_AXI_RLAST),
	.M_AXI_RREADY			(S02_AXI_RREADY)		
);

//conv_ddr_wr_wrapper instance
ddr_wr_wrapper1#(
	.RAM_LATENCY            (RAM_LATENCY),
    .RAM_ADDR_WIDTH         (addr_bit_out)
)conv_ddr_wr_wrapper
(
	.I_clk					(clk_out1),
	.I_rst_n				(peripheral_aresetn0),
    // .channel                (O_conv_config_data[63:48]),
    // .filter                 (O_conv_config_data[47:32]),
	.I_addr_offset			(O_conv_config_data[127:96]),
	.I_wr_lenth				(O_conv_config_data[95:64]),
	.I_offset_valid			(O_wr_start_signal),
    .I_conv_start_signal    (O_conv_start_signal),
    // .O_wr_tile_finish_signal(O_wr_tile_finish_signal),
	.O_wr_finish_signal		(I_conv_finish_signal),
	.O_ram_addr				(O_rd_ram_addr1),
	.O_rd_en				(O_rd_en1),
	.I_ram_data				(O_rd_ram_data1),
	.M_AXI_AWID				(S00_AXI_AWID),
	.M_AXI_AWADDR			(S00_AXI_AWADDR),
	.M_AXI_AWLEN			(S00_AXI_AWLEN),
	.M_AXI_AWSIZE			(S00_AXI_AWSIZE),
	.M_AXI_AWBURST			(S00_AXI_AWBURST),
	.M_AXI_AWLOCK			(S00_AXI_AWLOCK),
	.M_AXI_AWCACHE			(S00_AXI_AWCACHE),
	.M_AXI_AWPROT		    (S00_AXI_AWPROT),
	.M_AXI_AWQOS			(S00_AXI_AWQOS),
	.M_AXI_AWVALID			(S00_AXI_AWVALID),
	.M_AXI_AWREADY			(S00_AXI_AWREADY),
	.M_AXI_WDATA			(S00_AXI_WDATA),
	.M_AXI_WSTRB			(S00_AXI_WSTRB),
	.M_AXI_WVALID			(S00_AXI_WVALID),
	.M_AXI_WLAST			(S00_AXI_WLAST),
	.M_AXI_WREADY			(S00_AXI_WREADY),
	.M_AXI_BID				(S00_AXI_BID),
	.M_AXI_BRESP			(S00_AXI_BRESP),
	.M_AXI_BVALID			(S00_AXI_BVALID),
	.M_AXI_BREADY			(S00_AXI_BREADY)	
);

//rd finish_signal_gen
rd_finish_signal_gen inst_rd_finish_signal_gen(
	.I_clk(clk_out1),
	.I_rst_n(peripheral_aresetn0),
	.rd_finish_signal1(O_rd_finish_signal1),
	.rd_finish_signal2(O_rd_finish_signal2),
	.rd_finish_signal3(O_rd_finish_signal3),
	.rd_finish_signal(conv_rd_finish_signal)
);

//top controller
top_controller #(
    .PARAM_SIZE             (PARAM_SIZE             )
)inst_top_controller(
	.I_clk					(pcie_aclk		        ),
	.I_rst_n				(pcie_aresetn	        ),
	.S_AXI_AWADDR			(m_axil_awaddr	        ),
	.S_AXI_AWPROT			(m_axil_awprot 	        ),
	.S_AXI_AWVALID			(m_axil_awvalid	        ),
	.S_AXI_AWREADY			(m_axil_awready	        ),
	.S_AXI_WDATA			(m_axil_wdata           ),
	.S_AXI_WSTRB			(m_axil_wstrb           ),
	.S_AXI_WVALID			(m_axil_wvalid          ),
	.S_AXI_WREADY			(m_axil_wready          ),
	.S_AXI_BRESP			(m_axil_bresp           ),
	.S_AXI_BVALID			(m_axil_bvalid          ),
	.S_AXI_BREADY			(m_axil_bready          ),
	.S_AXI_ARADDR			(m_axil_araddr          ),
	.S_AXI_ARPROT			(m_axil_arprot          ),
	.S_AXI_ARVALID			(m_axil_arvalid         ),
	.S_AXI_ARREADY			(m_axil_arready         ),
	.S_AXI_RDATA			(m_axil_rdata           ),
	.S_AXI_RRESP			(m_axil_rresp           ),
	.S_AXI_RVALID			(m_axil_rvalid          ),
	.S_AXI_RREADY			(m_axil_rready	        ),
	.O_conv_config_data		(O_conv_config_data     ),
	.O_conv_start_signal	(O_conv_start_signal    ),
	.I_conv_finish_signal	(I_conv_finish_signal   ),
    .I_debug_status(core_debug_status),
    .O_ReLU_enable          (O_ReLU_enable          ),
    .first_layer (O_first_layer),
    .last_layer           (O_last_layer             )
);

// convolution
PG_sram #(
    .depth_inp          (depth_inp                ),
    .addr_bit_inp       (addr_bit_inp             ),
    .depth_weight       (depth_weight             ),
    .addr_bit_weight    (addr_bit_weight          ),
    .depth_bias         (depth_bias               ),
    .addr_bit_bias      (addr_bit_bias            ),
    .depth_out          (depth_out                ),
    .addr_bit_out       (addr_bit_out             ),
    .bits_input         (bits_input               ),
    .bits_weight        (bits_weight              ),
    .bits_bias          (bits_bias                ),
    .bits_eleout        (bits_eleout              ),
    .bits_addout        (bits_addout              ),
    .bits_macout        (bits_macout              ),
    .bits_quantout      (bits_quantout            ),
    .stride             (stride                   ),
    .pixel_para         (pixel_para               ),
    .ic_para            (ic_para                  ),
    .oc_para            (oc_para                  )
)ints_PG_sram(
    .clk                (clk_out1                 ),
    .rst                (peripheral_aresetn0      ),
    .channel            ({8'b0, O_conv_config_data[63:56]}),
    .filter_n           ({8'b0, O_conv_config_data[55:48]}),
    .pixel_w            ({4'b0, O_conv_config_data[18:6]} ),      
    .pixel_h            ({4'b0, O_conv_config_data[31:19]}),      
    .padding_left       (O_conv_config_data[129]),
    .padding_right      (O_conv_config_data[128]),
    .kernel_h           (O_conv_config_data[5:3] ),
    .kernel_w           (O_conv_config_data[5:3] ),
    .ReLU_enable        (O_ReLU_enable            ),
    .wEn_inp            (O_wr_en1                 ),
    .wAddr_inp          (O_wr_ram_addr1           ),
    .wData_inp          (O_wr_ram_data1           ),
    .wEn_weight         (O_wr_en2                 ),
    .wAddr_weight       (O_wr_ram_addr2           ),
    .wData_weight       (O_wr_ram_data2           ),
    .wEn_bias           (O_wr_en3                 ),
    .wAddr_bias         (O_wr_ram_addr3           ),
    .wData_bias         (O_wr_ram_data3           ),
    .rEn_out            (O_rd_en1                 ),
    .rAddr_out          (O_rd_ram_addr1           ),
    .rData_out          (O_rd_ram_data1           ),
    .quantization_scale (O_conv_config_data[47:32]),
    .acc_start_signal   (conv_rd_finish_signal    ),
    .acc_finish_signal  (O_wr_start_signal        ),
    .first_layer (O_first_layer),
    .last_layer         (O_last_layer             ),
    .pad_h              ({1'b0, O_conv_config_data[2:0]}),
    .pad_w              ({1'b0, O_conv_config_data[2:0]})  
);


//PCIE XMDA instance

IBUFDS_GTE4 inst_buffer (
    .O(pcie_sys_clk_gt),         // 1-bit output: Refer to Transceiver User Guide.
    .ODIV2(pcie_sys_clk), // 1-bit output: Refer to Transceiver User Guide.
    .CEB(1'b0),     // 1-bit input: Refer to Transceiver User Guide.
    .I(pcie_sys_clk_p),         // 1-bit input: Refer to Transceiver User Guide.
    .IB(pcie_sys_clk_n)        // 1-bit input: Refer to Transceiver User Guide.
);

IBUFDS IBUFDS_inst (
    .O(clk_out2),   // 1-bit output: Buffer output
    .I(ddr4_sys_clk_p),   // 1-bit input: Diff_p buffer input (connect directly to top-level port)
    .IB(ddr4_sys_clk_n)  // 1-bit input: Diff_n buffer input (connect directly to top-level port)
);

xdma_0 inst_xdma(
  .sys_clk              (pcie_sys_clk   ), // input wire sys_clk
  .sys_clk_gt           (pcie_sys_clk_gt), // input wire sys_clk_gt
  .sys_rst_n            (pcie_resetn    ), // input wire sys_rst_n
  .user_lnk_up          (user_lnk_up	), // output wire user_lnk_up
  .pci_exp_txp          (pcie_mgt_txp	), // output wire [15 : 0] pci_exp_txp
  .pci_exp_txn          (pcie_mgt_txn	), // output wire [15 : 0] pci_exp_txn
  .pci_exp_rxp          (pcie_mgt_rxp	), // input wire [15 : 0] pci_exp_rxp
  .pci_exp_rxn          (pcie_mgt_rxn	), // input wire [15 : 0] pci_exp_rxn
  .axi_aclk             (pcie_aclk      ), // output wire axi_aclk
  .axi_aresetn          (pcie_aresetn   ), // output wire axi_aresetn
  .usr_irq_req          (1'd0           ), // input wire [0 : 0] usr_irq_req
  .usr_irq_ack          (               ), // output wire [0 : 0] usr_irq_ack
  .msi_enable           (               ), // output wire msi_enable
  .msi_vector_width     (               ), // output wire [2 : 0] msi_vector_width
  .m_axi_awready        (S03_AXI_AWREADY), // input wire m_axi_awready
  .m_axi_wready         (S03_AXI_WREADY	), // input wire m_axi_wready
  .m_axi_bid            (S03_AXI_BID	), // input wire [3 : 0] m_axi_bid
  .m_axi_bresp          (S03_AXI_BRESP	), // input wire [1 : 0] m_axi_bresp
  .m_axi_bvalid         (S03_AXI_BVALID	), // input wire m_axi_bvalid
  .m_axi_arready        (S03_AXI_ARREADY), // input wire m_axi_arready
  .m_axi_rid            (S03_AXI_RID	), // input wire [3 : 0] m_axi_rid
  .m_axi_rdata          (S03_AXI_RDATA	), // input wire [511 : 0] m_axi_rdata
  .m_axi_rresp          (S03_AXI_RRESP	), // input wire [1 : 0] m_axi_rresp
  .m_axi_rlast          (S03_AXI_RLAST	), // input wire m_axi_rlast
  .m_axi_rvalid         (S03_AXI_RVALID	), // input wire m_axi_rvalid
  .m_axi_awid           (S03_AXI_AWID	), // output wire [3 : 0] m_axi_awid
  .m_axi_awaddr         (S03_AXI_AWADDR	), // output wire [63 : 0] m_axi_awaddr
  .m_axi_awlen          (S03_AXI_AWLEN	), // output wire [7 : 0] m_axi_awlen
  .m_axi_awsize         (S03_AXI_AWSIZE	), // output wire [2 : 0] m_axi_awsize
  .m_axi_awburst        (S03_AXI_AWBURST), // output wire [1 : 0] m_axi_awburst
  .m_axi_awprot         (S03_AXI_AWPROT	), // output wire [2 : 0] m_axi_awprot
  .m_axi_awvalid        (S03_AXI_AWVALID), // output wire m_axi_awvalid
  .m_axi_awlock         (S03_AXI_AWLOCK	), // output wire m_axi_awlock
  .m_axi_awcache        (S03_AXI_AWCACHE), // output wire [3 : 0] m_axi_awcache
  .m_axi_wdata          (S03_AXI_WDATA	), // output wire [511 : 0] m_axi_wdata
  .m_axi_wstrb          (S03_AXI_WSTRB	), // output wire [63 : 0] m_axi_wstrb
  .m_axi_wlast          (S03_AXI_WLAST	), // output wire m_axi_wlast
  .m_axi_wvalid         (S03_AXI_WVALID	), // output wire m_axi_wvalid
  .m_axi_bready         (S03_AXI_BREADY	), // output wire m_axi_bready
  .m_axi_arid           (S03_AXI_ARID	), // output wire [3 : 0] m_axi_arid
  .m_axi_araddr         (S03_AXI_ARADDR	), // output wire [63 : 0] m_axi_araddr
  .m_axi_arlen          (S03_AXI_ARLEN	), // output wire [7 : 0] m_axi_arlen
  .m_axi_arsize         (S03_AXI_ARSIZE	), // output wire [2 : 0] m_axi_arsize
  .m_axi_arburst        (S03_AXI_ARBURST), // output wire [1 : 0] m_axi_arburst
  .m_axi_arprot         (S03_AXI_ARPROT	), // output wire [2 : 0] m_axi_arprot
  .m_axi_arvalid        (S03_AXI_ARVALID), // output wire m_axi_arvalid
  .m_axi_arlock         (S03_AXI_ARLOCK	), // output wire m_axi_arlock
  .m_axi_arcache        (S03_AXI_ARCACHE), // output wire [3 : 0] m_axi_arcache
  .m_axi_rready         (S03_AXI_RREADY	), // output wire m_axi_rready
  .m_axil_awaddr        (m_axil_awaddr 	), // output wire [31 : 0] m_axil_awaddr
  .m_axil_awprot        (m_axil_awprot 	), // output wire [2 : 0] m_axil_awprot
  .m_axil_awvalid       (m_axil_awvalid	), // output wire m_axil_awvalid
  .m_axil_awready       (m_axil_awready	), // input wire m_axil_awready
  .m_axil_wdata         (m_axil_wdata   ), // output wire [31 : 0] m_axil_wdata
  .m_axil_wstrb         (m_axil_wstrb   ), // output wire [3 : 0] m_axil_wstrb
  .m_axil_wvalid        (m_axil_wvalid  ), // output wire m_axil_wvalid
  .m_axil_wready        (m_axil_wready  ), // input wire m_axil_wready
  .m_axil_bvalid        (m_axil_bvalid  ), // input wire m_axil_bvalid
  .m_axil_bresp         (m_axil_bresp   ), // input wire [1 : 0] m_axil_bresp
  .m_axil_bready        (m_axil_bready  ), // output wire m_axil_bready
  .m_axil_araddr        (m_axil_araddr  ), // output wire [31 : 0] m_axil_araddr
  .m_axil_arprot        (m_axil_arprot  ), // output wire [2 : 0] m_axil_arprot
  .m_axil_arvalid       (m_axil_arvalid ), // output wire m_axil_arvalid
  .m_axil_arready       (m_axil_arready ), // input wire m_axil_arready
  .m_axil_rdata         (m_axil_rdata   ), // input wire [31 : 0] m_axil_rdata
  .m_axil_rresp         (m_axil_rresp   ), // input wire [1 : 0] m_axil_rresp
  .m_axil_rvalid        (m_axil_rvalid  ), // input wire m_axil_rvalid
  .m_axil_rready        (m_axil_rready	), // output wire m_axil_rready
  .cfg_mgmt_addr        (19'd0          ), // input wire [18 : 0] cfg_mgmt_addr
  .cfg_mgmt_write       (1'b0           ), // input wire cfg_mgmt_write
  .cfg_mgmt_write_data  (32'd0          ), // input wire [31 : 0] cfg_mgmt_write_data
  .cfg_mgmt_byte_enable (4'd0           ), // input wire [3 : 0] cfg_mgmt_byte_enable
  .cfg_mgmt_read        (1'b0           ), // input wire cfg_mgmt_read
  .cfg_mgmt_read_data   (               ), // output wire [31 : 0] cfg_mgmt_read_data
  .cfg_mgmt_read_write_done(            )  // output wire cfg_mgmt_read_write_done
);

//ddr_controller instance
ddr4_controller inst_ddr4_controller(
  .c0_init_calib_complete       (init_calib_complete), // output wire c0_init_calib_complete
  .dbg_clk                      (                   ), // output wire dbg_clk
  .c0_sys_clk_i                 (clk_out2           ), // input wire c0_sys_clk_i
  .dbg_bus                      (                   ), // output wire [511 : 0] dbg_bus
  .c0_ddr4_adr                  (ddr4_adr           ), // output wire [16 : 0] c0_ddr4_addr
  .c0_ddr4_ba                   (ddr4_ba            ), // output wire [1 : 0] c0_ddr4_ba
  .c0_ddr4_cke                  (ddr4_cke           ), // output wire [0 : 0] c0_ddr4_cke
  .c0_ddr4_cs_n                 (ddr4_cs_n          ), // output wire [0 : 0] c0_ddr4_cs_n
  .c0_ddr4_dm_dbi_n             (ddr4_dm_dbi_n      ), // inout wire [7 : 0] c0_ddr4_dm_dbi_n
  .c0_ddr4_dq                   (ddr4_dq            ), // inout wire [63 : 0] c0_ddr4_dq
  .c0_ddr4_dqs_c                (ddr4_dqs_c         ), // inout wire [7 : 0] c0_ddr4_dqs_c
  .c0_ddr4_dqs_t                (ddr4_dqs_t         ), // inout wire [7 : 0] c0_ddr4_dqs_t
  .c0_ddr4_odt                  (ddr4_odt           ), // output wire [0 : 0] c0_ddr4_odt
  .c0_ddr4_bg                   (ddr4_bg            ), // output wire [0 : 0] c0_ddr4_bg
  .c0_ddr4_reset_n              (ddr4_reset_n       ), // output wire c0_ddr4_reset_n
  .c0_ddr4_act_n                (ddr4_act_n         ), // output wire c0_ddr4_act_n
  .c0_ddr4_ck_c                 (ddr4_ck_c          ), // output wire [0 : 0] c0_ddr4_ck_c
  .c0_ddr4_ck_t                 (ddr4_ck_t          ), // output wire [0 : 0] c0_ddr4_ck_t
  .c0_ddr4_ui_clk               (ui_clk             ), // output wire c0_ddr4_ui_clk
  .c0_ddr4_ui_clk_sync_rst      (ui_clk_sync_rst    ), // output wire c0_ddr4_ui_clk_sync_rst
  .c0_ddr4_aresetn              (peripheral_aresetn1), // input wire c0_ddr4_aresetn
  .c0_ddr4_s_axi_awid           (M00_axi_awid		), // input wire [7 : 0] c0_ddr4_s_axi_awid
  .c0_ddr4_s_axi_awaddr         (M00_axi_awaddr		), // input wire [31 : 0] c0_ddr4_s_axi_awaddr
  .c0_ddr4_s_axi_awlen          (M00_axi_awlen		), // input wire [7 : 0] c0_ddr4_s_axi_awlen
  .c0_ddr4_s_axi_awsize         (M00_axi_awsize		), // input wire [2 : 0] c0_ddr4_s_axi_awsize
  .c0_ddr4_s_axi_awburst        (M00_axi_awburst	), // input wire [1 : 0] c0_ddr4_s_axi_awburst
  .c0_ddr4_s_axi_awlock         (M00_axi_awlock		), // input wire [0 : 0] c0_ddr4_s_axi_awlock
  .c0_ddr4_s_axi_awcache        (M00_axi_awcache	), // input wire [3 : 0] c0_ddr4_s_axi_awcache
  .c0_ddr4_s_axi_awprot         (M00_axi_awprot		), // input wire [2 : 0] c0_ddr4_s_axi_awprot
  .c0_ddr4_s_axi_awqos          (M00_axi_awqos		), // input wire [3 : 0] c0_ddr4_s_axi_awqos
  .c0_ddr4_s_axi_awvalid        (M00_axi_awvalid	), // input wire c0_ddr4_s_axi_awvalid
  .c0_ddr4_s_axi_awready        (M00_axi_awready	), // output wire c0_ddr4_s_axi_awready
  .c0_ddr4_s_axi_wdata          (M00_axi_wdata		), // input wire [511 : 0] c0_ddr4_s_axi_wdata
  .c0_ddr4_s_axi_wstrb          (M00_axi_wstrb		), // input wire [63 : 0] c0_ddr4_s_axi_wstrb
  .c0_ddr4_s_axi_wlast          (M00_axi_wlast		), // input wire c0_ddr4_s_axi_wlast
  .c0_ddr4_s_axi_wvalid         (M00_axi_wvalid		), // input wire c0_ddr4_s_axi_wvalid
  .c0_ddr4_s_axi_wready         (M00_axi_wready		), // output wire c0_ddr4_s_axi_wready
  .c0_ddr4_s_axi_bready         (M00_axi_bready		), // input wire c0_ddr4_s_axi_bready
  .c0_ddr4_s_axi_bid            (M00_axi_bid		), // output wire [7 : 0] c0_ddr4_s_axi_bid
  .c0_ddr4_s_axi_bresp          (M00_axi_bresp		), // output wire [1 : 0] c0_ddr4_s_axi_bresp
  .c0_ddr4_s_axi_bvalid         (M00_axi_bvalid		), // output wire c0_ddr4_s_axi_bvalid
  .c0_ddr4_s_axi_arid           (M00_axi_arid		), // input wire [7 : 0] c0_ddr4_s_axi_arid
  .c0_ddr4_s_axi_araddr         (M00_axi_araddr		), // input wire [31 : 0] c0_ddr4_s_axi_araddr
  .c0_ddr4_s_axi_arlen          (M00_axi_arlen		), // input wire [7 : 0] c0_ddr4_s_axi_arlen
  .c0_ddr4_s_axi_arsize         (M00_axi_arsize		), // input wire [2 : 0] c0_ddr4_s_axi_arsize
  .c0_ddr4_s_axi_arburst        (M00_axi_arburst	), // input wire [1 : 0] c0_ddr4_s_axi_arburst
  .c0_ddr4_s_axi_arlock         (M00_axi_arlock		), // input wire [0 : 0] c0_ddr4_s_axi_arlock
  .c0_ddr4_s_axi_arcache        (M00_axi_arcache	), // input wire [3 : 0] c0_ddr4_s_axi_arcache
  .c0_ddr4_s_axi_arprot         (M00_axi_arprot		), // input wire [2 : 0] c0_ddr4_s_axi_arprot
  .c0_ddr4_s_axi_arqos          (M00_axi_arqos		), // input wire [3 : 0] c0_ddr4_s_axi_arqos
  .c0_ddr4_s_axi_arvalid        (M00_axi_arvalid	), // input wire c0_ddr4_s_axi_arvalid
  .c0_ddr4_s_axi_arready        (M00_axi_arready	), // output wire c0_ddr4_s_axi_arready
  .c0_ddr4_s_axi_rready         (M00_axi_rready		), // input wire c0_ddr4_s_axi_rready
  .c0_ddr4_s_axi_rlast          (M00_axi_rlast		), // output wire c0_ddr4_s_axi_rlast
  .c0_ddr4_s_axi_rvalid         (M00_axi_rvalid		), // output wire c0_ddr4_s_axi_rvalid
  .c0_ddr4_s_axi_rresp          (M00_axi_rresp		), // output wire [1 : 0] c0_ddr4_s_axi_rresp
  .c0_ddr4_s_axi_rid            (M00_axi_rid		), // output wire [7 : 0] c0_ddr4_s_axi_rid
  .c0_ddr4_s_axi_rdata          (M00_axi_rdata		), // output wire [511 : 0] c0_ddr4_s_axi_rdata
  .sys_rst                      (~sys_rst           )  // input wire sys_rst
);

endmodule
