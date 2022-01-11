// AXI4 Lite attempt

// Global signals
// ACLK: clock source
// ARESETn: active low reset signal

//        Write address channel signals
// Master AWID: write address id
// Master AWADDR: write address (first address for burst write)
// Master AWLEN: burst length (number of transfers)
// Master AWSIZE: burst size
// Master AWBURST: burst type
// Master AWLOCK: lock type (atomicity)
// Master AWCACHE: memory type
// Master AWPROT: protection type
// Master AWQOS: quality of service identifier
// Master AWREGION: region identifier
// Master AWUSER: user signal (optional)
// Master AWVALID: write address valid
// Slave  AWREADY: write address ready (slave ready to accept address write)

//        Write data channel signals
// Master WID: write id tag
// Master WDATA: write data
// Master WSTRB: write strobe (byte select mask, one bit per byte)
// Master WLAST: write last (at end of burst)
// Master WUSER: user signal (optional)
// Master WVALID: write data valid
// Slave  WREADY: write data ready

//        Write response channel signals
// Slave  BID: response id tag
// Slave  BRESP: write response
// Slave  BUSER: user signal (optional)
// Slave  BVALID: write response valid
// Master BREADY: response ready

//        Read address channel signals
// Master ARID: read address id
// Master ARADDR: read address
// Master ARLEN: burst length
// Master ARSIZE: burst size
// Master ARBURST: burst type
// Master ARLOCK: lock type (atomicity)
// Master ARCACHE: memory type
// Master ARPROT: protection type
// Master ARQOS: quality of service identifier
// Master ARREGION: region identifier
// Master ARUSER: user signal
// Master ARVALID: read address valid
// Slave  ARREADY: read address ready

//        Read data channel signals
// Slave  RID: read id tag
// Slave  RDATA: read data
// Slave  RRESP: read response
// Slave  RLAST: read last (last entry in burst)
// Slave  RUSER: user signal (optional)
// Slave  RVALID: read valid
// Master RREADY: read ready

// AXI4-Lite

interface axi4 (
	input ACLK,
	input ARESETn);

	logic [31:0] AWADDR = 32'd0;
	logic AWVALID = 1'b0;
	logic AWREADY;

	// Write data channel signals
	logic [31:0] WDATA = 32'd0;
	logic [3:0] WSTRB = 4'h0;
	logic WLAST;
	logic WVALID = 1'b0;
	logic WREADY;

	// Write response channel signals
	logic [1:0] BRESP; // 00:OKAY 01:EXOKAY 10:SLVERR 11:DECERR
	logic BVALID;
	logic BREADY = 1'b1; // always ready for write response (might ignore)

	// Read address channel signals
	logic [31:0] ARADDR = 32'd0;
	logic ARVALID = 1'b0;
	logic ARREADY;

	// Read data channel signals
	logic [31:0] RDATA;
	logic [1:0] RRESP; // 00:OKAY 01:EXOKAY 10:SLVERR 11:DECERR
	logic RLAST;
	logic RVALID;
	logic RREADY = 1'b0;

	modport MASTER(
		input ACLK, ARESETn,
		output AWADDR, AWVALID, input AWREADY,
		output WDATA, WSTRB, WLAST, WVALID, input WREADY,
		input  BRESP, BVALID, output BREADY,
		output ARADDR, ARVALID, input ARREADY,
		input RDATA, RRESP, RLAST, RVALID, output RREADY );

	modport SLAVE(
		input ACLK, ARESETn,
		input AWADDR, AWVALID, output AWREADY,
		input WDATA, WSTRB, WLAST, WVALID, output WREADY,
		output BRESP, BVALID, input BREADY,
		input ARADDR, ARVALID, output ARREADY,
		output RDATA, RRESP, RLAST, RVALID, input RREADY );

endinterface

interface axi4wide (
	input ACLK,
	input ARESETn);

	logic [31:0] AWADDR = 32'd0;
	logic AWVALID = 1'b0;
	logic AWREADY;

	// Write data channel signals
	logic [63:0] WDATA = 32'd0;
	logic [7:0] WSTRB = 8'h00;
	logic WLAST;
	logic WVALID = 1'b0;
	logic WREADY;

	// Write response channel signals
	logic [1:0] BRESP; // 00:OKAY 01:EXOKAY 10:SLVERR 11:DECERR
	logic BVALID;
	logic BREADY = 1'b1; // always ready for write response (might ignore)

	// Read address channel signals
	logic [31:0] ARADDR = 32'd0;
	logic ARVALID = 1'b0;
	logic ARREADY;

	// Read data channel signals
	logic [63:0] RDATA;
	logic [1:0] RRESP; // 00:OKAY 01:EXOKAY 10:SLVERR 11:DECERR
	logic RLAST;
	logic RVALID;
	logic RREADY = 1'b0;

	modport MASTER(
		input ACLK, ARESETn,
		output AWADDR, AWVALID, input AWREADY,
		output WDATA, WSTRB, WLAST, WVALID, input WREADY,
		input  BRESP, BVALID, output BREADY,
		output ARADDR, ARVALID, input ARREADY,
		input RDATA, RRESP, RLAST, RVALID, output RREADY );

	modport SLAVE(
		input ACLK, ARESETn,
		input AWADDR, AWVALID, output AWREADY,
		input WDATA, WSTRB, WLAST, WVALID, output WREADY,
		output BRESP, BVALID, input BREADY,
		input ARADDR, ARVALID, output ARREADY,
		output RDATA, RRESP, RLAST, RVALID, input RREADY );

endinterface


	/*modport MASTER(
		input ACLK, ARESETn,
		output AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION, AWUSER, AWVALID, input AWREADY,
		output WID, WDATA, WSTRB, WLAST, WUSER, WVALID, input WREADY,
		input BID, BRESP, BUSER, BVALID, output BREADY,
		output ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION, ARUSER, ARVALID, input ARREADY,
		input RID, RDATA, RRESP, RLAST, RUSER, RVALID, output RREADY );

	modport SLAVE(
		input ACLK, ARESETn,
		input AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION, AWUSER, AWVALID, output AWREADY,
		input WID, WDATA, WSTRB, WLAST, WUSER, WVALID, output WREADY,
		output BID, BRESP, BUSER, BVALID, input BREADY,
		input ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION, ARUSER, ARVALID, output ARREADY,
		output RID, RDATA, RRESP, RLAST, RUSER, RVALID, input RREADY );*/

	/*clocking cb_clk @(posedge ACLK);
		default input #1ns output #1ns;
	endclocking*/