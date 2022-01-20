`timescale 1ns / 1ps

module axi4buttons(
	axi4.slave axi4if,
	fpgadevicewires.def wires,
	fpgadeviceclocks.def clocks,
	output wire buttonfifoempty );

wire fifofull, fifovalid;
logic fifowe = 1'b0, fifore = 1'b0;
logic [4:0] fifodin = 5'd0;
wire [4:0] fifodout;

buttonfifo buttoninputfifo(
	.wr_clk(clocks.wallclock),
	.full(fifofull),
	.din(fifodin),
	.wr_en(fifowe),

	.rd_clk(axi4if.aclk),
	.empty(buttonfifoempty),
	.dout(fifodout),
	.rd_en(fifore),
	.valid(fifovalid),

	.rst(~axi4if.aresetn),
	
	.wr_rst_busy(),
	.rd_rst_busy() );

// State tracking in wall clock domain
logic [4:0] oldbuttons = 5'd0;

// Approximate clock shift to axi4 domain
logic [4:0] buttonsimmed0;
logic [4:0] buttonsimmed1;
logic [4:0] buttonsimmed2;

always @(posedge clocks.wallclock) begin
	fifowe <= 1'b0;

	if ((|(oldbuttons ^ buttonsimmed2)) & (~fifofull)) begin
		fifowe <= 1'b1;
		fifodin <= buttonsimmed2;
		oldbuttons <= buttonsimmed2;
	end
	
	buttonsimmed0 <= wires.buttons;
	buttonsimmed1 <= buttonsimmed0;
	buttonsimmed2 <= buttonsimmed1;
end

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

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
				if (axi4if.awvalid /*& cansend*/) begin
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
	//we <= 4'h0;
	case (writestate)
		2'b00: begin
			if (axi4if.wvalid /*& cansend*/) begin
				// Buttons are read-only
				//writedata <= axi4if.wdata;
				//we <= axi4if.wstrb;
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

		fifore <= 1'b0;

		// read address
		case (raddrstate)
			2'b00: begin
				if (axi4if.arvalid) begin
					axi4if.arready <= 1'b0;
					raddrstate <= 2'b01;
				end
			end
			2'b01: begin
				// master ready to accept and fifo has incoming data
				if (axi4if.rready) begin
					if (axi4if.araddr[3:0] == 4'h8) begin // Current immediate state read without fifo, with clock shift to this domain
						axi4if.rdata <= {27'd0, buttonsimmed2};
						axi4if.rvalid <= 1'b1;
						raddrstate <= 2'b11;
					end if (axi4if.araddr[3:0] == 4'h4) begin // Button state change available?
						axi4if.rdata <= {31'd0, ~buttonfifoempty};
						axi4if.rvalid <= 1'b1;
						raddrstate <= 2'b11; // delay one clock for master to pull down arvalid
					end else if (~buttonfifoempty) begin // Data from FIFO on state change
						fifore <= 1'b1;
						raddrstate <= 2'b10;
					end
				end
			end
			2'b10: begin
				if (fifovalid) begin
					axi4if.rdata <= {27'd0, fifodout}; // New button state
					axi4if.rvalid <= 1'b1;
					raddrstate <= 2'b11;
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
