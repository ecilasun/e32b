`timescale 1ns / 1ps

module axi4uart(
	axi4.slave axi4if,
	fpgadevicewires.def wires,
	fpgadeviceclocks.def clocks,
	output wire uartrcvempty );

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

//logic [31:0] writeaddress = 32'd0;
logic [7:0] din = 8'h00;
logic [3:0] we = 4'h0;

// ----------------------------------------------------------------------------
// uart transmitter
// ----------------------------------------------------------------------------

bit transmitbyte = 1'b0;
bit [7:0] datatotransmit = 8'h00;
wire uarttxbusy;

async_transmitter uart_transmit(
	.clk(clocks.uartbaseclock),
	.txd_start(transmitbyte),
	.txd_data(datatotransmit),
	.txd(wires.uart_rxd_out),
	.txd_busy(uarttxbusy) );

wire [7:0] uartsenddout;
bit uartsendre = 1'b0;
wire uartsendfull, uartsendempty, uartsendvalid;

uartout uartdataoutfifo(
	.full(uartsendfull),
	.din(din),
	.wr_en( (|we) ),
	.wr_clk(axi4if.aclk),
	.empty(uartsendempty),
	.valid(uartsendvalid),
	.dout(uartsenddout),
	.rd_en(uartsendre),
	.rd_clk(clocks.uartbaseclock),
	.rst(~axi4if.aresetn) );

bit [1:0] uartwritemode = 2'b00;

always @(posedge clocks.uartbaseclock) begin
	uartsendre <= 1'b0;
	transmitbyte <= 1'b0;
	unique case(uartwritemode)
		2'b00: begin // idle
			if (~uartsendempty & (~uarttxbusy)) begin
				uartsendre <= 1'b1;
				uartwritemode <= 2'b01; // write
			end
		end
		2'b01: begin // write
			if (uartsendvalid) begin
				transmitbyte <= 1'b1;
				datatotransmit <= uartsenddout;
				uartwritemode <= 2'b10; // finalize
			end
		end
		default/*2'b10*/: begin // finalize
			// need to give uarttx one clock to
			// kick 'busy' for any adjacent
			// requests which didn't set busy yet
			uartwritemode <= 2'b00; // idle
		end
	endcase
end

// ----------------------------------------------------------------------------
// uart receiver
// ----------------------------------------------------------------------------

wire uartbyteavailable;
wire [7:0] uartbytein;

async_receiver uart_receive(
	.clk(clocks.uartbaseclock),
	.rxd(wires.uart_txd_in),
	.rxd_data_ready(uartbyteavailable),
	.rxd_data(uartbytein),
	.rxd_idle(),
	.rxd_endofpacket() );

wire uartrcvfull, uartrcvvalid;
bit [7:0] uartrcvdin = 8'h00;
wire [7:0] uartrcvdout;
bit uartrcvre = 1'b0, uartrcvwe = 1'b0;

uartin uartdatainfifo(
	.full(uartrcvfull),
	.din(uartrcvdin),
	.wr_en(uartrcvwe),
	.wr_clk(clocks.uartbaseclock),
	.empty(uartrcvempty),
	.dout(uartrcvdout),
	.rd_en(uartrcvre),
	.valid(uartrcvvalid),
	.rd_clk(axi4if.aclk),
	.rst(~axi4if.aresetn) );

always @(posedge clocks.uartbaseclock) begin
	uartrcvwe <= 1'b0;
	// note: any byte that won't fit into the fifo will be dropped
	// make sure to consume them quickly on arrival!
	if (uartbyteavailable & (~uartrcvfull)) begin
		uartrcvwe <= 1'b1;
		uartrcvdin <= uartbytein;
	end
end

// main state machine
always @(posedge axi4if.aclk) begin
	if (~axi4if.aresetn) begin
		axi4if.awready <= 1'b1;
	end else begin
		// write address
		case (waddrstate)
			2'b00: begin
				if (axi4if.awvalid & (~uartsendfull)) begin
					axi4if.awready <= 1'b0;
					//writeaddress <= axi4if.awaddr; // todo: select subdevice using some bits of address
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
	we <= 4'h0;
	case (writestate)
		2'b00: begin
			if (axi4if.wvalid & (~uartsendfull)) begin
				// latch the data and byte select
				din <= axi4if.wdata[7:0];
				we <= axi4if.wstrb;
				axi4if.wready <= 1'b1;
				writestate <= 2'b01;
			end
		end
		2'b01: begin
			axi4if.wready <= 1'b0;
			if (axi4if.bready) begin
				axi4if.bvalid <= 1'b1;
				axi4if.bresp <= 2'b00; // okay
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
	end else begin
		// read address
		uartrcvre <= 1'b0;
		case (raddrstate)
			2'b00: begin
				if (axi4if.arvalid) begin
					axi4if.arready <= 1'b0;
					if (axi4if.araddr[3:0] == 4'h8) begin // data i/o port
						uartrcvre <= 1'b1;
						raddrstate <= 2'b01;
					end else begin
						raddrstate <= 2'b10;
					end
				end
			end
			2'b01: begin
				// master ready to accept
				if (axi4if.rready & uartrcvvalid) begin
					axi4if.rdata <= {uartrcvdout, uartrcvdout, uartrcvdout, uartrcvdout};
					axi4if.rvalid <= 1'b1;
					//axi4if.rlast <= 1'b1; // last in burst
					raddrstate <= 2'b11; // delay one clock for master to pull down arvalid
				end
			end
			2'b10: begin
				// master ready to accept
				if (axi4if.rready) begin
					if (axi4if.araddr[3:0] == 4'h4) // byteavailable port
						axi4if.rdata <= {31'd0, ~uartrcvempty};
					else /*if (axi4if.araddr[3:0] == 4'h0)*/ // sendfifofull port
						axi4if.rdata <= {31'd0, uartsendfull};
					axi4if.rvalid <= 1'b1;
					//axi4if.rlast <= 1'b1; // last in burst
					raddrstate <= 2'b11; // delay one clock for master to pull down arvalid
				end
			end
			default/*2'b11*/: begin
				// at this point master should have responded properly with arvalid=0
				axi4if.rvalid <= 1'b0;
				axi4if.arready <= 1'b1;
				//axi4if.rlast <= 1'b0;
				raddrstate <= 2'b00;
			end
		endcase
	end
end

endmodule
