`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// company: digilent inc.
// engineer: thomas kappenman
// 
// create date: 03/03/2015 09:33:36 pm
// design name: 
// module name: ps2receiver
// project name: nexys4ddr keyboard demo
// target devices: nexys4ddr
// tool versions: 
// description: ps2 receiver module used to shift in keycodes from a keyboard plugged into the ps2 port
// 
// dependencies: 
// 
// revision:
// revision 0.01 - file created
// additional comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module ps2receiver(
    input clk,
    input ps2_clk,
    input ps2_data,
    output reg [15:0] keycode = 16'd0,
    output reg oflag = 1'b0
    );

reg [7:0] datashift = 0;
reg [7:0] dataprev = 0;
reg [3:0] cnt = 0;
reg rdy = 0;
    
always@(negedge(ps2_clk))begin
    case(cnt)
		0:;//start bit
		1:datashift[0]<=ps2_data;
		2:datashift[1]<=ps2_data;
		3:datashift[2]<=ps2_data;
		4:datashift[3]<=ps2_data;
		5:datashift[4]<=ps2_data;
		6:datashift[5]<=ps2_data;
		7:datashift[6]<=ps2_data;
		8:datashift[7]<=ps2_data;
		9:rdy<=1'b1; // stop bit
		10:rdy<=1'b0;
    endcase
	if(cnt<=9)
		cnt<=cnt+1;
	else if(cnt==10)
		cnt<=0;
end

reg pflag;
always@(posedge clk) begin
    if (rdy == 1'b1 && pflag == 1'b0) begin
        keycode <= {dataprev, datashift};
        oflag <= 1'b1;
        dataprev <= datashift;
    end else
        oflag <= 'b0;
    pflag <= rdy;
end

endmodule
