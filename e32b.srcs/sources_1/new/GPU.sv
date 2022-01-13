`timescale 1ns / 1ps

module axi4gpu(
	axi4.SLAVE axi4if,
	FPGADeviceWires.DEFAULT wires,
	FPGADeviceClocks.DEFAULT clocks,
	GPUDataOutput.DEFAULT gpudata );

// ----------------------------------------------------------------------------
// Color palette unit
// ----------------------------------------------------------------------------

wire [7:0] paletteReadAddress;
logic [7:0] paletteWriteAddress;
logic palettewe = 1'b0;
logic [23:0] palettedin = 24'd0;
wire [23:0] palettedout;

colorpalette Palette(
	.gpuclock(axi4if.ACLK),
	.we(palettewe),
	.waddress(paletteWriteAddress),
	.raddress(paletteReadAddress),
	.din(palettedin),
	.dout(palettedout) );

// ----------------------------------------------------------------------------
// Video units
// ----------------------------------------------------------------------------

wire [11:0] video_x;
wire [11:0] video_y;

// Normally GPU boots in single buffer mode
// where reads and writes happen from the same video page.
logic videowritepage = 1'b0;
logic videoreadpage = 1'b0;

logic [3:0] videowe = 4'h0;
logic [31:0] videodin = 32'd0;
logic [14:0] videowaddr = 15'd0;

wire [7:0] paletteReadAddressA;
wire [7:0] paletteReadAddressB;

wire inDisplayWindow = (video_x<640) && (video_y<480);
wire pixelclock;

videounit TiledFramebufferA(
	.gpuclock(axi4if.ACLK),
	.pixelclock(pixelclock),
	.video_x(video_x),
	.video_y(video_y),
	.waddr(videowaddr),
	.we(videowe),
	.din(videodin),
	.paletteindexout(paletteReadAddressA) );

assign paletteReadAddress = paletteReadAddressA;//videoreadpage ? paletteReadAddressA : paletteReadAddressB;

// ----------------------------------------------------------------------------
// Video output unit
// ----------------------------------------------------------------------------

wire hSync, vSync;
wire vsync_we;
wire [31:0] vsynccounter;

videosignalgen VideoSignalGenerator(
	.clk_i(pixelclock),
	.rst_i(clocks.devicereset),
	.hsync_o(hSync),
	.vsync_o(vSync),
	.counter_x(video_x),
	.counter_y(video_y),
	.vsynctrigger_o(vsync_we),
	.vsynccounter(vsynccounter) );

HDMI_test VideoScanOutUnit(
	.clk(clocks.videoclock),	// 125MHz
	.pixclk(pixelclock),		// pixel clock output
	.hSync(hSync),
	.vSync(vSync),
	.color(palettedout),
	.inDrawArea(inDisplayWindow),
	.TMDSp(gpudata.TMDSp),
	.TMDSn(gpudata.TMDSn),
	.TMDSp_clock(gpudata.TMDSCLKp),
	.TMDSn_clock(gpudata.TMDSCLKn)
);

// ----------------------------------------------------------------------------
// Domain crossing vsync fifo
// ----------------------------------------------------------------------------

/*wire [31:0] vsync_fastdomain;
wire vsyncfifoempty;
wire vsyncfifovalid;

logic vsync_re;
DomainCrossSignalFifo GPUVGAVSyncQueue(
	.full(), // Not really going to get full (read clock faster than write clock)
	.din(vsynccounter),
	.wr_en(vsync_we),
	.empty(vsyncfifoempty),
	.dout(vsync_fastdomain),
	.rd_en(vsync_re),
	.wr_clk(videoclock),
	.rd_clk(gpuclock),
	.rst(reset),
	.valid(vsyncfifovalid) );

// Drain the vsync fifo and set a new vsync signal for the GPU every time we find one
// This is done in GPU clocks so we don't need to further sync the read data to GPU
always @(posedge gpuclock) begin
	vsync_re <= 1'b0;
	if (~vsyncfifoempty) begin
		vsync_re <= 1'b1;
	end
	if (vsyncfifovalid) begin
		vsyncID <= vsync_fastdomain;
	end
end*/

// ----------------------------------------------------------------------------
// Linear address to tile address converter
// ----------------------------------------------------------------------------

logic [29:0] writeaddress = 30'd0;

wire [6:0] wx = writeaddress[6:0];		// wa%128
wire [7:0] wy = writeaddress[14:7];		// wa/128
wire [3:0] tx = wx[6:3];				// wx/8
wire [2:0] lx = wx[2:0];				// tile horizontal word index (0..7)
wire [2:0] ty = wy[7:5];				// wy/32
wire [4:0] ly = wy[4:0];				// tile vertical word index (0..31)

// Linear memory address to tile id
wire [6:0] tileid = tx + ty*10;			// linear tile index (0..69)

// Linear memory address to tile local address
wire [7:0] laddress = {ly, lx};			// linear tile local address (0..255)

// ----------------------------------------------------------------------------
// GPU
// ----------------------------------------------------------------------------

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

// Not used yet
logic re = 1'b0;
wire [31:0] dout = 32'h0;

always @(posedge axi4if.ACLK) begin
	if (~axi4if.ARESETn) begin
		axi4if.AWREADY <= 1'b1;
	end else begin
		// Write address
		case (waddrstate)
			2'b00: begin
				if (axi4if.AWVALID) begin
					axi4if.AWREADY <= 1'b0;
					writeaddress <= axi4if.AWADDR[31:2]; // Word aligned write address
					waddrstate <= 2'b01;
				end
			end
			default/*2'b01*/: begin
				axi4if.AWREADY <= 1'b1;
				waddrstate <= 2'b00;
			end
		endcase
	end
end

always @(posedge axi4if.ACLK) begin
	if (~axi4if.ARESETn) begin
		//
	end else begin

		videowe <= 4'h0;
		palettewe <= 1'b0;
		axi4if.WREADY <= 1'b0;
		axi4if.BVALID <= 1'b0;

		if (axi4if.WVALID /*& canActuallyWrite*/) begin
			// Latch the data and byte select
			// TODO: Detect which video page or command stream we're writing to via address
			//00000-1FFFF: page 0
			//20000-3FFFF: page 1 (i.e. writeaddress[15]==pageselect)
			//40000-401FF: color palette (writeaddress[18]==1)
			//80000-8FFFF: device control (read/write page selection, vsync etc)
			if (writeaddress[16]==1'b1) begin // Palette
				paletteWriteAddress <= writeaddress[7:0]; // Palette index, multiples of word addresses
				palettewe <= 1'b1;
				palettedin <= axi4if.WDATA[23:0];
			end else if (writeaddress[17]==1'b1) begin // Device control
				// [31:18]: unused, TBD
				// [17:17]: scanout page
				// [16:16]: write page
				// [15:0]: unused
				videowritepage <= axi4if.WDATA[16];	// Setting this to 0 or 1 will select the corresponding video memory range active for write
				videoreadpage <= axi4if.WDATA[17];	// Setting this to 0 or 1 will select the corresponding video memory range active for output
			end else begin // Framebuffers
				videowaddr <= {tileid, laddress};
				videowe <= axi4if.WSTRB;
				videodin <= axi4if.WDATA;
			end
			axi4if.WREADY <= 1'b1;
			if(axi4if.BREADY) begin
				axi4if.BVALID <= 1'b1;
				axi4if.BRESP <= 2'b00; // OKAY
				writestate <= 2'b10;
			end
		end
	end
end

always @(posedge axi4if.ACLK) begin
	if (~axi4if.ARESETn) begin
		axi4if.ARREADY <= 1'b1;
		axi4if.RVALID <= 1'b0;
		axi4if.RRESP <= 2'b00;
	end else begin
		// Read address
		re <= 1'b0;
		case (raddrstate)
			2'b00: begin
				if (axi4if.ARVALID) begin
					// TODO: Reads from 80000-8FFFF will return vsync id
					axi4if.ARREADY <= 1'b0;
					re <= 1'b1;
					raddrstate <= 2'b01;
				end
			end
			2'b01: begin
				// Master ready to accept?
				if (axi4if.RREADY /*& dataActuallyRead*/) begin
					axi4if.RDATA <= dout;
					axi4if.RVALID <= 1'b1;
					raddrstate <= 2'b10; // Delay one clock for master to pull down ARVALID
				end
			end
			default/*2'b10*/: begin
				axi4if.RVALID <= 1'b0;
				axi4if.ARREADY <= 1'b1;
				raddrstate <= 2'b00;
			end
		endcase
	end
end

endmodule
