`timescale 1ns / 1ps

module axi4spi(
	axi4.slave axi4if,
	fpgadevicewires.def wires,
	fpgadeviceclocks.def clocks );

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

logic [7:0] writedata = 7'd0;
wire [7:0] readdata;
logic we = 1'b0;

// ----------------------------------------------------------------------------
// spi master device
// ----------------------------------------------------------------------------

wire cansend;

wire hasvaliddata;
wire [7:0] spiincomingdata;

// base clock is @100mhz, therefore we're running at 25mhz (2->2x2 due to 'half'->100/4==25)
spi_master #(.spi_mode(0), .clks_per_half_bit(2)) spi(
   // control/data signals,
   .i_rst_l(axi4if.aresetn),
   .i_clk(clocks.spibaseclock),

   // tx (mosi) signals
   .i_tx_byte(writedata),
   .i_tx_dv(we),
   .o_tx_ready(cansend),

   // rx (miso) signals
   .o_rx_dv(hasvaliddata),
   .o_rx_byte(spiincomingdata),

   // spi interface
   .o_spi_clk(wires.spi_sck),
   .i_spi_miso(wires.spi_miso),
   .o_spi_mosi(wires.spi_mosi) );

assign wires.spi_cs_n = 1'b0; // keep attached spi device selected/powered on

wire infifofull, infifoempty, infifovalid;
logic infifowe = 1'b0, infifore = 1'b0;
logic [7:0] infifodin = 8'h00;
wire [7:0] infifodout;

spimasterinfifo spiinputfifo(
	.wr_clk(clocks.spibaseclock),
	.full(infifofull),
	.din(infifodin),
	.wr_en(infifowe),

	.rd_clk(axi4if.aclk),
	.empty(infifoempty),
	.dout(infifodout),
	.rd_en(infifore),
	.valid(infifovalid),

	.rst(~axi4if.aresetn),
	.wr_rst_busy(),
	.rd_rst_busy() );

always @(posedge clocks.spibaseclock) begin
	infifowe <= 1'b0;

	if (hasvaliddata & (~infifofull)) begin // make sure to drain the fifo!
		// stash incoming byte in fifo
		infifowe <= 1'b1;
		infifodin <= spiincomingdata;
	end
end

wire outfifofull, outfifoempty, outfifovalid;
logic outfifowe = 1'b0, outfifore = 1'b0;
logic [7:0] outfifodin = 8'h00;
wire [7:0] outfifodout;

spimasterinfifo spioutputfifo(
	.wr_clk(axi4if.aclk),
	.full(outfifofull),
	.din(outfifodin),
	.wr_en(outfifowe),

	.rd_clk(clocks.spibaseclock),
	.empty(outfifoempty),
	.dout(outfifodout),
	.rd_en(outfifore),
	.valid(outfifovalid),

	.rst(~axi4if.aresetn),
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
// main state machine
// ----------------------------------------------------------------------------

always @(posedge axi4if.aclk) begin
	if (~axi4if.aresetn) begin
		axi4if.awready <= 1'b1;
	end else begin
		// write address
		case (waddrstate)
			2'b00: begin
				if (axi4if.awvalid & (~outfifofull)) begin
					//writeaddress <= axi4if.awaddr;
					axi4if.awready <= 1'b0;
					waddrstate <= 2'b01;
				end
			end
			default/*2'b01*/: begin
				axi4if.awready <= 1'b1;
				waddrstate <= 2'b00;
			end
		endcase
	end
end

always @(posedge axi4if.aclk) begin
	// write data
	outfifowe <= 1'b0;
	case (writestate)
		2'b00: begin
			if (axi4if.wvalid & (~outfifofull)) begin
				outfifodin <= axi4if.wdata[7:0];
				outfifowe <= 1'b1; // (|axi4if.wstrb)
				axi4if.wready <= 1'b1;
				writestate <= 2'b01;
			end
		end
		2'b01: begin
			axi4if.wready <= 1'b0;
			if(axi4if.bready) begin
				axi4if.bvalid <= 1'b1;
				axi4if.bresp = 2'b00; // okay
				writestate <= 2'b10;
			end
		end
		default/*2'b10*/: begin
			axi4if.bvalid <= 1'b0;
			writestate <= 2'b00;
		end
	endcase
end

always @(posedge axi4if.aclk) begin
	if (~axi4if.aresetn) begin
		axi4if.arready <= 1'b1;
		axi4if.rvalid <= 1'b0;
		axi4if.rresp <= 2'b00;
		axi4if.rdata <= 32'd0;
	end else begin

		infifore <= 1'b0;

		// read address
		case (raddrstate)
			2'b00: begin
				if (axi4if.arvalid) begin
					axi4if.arready <= 1'b0;
					// axi4if.araddr; unused, device has single mapped address
					raddrstate <= 2'b01;
				end
			end
			2'b01: begin
				// master ready to accept and fifo has incoming data
				if (axi4if.rready & (~infifoempty)) begin
					infifore <= 1'b1;
					raddrstate <= 2'b10;
				end
			end
			2'b10: begin
				if (infifovalid) begin
					axi4if.rdata <= {infifodout, infifodout, infifodout, infifodout};
					axi4if.rvalid <= 1'b1;
					raddrstate <= 2'b11; // delay one clock for master to pull down arvalid
				end
			end
			default/*2'b11*/: begin
				axi4if.rvalid <= 1'b0;
				axi4if.arready <= 1'b1;
				raddrstate <= 2'b00;
			end
		endcase
	end
end

endmodule
