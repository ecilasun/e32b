`timescale 1ns / 1ps

module axi4ps2keyboard(
	axi4.slave axi4if,
	fpgadevicewires.def wires,
	fpgadeviceclocks.def clocks );

wire flag;
wire [15:0] keycode;
ps2receiver uut (
	.clk(clocks.clk50mhz),
	.ps2_clk(wires.ps2_clk),
	.ps2_data(wires.ps2_data),
	.keycode(keycode),
	.oflag(flag) );

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

wire fifofull, fifoempty, fifovalid;
logic fifowe = 1'b0, fifore = 1'b0;
logic [15:0] fifodin = 16'd0;
wire [15:0] fifodout;

ps2infifo ps2inputfifo(
	.wr_clk(clocks.clk50mhz),
	.full(fifofull),
	.din(fifodin),
	.wr_en(fifowe),

	.rd_clk(axi4if.aclk),
	.empty(fifoempty),
	.dout(fifodout),
	.rd_en(fifore),
	.valid(fifovalid),

	.rst(~axi4if.aresetn),
	.wr_rst_busy(),
	.rd_rst_busy() );

always @(posedge clocks.clk50mhz) begin
	fifowe <= 1'b0;

	if (flag & (~fifofull)) begin // make sure to drain the fifo!
		// stash incoming byte in fifo
		fifowe <= 1'b1;
		fifodin <= keycode;
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
				// latch the data and byte select
				//writedata <= axi4if.wdata[15:0]; // keyboard control etc? unused for now.
				//we <= axi4if.wstrb;
				//wires.ps2_clk <= 1'b0; // hold low for send?
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
					if (axi4if.araddr[3:0] == 4'h8) begin // incoming data available?
						axi4if.rdata <= {31'd0, ~fifoempty};
						axi4if.rvalid <= 1'b1;
						raddrstate <= 2'b11; // delay one clock for master to pull down arvalid
					end else if (~fifoempty) begin
						fifore <= 1'b1;
						raddrstate <= 2'b10;
					end
				end
			end
			2'b10: begin
				if (fifovalid) begin
					axi4if.rdata <= {16'd0, fifodout}; // key scan code
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
