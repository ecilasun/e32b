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
    input kclk,
    input kdata,
    output reg [15:0] keycode = 16'd0,
    output reg oflag = 1'b0
    );

wire kclkf, kdataf;
reg [7:0] datacur = 0;
reg [7:0] dataprev = 0;
reg [3:0] cnt = 0;
reg flag = 0;

debouncer #(
    .count_max(19),
    .count_width(5)
) db_clk(
    .clk(clk),
    .i(kclk),
    .o(kclkf)
);

debouncer #(
   .count_max(19),
   .count_width(5)
) db_data(
    .clk(clk),
    .i(kdata),
    .o(kdataf)
);
    
always@(negedge(kclkf))begin
    case(cnt)
		0:;//start bit
		1:datacur[0]<=kdataf;
		2:datacur[1]<=kdataf;
		3:datacur[2]<=kdataf;
		4:datacur[3]<=kdataf;
		5:datacur[4]<=kdataf;
		6:datacur[5]<=kdataf;
		7:datacur[6]<=kdataf;
		8:datacur[7]<=kdataf;
		9:flag<=1'b1;
		10:flag<=1'b0;

    endcase
	if(cnt<=9)
		cnt<=cnt+1;
	else if(cnt==10)
		cnt<=0;
end

reg pflag;
always@(posedge clk) begin
    if (flag == 1'b1 && pflag == 1'b0) begin
        keycode <= {dataprev, datacur};
        oflag <= 1'b1;
        dataprev <= datacur;
    end else
        oflag <= 'b0;
    pflag <= flag;
end

endmodule