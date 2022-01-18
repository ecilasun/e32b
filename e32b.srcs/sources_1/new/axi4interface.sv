// AXI4-Lite

interface axi4 (
	input aclk,
	input aresetn);

	logic [31:0] awaddr = 32'd0;
	logic awvalid = 1'b0;
	logic awready;

	// write data channel signals
	logic [31:0] wdata = 32'd0;
	logic [3:0] wstrb = 4'h0;
	logic wlast;
	logic wvalid = 1'b0;
	logic wready;

	// write response channel signals
	logic [1:0] bresp; // 00:okay 01:exokay 10:slverr 11:decerr
	logic bvalid;
	logic bready = 1'b1; // always ready for write response (might ignore)

	// read address channel signals
	logic [31:0] araddr = 32'd0;
	logic arvalid = 1'b0;
	logic arready;

	// read data channel signals
	logic [31:0] rdata;
	logic [1:0] rresp; // 00:okay 01:exokay 10:slverr 11:decerr
	logic rlast;
	logic rvalid;
	logic rready = 1'b0;

	modport master(
		input aclk, aresetn,
		output awaddr, awvalid, input awready,
		output wdata, wstrb, wlast, wvalid, input wready,
		input  bresp, bvalid, output bready,
		output araddr, arvalid, input arready,
		input rdata, rresp, rlast, rvalid, output rready );

	modport slave(
		input aclk, aresetn,
		input awaddr, awvalid, output awready,
		input wdata, wstrb, wlast, wvalid, output wready,
		output bresp, bvalid, input bready,
		input araddr, arvalid, output arready,
		output rdata, rresp, rlast, rvalid, input rready );

endinterface

interface axi4wide (
	input aclk,
	input aresetn);

	logic [31:0] awaddr = 32'd0;
	logic awvalid = 1'b0;
	logic awready;

	// write data channel signals
	logic [63:0] wdata = 32'd0;
	logic [7:0] wstrb = 8'h00;
	logic wlast;
	logic wvalid = 1'b0;
	logic wready;

	// write response channel signals
	logic [1:0] bresp; // 00:okay 01:exokay 10:slverr 11:decerr
	logic bvalid;
	logic bready = 1'b1; // always ready for write response (might ignore)

	// read address channel signals
	logic [31:0] araddr = 32'd0;
	logic arvalid = 1'b0;
	logic arready;

	// read data channel signals
	logic [63:0] rdata;
	logic [1:0] rresp; // 00:okay 01:exokay 10:slverr 11:decerr
	logic rlast;
	logic rvalid;
	logic rready = 1'b0;

	modport master(
		input aclk, aresetn,
		output awaddr, awvalid, input awready,
		output wdata, wstrb, wlast, wvalid, input wready,
		input  bresp, bvalid, output bready,
		output araddr, arvalid, input arready,
		input rdata, rresp, rlast, rvalid, output rready );

	modport slave(
		input aclk, aresetn,
		input awaddr, awvalid, output awready,
		input wdata, wstrb, wlast, wvalid, output wready,
		output bresp, bvalid, input bready,
		input araddr, arvalid, output arready,
		output rdata, rresp, rlast, rvalid, input rready );

endinterface


	/*modport master(
		input aclk, aresetn,
		output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion, awuser, awvalid, input awready,
		output wid, wdata, wstrb, wlast, wuser, wvalid, input wready,
		input bid, bresp, buser, bvalid, output bready,
		output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion, aruser, arvalid, input arready,
		input rid, rdata, rresp, rlast, ruser, rvalid, output rready );

	modport slave(
		input aclk, aresetn,
		input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion, awuser, awvalid, output awready,
		input wid, wdata, wstrb, wlast, wuser, wvalid, output wready,
		output bid, bresp, buser, bvalid, input bready,
		input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion, aruser, arvalid, output arready,
		output rid, rdata, rresp, rlast, ruser, rvalid, input rready );*/

	/*clocking cb_clk @(posedge aclk);
		default input #1ns output #1ns;
	endclocking*/