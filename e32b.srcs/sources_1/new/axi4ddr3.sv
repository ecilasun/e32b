`timescale 1ns / 1ps

module axi4ddr3(
	axi4.SLAVE axi4if,
	FPGADeviceClocks.DEFAULT clocks,
	FPGADeviceWires.DEFAULT wires,
	input wire ifetch,
	output wire calib_done,
	output wire ui_clk );

wire ui_clk_sync_rst;

axi4wide ddr3if(axi4if.ACLK, axi4if.ARESETn);

ddr3drv DDR3Driver(
	.ddr3if(ddr3if),
	.clocks(clocks),
	.wires(wires),
	.calib_done(calib_done),
	.ui_clk(ui_clk) );

ddr3frontend DDR3FrontEnd(
	.ddr3if(ddr3if),
	.axi4if(axi4if),
	.ifetch(ifetch) );

endmodule
