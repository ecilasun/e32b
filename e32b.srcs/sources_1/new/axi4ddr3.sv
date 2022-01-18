`timescale 1ns / 1ps

module axi4ddr3(
	axi4.slave axi4if,
	fpgadeviceclocks.def clocks,
	fpgadevicewires.def wires,
	input wire ifetch,
	output wire calib_done,
	output wire ui_clk );

wire ui_clk_sync_rst;

axi4wide ddr3if(axi4if.aclk, axi4if.aresetn);

ddr3drv ddr3driver(
	.ddr3if(ddr3if),
	.clocks(clocks),
	.wires(wires),
	.calib_done(calib_done),
	.ui_clk(ui_clk) );

ddr3frontend ddr3frontend(
	.ddr3if(ddr3if),
	.axi4if(axi4if),
	.ifetch(ifetch) );

endmodule
