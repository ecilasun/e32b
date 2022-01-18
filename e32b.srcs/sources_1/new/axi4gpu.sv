`timescale 1ns / 1ps

module axi4gpu(
	axi4.slave axi4if,
	fpgadevicewires.default wires,
	fpgadeviceclocks.default clocks,
	gpudataoutput.default gpudata );

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

logic [31:0] writeaddress = 32'd0;
logic [7:0] din = 8'h00;
logic [3:0] we = 4'h0;
logic re = 1'b0;
wire [31:0] dout = 32'hffffffff;

always @(posedge axi4if.aclk) begin
	// write address
	case (waddrstate)
		2'b00: begin
			if (axi4if.awvalid) begin
				writeaddress <= axi4if.awaddr;
				axi4if.awready <= 1'b1;
				waddrstate <= 2'b01;
			end
		end
		default/*2'b01*/: begin
			axi4if.awready <= 1'b0;
			waddrstate <= 2'b00;
		end
	endcase
end

always @(posedge axi4if.aclk) begin
	// write data
	we <= 4'h0;
	case (writestate)
		2'b00: begin
			if (axi4if.wvalid /*& canactuallywrite*/) begin
				// latch the data and byte select
				din <= axi4if.wdata[7:0];
				we <= axi4if.wstrb;
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
		axi4if.arready <= 1'b0;
		axi4if.rvalid <= 1'b0;
		axi4if.rresp <= 2'b00;
	end else begin
		// read address
		re <= 1'b0;
		case (raddrstate)
			2'b00: begin
				if (axi4if.arvalid) begin
					axi4if.arready <= 1'b1;
					re <= 1'b1;
					raddrstate <= 2'b01;
				end
			end
			2'b01: begin
				axi4if.arready <= 1'b0;
				// master ready to accept
				if (axi4if.rready /*& dataactuallyread*/) begin
					axi4if.rdata <= dout;
					axi4if.rvalid <= 1'b1;
					//axi4if.rlast <= 1'b1; // last in burst
					raddrstate <= 2'b10; // delay one clock for master to pull down arvalid
				end
			end
			default/*2'b10*/: begin
				// at this point master should have responded properly with arvalid=0
				axi4if.rvalid <= 1'b0;
				//axi4if.rlast <= 1'b0;
				raddrstate <= 2'b00;
			end
		endcase
	end
end

endmodule
