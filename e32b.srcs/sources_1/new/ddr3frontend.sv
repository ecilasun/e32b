`timescale 1ns / 1ps

module ddr3frontend(
	axi4wide.MASTER ddr3if,	// To memory
	axi4.SLAVE axi4if,		// From bus
	input wire ifetch );

logic [15:0] ptag;					// Previous cache tag (16 bits)
logic [15:0] ctag;					// Current cache tag (16 bits)
logic [8:0] cline;					// Current cache line 0..512 (there are 512 cache lines)
logic [2:0] coffset;				// Current word offset 0..7 (each cache line is 8xWORDs (256bits))
logic [31:0] cwidemask;				// Wide write mask
logic [31:0] wdata;					// Input data to write from bus side
//logic loadindex = 1'b0;				// Cache load index (high/low 128 bits)
logic [3:0] burstindex = 4'b0001;	// Index of current burst

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
localparam DDR3AXI4READACCEPT		= 4'd3;
localparam DDR3AXI4READ				= 4'd4;
localparam DDR3AXI4WRITEACCEPT		= 4'd5;
localparam DDR3AXI4WRITE			= 4'd6;
localparam DDR3AXI4WRITECOMPLETE	= 4'd7;

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

		case (ddr3axi4state)

			DDR3AXI4IDLE: begin
				axi4if.RVALID <= 1'b0;
				axi4if.ARREADY <= 1'b1;

				axi4if.BVALID <= 1'b0;
				axi4if.AWREADY <= 1'b1;

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
						ddr3axi4state <= DDR3AXI4IDLE;
					end else begin
						// Master not ready to accept response yet
						ddr3axi4state <= DDR3AXI4WRITECHECK;
					end
				end else begin // Cache miss
					returnstate <= DDR3AXI4WRITECHECK;
					burstindex <= 4'b0001;
					if (ddr3valid[cline]) begin
						ddr3if.ARADDR <= {3'd0, ctag, cline[8:1], 5'd0}; // 32 byte aligned
						ddr3if.ARVALID <= 1'b1;
						ddr3if.RREADY <= 1'b1;
						ddr3axi4state <= DDR3AXI4READACCEPT;
					end else begin
						ddr3if.AWADDR <= {3'd0, ptag, cline[8:1], 5'd0}; // 32 byte aligned
						ddr3if.AWVALID <= 1'b1;
						ddr3if.BREADY <= 1'b1;
						ddr3if.WLAST <= 1'b0;
						ddr3axi4state <= DDR3AXI4WRITEACCEPT;
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
						ddr3axi4state <= DDR3AXI4IDLE;
					end else begin
						// Master not ready to receive yet
						ddr3axi4state <= DDR3AXI4READCHECK;
					end
				end else begin // Cache miss
					returnstate <= DDR3AXI4READCHECK;
					burstindex <= 4'b0001;
					if (ddr3valid[cline]) begin
						ddr3if.ARADDR <= {3'd0, ctag, cline[8:1], 5'd0}; // 32 byte aligned
						ddr3if.ARVALID <= 1'b1;
						ddr3if.RREADY <= 1'b1;
						ddr3axi4state <= DDR3AXI4READACCEPT;
					end else begin
						ddr3if.AWADDR <= {3'd0, ptag, cline[8:1], 5'd0}; // 32 byte aligned
						ddr3if.AWVALID <= 1'b1;
						ddr3if.BREADY <= 1'b1;
						ddr3if.WLAST <= 1'b0;
						ddr3axi4state <= DDR3AXI4WRITEACCEPT;
					end
				end
			end

			DDR3AXI4WRITEACCEPT: begin
				if (ddr3if.AWREADY) begin
					ddr3if.AWVALID <= 1'b0;
					ddr3axi4state <= DDR3AXI4WRITE;
				end
			end

			DDR3AXI4WRITE: begin
				ddr3if.WSTRB <= 8'hFF;
				ddr3if.WVALID <= 1'b1;
				case (1'b1)
					burstindex[0]: ddr3if.WDATA <= ddr3cache[cline][63:0];
					burstindex[1]: ddr3if.WDATA <= ddr3cache[cline][127:64];
					burstindex[2]: ddr3if.WDATA <= ddr3cache[cline][191:128];
					burstindex[3]: ddr3if.WDATA <= ddr3cache[cline][255:192];
				endcase

				// Next entry
				if (ddr3if.WREADY) begin
					burstindex <= {burstindex[2:0], burstindex[3]}; // Shift left
					if (burstindex[3]) begin
						ddr3if.WLAST <= 1'b1;
						ddr3axi4state <= DDR3AXI4WRITECOMPLETE;
					end
				end
			end

			DDR3AXI4WRITECOMPLETE: begin
				ddr3if.WSTRB <= 8'h00;
				ddr3if.WVALID <= 1'b0;

				if (ddr3if.BVALID) begin
					burstindex <= 4'b0001;
					ddr3if.ARADDR <= {3'd0, ctag, cline[8:1], 5'd0};
					ddr3if.ARVALID <= 1'b1;
					ddr3if.RREADY <= 1'b1;
					ddr3axi4state <= DDR3AXI4READACCEPT;
				end
			end

			DDR3AXI4READACCEPT: begin
				if (ddr3if.ARREADY) begin
					// Handshake done, burst data incoming...
					ddr3if.ARVALID <= 1'b0;
					ddr3axi4state <= DDR3AXI4READ;
				end
			end

			DDR3AXI4READ: begin
				if (ddr3if.RVALID) begin
					burstindex <= {burstindex[2:0], burstindex[3]}; // Shift left
					case (1'b1)
						burstindex[0]: ddr3cache[cline][63:0] <= ddr3if.RDATA;
						burstindex[1]: ddr3cache[cline][127:64] <= ddr3if.RDATA;
						burstindex[2]: ddr3cache[cline][191:128] <= ddr3if.RDATA;
						burstindex[3]: ddr3cache[cline][255:192] <= ddr3if.RDATA;
					endcase
					if (ddr3if.RLAST) begin
						ptag <= ctag;
						ddr3valid[cline] <= 1'b1;
						ddr3tags[cline] <= ctag;
						ddr3if.RREADY <= 1'b0;
						ddr3axi4state <= returnstate;
					end
				end
			end
		endcase
	end
end

endmodule
