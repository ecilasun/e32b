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
	.gpuclock(clocks.gpubaseclock),
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

logic videopagesel = 1'b0;
logic [3:0] videowe = 4'h0;
logic [31:0] videodin = 32'd0;
logic [14:0] videowaddr = 15'd0;

//wire paletteReadAddressA, paletteReadAddressB;

wire [11:0] actual_y = video_y-12'd16;
wire [3:0] video_tile_x = video_x[9:6];		// x10 horizontal tiles of width 32
wire [3:0] video_tile_y = actual_y[9:6];	// x7 vertical tiles of width 32 (/64 instead of 32 since pixels are x2 in size)
wire [4:0] tile_pixel_x = video_x[5:1];
wire [4:0] tile_pixel_y = actual_y[5:1];

wire inDisplayWindow = (video_x<640) && (video_y<480);

videounit VideoUnitA (
		.clocks(clocks),
		.writesenabled(1'b1),//~videopagesel), // 0->active for writes, inactive for output
		.video_x(video_x),
		.video_y(video_y),
		.waddr(videowaddr),
		.we(videowe),
		.din(videodin),
		.lanemask(15'd0), // TODO: enable to allow simultaneous writes
		.paletteindexout(paletteReadAddress/*A*/) );

/*videounit VideoUnitB (
		.gpuclock(clocks.gpubaseclock),
		.vgaclock(clocks.videoclock),
		.writesenabled(videopagesel), // 1->active for writes, inactive for output
		.video_x(video_x),
		.video_y(video_y),
		.waddr(videowaddr),
		.we(videowe),
		.din(videodin),
		.lanemask(15'd0),
		.paletteindexout(paletteReadAddressB) );

assign inDisplayWindow = videopagesel ? inDisplayWindowA : inDisplayWindowB;
assign dataEnable = videopagesel ? dataEnableA : dataEnableB;
assign paletteReadAddress = videopagesel ? paletteReadAddressA : paletteReadAddressB;*/

// ----------------------------------------------------------------------------
// Video output unit
// ----------------------------------------------------------------------------

wire hSync, vSync;
wire vsync_we;
wire [31:0] vsynccounter;

wire [7:0] VIDEO_B = palettedout[7:0];
wire [7:0] VIDEO_R = palettedout[15:8];
wire [7:0] VIDEO_G = palettedout[23:16];

videosignalgen VideoSignalGenerator(
	.clk_i(clocks.videoclock),
	.rst_i(~axi4if.ARESETn),
	.hsync_o(hSync),
	.vsync_o(vSync),
	.counter_x(video_x),
	.counter_y(video_y),
	.vsynctrigger_o(vsync_we),
	.vsynccounter(vsynccounter) );

HDMIOut VideoScanOutUnit(
	.pixclk(clocks.videoclock),		// 25MHz pixel clock
	.pixclk10(clocks.videoclock10),	// 250Mhz 10:1 TDMS shif clock
	.red(VIDEO_R),
	.green(VIDEO_G),
	.blue(VIDEO_B),
	.inDrawArea(inDisplayWindow),
	.hSync(hSync),
	.vSync(vSync),
	.TMDSp(gpudata.TMDSp),
	.TMDSn(gpudata.TMDSn),
	.TMDSp_clock(gpudata.TMDSCLKp),
	.TMDSn_clock(gpudata.TMDSCLKn) );

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
// GPU
// ----------------------------------------------------------------------------

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

logic [31:0] writeaddress = 32'd0;
logic [7:0] din = 8'h00;
logic [3:0] we = 4'h0;
logic re = 1'b0;
wire [31:0] dout = 32'hFFFFFFFF;

always @(posedge axi4if.ACLK) begin
	// Write address
	case (waddrstate)
		2'b00: begin
			if (axi4if.AWVALID) begin
				writeaddress <= axi4if.AWADDR;
				axi4if.AWREADY <= 1'b1;
				waddrstate <= 2'b01;
			end
		end
		default/*2'b01*/: begin
			axi4if.AWREADY <= 1'b0;
			waddrstate <= 2'b00;
		end
	endcase
end

always @(posedge axi4if.ACLK) begin
	// Write data
	videowe <= 4'h0;
	palettewe = 1'b0;
	case (writestate)
		2'b00: begin
			if (axi4if.WVALID /*& canActuallyWrite*/) begin
				// Latch the data and byte select
				// TODO: Detect which video page or command stream we're writing to via address
				//00000-1FFFF: page 0
				//20000-3FFFF: page 1 (i.e. writeaddress[15]==pageselect)
				//40000-401FF: color palette
				if (writeaddress[18]==1'b1) begin
					paletteWriteAddress = writeaddress[9:2]; // Palette index, multiples of word addresses
					palettewe = 1'b1;
					palettedin = axi4if.WDATA[23:0];
				end else begin
					videowaddr <= writeaddress[16:2]; // Word aligned
					videowe <= axi4if.WSTRB;
					videodin <= axi4if.WDATA;
				end
				axi4if.WREADY <= 1'b1;
				writestate <= 2'b01;
			end
		end
		2'b01: begin
			axi4if.WREADY <= 1'b0;
			if(axi4if.BREADY) begin
				axi4if.BVALID <= 1'b1;
				axi4if.BRESP = 2'b00; // OKAY
				writestate <= 2'b10;
			end
		end
		default/*2'b10*/: begin
			axi4if.BVALID <= 1'b0;
			writestate <= 2'b00;
		end
	endcase
end

always @(posedge axi4if.ACLK) begin
	if (~axi4if.ARESETn) begin
		axi4if.ARREADY <= 1'b0;
		axi4if.RVALID <= 1'b0;
		axi4if.RRESP <= 2'b00;
	end else begin
		// Read address
		re <= 1'b0;
		case (raddrstate)
			2'b00: begin
				if (axi4if.ARVALID) begin
					// We're ready with the addres
					axi4if.ARREADY <= 1'b1;
					// Set up for read
					re <= 1'b1;
					raddrstate <= 2'b01;
				end
			end
			2'b01: begin
				axi4if.ARREADY <= 1'b0; // Can take this down after arvalid/ready handshake
				// Master ready to accept?
				if (axi4if.RREADY /*& dataActuallyRead*/) begin
					// Actually read
					axi4if.RDATA <= dout;
					// Read valid
					axi4if.RVALID <= 1'b1;
					//axi4if.RLAST <= 1'b1; // Last entry in burst
					raddrstate <= 2'b10; // Delay one clock for master to pull down ARVALID
				end
			end
			default/*2'b10*/: begin
				axi4if.RVALID <= 1'b0;
				//axi4if.RLAST <= 1'b0;
				raddrstate <= 2'b00;
			end
		endcase
	end
end

endmodule
