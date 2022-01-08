`timescale 1ns / 1ps

module topmodule(
	// FPGA external clock
	input wire sys_clock,
	// Device wires
	output wire uart_rxd_out,
	input  wire uart_txd_in,
	// SPI (SDCard)
	output wire spi_cs_n,
	output wire spi_mosi,
	input wire spi_miso,
	output wire spi_sck,
	input wire spi_cd,
	output wire sd_poweron_n, // Always grounded to keep SDCard powered
	// HDMI
	output wire [2:0] hdmi_tx_p,
	output wire [2:0] hdmi_tx_n,
	output wire hdmi_tx_clk_p,
	output wire hdmi_tx_clk_n,
    // DDR3
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
    inout wire [15:0] ddr3_dq );

// ----------------------------------------------------------------------------
// Device wire interface
// ----------------------------------------------------------------------------

// Keep SDCard powered on
// TODO: Tie to axi4-lite control
assign sd_poweron_n = 1'b0;

wire ui_clk;

FPGADeviceWires wires(
	.uart_txd_in(uart_txd_in),
	.uart_rxd_out(uart_rxd_out),
	.spi_cs_n(spi_cs_n),
	.spi_mosi(spi_mosi),
	.spi_miso(spi_miso),
	.spi_sck(spi_sck),
	.spi_cd(spi_cd),
    // DDR3
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
    .ddr3_dq(ddr3_dq) );

GPUDataOutput gpudata(
	.TMDSp(hdmi_tx_p),
	.TMDSn(hdmi_tx_n),
	.TMDSCLKp(hdmi_tx_clk_p ),
	.TMDSCLKn(hdmi_tx_clk_n) );

// ----------------------------------------------------------------------------
// Clock and reset generator
// ----------------------------------------------------------------------------

wire wallclock, cpuclock, uartbaseclock, spibaseclock;
wire clk_sys_i, clk_ref_i;
wire gpubaseclock, videoclock, videoclock10;
wire devicereset, calib_done;

clockandresetgen ClockAndResetGenerator(
	.sys_clock_i(sys_clock),
	.wallclock(wallclock),
	.cpuclock(cpuclock),
	.uartbaseclock(uartbaseclock),
	.spibaseclock(spibaseclock),
	.gpubaseclock(gpubaseclock),
	.videoclock(videoclock),
	.videoclock10(videoclock10),
	.clk_sys_i(clk_sys_i),
	.clk_ref_i(clk_ref_i),
	.devicereset(devicereset) );

FPGADeviceClocks clocks(
	.calib_done(calib_done),
	.cpuclock(cpuclock), // Bus/CPU clock taken over by DDR3 generated clock
	.wallclock(wallclock),
	.uartbaseclock(uartbaseclock),
	.spibaseclock(spibaseclock),
	.gpubaseclock(gpubaseclock),
	.videoclock(videoclock),
	.videoclock10(videoclock10),
	.ui_clk(ui_clk), // DDR3 driven clock
	.clk_sys_i(clk_sys_i),
	.clk_ref_i(clk_ref_i) );

// ----------------------------------------------------------------------------
// AXI4 chain
// ----------------------------------------------------------------------------

wire [3:0] irq;
wire ifetch;

axi4 axi4chain(
	.ACLK(cpuclock),
	.ARESETn(~devicereset) );

axi4chain AXIChain(
	.axi4if(axi4chain),
	.clocks(clocks),
	.wires(wires),
	.gpudata(gpudata),
	.ifetch(ifetch),
	.irq(irq),
	.calib_done(calib_done),
	.ui_clk(ui_clk) );

// ----------------------------------------------------------------------------
// Master device (CPU)
// Reset vector points at B-RAM which contains the startup code
// ----------------------------------------------------------------------------

axi4cpu #(.RESETVECTOR(32'h80000000)) HART0(
	.axi4if(axi4chain),
	.clocks(clocks),
	.wires(wires),
	.ifetch(ifetch), // High when we're requesting an instruction
	.irq(irq),
	.calib_done(calib_done) );

endmodule
