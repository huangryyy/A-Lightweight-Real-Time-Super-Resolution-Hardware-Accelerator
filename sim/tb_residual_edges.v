`timescale 1ns/1ps
module tb_residual_edges;
reg signed[17:0]q;reg signed[7:0]r;reg last;wire[7:0]v;
residual_add_saturate dut(.quantized(q),.residual(r),.last_layer(last),.value(v));
task check(input integer a,b,enable,expected);
begin q=a;r=b;last=enable;#1;if(v!==expected[7:0])$fatal(1,"Residual edge %0d+%0d enable=%0d got=%h expected=%h",a,b,enable,v,expected[7:0]);end
endtask
initial begin
 check(200,-100,1,100);check(-200,100,1,-100);
 check(131071,127,1,127);check(-131072,-128,1,-128);
 check(-1,0,1,-1);check(127,1,1,127);check(-128,-1,1,-128);
 check(-1,100,0,0);check(300,-100,0,255);check(200,-100,0,200);
 $display("PASS residual edges: add-before-clip, signed extension, overflow and unsigned bypass");$finish;
end
endmodule
