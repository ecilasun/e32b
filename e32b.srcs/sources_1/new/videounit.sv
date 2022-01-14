`timescale 1ns / 1ps

module videounit(
		input wire gpuclock,
		input wire pixelclock,
		input wire [11:0] video_x,
		input wire [11:0] video_y,
		// For direct writes from GPU
		input wire [14:0] waddr,
		input wire [3:0] we,
		input wire [31:0] din,
		// Output to scanout hardware
		output wire [7:0] paletteindexout );

wire [14:0] saddr = video_y[8:1]*80 + video_x[11:3]; // x/8 for word address, y/2 for double-height scanline offset, times 320 stride in memory
wire [1:0] videobyteselect = video_x[2:1];

logic [7:0] videooutbyte;
assign paletteindexout = videooutbyte;

wire [31:0] scanout;
VRAM VideoMemory(
	// Port A: CPU read/write (routed through GPU)
	.addra(waddr),		// Address converted from stride512 to stride320
	.clka(gpuclock),
	.dina(din),
	.douta(),			// TBD
	.ena((|we)),		// include | re later when CPU can read back data
	.wea(we),
	// Port B: scanout read / unused GPU writes (for now)
	.addrb(saddr),
	.clkb(pixelclock),
	.dinb(32'd0),
	.doutb(scanout),
	.enb(video_x[2:0]==3'b000),
	.web(4'h0)
);

always @(posedge pixelclock) begin
	case (videobyteselect)
		2'b00: begin
			videooutbyte <= scanout[7:0];
		end
		2'b01: begin
			videooutbyte <= scanout[15:8];
		end
		2'b10: begin
			videooutbyte <= scanout[23:16];
		end
		default/*2'b11*/: begin
			videooutbyte <= scanout[31:24];
		end
	endcase
end

endmodule