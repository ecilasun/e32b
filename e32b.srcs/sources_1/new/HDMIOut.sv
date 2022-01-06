`timescale 1ns / 1ps

// (c) fpga4fun.com & KNJN LLC 2013
// Modified slightly to fit custom code

module HDMIOut(
	input wire pixclk,		// 25MHz
	input wire pixclk10,	// 250MHz
	input wire [7:0] red,
	input wire [7:0] green,
	input wire [7:0] blue,
	input wire inDrawArea,
	input wire hSync, vSync,
	output wire [2:0] TMDSp,
	output wire [2:0] TMDSn,
	output wire TMDSp_clock,
	output wire TMDSn_clock );

wire [9:0] TMDS_red, TMDS_green, TMDS_blue;
TMDS_encoder encode_R(.clk(pixclk), .VD(red  ), .CD(2'b00)        , .VDE(inDrawArea), .TMDS(TMDS_red));
TMDS_encoder encode_G(.clk(pixclk), .VD(green), .CD(2'b00)        , .VDE(inDrawArea), .TMDS(TMDS_green));
TMDS_encoder encode_B(.clk(pixclk), .VD(blue ), .CD({vSync,hSync}), .VDE(inDrawArea), .TMDS(TMDS_blue));

logic [3:0] TMDS_mod10=0;  // modulus 10 counter
logic [9:0] TMDS_shift_red=0, TMDS_shift_green=0, TMDS_shift_blue=0;
logic TMDS_shift_load=0;
always @(posedge pixclk10) TMDS_shift_load <= (TMDS_mod10==4'd9);

always @(posedge pixclk10)
begin
	TMDS_shift_red   <= TMDS_shift_load ? TMDS_red   : TMDS_shift_red  [9:1];
	TMDS_shift_green <= TMDS_shift_load ? TMDS_green : TMDS_shift_green[9:1];
	TMDS_shift_blue  <= TMDS_shift_load ? TMDS_blue  : TMDS_shift_blue [9:1];	
	TMDS_mod10 <= (TMDS_mod10==4'd9) ? 4'd0 : TMDS_mod10+4'd1;
end

OBUFDS OBUFDS_red  (.I(TMDS_shift_red  [0]), .O(TMDSp[2]), .OB(TMDSn[2]));
OBUFDS OBUFDS_green(.I(TMDS_shift_green[0]), .O(TMDSp[1]), .OB(TMDSn[1]));
OBUFDS OBUFDS_blue (.I(TMDS_shift_blue [0]), .O(TMDSp[0]), .OB(TMDSn[0]));
OBUFDS OBUFDS_clock(.I(pixclk), .O(TMDSp_clock), .OB(TMDSn_clock));

endmodule
