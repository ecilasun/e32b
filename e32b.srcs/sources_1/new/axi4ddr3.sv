`timescale 1ns / 1ps

// NOTE: This module uses a direct mapped cache with address space divided
// between D$ and I$ so that D$ ranges from cache line #0 to #255 (inclusive)
// and I$ starts at cache line #256 and goes up to cache line #511 (inclusive).
// Cache contents are written back when a tag change occurs and if the contents
// at that cache line are invalid (wback-on r/w)

module axi4ddr3(
	axi4.SLAVE axi4if,
	FPGADeviceClocks.DEFAULT clocks,
	FPGADeviceWires.DEFAULT wires,
	input wire ifetch,
	output wire calib_done );

wire ui_clk;
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
logic [64:0] ddr3cmd_din;
logic ddr3cmd_we = 1'b0;

wire ddr3cmd_empty;
wire [64:0] ddr3cmd_dout;
logic ddr3cmd_re = 1'b0;
wire ddr3cmd_valid;

ddr3cmdfifo DDR3CommandFIFO(
	// Bus side
	.wr_clk(axi4if.ACLK),
	.full(ddr3cmd_full),
	.din(ddr3cmd_din),
	.wr_en(ddr3cmd_we),
	// DDR3 app side
	.rd_clk(ui_clk),
	.empty(ddr3cmd_empty),
	.dout(ddr3cmd_dout),
	.rd_en(ddr3cmd_re),
	.valid(ddr3cmd_valid),
	// Reset/status
	.rst(ui_clk_sync_rst) );

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
	.wr_clk(ui_clk),
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
	.rst(ui_clk_sync_rst) );

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

logic [16:0] ptag;					// Previous cache tag (17 bits)
logic [16:0] ctag;					// Current cache tag (17 bits)
logic [8:0] cline;					// Current cache line 0..512 (there are 512 cache lines)
logic [1:0] coffset;				// Current word offset 0..3 (each cache line is 4xWORDs (128bits))
logic [31:0] cwidemask;				// Wide write mask

logic ccmd = 1'b0;					// Cache command (0'b0:read, 1'b1:write)

logic ddr3valid [0:511];			// Cache line valid bits
logic [127:0] ddr3cache [0:511];	// Cache lines x2
logic [16:0] ddr3tags [0:511];		// Cache line tags

logic [31:0] ddr3din = 32'd0;		// Input data to write from bus side

initial begin
	integer i;
	// All pages are 'clean', all tags are invalid and cache is zeroed out by default
	for (int i=0; i<512; i=i+1) begin
		ddr3valid[i] = 1'b1;		// Cache lines are all valid by default
		ddr3tags[i]  = 17'h1FFFF;	// All bits set for default tag
		ddr3cache[i] = 128'd0;		// Initially, cache line contains zero
	end
end

always @(posedge ui_clk) begin
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
					coffset <= ddr3cmd_dout[1:0];								// Cache offset 0..3 (last 2 bits of memory address discarded, this is word offset into 128bits)
					cline <= {ddr3cmd_dout[9:2], ddr3cmd_dout[28]};				// Cache line 0..255 (last 4 bits of memory address discarded, this is a 128-bit aligned address)
					ctag <= ddr3cmd_dout[26:10];								// Cache tag 00000..1FFFF
					ccmd <= ddr3cmd_dout[27];									// Read/write command
					//ifetchmode <= ddr3cmd_dout[28];							// Instruction fetch mode
					ddr3din <= ddr3cmd_dout[60:29];								// Data to write

					ptag <= ddr3tags[{ddr3cmd_dout[9:2], ddr3cmd_dout[28]}];	// Previous cache tag

					cwidemask <= {	{8{ddr3cmd_dout[64]}},
									{8{ddr3cmd_dout[63]}},
									{8{ddr3cmd_dout[62]}},
									{8{ddr3cmd_dout[61]}} };					// Build byte-wide mask for selective writes to cache

					// Test for cache hit or miss
					ddr3uistate <= CACHERESOLVE;
				end
			end

			CACHERESOLVE: begin
				// If previous tag from cache is same as new tag, we have a cache hit
				if (ptag == ctag) begin
					if (ccmd == 1'b1) begin // Write
						case (coffset)
							2'b00: ddr3cache[cline][31:0]	<= ((~cwidemask)&ddr3cache[cline][31:0]) | (cwidemask&ddr3din);
							2'b01: ddr3cache[cline][63:32]	<= ((~cwidemask)&ddr3cache[cline][63:32]) | (cwidemask&ddr3din);
							2'b10: ddr3cache[cline][95:64]	<= ((~cwidemask)&ddr3cache[cline][95:64]) | (cwidemask&ddr3din);
							2'b11: ddr3cache[cline][127:96]	<= ((~cwidemask)&ddr3cache[cline][127:96]) | (cwidemask&ddr3din);
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
					// If the current cache line is valid, 1)reload and 2)resolve
					// If the current cache line is invalid, 1)flush, 2)reload and 3)resolve
					ddr3uistate <= ddr3valid[cline] ? CACHEPOPULATE : CACHEWRITEBACK;
				end
			end

			CACHEWRITEBACK: begin
				if (app_rdy & app_wdf_rdy) begin
					app_en <= 1;
					app_wdf_wren <= 1;
					// Use previous tag to create writeback address (lines overlap)
					// NOTE: Addresses are aligned to multiples of 8x16 bits == 128 bits (16 bytes)
					app_addr <= {1'b0, ptag, cline[8:1], 3'b000}; // Drop the ifetch bit from cline when making memory address
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
					// NOTE: Addresses are aligned to multiples of 8x16 bits == 128 bits (16 bytes)
					app_addr <= {1'b0, ctag, cline[8:1], 3'b000}; // Drop the ifetch bit from cline when making memory address
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
localparam WAACK  = 2'd1;

localparam WIDLE   = 2'd0;
localparam WACCEPT = 2'd1;
localparam WDELAY  = 2'd2;

localparam RAIDLE = 2'd0;
localparam RAACK  = 2'd1;

localparam RIDLE     = 2'd0;
localparam RDELAY    = 2'd1;
localparam RFINALIZE = 2'd2;

logic [1:0] waddrstate = WAIDLE;
logic [1:0] writestate = WIDLE;
logic [1:0] raddrstate = RAIDLE;
logic [1:0] readstate  = RIDLE;

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
					// Convert bus address to word-aligned address by dropping the byte and half offset bits
					//                   [64:61]       [60:29]  [28]  [27]               [26:0]
					ddr3cmd_din <= {axi4if.WSTRB, axi4if.WDATA, 1'b0, 1'b1, axi4if.AWADDR[28:2]}; // ifetch not used during writes
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
					// Convert bus address to word-aligned address by dropping the byte and half offsetess bits
					//              [64:61]  [60:29]    [28]  [27]               [26:0]
					ddr3cmd_din <= {   4'h0,   32'd0, ifetch, 1'b0, axi4if.ARADDR[28:2]}; // ifetch only affects reads
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
