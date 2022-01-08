`timescale 1ns / 1ps

module axi4ddr3(
	axi4.SLAVE axi4if,
	FPGADeviceClocks.DEFAULT clocks,
	FPGADeviceWires.DEFAULT wires,
	output wire calib_done,
	output wire ui_clk);

//assign calib_done = 1'b1;
//assign ui_clk = axi4if.ACLK;

wire ui_clk_sync_rst;

logic [28:0] app_addr = 29'd0;
logic [2:0]  app_cmd = 3'd0;
logic app_en = 1'b0;
wire app_rdy;

logic [127:0] app_wdf_data = 128'd0;
logic app_wdf_wren = 1'b0;
wire app_wdf_rdy;

wire [127:0] app_rd_data;
wire app_rd_data_end;
wire app_rd_data_valid;

// 128bit reads/writes
mig_7series_0 u_mig_7series_0 (
    .ddr3_addr                      (wires.ddr3_addr),
    .ddr3_ba                        (wires.ddr3_ba),
    .ddr3_cas_n                     (wires.ddr3_cas_n),
    .ddr3_ck_n                      (wires.ddr3_ck_n),
    .ddr3_ck_p                      (wires.ddr3_ck_p),
    .ddr3_cke                       (wires.ddr3_cke),
    .ddr3_ras_n                     (wires.ddr3_ras_n),
    .ddr3_reset_n                   (wires.ddr3_reset_n),
    .ddr3_we_n                      (wires.ddr3_we_n),
    .ddr3_dq                        (wires.ddr3_dq),
    .ddr3_dqs_n                     (wires.ddr3_dqs_n),
    .ddr3_dqs_p                     (wires.ddr3_dqs_p),
    .ddr3_dm                        (wires.ddr3_dm),
    .ddr3_odt                       (wires.ddr3_odt),

    .app_addr                       (app_addr),
    .app_cmd                        (app_cmd),
    .app_en                         (app_en),
    .app_wdf_data                   (app_wdf_data),
    .app_wdf_end                    (app_wdf_wren), // one burst, same as wren
    .app_wdf_wren                   (app_wdf_wren),
    .app_rd_data                    (app_rd_data),
    .app_rd_data_end                (app_rd_data_end),
    .app_rd_data_valid              (app_rd_data_valid),
    .app_rdy                        (app_rdy),
    .app_wdf_rdy                    (app_wdf_rdy),
    .app_sr_req                     (1'b0),
    .app_ref_req                    (1'b0),
    .app_zq_req                     (1'b0),
    .app_sr_active                  (),
    .app_ref_ack                    (),
    .app_zq_ack                     (),
    .app_wdf_mask                   (16'h0000),			// Active low

    .ui_clk                         (ui_clk),
    .ui_clk_sync_rst                (ui_clk_sync_rst),
    .init_calib_complete            (calib_done),
    .device_temp					(),					// Unused, TODO: Maybe we can expose this via the axi4 bus, to use as a random number seed or simply for monitoring?

    .sys_clk_i                      (clocks.clk_sys_i), // 100MHz
    .clk_ref_i                      (clocks.clk_ref_i), // 200MHz
    .sys_rst                        (axi4if.ARESETn)
);

wire ddr3cmd_full;
logic [65:0] ddr3cmd_din;
logic ddr3cmd_we = 1'b0;

wire ddr3cmd_empty;
wire [65:0] ddr3cmd_dout;
logic ddr3cmd_re = 1'b0;
wire ddr3cmd_valid;

ddr3cmdfifo DDR3CommandFIFO(
	// Bus side
	.wr_clk(axi4if.ACLK),
	.full(ddr3cmd_full),
	.din(ddr3cmd_din),
	.wr_en(ddr3cmd_we),
	// DDR3 app side
	.rd_clk(clocks.ui_clk),
	.empty(ddr3cmd_empty),
	.dout(ddr3cmd_dout),
	.rd_en(ddr3cmd_re),
	.valid(ddr3cmd_valid),
	// Reset/status
	.rst(ui_clk_sync_rst),
	.wr_rst_busy(),
	.rd_rst_busy() );

// Read done queue
wire ddr3readfull;
logic [31:0] ddr3readin;
logic ddr3readwe = 1'b0;

wire ddr3readempty;
wire [31:0] ddr3readout;
logic ddr3readre = 1'b0;
wire ddr3readvalid;

ddr3readdone DDR3ReadDoneQueue(
	// DDR3 app side
	.wr_clk(clocks.ui_clk),
	.full(ddr3readfull),
	.din(ddr3readin),
	.wr_en(ddr3readwe),
	// Bus side
	.rd_clk(axi4if.ACLK),
	.empty(ddr3readempty),
	.dout(ddr3readout),
	.rd_en(ddr3readre),
	.valid(ddr3readvalid),
	// Reset/status
	.rst(ui_clk_sync_rst),
	.wr_rst_busy(),
	.rd_rst_busy() );

localparam CACHEIDLE			= 3'd0;
localparam CACHELOOKUPSETUP		= 3'd1;
localparam CACHERESOLVE			= 3'd2;
localparam CACHEWRITEBACK		= 3'd3;
localparam CACHEWRITEBACKDONE	= 3'd4;
localparam CACHEPOPULATE 		= 3'd5;
localparam CACHEPOPULATEDONE	= 3'd6;

localparam CMD_WRITE = 3'b000;
localparam CMD_READ = 3'b001;

logic [2:0] ddr3uistate = CACHEIDLE;

// [65:62]     [61:30]    [29:1]                   [0]
// wmask[3:0], din[31:0], warrd[29:1]/raddr[29:1], cmdr/cmdw[0:0] == total of 66 bits

// logic [65:0] ddr3cmd = {we, din, waddr, 1'b1} -> write
// logic [65:0] ddr3cmd = {36'dz, raddr, 1'b0} -> read

logic [17:0] ptag;		// Previous cache tag (18 bits)
logic [17:0] ctag;		// Current cache tag (18 bits)
logic [7:0] cline;		// Current cache line 0..255 (there are 256 cache lines)
logic [1:0] coffset;	// Current word offset 0..3 (each cache line is 4xWORDs (128bits))
logic [31:0] cwidemask;	// Wide write mask

logic ddr3valid [0:255];			// Cache line valid bits
logic [127:0] ddr3cache [0:255];	// Cache lines
logic [17:0] ddr3tags [0:255];		// Cache line tags

// Incoming data to write from bus side
logic [31:0] ddr3din = 32'd0;

initial begin
	integer i;
	// All pages are 'clean', all tags are invalid and cache is zeroed out by default
	for (int i=0; i<256; i=i+1) begin
		ddr3valid[i] = 1'b1;		// Cache lines are all valid by default
		ddr3tags[i] = 18'h3FFFF;	// All bits set for default tag
		ddr3cache[i] = 128'd0;		// Initially, cache line contains zero
	end
end

// NOTE: This module uses a direct mapped cache with no dedicated I$/D$ but a combined cache, therefore will function
// very poorly as-is. Separate I$ will follow in following versions.

always @(posedge clocks.ui_clk) begin
	if (ui_clk_sync_rst) begin

		// noop

	end else begin

		// Stop read/write requests
		ddr3readwe <= 1'b0;
		ddr3cmd_re <= 1'b0;

		case (ddr3uistate)

			CACHEIDLE: begin
				// Pull one command from the queue if we have something
				if (~ddr3cmd_empty) begin
					ddr3cmd_re <= 1'b1;
					ddr3uistate <= CACHELOOKUPSETUP;
				end
			end

			CACHELOOKUPSETUP: begin
				if (ddr3cmd_valid) begin
					// Set up cache access data
					cwidemask <= {	{8{ddr3cmd_dout[65]}},
									{8{ddr3cmd_dout[64]}},
									{8{ddr3cmd_dout[63]}},
									{8{ddr3cmd_dout[62]}} };	// Build byte-wide mask for selective writes to cache
					ddr3din <= ddr3cmd_dout[61:30];				// Data to write
					ctag <= ddr3cmd_dout[29:12];				// axi4if.AxADDR[29:12] Cache tag 0..256144 (reaches up to 512Mbyte range with 29:0 range)
					cline <= ddr3cmd_dout[11:4];				// axi4if.AxADDR[11:4] Cache line 0..255
					coffset <= ddr3cmd_dout[3:2];				// axi4if.AxADDR[3:2] WORD offset 0..3
					ptag <= ddr3tags[ddr3cmd_dout[11:4]];		// Previous tag stored for this cache line
					// Test for cache hit or miss
					ddr3uistate <= CACHERESOLVE;
				end
			end

			CACHERESOLVE: begin
				// If previous tag from cache is same as new tag, we have a cache hit
				if (ptag == ctag) begin
					if (ddr3cmd_dout[0] == 1'b1) begin // Write
						case (coffset)
							2'b00: ddr3cache[cline][31:0] <= ((~cwidemask)&ddr3cache[cline][31:0]) | (cwidemask&ddr3din);
							2'b01: ddr3cache[cline][63:32] <= ((~cwidemask)&ddr3cache[cline][63:32]) | (cwidemask&ddr3din);
							2'b10: ddr3cache[cline][95:64] <= ((~cwidemask)&ddr3cache[cline][95:64]) | (cwidemask&ddr3din);
							2'b11: ddr3cache[cline][127:96] <= ((~cwidemask)&ddr3cache[cline][127:96]) | (cwidemask&ddr3din);
						endcase
						// Mark this cache line invalid so that it can be flushed to DDR3 memory next time
						ddr3valid[cline] <= 1'b0;
					end else begin // Read
						case (coffset)
							2'b00: ddr3readin <= ddr3cache[cline][31:0];
							2'b01: ddr3readin <= ddr3cache[cline][63:32];
							2'b10: ddr3readin <= ddr3cache[cline][95:64];
							2'b11: ddr3readin <= ddr3cache[cline][127:96];
						endcase
						// Write the output value
						ddr3readwe <= 1'b1;
					end
					// We're done, listen to next command
					ddr3uistate <= CACHEIDLE;
				end else begin // Otherwise, we have a cache miss
					// If the current cache line is invalid, 1)flush, 2)reload and 3)resolve
					// If the current cache line is valid, 1)reload and 2)resolve
					ddr3uistate <= ddr3valid[cline] ? CACHEPOPULATE : CACHEWRITEBACK;
				end
			end

			CACHEWRITEBACK: begin
				if (app_rdy & app_wdf_rdy) begin
					app_en <= 1;
					app_wdf_wren <= 1;
					// Use previous tag to create writeback address (lines overlap)
					// NOTE: Addresses are in multiples of 16 bits x8 == 128 bits (16 bytes)
					app_addr <= {ptag, cline, 3'b000};
					app_cmd <= CMD_WRITE;
					app_wdf_data <= ddr3cache[cline];
					ddr3uistate <= CACHEWRITEBACKDONE;
				end // Else, wait until we get a chance to write
			end

			CACHEWRITEBACKDONE: begin
				if (app_rdy & app_en) begin
					app_en <= 0;
				end
				if (app_wdf_rdy & app_wdf_wren) begin
					app_wdf_wren <= 0;
				end
				if (~app_en & ~app_wdf_wren) begin
					// Set valid bit
					ddr3valid[cline] <= 1'b1;
					ddr3uistate <= CACHEPOPULATE; // We can now load the new page
				end
			end

			CACHEPOPULATE: begin
				// Load new page
				if (app_rdy) begin
					app_en <= 1;
					// Use current tag to create load address
					// NOTE: Addresses are in multiples of 16 bits x8 == 128 bits (16 bytes)
					app_addr <= {ctag, cline, 3'b000};
					app_cmd <= CMD_READ;
					ddr3uistate <= CACHEPOPULATEDONE;
				end
			end

			default: begin // CACHEPOPULATEDONE
				if (app_rdy & app_en) begin
					app_en <= 0;
				end

				if (app_rd_data_valid) begin
					// Update tag
					ptag <= ctag;
					ddr3tags[cline] <= ctag;
					// Update previous/current cache contents
					ddr3cache[cline] <= app_rd_data;
					// Go to resolve
					ddr3uistate <= CACHERESOLVE;
				end
			end

		endcase
	end
end

// ----------------------------------------------------------------------------
// DDR3 frontend
// ----------------------------------------------------------------------------

localparam WAIDLE = 2'd0;
localparam WAACK = 2'd1;

localparam WIDLE = 2'd0;
localparam WACCEPT = 2'd1;
localparam WDELAY = 2'd2;

localparam RIDLE = 2'd0;
localparam RREAD = 2'd1;
localparam RDELAY = 2'd2;
localparam RFINALIZE = 2'd3;

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

always @(posedge axi4if.ACLK) begin
	if (~axi4if.ARESETn) begin
		axi4if.AWREADY <= 1'b1;
		axi4if.ARREADY <= 1'b1;
		axi4if.RVALID <= 1'b0;
		axi4if.RRESP <= 2'b00; // 00:OK(all ok) 01:EXACCESSOK(exclusive access ok) 10:SLAVEERR(r/w or wait error) 11:DECODERERR(address error)
		axi4if.WREADY <= 1'b0;
		axi4if.BRESP <= 2'b00; // 00:OK(all ok) 01:EXACCESSOK(exclusive access ok) 10:SLAVEERR(r/w or wait error) 11:DECODERERR(address error)
		axi4if.BVALID <= 1'b0;
	end else begin

		ddr3cmd_we <= 1'b0;

		// Write address
		case (waddrstate)
			WAIDLE: begin
				if (axi4if.AWVALID) begin
					axi4if.AWREADY <= 1'b0;
					waddrstate <= WAACK;
				end
			end
			default: begin // WAACK
				axi4if.AWREADY <= 1'b1;
				waddrstate <= WAIDLE;
			end
		endcase
	
		// Write data
		case (writestate)
			WIDLE: begin
				if (axi4if.WVALID & (~ddr3cmd_full)) begin
					axi4if.WREADY <= 1'b1;
					// Convert bus address to half-aligned address by dropping the byte
					ddr3cmd_din <= {axi4if.WSTRB, axi4if.WDATA, axi4if.AWADDR[29:1], 1'b1};
					ddr3cmd_we <= 1'b1;
					writestate <= WACCEPT;
				end
			end
			WACCEPT: begin
				axi4if.WREADY <= 1'b0;
				if(axi4if.BREADY) begin
					// Done
					axi4if.BVALID <= 1'b1;
					axi4if.BRESP = 2'b00; // OKAY
					writestate <= WDELAY;
				end
			end
			default: begin // WDELAY
				axi4if.BVALID <= 1'b0;
				writestate <= WIDLE;
			end
		endcase

		// Read data
		ddr3readre <= 1'b0;
		case (raddrstate)
			RIDLE: begin
				if (axi4if.ARVALID & (~ddr3cmd_full)) begin
					// Convert bus address to half-aligned address by dropping the byte
					ddr3cmd_din <= {4'h0, 32'd0, axi4if.ARADDR[29:1], 1'b0};
					ddr3cmd_we <= 1'b1;
					axi4if.ARREADY <= 1'b0;
					raddrstate <= RREAD;
				end
			end
			RREAD: begin
				// Master ready to accept, and FIFO is not empty
				if (axi4if.RREADY & (~ddr3readempty)) begin
					ddr3readre <= 1'b1;		// Read the outcome
					raddrstate <= RDELAY;	// Delay one clock for master to pull down ARVALID
				end
			end
			RDELAY: begin
				if (ddr3readvalid) begin
					axi4if.RDATA <= ddr3readout;
					axi4if.RVALID <= 1'b1;
					//axi4if.RLAST <= 1'b1; // Last in burst
					raddrstate <= RFINALIZE;
				end
			end
			default: begin //RFINALIZE
				axi4if.RVALID <= 1'b0;
				axi4if.ARREADY <= 1'b1;
				//axi4if.RLAST <= 1'b0;
				raddrstate <= RIDLE;
			end
		endcase
	end
end

endmodule
