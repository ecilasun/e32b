`timescale 1ns / 1ps

module topmodule(
	// fpga external clock
	input wire sys_clock,
	// device wires
	output wire uart_rxd_out,
	input  wire uart_txd_in,
	// spi (sdcard)
	output wire spi_cs_n,
	output wire spi_mosi,
	input wire spi_miso,
	output wire spi_sck,
	input wire spi_cd,
	output wire sd_poweron_n, // always grounded to keep sdcard powered
	// hdmi
	output wire [2:0] hdmi_tx_p,
	output wire [2:0] hdmi_tx_n,
	output wire hdmi_tx_clk_p,
	output wire hdmi_tx_clk_n,
    // ddr3
    output wire ddr3_reset_n,
    output wire [0:0] ddr3_cke,
    output wire [0:0] ddr3_ck_p, 
    output wire [0:0] ddr3_ck_n,
    output wire ddr3_ras_n, 
    output wire ddr3_cas_n, 
    output wire ddr3_we_n,
    output wire [2:0] ddr3_ba,
    output wire [14:0] ddr3_addr,
    output wire [0:0] ddr3_odt,
    output wire [1:0] ddr3_dm,
    inout wire [1:0] ddr3_dqs_p,
    inout wire [1:0] ddr3_dqs_n,
    inout wire [15:0] ddr3_dq,
    // hid
    /*input wire ps2_clk,
    input wire ps2_data,*/
    // buttons
    input wire [4:0] buttons );

// ----------------------------------------------------------------------------
// device wire interface
// ----------------------------------------------------------------------------

// keep sdcard powered on
// todo: tie to axi4-lite control
assign sd_poweron_n = 1'b0;

wire ui_clk;

fpgadevicewires wires(
	.uart_txd_in(uart_txd_in),
	.uart_rxd_out(uart_rxd_out),
	.spi_cs_n(spi_cs_n),
	.spi_mosi(spi_mosi),
	.spi_miso(spi_miso),
	.spi_sck(spi_sck),
	.spi_cd(spi_cd),
    // ddr3
    .ddr3_reset_n(ddr3_reset_n),
    .ddr3_cke(ddr3_cke),
    .ddr3_ck_p(ddr3_ck_p), 
    .ddr3_ck_n(ddr3_ck_n),
    .ddr3_ras_n(ddr3_ras_n), 
    .ddr3_cas_n(ddr3_cas_n), 
    .ddr3_we_n(ddr3_we_n),
    .ddr3_ba(ddr3_ba),
    .ddr3_addr(ddr3_addr),
    .ddr3_odt(ddr3_odt),
    .ddr3_dm(ddr3_dm),
    .ddr3_dqs_p(ddr3_dqs_p),
    .ddr3_dqs_n(ddr3_dqs_n),
    .ddr3_dq(ddr3_dq),
    // hid
    /*.ps2_clk(ps2_clk),
    .ps2_data(ps2_data),*/
    // buttons
    .buttons(buttons) );

gpudataoutput gpudata(
	.tmdsp(hdmi_tx_p),
	.tmdsn(hdmi_tx_n),
	.tmdsclkp(hdmi_tx_clk_p ),
	.tmdsclkn(hdmi_tx_clk_n) );

// ----------------------------------------------------------------------------
// clock and reset generator
// ----------------------------------------------------------------------------

wire wallclock, uartbaseclock, spibaseclock;
wire clk_sys_i, clk_ref_i;
wire gpubaseclock, pixelclock, videoclock, clk50mhz;
wire devicereset, calib_done;

clockandresetgen clockandresetgenerator(
	.sys_clock_i(sys_clock),
	.wallclock(wallclock),
	.uartbaseclock(uartbaseclock),
	.spibaseclock(spibaseclock),
	.gpubaseclock(gpubaseclock),
	.pixelclock(pixelclock),
	.videoclock(videoclock),
	.clk50mhz(clk50mhz),
	.clk_sys_i(clk_sys_i),
	.clk_ref_i(clk_ref_i),
	.devicereset(devicereset) );

fpgadeviceclocks clocks(
	.calib_done(calib_done),
	.cpuclock(ui_clk), // bus/cpu clock taken over by ddr3 generated clock
	.wallclock(wallclock),
	.uartbaseclock(uartbaseclock),
	.spibaseclock(spibaseclock),
	.gpubaseclock(gpubaseclock),
	.pixelclock(pixelclock),
	.videoclock(videoclock),
	.clk50mhz(clk50mhz),
	.clk_sys_i(clk_sys_i),
	.clk_ref_i(clk_ref_i),
	.devicereset(devicereset) );

// ----------------------------------------------------------------------------
// axi4 chain
// ----------------------------------------------------------------------------

wire [3:0] irq;
wire ifetch;

axi4 axi4busa(
	.aclk(ui_clk),
	.aresetn(~devicereset) );

/*axi4 axi4busb(
	.aclk(ui_clk),
	.aresetn(~devicereset) );*/

axi4chain axichain(
	.axi4if(axi4busa),
	.clocks(clocks),
	.wires(wires),
	.gpudata(gpudata),
	.ifetch(ifetch),
	.irq(irq),
	.calib_done(calib_done),
	.ui_clk(ui_clk) );

// ----------------------------------------------------------------------------
// master device (cpu)
// ----------------------------------------------------------------------------

// reset vector in b-ram (rom)
axi4cpu #(.resetvector(32'h80000000)) hart0(
	.axi4if(axi4busa),
	.clocks(clocks),
	.wires(wires),
	.ifetch(ifetch),
	.irq(irq),
	.calib_done(calib_done) );

// reset vector: s-ram
/*axi4cpu #(.resetvector(32'h80010000)) hart1(
	.axi4if(axi4busb),
	.clocks(clocks),
	.wires(wires),
	.ifetch(ifetch),
	.irq(irq),
	.calib_done(calib_done) );*/

endmodule
