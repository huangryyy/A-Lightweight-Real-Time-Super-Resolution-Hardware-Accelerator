`timescale 1ns/1ps
module tb_FSRCNN_X4 #(parameter WIDTH=16, HEIGHT=8, DATA_DIR=".");
localparam WORDS=WIDTH*HEIGHT/4;
reg clk=0;always #5 clk=~clk;
reg rst=0,start=0,first=0,last=0,relu=1;
reg wi=0,ww=0,wb=0,ro=0;
reg[15:0]ia=0,oa=0;reg[7:0]wa=0;reg[3:0]ba=0;
reg[511:0]id=0;reg[2047:0]wd=0;reg[255:0]bd=0;
reg[2:0]kernel=5;reg[3:0]pad=2;reg[15:0]scale=1191;
wire done;wire[511:0]out;
PG_sram #(.bits_input(8),.bits_weight(8),.bits_bias(16),.bits_eleout(16),
 .bits_addout(31),.bits_macout(18),.bits_quantout(8),.addr_bit_inp(16),.addr_bit_out(16),
 .addr_bit_weight(8),.addr_bit_bias(4),.ic_para(16),.oc_para(16),.pixel_para(4)) dut(
 .clk(clk),.rst(rst),.channel(16'd16),.pixel_h(HEIGHT[15:0]),.pixel_w(WIDTH[15:0]),.filter_n(16'd16),
 .kernel_h(kernel),.kernel_w(kernel),.ReLU_enable(relu),.first_layer(first),.last_layer(last),
 .wEn_inp(wi),.padding_left(1'b1),.padding_right(1'b1),.wAddr_inp(ia),.wData_inp(id),
 .wEn_weight(ww),.wAddr_weight(wa),.wData_weight(wd),.wEn_bias(wb),.wAddr_bias(ba),.wData_bias(bd),
 .rEn_out(ro),.rAddr_out(oa),.rData_out(out),.quantization_scale(scale),
 .acc_start_signal(start),.acc_finish_signal(done),.pad_h(pad),.pad_w(pad));
reg[511:0]input_mem[0:WORDS-1],expected[0:WORDS-1],next_input[0:WORDS-1];
reg[2047:0]weights[0:71];reg[255:0]biases[0:7];
integer ks[0:7],ss[0:7];integer layer,i,woff=0,errors=0;
reg[1023:0]fname,dir;
initial begin
 if(!$value$plusargs("DATA_DIR=%s",dir))dir=DATA_DIR;
 $sformat(fname,"%0s/input.mem",dir);$readmemh(fname,input_mem);
 $sformat(fname,"%0s/weights.mem",dir);$readmemh(fname,weights);
 $sformat(fname,"%0s/bias.mem",dir);$readmemh(fname,biases);
 ks[0]=5;ks[1]=1;ks[2]=3;ks[3]=3;ks[4]=3;ks[5]=3;ks[6]=1;ks[7]=3;
 ss[0]='h04a7;ss[1]='h076e;ss[2]='h0591;ss[3]='h03f7;
 ss[4]='h0729;ss[5]='h06d7;ss[6]='h048c;ss[7]='h0055;
 repeat(5)@(negedge clk);rst=1;
 for(layer=0;layer<8;layer=layer+1)begin
  @(negedge clk);first=(layer==0);last=(layer==7);relu=(layer!=7);
  kernel=ks[layer];pad=ks[layer]/2;scale=ss[layer];
  wi=1;
  for(i=0;i<WORDS;i=i+1)begin ia=i;id=(layer==0)?input_mem[i]:next_input[i];@(negedge clk);end
  wi=0;ww=1;
  for(i=0;i<ks[layer]*ks[layer];i=i+1)begin wa=i;wd=weights[woff+i];@(negedge clk);end
  ww=0;wb=1;ba=0;bd=biases[layer];@(negedge clk);wb=0;woff=woff+ks[layer]*ks[layer];
  repeat(10)@(negedge clk);start=1;@(negedge clk);start=0;
  wait(done===1);repeat(10)@(negedge clk);
  $sformat(fname,"%0s/expected%0d.mem",dir,layer);$readmemh(fname,expected);
  ro=1;
  for(i=0;i<WORDS;i=i+1)begin
   oa=i;@(posedge clk);#1;next_input[i]=out;
   if(out!==expected[i])begin
    if(errors<4)$display("MISMATCH layer=%0d word=%0d expected=%h got=%h",layer,i,expected[i],out);
    errors=errors+1;
   end
   @(negedge clk);
  end
  ro=0;
  if(errors)$fatal(1,"3DIC8 mismatch layer %0d count=%0d",layer,errors);
  $display("PASS layer %0d: all %0d words / %0d bytes",layer,WORDS,WORDS*64);
  repeat(10)@(negedge clk);
 end
 $display("PASS: eight layers + signed residual match independent 3DIC reference");$finish;
end
initial begin #50000000;$fatal(1,"Simulation timeout");end
endmodule

