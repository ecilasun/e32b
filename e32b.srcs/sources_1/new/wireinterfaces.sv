interface fpgadevicewires (
		output uart_rxd_out,
		input uart_txd_in,
		output spi_cs_n,
		output spi_mosi,
		input spi_miso,
		output spi_sck,
		input spi_cd,
		// ddr3
		output ddr3_reset_n,
		output [0:0] ddr3_cke,
		output [0:0] ddr3_ck_p, 
		output [0:0] ddr3_ck_n,
		output ddr3_ras_n, 
		output ddr3_cas_n, 
		output ddr3_we_n,
		output [2:0] ddr3_ba,
		output [14:0] ddr3_addr,
		output [0:0] ddr3_odt,
		output [1:0] ddr3_dm,
		inout [1:0] ddr3_dqs_p,
		inout [1:0] ddr3_dqs_n,
		inout [15:0] ddr3_dq,
		// hid
		input ps2_clk,
		input ps2_data,
		// buttons
		input [4:0] buttons);

	modport def (
		output uart_rxd_out,
		input uart_txd_in,
		output spi_cs_n,
		output spi_mosi,
		input spi_miso,
		output spi_sck,
		input spi_cd,
		output ddr3_reset_n,
		output ddr3_cke,
		output ddr3_ck_p, 
		output ddr3_ck_n,
		output ddr3_ras_n, 
		output ddr3_cas_n, 
		output ddr3_we_n,
		output ddr3_ba,
		output ddr3_addr,
		output ddr3_odt,
		output ddr3_dm,
		inout ddr3_dqs_p,
		inout ddr3_dqs_n,
		inout ddr3_dq,
		// hid
		input ps2_clk,
		input ps2_data,
		// buttons
		input buttons );

endinterface


interface fpgadeviceclocks (
		input calib_done,
		input wallclock,
		input uartbaseclock,
		input spibaseclock,
		input gpubaseclock,
		input pixelclock,
		input videoclock,
		input clk50mhz,
		input clk_sys_i,
		input clk_ref_i,
		input devicereset );

	modport def (
		input calib_done,
		input wallclock,
		input uartbaseclock,
		input spibaseclock,
		input gpubaseclock,
		input pixelclock,
		input videoclock,
		input clk50mhz,
		input clk_sys_i,
		input clk_ref_i,
		input devicereset );

endinterface

interface gpudataoutput(
	// hdmi
	output [2:0] tmdsp,
	output [2:0] tmdsn,
	output tmdsclkp,
	output tmdsclkn );

	modport def (
		output tmdsp,
		output tmdsn,
		output tmdsclkp,
		output tmdsclkn );

endinterface
