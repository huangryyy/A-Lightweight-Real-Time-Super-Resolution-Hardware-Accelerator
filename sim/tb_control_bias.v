`timescale 1ns/1ps
module tb_control_bias;
reg clk=0;always #5 clk=~clk;
reg rst=0;reg[31:0]awaddr=0,wd=0,araddr=0;
reg awv=0,wv=0,arv=0,conv_done=0;
wire awr,wr,bv,arr,rv;wire[31:0]rd;wire[319:0]cfg;wire launch,first,last,relu;
top_controller ctrl(.I_clk(clk),.I_rst_n(rst),.S_AXI_AWADDR(awaddr),.S_AXI_AWPROT(3'd0),
 .S_AXI_AWVALID(awv),.S_AXI_AWREADY(awr),.S_AXI_WDATA(wd),.S_AXI_WSTRB(4'hf),
 .S_AXI_WVALID(wv),.S_AXI_WREADY(wr),.S_AXI_BRESP(),.S_AXI_BVALID(bv),.S_AXI_BREADY(1'b1),
 .S_AXI_ARADDR(araddr),.S_AXI_ARPROT(3'd0),.S_AXI_ARVALID(arv),.S_AXI_ARREADY(arr),
 .S_AXI_RDATA(rd),.S_AXI_RRESP(),.S_AXI_RVALID(rv),.S_AXI_RREADY(1'b1),
 .O_conv_config_data(cfg),.O_conv_start_signal(launch),.I_conv_finish_signal(conv_done),
 .O_ReLU_enable(relu),.first_layer(first),.last_layer(last),.I_debug_status(32'd0));
task write_reg(input[31:0]a,input[31:0]d);
begin
 @(negedge clk);awaddr=a;awv=1;wd=d;
 @(posedge clk);while(!awr)@(posedge clk);
 @(negedge clk);awv=0;wv=1;
 @(posedge clk);while(!wr)@(posedge clk);
 @(negedge clk);wv=0;wd=32'hdeadbeef; // AXI permits WDATA to change after handshake
 wait(bv);@(negedge clk);
end endtask
integer pass,l,j;
reg bias_pass=0;
initial begin
 repeat(5)@(negedge clk);rst=1;
 @(negedge clk);araddr=68;arv=1;
 @(posedge clk);while(!arr)@(posedge clk);
 @(negedge clk);arv=0;wait(rv);#1;
 if(rd!==32'h38475231)$fatal(1,"Model capability register wrong: %h",rd);
 $display("PASS capability register");
 // A serial-class PCIe device can receive partial register probes before XDMA.
 // These must not create a convolution descriptor or skew the next packet.
 for(j=0;j<12;j=j+1)write_reg((j%2)*4,32'h55aa0000+j);
 for(pass=0;pass<2;pass=pass+1)begin
  for(l=0;l<8;l=l+1)for(j=0;j<10;j=j+1)write_reg(j*4,l*100+j);
  $display("Configurations queued pass %0d",pass);
  write_reg(60,1);
  for(l=0;l<8;l=l+1)begin
   wait(launch===1);repeat(4)@(negedge clk);
   if(cfg[31:0] !== l*100+9)
    $fatal(1,"Configuration FIFO captured invalid WDATA after handshake: layer=%0d got=%h expected=%h",l,cfg[31:0],l*100+9);
   if(first!==(l==0)||last!==(l==7)||relu!==(l!=7))
    $fatal(1,"Layer flags wrong layer=%0d first=%b last=%b relu=%b",l,first,last,relu);
   wait(ctrl.r_state==4);@(negedge clk);
   conv_done=1;@(negedge clk);conv_done=0;
   repeat(6)@(negedge clk);
   if(l<7&&ctrl.r_pl_state!==0)$fatal(1,"Completed before eighth layer");
  end
  wait(ctrl.r_pl_state===1);write_reg(60,2);wait(ctrl.r_pl_state===0);
  $display("PASS controller: run %0d, exactly eight layers and correct first/last/ReLU",pass);
 end
 wait(bias_pass===1);
 $display("PASS control + bias interface");$finish;
end
reg bias_start=0;wire bias_done,bias_we;wire[3:0]bias_addr;
wire[255:0]bias_data;wire[31:0]ddr_addr;wire[7:0]ddr_len;
wire ddr_req,ddr_ready;reg[511:0]ddr_data=0;reg ddr_valid=0;
localparam[255:0]EXPECTED=256'h0102_fffe_0304_8001_0506_7fff_0708_ffff_0910_0000_1112_1234_1314_fedc_1516_abcd;
ddr_rd_wrapper3 #(.RAM_ADDR_WIDTH(4)) bias_dut(
 .I_clk(clk),.I_rst_n(rst),.I_addr_offset(32'h4800),.I_rd_lenth(32'd1),.I_offset_valid(bias_start),
 .O_rd_finish_signal(bias_done),.O_ram_addr(bias_addr),.O_wr_en(bias_we),.O_ram_data(bias_data),
 .M_AXI_ARID(),.M_AXI_ARADDR(ddr_addr),.M_AXI_ARLEN(ddr_len),.M_AXI_ARSIZE(),.M_AXI_ARBURST(),
 .M_AXI_ARLOCK(),.M_AXI_ARCACHE(),.M_AXI_ARPROT(),.M_AXI_ARQOS(),.M_AXI_ARVALID(ddr_req),
 .M_AXI_ARREADY(1'b1),.M_AXI_RID(4'd0),.M_AXI_RDATA(ddr_data),.M_AXI_RRESP(2'd0),
 .M_AXI_RVALID(ddr_valid),.M_AXI_RLAST(1'b1),.M_AXI_RREADY(ddr_ready));
initial begin
 wait(rst);repeat(5)@(negedge clk);bias_start=1;@(negedge clk);bias_start=0;
 wait(ddr_req);#1;if(ddr_len!==0||ddr_addr!==32'h4800)$fatal(1,"Wrong bias DDR request");
 repeat(5)@(negedge clk);ddr_data={256'hdeadbeef,EXPECTED};ddr_valid=1;
 @(posedge clk);while(!ddr_ready)@(posedge clk);
 @(negedge clk);ddr_valid=0;wait(bias_we);#1;
 if(bias_addr!==0||bias_data!==EXPECTED)$fatal(1,"Bias256 data/address mismatch %h",bias_data);
 wait(bias_done);bias_pass=1;$display("PASS DDR bias: one DDR512 beat -> sixteen signed bias16 values");
end
initial begin #1000000;
 $display("DEBUG wrstate=%d rdstate=%d state=%d awv=%b awr=%b wv=%b wr=%b bv=%b arv=%b arr=%b rv=%b rd=%h counter=%d layer=%d startreg=%h",ctrl.r_wr_state,ctrl.r_rd_state,ctrl.r_state,awv,awr,wv,wr,bv,arv,arr,rv,rd,ctrl.r_conv_cal_cnt,ctrl.r_layer_scale_cnt,ctrl.r_reg_grp[15]);
 $fatal(1,"Controller/bias test timeout");end
endmodule
