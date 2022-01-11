`timescale 1ns / 1ps

// NOTE: This module uses a direct mapped cache with address space divided
// between D$ and I$ so that D$ uses even cache entries and I$ uses the odd.
// Each cache line consists of 8 words (256 bits).
// Cache contents are written back when a tag change occurs and if the contents
// at that cache line are invalid (wback-on r/w)

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
