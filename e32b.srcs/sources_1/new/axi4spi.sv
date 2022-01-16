`timescale 1ns / 1ps

module axi4spi(
	axi4.SLAVE axi4if,
	FPGADeviceWires.DEFAULT wires,
	FPGADeviceClocks.DEFAULT clocks );

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

logic [7:0] writedata = 7'd0;
wire [7:0] readdata;
logic we = 1'b0;

// ----------------------------------------------------------------------------
// SPI Master Device
// ----------------------------------------------------------------------------

wire cansend;

wire hasvaliddata;
wire [7:0] spiincomingdata;

// Base clock is @100MHz, therefore we're running at 25MHz (2->2x2 due to 'half'->100/4==25)
SPI_Master #(.SPI_MODE(0), .CLKS_PER_HALF_BIT(2)) SPI(
   // Control/Data Signals,
   .i_Rst_L(axi4if.ARESETn),
   .i_Clk(clocks.spibaseclock),

   // TX (MOSI) Signals
   .i_TX_Byte(writedata),
   .i_TX_DV(we),
   .o_TX_Ready(cansend),

   // RX (MISO) Signals
   .o_RX_DV(hasvaliddata),
   .o_RX_Byte(spiincomingdata),

   // SPI Interface
   .o_SPI_Clk(wires.spi_sck),
   .i_SPI_MISO(wires.spi_miso),
   .o_SPI_MOSI(wires.spi_mosi) );

assign wires.spi_cs_n = 1'b0; // Keep attached SPI device selected/powered on

wire infifofull, infifoempty, infifovalid;
logic infifowe = 1'b0, infifore = 1'b0;
logic [7:0] infifodin = 8'h00;
wire [7:0] infifodout;

spimasterinfifo SPIInputFIFO(
	.wr_clk(clocks.spibaseclock),
	.full(infifofull),
	.din(infifodin),
	.wr_en(infifowe),

	.rd_clk(axi4if.ACLK),
	.empty(infifoempty),
	.dout(infifodout),
	.rd_en(infifore),
	.valid(infifovalid),

	.rst(~axi4if.ARESETn),
	.wr_rst_busy(),
	.rd_rst_busy() );

always @(posedge clocks.spibaseclock) begin
	infifowe <= 1'b0;

	if (hasvaliddata & (~infifofull)) begin // Make sure to drain the fifo!
		// Stash incoming byte in FIFO
		infifowe <= 1'b1;
		infifodin <= spiincomingdata;
	end
end

wire outfifofull, outfifoempty, outfifovalid;
logic outfifowe = 1'b0, outfifore = 1'b0;
logic [7:0] outfifodin = 8'h00;
wire [7:0] outfifodout;

spimasterinfifo SPIOutputFIFO(
	.wr_clk(axi4if.ACLK),
	.full(outfifofull),
	.din(outfifodin),
	.wr_en(outfifowe),

	.rd_clk(clocks.spibaseclock),
	.empty(outfifoempty),
	.dout(outfifodout),
	.rd_en(outfifore),
	.valid(outfifovalid),

	.rst(~axi4if.ARESETn),
	.wr_rst_busy(),
	.rd_rst_busy() );

always @(posedge clocks.spibaseclock) begin
	outfifore <= 1'b0;
	we <= 1'b0;

	if ((~outfifoempty) & cansend) begin
		outfifore <= 1'b1;
	end

	if (outfifovalid) begin
		writedata <= outfifodout;
		we <= 1'b1;
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
				if (axi4if.AWVALID & (~outfifofull)) begin
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
	outfifowe <= 1'b0;
	case (writestate)
		2'b00: begin
			if (axi4if.WVALID & (~outfifofull)) begin
				outfifodin <= axi4if.WDATA[7:0];
				outfifowe <= 1'b1; // (|axi4if.WSTRB)
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

		infifore <= 1'b0;

		// Read address
		case (raddrstate)
			2'b00: begin
				if (axi4if.ARVALID) begin
					axi4if.ARREADY <= 1'b0;
					// axi4if.ARADDR; unused, device has single mapped address
					raddrstate <= 2'b01;
				end
			end
			2'b01: begin
				// Master ready to accept and fifo has incoming data
				if (axi4if.RREADY & (~infifoempty)) begin
					infifore <= 1'b1;
					raddrstate <= 2'b10;
				end
			end
			2'b10: begin
				if (infifovalid) begin
					axi4if.RDATA <= {infifodout, infifodout, infifodout, infifodout};
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
