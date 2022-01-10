`timescale 1ns / 1ps

// NOTE: This module uses a direct mapped cache with address space divided
// between D$ and I$ so that D$ uses even cache entries and I$ uses the odd.
// Each cache line consists of 8 words (256 bits).
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

localparam DDR3IDLE			= 3'd0;
localparam DDR3DECODECMD	= 3'd1;
localparam DDR3WRITE		= 3'd2;
localparam DDR3WRITE_DONE	= 3'd3;
localparam DDR3READ			= 3'd4;
localparam DDR3READ_DONE	= 3'd5;

localparam CMD_WRITE	= 3'b000;
localparam CMD_READ		= 3'b001;

logic [2:0] ddr3uistate = DDR3IDLE;

logic ddr3cmdre = 1'b0;
wire ddr3cmdempty, ddr3cmdvalid;
wire [153:0] ddr3cmdout; // cmd[153:153] qwordaddrs[152:128] din[127:0]

wire ddr3readfull;
logic ddr3readwe = 1'b0;
logic [127:0] ddr3readin = 128'd0;

// ddr3 driver
always @ (posedge ui_clk) begin
	if (ui_clk_sync_rst) begin
		//
	end else begin

		case (ddr3uistate)

			DDR3IDLE: begin
				ddr3readwe <= 1'b0;
				if (~ddr3cmdempty) begin
					ddr3cmdre <= 1'b1;
					ddr3uistate <= DDR3DECODECMD;
				end
			end

			DDR3DECODECMD: begin
				ddr3cmdre <= 1'b0;
				if (ddr3cmdvalid) begin
					if (ddr3cmdout[153]==1'b1) begin // Write request?
						if (app_rdy & app_wdf_rdy) begin
							// Take early opportunity to write
							app_en <= 1;
							app_wdf_wren <= 1;
							app_addr <= {1'b0, ddr3cmdout[152:128], 3'b000}; // Addresses are in multiples of 16 bits x8 == 128 bits, top bit is supposed to stay zero
							app_cmd <= CMD_WRITE;
							app_wdf_data <= ddr3cmdout[127:0]; // 128bit value to write to memory from cache
							ddr3uistate <= DDR3WRITE_DONE;
						end else
							ddr3uistate <= DDR3WRITE;
					end else begin
						if (app_rdy) begin
							// Take early opportunity to read
							app_en <= 1;
							app_addr <= {1'b0, ddr3cmdout[152:128], 3'b000}; // Addresses are in multiples of 16 bits x8 == 128 bits, top bit is supposed to stay zero
							app_cmd <= CMD_READ;
							ddr3uistate <= DDR3READ_DONE;
						end else
							ddr3uistate <= DDR3READ;
					end
				end
			end

			DDR3WRITE: begin
				if (app_rdy & app_wdf_rdy) begin
					app_en <= 1;
					app_wdf_wren <= 1;
					app_addr <= {1'b0, ddr3cmdout[152:128], 3'b000}; // Addresses are in multiples of 16 bits x8 == 128 bits, top bit is supposed to stay zero
					app_cmd <= CMD_WRITE;
					app_wdf_data <= ddr3cmdout[127:0]; // 128bit value to write to memory from cache
					ddr3uistate <= DDR3WRITE_DONE;
				end
			end

			DDR3WRITE_DONE: begin
				if (app_rdy & app_en) begin
					app_en <= 0;
				end
			
				if (app_wdf_rdy & app_wdf_wren) begin
					app_wdf_wren <= 0;
				end
			
				if (~app_en & ~app_wdf_wren) begin
					ddr3uistate <= DDR3IDLE;
				end
			end

			DDR3READ: begin
				if (app_rdy) begin
					app_en <= 1;
					app_addr <= {1'b0, ddr3cmdout[152:128], 3'b000}; // Addresses are in multiples of 16 bits x8 == 128 bits, top bit is supposed to stay zero
					app_cmd <= CMD_READ;
					ddr3uistate <= DDR3READ_DONE;
				end
			end

			default /*DDR3READ_DONE*/: begin
				if (app_rdy & app_en) begin
					app_en <= 0;
				end

				if (app_rd_data_valid) begin
					// After this step, full 128bit value will be available on the
					// ddr3readre when read is asserted and ddr3readvalid is high
					ddr3readwe <= 1'b1;
					ddr3readin <= app_rd_data;
					ddr3uistate <= DDR3IDLE;
				end
			end

		endcase
	end
end

// Command input
wire ddr3cmdfull;
logic [153:0] ddr3cmdin; // cmd[153:153] qwordaddrs[152:128] din[127:0]
logic ddr3cmdwe = 1'b0;

// Data output
wire ddr3readvalid;
wire ddr3readempty;
logic ddr3readre = 1'b0;
wire [127:0] ddr3readout;

// Command fifo
ddr3cmdfifo DDR3Cmd(
	.full(ddr3cmdfull),
	.din(ddr3cmdin),
	.wr_en(ddr3cmdwe),
	.wr_clk(axi4if.ACLK),
	.empty(ddr3cmdempty),
	.dout(ddr3cmdout),
	.rd_en(ddr3cmdre),
	.valid(ddr3cmdvalid),
	.rd_clk(ui_clk),
	.rst(~axi4if.ARESETn),
	.wr_rst_busy(),
	.rd_rst_busy() );

// Read done queue
ddr3readdonequeue DDR3ReadDone(
	.full(ddr3readfull),
	.din(ddr3readin),
	.wr_en(ddr3readwe),
	.wr_clk(ui_clk),
	.empty(ddr3readempty),
	.dout(ddr3readout),
	.rd_en(ddr3readre),
	.valid(ddr3readvalid),
	.rd_clk(axi4if.ACLK),
	.rst(ui_clk_sync_rst),
	.wr_rst_busy(),
	.rd_rst_busy() );

// ----------------------------------------------------------------------------
// DDR3 frontend
// ----------------------------------------------------------------------------

logic [15:0] ptag;					// Previous cache tag (16 bits)
logic [15:0] ctag;					// Current cache tag (16 bits)
logic [8:0] cline;					// Current cache line 0..512 (there are 512 cache lines)
logic [2:0] coffset;				// Current word offset 0..7 (each cache line is 8xWORDs (256bits))
logic [31:0] cwidemask;				// Wide write mask
logic [31:0] wdata;					// Input data to write from bus side
logic loadindex;					// Cache load index (high/low 128 bits)

logic ddr3valid [0:511];			// Cache line valid bits
logic [255:0] ddr3cache [0:511];	// Cache lines x2
logic [15:0] ddr3tags [0:511];		// Cache line tags

initial begin
	integer i;
	// All pages are 'clean', all tags are invalid and cache is zeroed out by default
	for (int i=0; i<512; i=i+1) begin
		ddr3valid[i] = 1'b1;		// Cache lines are all valid by default
		ddr3tags[i]  = 16'hFFFF;	// All bits set for default tag
		ddr3cache[i] = 256'd0;		// Initially, cache line contains zero
	end
end

localparam DDR3AXI4IDLE				= 4'd0;
localparam DDR3AXI4WRITECHECK		= 4'd1;
localparam DDR3AXI4READCHECK		= 4'd2;
localparam DDR3AXI4WRITEDONE		= 4'd3;
localparam DDR3AXI4READDONE			= 4'd4;
localparam CACHEWRITEHI				= 4'd5;
localparam CACHEPOPULATELO			= 4'd6;
localparam CACHEPOPULATEHI			= 4'd7;
localparam CACHEPOPULATEWAIT		= 4'd8;
localparam CACHEPOPULATEFINALIZE	= 4'd9;

logic [3:0] ddr3axi4state = DDR3AXI4IDLE;
logic [3:0] returnstate = DDR3AXI4IDLE;

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

		ddr3cmdwe <= 1'b0;
		ddr3readre <= 1'b0;

		case (ddr3axi4state)
			DDR3AXI4IDLE: begin
				if (axi4if.AWVALID) begin
					coffset <= axi4if.AWADDR[4:2];					// Cache offset 0..7 (last 2 bits of memory address discarded, this is word offset into 256bits)
					cline <= {axi4if.AWADDR[12:5], 1'b0};			// Cache line 0..255 (last 4 bits of memory address discarded, this is a 256-bit aligned address) (sans ifetch since this is a write)
					ctag <= axi4if.AWADDR[28:13];					// Cache tag 00000..1FFFF
					ptag <= ddr3tags[{axi4if.AWADDR[12:5], 1'b0}];	// Previous cache tag (sans ifetch since this is a write)
					wdata <= axi4if.WDATA;							// Incoming data
					cwidemask <= {	{8{axi4if.WSTRB[3]}},
									{8{axi4if.WSTRB[2]}},
									{8{axi4if.WSTRB[1]}},
									{8{axi4if.WSTRB[0]}} };			// Build byte-wide mask for selective writes to cache

					axi4if.AWREADY <= 1'b0;
					ddr3axi4state <= DDR3AXI4WRITECHECK;
				end

				if (axi4if.ARVALID) begin
					coffset <= axi4if.ARADDR[4:2];						// Cache offset 0..3 (last 2 bits of memory address discarded, this is word offset into 128bits)
					cline <= {axi4if.ARADDR[12:5], ifetch};				// Cache line 0..255 (last 4 bits of memory address discarded, this is a 128-bit aligned address)
					ctag <= axi4if.ARADDR[28:13];						// Cache tag 00000..1FFFF
					ptag <= ddr3tags[{axi4if.ARADDR[12:5], ifetch}];	// Previous cache tag

					axi4if.RVALID <= 1'b0;
					axi4if.ARREADY <= 1'b0;
					ddr3axi4state <= DDR3AXI4READCHECK;
				end
			end

			DDR3AXI4WRITECHECK: begin
				if (ctag == ptag) begin // Cache hit
					if (axi4if.BREADY) begin
						case (coffset)
							3'b000: ddr3cache[cline][31:0]		<= ((~cwidemask)&ddr3cache[cline][31:0]) | (cwidemask&wdata);
							3'b001: ddr3cache[cline][63:32]		<= ((~cwidemask)&ddr3cache[cline][63:32]) | (cwidemask&wdata);
							3'b010: ddr3cache[cline][95:64]		<= ((~cwidemask)&ddr3cache[cline][95:64]) | (cwidemask&wdata);
							3'b011: ddr3cache[cline][127:96]	<= ((~cwidemask)&ddr3cache[cline][127:96]) | (cwidemask&wdata);
							3'b100: ddr3cache[cline][159:128]	<= ((~cwidemask)&ddr3cache[cline][159:128]) | (cwidemask&wdata);
							3'b101: ddr3cache[cline][191:160]	<= ((~cwidemask)&ddr3cache[cline][191:160]) | (cwidemask&wdata);
							3'b110: ddr3cache[cline][223:192]	<= ((~cwidemask)&ddr3cache[cline][223:192]) | (cwidemask&wdata);
							3'b111: ddr3cache[cline][255:224]	<= ((~cwidemask)&ddr3cache[cline][255:224]) | (cwidemask&wdata);
						endcase
						// Mark line invalid (needs writeback)
						ddr3valid[cline] <= 1'b0;
						// Done
						axi4if.BVALID <= 1'b1;
						axi4if.BRESP = 2'b00; // OKAY
						ddr3axi4state <= DDR3AXI4WRITEDONE;
					end else begin
						// Master not ready to accept response yet
						ddr3axi4state <= DDR3AXI4WRITECHECK;
					end
				end else begin // Cache miss
					returnstate <= DDR3AXI4WRITECHECK;
					if (~ddr3cmdfull) begin
						if (ddr3valid[cline]) begin
							ddr3cmdin <= { 1'b0, ctag, cline[8:1], 1'b0, 128'd0 };					// Request a read of new cache line contents
							ddr3cmdwe <= 1'b1;
							ddr3axi4state <= CACHEPOPULATEHI;
						end else begin
							ddr3cmdin <= { 1'b1, ptag, cline[8:1], 1'b0, ddr3cache[cline][127:0] };	// Request write contents of this cache line to memory
							ddr3valid[cline] <= 1'b1;												// Cache can now be assumed valid, go ahead and load new contents next
							ddr3cmdwe <= 1'b1;
							ddr3axi4state <= CACHEWRITEHI;
						end
					end else begin
						ddr3axi4state <= DDR3AXI4WRITECHECK;
					end
				end
			end

			DDR3AXI4READCHECK: begin
				if (ctag == ptag) begin // Cache hit
					if (axi4if.RREADY) begin
						case (coffset)
							3'b000: axi4if.RDATA <= ddr3cache[cline][31:0];
							3'b001: axi4if.RDATA <= ddr3cache[cline][63:32];
							3'b010: axi4if.RDATA <= ddr3cache[cline][95:64];
							3'b011: axi4if.RDATA <= ddr3cache[cline][127:96];
							3'b100: axi4if.RDATA <= ddr3cache[cline][159:128];
							3'b101: axi4if.RDATA <= ddr3cache[cline][191:160];
							3'b110: axi4if.RDATA <= ddr3cache[cline][223:192];
							3'b111: axi4if.RDATA <= ddr3cache[cline][255:224];
						endcase
						// Done
						axi4if.RVALID <= 1'b1;
						ddr3axi4state <= DDR3AXI4READDONE;
					end else begin
						// Master not ready to receive yet
						ddr3axi4state <= DDR3AXI4READCHECK;
					end
				end else begin // Cache miss
					returnstate <= DDR3AXI4READCHECK;
					if (~ddr3cmdfull) begin
						if (ddr3valid[cline]) begin
							ddr3cmdin <= { 1'b0, ctag, cline[8:1], 1'b0, 128'd0 };					// Request a read of new cache line contents
							ddr3cmdwe <= 1'b1;
							ddr3axi4state <= CACHEPOPULATEHI;
						end else begin
							ddr3cmdin <= { 1'b1, ptag, cline[8:1], 1'b0, ddr3cache[cline][127:0] };	// Request write contents of this cache line to memory
							ddr3valid[cline] <= 1'b1;												// Cache can now be assumed valid, go ahead and load new contents next
							ddr3cmdwe <= 1'b1;
							ddr3axi4state <= CACHEWRITEHI;
						end
					end else begin
						ddr3axi4state <= DDR3AXI4READCHECK;
					end
				end
			end
	
			DDR3AXI4WRITEDONE: begin
				axi4if.BVALID <= 1'b0;
				axi4if.AWREADY <= 1'b1;
				ddr3axi4state <= DDR3AXI4IDLE;
			end

			DDR3AXI4READDONE: begin
				axi4if.RVALID <= 1'b0;
				axi4if.ARREADY <= 1'b1;
				ddr3axi4state <= DDR3AXI4IDLE;
			end
			
			CACHEWRITEHI: begin
				if (~ddr3cmdfull) begin
					ddr3cmdin <= { 1'b1, ptag, cline[8:1], 1'b1, ddr3cache[cline][255:128]};
					ddr3cmdwe <= 1'b1;
					ddr3axi4state <= CACHEPOPULATELO;
				end else begin
					ddr3axi4state <= CACHEWRITEHI;
				end
			end

			CACHEPOPULATELO: begin
				if (~ddr3cmdfull) begin
					ddr3cmdin <= { 1'b0, ctag, cline[8:1], 1'b0, 128'd0 };		// Request a read of new cache line contents
					ddr3cmdwe <= 1'b1;
					ddr3axi4state <= CACHEPOPULATEHI;
				end else begin
					ddr3axi4state <= CACHEPOPULATELO;
				end
			end

			CACHEPOPULATEHI: begin
				if (~ddr3cmdfull) begin
					ddr3cmdin <= { 1'b0, ctag, cline[8:1], 1'b1, 128'd0 };		// Request a read of new cache line contents
					ddr3cmdwe <= 1'b1;
					loadindex <= 1'b0;
					ddr3axi4state <= CACHEPOPULATEWAIT;
				end else begin
					ddr3axi4state <= CACHEPOPULATEHI;
				end
			end

			CACHEPOPULATEWAIT: begin
				if (~ddr3readempty) begin										// We can now place a read request to fill the cache
					ddr3readre <= 1'b1;
					ddr3axi4state <= CACHEPOPULATEFINALIZE;
				end else begin
					ddr3axi4state <= CACHEPOPULATEWAIT;
				end
			end

			default /*CACHEPOPULATEFINALIZE*/: begin
				if (ddr3readvalid) begin
					case (loadindex)
						1'b0: begin
							ddr3cache[cline][127:0] <= ddr3readout;				// Replace low part of cache line
							loadindex <= 1'b1;
							// Read one more
							ddr3axi4state <= CACHEPOPULATEWAIT;
						end
						1'b1: begin
							ddr3cache[cline][255:128] <= ddr3readout;			// Replace high part of cache line
							ptag <= ctag;										// Set 'previous' tag so that we have a cache hits
							ddr3tags[cline] <= ctag;							// Update the tag for next time around
							ddr3axi4state <= returnstate;						// Try the last operation again (this time it'll result in a cache hit)
						end
					endcase
				end else begin
					ddr3axi4state <= CACHEPOPULATEFINALIZE;						// Still no response, wait a bit more
				end
			end
		endcase
	end
end

endmodule
