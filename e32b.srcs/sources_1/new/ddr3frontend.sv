`timescale 1ns / 1ps

module ddr3frontend(
	axi4wide.master ddr3if,	// to memory
	axi4.slave axi4if,		// from bus
	input wire ifetch );

logic [15:0] ptag;				// previous cache tag (16 bits)
logic [15:0] ctag;				// current cache tag (16 bits)
logic [8:0] cline;				// current cache line 0..512 (there are 512 cache lines)
logic [2:0] coffset;			// current word offset 0..7 (each cache line is 8xwords (256bits))
logic [31:0] cwidemask;			// wide write mask
logic [31:0] wdata;				// input data to write from bus side
logic [3:0] burstindex = 4'b1;	// index of current burst

logic ddr3valid [0:511];			// cache line valid bits
logic [255:0] ddr3cache [0:511];	// cache lines x2
logic [15:0] ddr3tags [0:511];		// cache line tags

initial begin
	integer i;
	// all pages are 'clean', all tags are invalid and cache is zeroed out by default
	for (int i=0; i<512; i=i+1) begin
		ddr3valid[i] = 1'b1;		// cache lines are all valid by default
		ddr3tags[i]  = 16'hffff;	// all bits set for default tag
		ddr3cache[i] = 256'd0;		// initially, cache line contains zero
	end
end

typedef enum logic [2 : 0] {IDLE, WRITECHK, READCHK, RACCEPT, READ, WACCEPT, WRITE, WCOMPLETE} ddr3_state_type;
ddr3_state_type ddr3axi4state;
ddr3_state_type returnstate;

always @(posedge axi4if.aclk) begin
	if (~axi4if.aresetn) begin
		axi4if.awready <= 1'b1;
		axi4if.arready <= 1'b1;
		axi4if.rvalid <= 1'b0;
		axi4if.rresp <= 2'b00; // 00:ok(all ok) 01:exaccessok(exclusive access ok) 10:slaveerr(r/w or wait error) 11:decodererr(address error)
		axi4if.wready <= 1'b0;
		axi4if.bresp <= 2'b00; // 00:ok(all ok) 01:exaccessok(exclusive access ok) 10:slaveerr(r/w or wait error) 11:decodererr(address error)
		axi4if.bvalid <= 1'b0;
	end else begin
	
		// todo: when an fence.i is detected, the next memory operation has to invalidate all i$ tags so that i$ may reload the whole cache.
		// otherwise this will cause issues when d$ writes to memory but i$ doesn't know the memory contents have been changed, may therefore
		// fail to load program instructions from memory after a new executable has been loaded.

		case (ddr3axi4state)

			IDLE: begin
				axi4if.rvalid <= 1'b0;
				axi4if.arready <= 1'b1;

				axi4if.bvalid <= 1'b0;
				axi4if.awready <= 1'b1;

				// no simultaneous read/writes supported yet
				if (axi4if.awvalid) begin
					coffset <= axi4if.awaddr[4:2];					// cache offset 0..7 (last 2 bits of memory address discarded, this is word offset into 256bits)
					cline <= {axi4if.awaddr[12:5], 1'b0};			// cache line 0..255 (last 4 bits of memory address discarded, this is a 256-bit aligned address) (sans ifetch since this is a write)
					ctag <= axi4if.awaddr[28:13];					// cache tag 00000..1ffff
					ptag <= ddr3tags[{axi4if.awaddr[12:5], 1'b0}];	// previous cache tag (sans ifetch since this is a write)
					wdata <= axi4if.wdata;							// incoming data
					cwidemask <= {	{8{axi4if.wstrb[3]}},
									{8{axi4if.wstrb[2]}},
									{8{axi4if.wstrb[1]}},
									{8{axi4if.wstrb[0]}} };			// build byte-wide mask for selective writes to cache

					axi4if.awready <= 1'b0;
					ddr3axi4state <= WRITECHK;
				end else if (axi4if.arvalid) begin
					coffset <= axi4if.araddr[4:2];						// cache offset 0..3 (last 2 bits of memory address discarded, this is word offset into 128bits)
					cline <= {axi4if.araddr[12:5], ifetch};				// cache line 0..255 (last 4 bits of memory address discarded, this is a 128-bit aligned address)
					ctag <= axi4if.araddr[28:13];						// cache tag 00000..1ffff
					ptag <= ddr3tags[{axi4if.araddr[12:5], ifetch}];	// previous cache tag

					axi4if.rvalid <= 1'b0;
					axi4if.arready <= 1'b0;
					ddr3axi4state <= READCHK;
				end
			end

			WRITECHK: begin
				if (ctag == ptag) begin // cache hit
					if (axi4if.bready) begin
						case (coffset)
							3'b000:  ddr3cache[cline] <= {ddr3cache[cline][255:32 ], ((~cwidemask)&ddr3cache[cline][31:0]   ) | (cwidemask&wdata)                         };
							3'b001:  ddr3cache[cline] <= {ddr3cache[cline][255:64 ], ((~cwidemask)&ddr3cache[cline][63:32]  ) | (cwidemask&wdata), ddr3cache[cline][31:0] };
							3'b010:  ddr3cache[cline] <= {ddr3cache[cline][255:96 ], ((~cwidemask)&ddr3cache[cline][95:64]  ) | (cwidemask&wdata), ddr3cache[cline][63:0] };
							3'b011:  ddr3cache[cline] <= {ddr3cache[cline][255:128], ((~cwidemask)&ddr3cache[cline][127:96] ) | (cwidemask&wdata), ddr3cache[cline][95:0] };
							3'b100:  ddr3cache[cline] <= {ddr3cache[cline][255:160], ((~cwidemask)&ddr3cache[cline][159:128]) | (cwidemask&wdata), ddr3cache[cline][127:0]};
							3'b101:  ddr3cache[cline] <= {ddr3cache[cline][255:192], ((~cwidemask)&ddr3cache[cline][191:160]) | (cwidemask&wdata), ddr3cache[cline][159:0]};
							3'b110:  ddr3cache[cline] <= {ddr3cache[cline][255:224], ((~cwidemask)&ddr3cache[cline][223:192]) | (cwidemask&wdata), ddr3cache[cline][191:0]};
							default: ddr3cache[cline] <= {                           ((~cwidemask)&ddr3cache[cline][255:224]) | (cwidemask&wdata), ddr3cache[cline][223:0]}; //3'b111
						endcase
						// mark line invalid (needs writeback)
						ddr3valid[cline] <= 1'b0;
						// done
						axi4if.bvalid <= 1'b1;
						axi4if.bresp = 2'b00; // okay
						ddr3axi4state <= IDLE;
					end else begin
						// master not ready to accept response yet
						ddr3axi4state <= WRITECHK;
					end
				end else begin // cache miss
					returnstate <= WRITECHK;
					burstindex <= 4'd1;
					if (ddr3valid[cline]) begin
						ddr3if.araddr <= {3'd0, ctag, cline[8:1], 5'd0}; // 32 byte aligned
						ddr3if.arvalid <= 1'b1;
						ddr3if.rready <= 1'b1;
						ddr3axi4state <= RACCEPT;
					end else begin
						ddr3if.awaddr <= {3'd0, ptag, cline[8:1], 5'd0}; // 32 byte aligned
						ddr3if.awvalid <= 1'b1;
						ddr3if.bready <= 1'b1;
						ddr3if.wlast <= 1'b0;
						ddr3axi4state <= WACCEPT;
					end
				end
			end

			READCHK: begin
				if (ctag == ptag) begin // cache hit
					if (axi4if.rready) begin
						case (coffset)
							3'b000:  axi4if.rdata <= ddr3cache[cline][31:0];
							3'b001:  axi4if.rdata <= ddr3cache[cline][63:32];
							3'b010:  axi4if.rdata <= ddr3cache[cline][95:64];
							3'b011:  axi4if.rdata <= ddr3cache[cline][127:96];
							3'b100:  axi4if.rdata <= ddr3cache[cline][159:128];
							3'b101:  axi4if.rdata <= ddr3cache[cline][191:160];
							3'b110:  axi4if.rdata <= ddr3cache[cline][223:192];
							default: axi4if.rdata <= ddr3cache[cline][255:224]; // 3'b111
						endcase
						// done
						axi4if.rvalid <= 1'b1;
						ddr3axi4state <= IDLE;
					end else begin
						// master not ready to receive yet
						ddr3axi4state <= READCHK;
					end
				end else begin // cache miss
					returnstate <= READCHK;
					burstindex <= 4'd1;
					if (ddr3valid[cline]) begin
						ddr3if.araddr <= {3'd0, ctag, cline[8:1], 5'd0}; // 32 byte aligned
						ddr3if.arvalid <= 1'b1;
						ddr3if.rready <= 1'b1;
						ddr3axi4state <= RACCEPT;
					end else begin
						ddr3if.awaddr <= {3'd0, ptag, cline[8:1], 5'd0}; // 32 byte aligned
						ddr3if.awvalid <= 1'b1;
						ddr3if.bready <= 1'b1;
						ddr3if.wlast <= 1'b0;
						ddr3axi4state <= WACCEPT;
					end
				end
			end

			WACCEPT: begin
				if (ddr3if.awready) begin
					ddr3if.awvalid <= 1'b0;
					ddr3axi4state <= WRITE;
				end
			end

			WRITE: begin
				ddr3if.wstrb <= 8'hff;
				ddr3if.wvalid <= 1'b1;
				case (1'b1)
					burstindex[0]: ddr3if.wdata <= ddr3cache[cline][63:0];
					burstindex[1]: ddr3if.wdata <= ddr3cache[cline][127:64];
					burstindex[2]: ddr3if.wdata <= ddr3cache[cline][191:128];
					burstindex[3]: ddr3if.wdata <= ddr3cache[cline][255:192];
				endcase

				// next entry
				if (ddr3if.wready) begin
					burstindex <= {burstindex[2:0], burstindex[3]}; // shift left
					if (burstindex[3]) begin
						ddr3if.wlast <= 1'b1;
						ddr3axi4state <= WCOMPLETE;
					end
				end
			end

			WCOMPLETE: begin
				ddr3if.wstrb <= 8'h00;
				ddr3if.wvalid <= 1'b0;

				if (ddr3if.bvalid) begin
					burstindex <= 4'd1;
					ddr3if.araddr <= {3'd0, ctag, cline[8:1], 5'd0}; // 32 byte aligned
					ddr3if.arvalid <= 1'b1;
					ddr3if.rready <= 1'b1;
					ddr3axi4state <= RACCEPT;
				end
			end

			RACCEPT: begin
				if (ddr3if.arready) begin
					// handshake done, burst data incoming...
					ddr3if.arvalid <= 1'b0;
					ddr3axi4state <= READ;
				end
			end

			default: begin // READ
				if (ddr3if.rvalid) begin
					burstindex <= {burstindex[2:0], burstindex[3]}; // shift left
					case (1'b1)
						burstindex[0]: ddr3cache[cline][63:0] <= ddr3if.rdata;
						burstindex[1]: ddr3cache[cline][127:64] <= ddr3if.rdata;
						burstindex[2]: ddr3cache[cline][191:128] <= ddr3if.rdata;
						burstindex[3]: ddr3cache[cline][255:192] <= ddr3if.rdata;
					endcase
					if (ddr3if.rlast) begin
						ptag <= ctag;
						ddr3valid[cline] <= 1'b1;
						ddr3tags[cline] <= ctag;
						ddr3if.rready <= 1'b0;
						ddr3axi4state <= returnstate;
					end
				end
			end
		endcase
	end
end

endmodule
