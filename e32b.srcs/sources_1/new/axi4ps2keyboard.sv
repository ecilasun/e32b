`timescale 1ns / 1ps

module axi4ps2keyboard(
	axi4.SLAVE axi4if,
	FPGADeviceWires.DEFAULT wires,
	FPGADeviceClocks.DEFAULT clocks );

wire flag;
wire [15:0] keycode;
PS2Receiver uut (
	.clk(clocks.clk50mhz),
	.kclk(wires.ps2_clk),
	.kdata(wires.ps2_data),
	.keycode(keycode),
	.oflag(flag) );

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

wire fifofull, fifoempty, fifovalid;
logic fifowe = 1'b0, fifore = 1'b0;
logic [15:0] fifodin = 16'd0;
wire [15:0] fifodout;

ps2infifo PS2InputFIFO(
	.wr_clk(clocks.clk50mhz),
	.full(fifofull),
	.din(fifodin),
	.wr_en(fifowe),

	.rd_clk(axi4if.ACLK),
	.empty(fifoempty),
	.dout(fifodout),
	.rd_en(fifore),
	.valid(fifovalid),

	.rst(~axi4if.ARESETn),
	.wr_rst_busy(),
	.rd_rst_busy() );

always @(posedge clocks.clk50mhz) begin
	fifowe <= 1'b0;

	if (flag & (~fifofull)) begin // Make sure to drain the fifo!
		// Stash incoming byte in FIFO
		fifowe <= 1'b1;
		fifodin <= keycode;
	end
end

// ----------------------------------------------------------------------------
// Main state machine
// ----------------------------------------------------------------------------

always @(posedge axi4if.ACLK) begin
	if (~axi4if.ARESETn) begin
		axi4if.AWREADY <= 1'b1;
	end else begin
		// Write address
		case (waddrstate)
			2'b00: begin
				if (axi4if.AWVALID /*& cansend*/) begin
					//writeaddress <= axi4if.AWADDR;
					axi4if.AWREADY <= 1'b0;
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
	// Write data
	//we <= 4'h0;
	case (writestate)
		2'b00: begin
			if (axi4if.WVALID /*& cansend*/) begin
				// Latch the data and byte select
				//writedata <= axi4if.WDATA[15:0]; // Keyboard control etc? Unused for now.
				//we <= axi4if.WSTRB;
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
		axi4if.ARREADY <= 1'b1;
		axi4if.RVALID <= 1'b0;
		axi4if.RRESP <= 2'b00;
		axi4if.RDATA <= 32'd0;
	end else begin

		fifore <= 1'b0;

		// Read address
		case (raddrstate)
			2'b00: begin
				if (axi4if.ARVALID) begin
					axi4if.ARREADY <= 1'b0;
					if (axi4if.ARADDR[3:0] == 4'h8) begin // Incoming data available?
						axi4if.RDATA <= {31'd0, ~fifoempty};
						axi4if.RVALID <= 1'b1;
						raddrstate <= 2'b11; // Delay one clock for master to pull down ARVALID
					end else begin
						raddrstate <= 2'b01;
					end
				end
			end
			2'b01: begin
				// Master ready to accept and fifo has incoming data
				if (axi4if.RREADY & (~fifoempty)) begin
					fifore <= 1'b1;
					raddrstate <= 2'b10;
				end
			end
			2'b10: begin
				if (fifovalid) begin
					axi4if.RDATA <= {16'd0, fifodout}; // Key scan code
					axi4if.RVALID <= 1'b1;
					raddrstate <= 2'b11; // Delay one clock for master to pull down ARVALID
				end
			end
			default/*2'b11*/: begin
				axi4if.RVALID <= 1'b0;
				axi4if.ARREADY <= 1'b1;
				raddrstate <= 2'b00;
			end
		endcase
	end
end

endmodule
