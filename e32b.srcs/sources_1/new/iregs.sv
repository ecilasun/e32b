`timescale 1ns / 1ps

module registerfile(
	input wire clock,			// writes are clocked, reads are not
	input wire [4:0] rs1,		// source register 1
	input wire [4:0] rs2,		// source register 2
	input wire [4:0] rd,		// destination register
	input wire wren,			// write enable bit for writing to register rd 
	input wire [31:0] din,		// data to write to register rd
	output wire [31:0] rval1,	// register values for rs1 and rs2
	output wire [31:0] rval2 );

logic [31:0] registers[0:31];

// the whole register file is zero at boot
initial begin
	int ri;
	for (ri=0;ri<32;ri=ri+1) begin
		registers[ri]  = 32'h00000000;
	end
end

always @(posedge clock) begin
	if (wren && rd != 5'd0) // rd != 5'd0 check is integer regsiter file specific (to avoid writes to zero register)
		registers[rd] <= din;
end

assign rval1 = registers[rs1];
assign rval2 = registers[rs2];

endmodule
