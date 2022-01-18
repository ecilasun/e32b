`timescale 1ns / 1ps

module clockandresetgen(
	input wire sys_clock_i,
	output wire wallclock,
	output wire uartbaseclock,
	output wire spibaseclock,
	output wire gpubaseclock,
	output wire videoclock,
	output wire clk50mhz,
	output wire clk_sys_i,
	output wire clk_ref_i,
	output logic devicereset = 1'b1 );

wire centralclocklocked, ddr3clklocked, videoclklocked;

centralclockgen centralclock(
	.clk_in1(sys_clock_i),
	.wallclock(wallclock),
	.uartbaseclock(uartbaseclock),
	.spibaseclock(spibaseclock),
	.clk50mhz(clk50mhz),
	.locked(centralclocklocked) );

ddr3clk ddr3memoryclock(
	.clk_in1(sys_clock_i),
	.ddr3sys(clk_sys_i),
	.ddr3ref(clk_ref_i),
	.locked(ddr3clklocked) );

videoclocks graphicsclock(
	.clk_in1(sys_clock_i),
	.gpubaseclock(gpubaseclock),
	.videoclock(videoclock),
	.locked(videoclklocked) );

// hold reset until clocks are locked
wire internalreset = ~(centralclocklocked & ddr3clklocked & videoclklocked);

// delayed reset post-clock-lock
logic [3:0] resetcountdown = 4'hf;
always @(posedge wallclock) begin // using slowest clock
	if (internalreset) begin
		resetcountdown <= 4'hf;
		devicereset <= 1'b1;
	end else begin
		if (/*busready &&*/ (resetcountdown == 4'h0))
			devicereset <= 1'b0;
		else
			resetcountdown <= resetcountdown - 4'h1;
	end
end

endmodule
