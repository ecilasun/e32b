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

// Tile arrangement (10x8)
//            <-10 tiles wide->
//         0                                   9
//   ^   0[  ][  ][  ][  ][  ][  ][  ][  ][  ][  ]
//   |    [  ][  ][  ][  ][  ][  ][  ][  ][  ][  ]
//   8    [  ][  ][  ][  ][  ][  ][  ][  ][  ][  ]
// tiles  [  ][  ][  ][  ][  ][  ][  ][  ][  ][  ]
// high   [  ][  ][  ][  ][  ][  ][  ][  ][  ][  ]
//   |    [  ][  ][  ][  ][  ][  ][  ][  ][  ][  ]
//   v   7[  ][  ][  ][  ][  ][  ][  ][  ][  ][  ]
// Each tile is 32x32 pixels, or 8x32 words in length,
// with the first address of each tile at upper left hand corner,
// scanning right then down:
// 00: 00 00 00 00 00 00 00 00
// 01: 00 00 00 00 00 00 00 00
// ...
// 1E: 00 00 00 00 00 00 00 00
// 1F: 00 00 00 00 00 00 00 00

// Scan-out tile id
wire [3:0] stx = video_x[9:6]; // (vx%1024)/64 -> pixels are x2 wide
wire [2:0] sty = video_y[8:6]; // (vy%1024)/64 -> pixels are x2 high
wire [6:0] scantileid = stx + sty*10; // id -> 0..79

// Scan-out tile local address
wire [2:0] slx = video_x[5:3]; // (vx%64)/8
wire [4:0] sly = video_y[5:1]; // (vy%64)
wire [7:0] sladdress = {sly, slx};

// Byte select within the scanout word
wire [1:0] videobyteselect = video_x[2:1];

wire [31:0] vram_data[0:79]; // One read slot per tile
logic [7:0] videooutbyte;

assign paletteindexout = videooutbyte;

// Generate 10*8 tiles of 32*32 pixels each for an image of 320*256, out of which we scan out a 320x240 window
genvar tilegen;
generate for (tilegen = 0; tilegen < 80; tilegen = tilegen + 1) begin : video_tiles
	//videowaddr <= {tileid, laddress};
	graphicstile32x32 vtile_inst(
		// Write to the matching tile
		.addra(waddr[7:0]), // Per-tile address (0..255)
		.clka(gpuclock),
		.dina(din),
		.ena(1'b1),
		.wea(waddr[14:8]==tilegen[6:0] ? we : 4'b0000), // Select tile to write to
		// Read out to respective vram_data elements for each tile
		.addrb(sladdress),
		.enb(scantileid==tilegen[6:0] ? 1'b1 : 1'b0), // Every tile always reads into their respective outputs
		.clkb(pixelclock),
		.doutb(vram_data[tilegen]) );
end endgenerate

always @(posedge pixelclock) begin
	case (videobyteselect)
		2'b00: begin
			videooutbyte <= vram_data[scantileid][7:0];
		end
		2'b01: begin
			videooutbyte <= vram_data[scantileid][15:8];
		end
		2'b10: begin
			videooutbyte <= vram_data[scantileid][23:16];
		end
		2'b11: begin
			videooutbyte <= vram_data[scantileid][31:24];
		end
	endcase
end

endmodule