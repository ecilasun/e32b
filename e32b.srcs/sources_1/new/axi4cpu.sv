`timescale 1ns / 1ps

`include "shared.vh"

module axi4cpu #(
	parameter resetvector=32'h00000000 ) (
	axi4.master axi4if,
	fpgadeviceclocks.def clocks,
	fpgadevicewires.def wires,
	output logic ifetch = 1'b0,
	input wire [3:0] irq,
	input wire calib_done );

// cpu states
localparam cpuinit = 1;
localparam cpuretire = 2;
localparam cpufetch = 4;
localparam cpudecode = 8;
localparam cpuexecute = 16;
localparam cpuloadwait = 32;
localparam cpustorewait = 64;
localparam cpuimathwait = 128;
localparam cpufpuop = 256;
localparam cpuwback = 512;
localparam cpuwfi = 1024;
localparam cpufpuwritewait = 2048;
localparam cpufpuread = 4096;
localparam cpufpureadwait = 8192;

logic [13:0] cpustate = cpuinit;
logic [31:0] pc = resetvector;
logic [31:0] adjacentpc = resetvector + 32'd4;
logic [31:0] csrval = 32'd0;

logic hwinterrupt = 1'b0;
logic illegalinstruction = 1'b0;
logic timerinterrupt = 1'b0;
logic miena = 1'b0;
logic msena = 1'b0;
logic mtena = 1'b0;
logic ecall = 1'b0;
logic ebreak = 1'b0;
logic wfi = 1'b0;
logic mret = 1'b0;
logic trq = 1'b0;
logic [2:0] mip = 3'b000;
logic [31:0] mtvec = 32'd0;

// ------------------------------------------------------------------------------------
// timer unit
// ------------------------------------------------------------------------------------

logic [3:0] shortcnt = 4'h0;
logic [63:0] cpusidetrigger = 64'hffffffffffffffff;
logic [63:0] clockcounter = 64'd0;

// count in cpu clock domain
// the ratio of wall clock to cpu clock is 1/10
// so we can increment this every 10th clock
always @(posedge axi4if.aclk) begin
	shortcnt <= shortcnt + 1;
	if (shortcnt == 9) begin
		shortcnt <= 0;
		clockcounter <= clockcounter + 64'd1;
	end
	trq <= (clockcounter >= cpusidetrigger) ? 1'b1 : 1'b0;
end

// ------------------------------------------------------------------------------------
// csr
// ------------------------------------------------------------------------------------

logic [31:0] csrreg [0:`csr_register_count-1];
wire [4:0] csrindex;
bit csrwe = 1'b0;
bit [31:0] csrin = 32'd0;
bit [4:0] csrindex_l;

// see https://cv32e40p.readthedocs.io/en/latest/control_status_registers/#cs-registers for defaults
initial begin
	csrreg[`csr_unused]		= 32'd0;
	csrreg[`csr_mstatus]	= 32'h00001800; // mpp (machine previous priviledge mode 12:11) hardwired to 2'b11 on startup
	csrreg[`csr_mie]		= 32'd0;
	csrreg[`csr_mtvec]		= 32'd0;
	csrreg[`csr_mepc]		= 32'd0;
	csrreg[`csr_mcause]		= 32'd0;
	csrreg[`csr_mtval]		= 32'd0;
	csrreg[`csr_mip]		= 32'd0;
	csrreg[`csr_timecmplo]	= 32'hffffffff; // timecmp = 0xffffffffffffffff
	csrreg[`csr_timecmphi]	= 32'hffffffff;
	csrreg[`csr_cyclelo]	= 32'd0;
	csrreg[`csr_cyclehi]	= 32'd0;
	csrreg[`csr_timelo]		= 32'd0;
	csrreg[`csr_retilo]		= 32'd0;
	csrreg[`csr_timehi]		= 32'd0;
	csrreg[`csr_retihi]		= 32'd0;
end

// ------------------------------------------------------------------------------------
// decoder unit
// ------------------------------------------------------------------------------------

bit [31:0] instruction = {25'd0,`opcode_op_imm,2'b11}; // noop (addi x0,x0,0)
bit decen = 1'b0;

wire isrecordingform;
wire [17:0] instronehot;
wire selectimmedasrval2;
wire [31:0] immed;
wire [4:0] rs1, rs2, rs3, rd;
wire [2:0] func3;
wire [6:0] func7;
wire [11:0] func12;
wire [3:0] aluop;
wire [2:0] bluop;

decoder instructiondecoder(
	.enable(decen),								// hold high for one clock when din is valid to decode
	.instruction(instruction),					// incoming instruction to decode
	.instronehotout(instronehot),				// one-hot form of decoded instruction
	.isrecordingform(isrecordingform),			// high if instruction result should be saved to a register
	.aluop(aluop),								// arithmetic unit op
	.bluop(bluop),								// branch unit op
	.func3(func3),								// sub-function
	.func7(func7),								// sub-function
	.func12(func12),							// sub-function
	.rs1(rs1),									// source register 1
	.rs2(rs2),									// source register 2
	.rs3(rs3),									// source register 3 (used for fused operations)
	.rd(rd),									// destination register
	.csrindex(csrindex),						// csr register index
	.immed(immed),								// immediate, converted to 32 bits
	.selectimmedasrval2(selectimmedasrval2) );	// route to use either immed or value of source register 2 

// ------------------------------------------------------------------------------------
// register files
// ------------------------------------------------------------------------------------

logic rwren = 1'b0;
logic frwe = 1'b0;
logic [31:0] rdin = 32'd0;
logic [31:0] frdin = 32'd0;
wire [31:0] rval1, rval2;
wire [31:0] frval1, frval2, frval3;
logic [15:0] fpustrobe; // Floating point unit command strobe
logic [3:0] fpuwritecount = 4'd0;

registerfile integerregisters(
	.clock(axi4if.aclk),
	.rs1(rs1),		// source register read address
	.rs2(rs2),		// source register read address
	.rd(rd),		// destination register write address
	.wren(rwren),	// write enable for destination register
	.din(rdin),		// data to write to destination register (written at end of this clock)
	.rval1(rval1),	// values output from source registers (available on same clock)
	.rval2(rval2) );

// floating point register file
floatregisterfile floatregisters(
	.clock(axi4if.aclk),
	.rs1(rs1),
	.rs2(rs2),
	.rs3(rs3),
	.rd(rd),
	.wren(frwe),
	.datain(frdin),
	.rval1(frval1),
	.rval2(frval2),
	.rval3(frval3) );

// ------------------------------------------------------------------------------------
// alu / blu
// ------------------------------------------------------------------------------------

bit aluen = 1'b0;
wire reqalu = instronehot[`o_h_auipc] | instronehot[`o_h_jal] | instronehot[`o_h_branch]; // these instructions require the first operand to be pc and second one to be the immediate

wire [31:0] aluout;

arithmeticlogicunit alu(
	.enable(aluen),											// hold high to get a result on next clock
	.aluout(aluout),										// result of calculation
	.func3(func3),											// alu sub-operation code
	.val1(reqalu ? pc : rval1),								// input value 1
	.val2((selectimmedasrval2 | reqalu) ? immed : rval2),	// input value 2
	.aluop(reqalu ? `alu_add : aluop) );					// alu operation code (also add for jalr for rval1+immed)

wire branchout;
bit branchr = 1'b0;

branchlogicunit blu(
	.branchout(branchout),	// high when branch should be taken based on op
	.val1(rval1),			// input value 1
	.val2(rval2),			// input value 2
	.bluop(bluop) );		// comparison operation code

// -----------------------------------------------------------------------
// integer math (mul/div)
// -----------------------------------------------------------------------

logic [31:0] mout = 32'd0;
logic mwrite = 1'b0;

wire mulbusy, divbusy, divbusyu;
wire [31:0] product;
wire [31:0] quotient;
wire [31:0] quotientu;
wire [31:0] remainder;
wire [31:0] remainderu;

wire isexecuting = (cpustate==cpuexecute);
wire isexecutingimath = isexecuting & instronehot[`o_h_op];
//wire isexecutingfloatop = isexecuting & instronehot[`o_h_float_op];

// pulses to kick math operations
wire mulstart = isexecutingimath & (aluop==`alu_mul);
multiplier themul(
    .clk(axi4if.aclk),
    .reset(~axi4if.aresetn),
    .start(mulstart),
    .busy(mulbusy),           // calculation in progress
    .func3(func3),
    .multiplicand(rval1),
    .multiplier(rval2),
    .product(product) );

wire divstart = isexecutingimath & (aluop==`alu_div | aluop==`alu_rem);
divu unsigneddivider (
	.clk(axi4if.aclk),
	.reset(~axi4if.aresetn),
	.start(divstart),		// start signal
	.busy(divbusyu),		// calculation in progress
	.dividend(rval1),		// dividend
	.divisor(rval2),		// divisor
	.quotient(quotientu),	// result: quotient
	.remainder(remainderu)	// result: remainer
);

div signeddivider (
	.clk(axi4if.aclk),
	.reset(~axi4if.aresetn),
	.start(divstart),		// start signal
	.busy(divbusy),			// calculation in progress
	.dividend(rval1),		// dividend
	.divisor(rval2),		// divisor
	.quotient(quotient),	// result: quotient
	.remainder(remainder)	// result: remainder
);

// stall status
wire imathstart = divstart | mulstart;
wire imathbusy = divbusy | divbusyu | mulbusy;

// ------------------------------------------------------------------------------------
// cpu
// ------------------------------------------------------------------------------------

bit [31:0] loadstoreaddress = 32'd0;

always @(posedge axi4if.aclk) begin
	decen <= 1'b0;
	aluen <= 1'b0;
	rwren <= 1'b0;
	csrwe <= 1'b0;
	mwrite <= 1'd0;
	frwe <= 1'b0;

	case (cpustate)
		cpuinit: begin
			pc <= resetvector;
			if (~axi4if.aresetn)
				cpustate <= cpuinit;
			else begin
				if (calib_done)
					cpustate <= cpuretire;
				else
					cpustate <= cpuinit;
			end
		end

		cpuwfi: begin
			hwinterrupt <= (|irq) & miena & (~(|mip));
			timerinterrupt <= trq & mtena & (~(|mip));

			if (hwinterrupt | timerinterrupt) begin
				cpustate <= cpuretire;
			end else begin
				cpustate <= cpuwfi;
			end
		end

		cpuretire: begin
			// write back to csr register file
			if (csrwe)
				csrreg[csrindex_l] <= csrin;

			// ordering according to privileged isa is: mei/msi/mti/sei/ssi/sti
			if (hwinterrupt) begin // mei, external hardware interrupt
				// using non-vectored interrupt handlers (last 2 bits are 2'b00)
				csrreg[`csr_mip][11] <= 1'b1;
				csrreg[`csr_mepc] <= adjacentpc;
				csrreg[`csr_mtval] <= {28'd0, irq}; // interrupting hardware selector
				csrreg[`csr_mcause] <= 32'h8000000b; // [31]=1'b1(interrupt), 11->h/w
			end else if (illegalinstruction | ecall) begin // msi, exception
				// using non-vectored interrupt handlers (last 2 bits are 2'b00)
				csrreg[`csr_mip][3] <= 1'b1;
				csrreg[`csr_mepc] <= adjacentpc;
				csrreg[`csr_mtval] <= instruction;
				csrreg[`csr_mcause] <= ecall ? 32'h0000000b : 32'h00000002; // [31]=1'b0(exception), 0xb->ecall, 0x2->illegal instruction
			end else if (timerinterrupt) begin // mti, timer interrupt
				csrreg[`csr_mip][7] <= 1'b1;
				csrreg[`csr_mepc] <= adjacentpc;
				csrreg[`csr_mtval] <= 32'd0;
				csrreg[`csr_mcause] <= 32'h80000007; // [31]=1'b1(interrupt), 7->timer
			end

			// point at the current instruction address based on irq status
			if (hwinterrupt | illegalinstruction | timerinterrupt | ecall) begin
				pc <= mtvec;
				axi4if.araddr <= mtvec;
			end else begin
				axi4if.araddr <= pc;
			end

			axi4if.arvalid <= 1'b1;
			axi4if.rready <= 1'b1;	// ready to accept
			ifetch <= 1'b1;			// this is an instruction fetch

			cpustate <= cpufetch;
		end

		cpufetch: begin
			if (axi4if.arready) begin
				axi4if.arvalid <= 1'b0; // address handshake complete
			end

			if (axi4if.rvalid) begin
				axi4if.rready <= 1'b0; // data read complete

				// latch instruction and enable decoder
				instruction <= axi4if.rdata;
				decen <= 1'b1;
				// this is to be used at later stages
				adjacentpc <= pc + 32'd4;

				// pre-read some registers to check during this instruction
				// todo: only need to update these when they're changed, move to a separate stage post-csr-write
				{miena, msena, mtena} <= {csrreg[`csr_mie][11], csrreg[`csr_mie][3], csrreg[`csr_mie][7]}; // interrupt enable state
				mtvec <= {csrreg[`csr_mtvec][31:2], 2'b00};
				mip <= {csrreg[`csr_mip][11], csrreg[`csr_mip][3], csrreg[`csr_mip][7]}; // high if interrupt pending
				cpusidetrigger <= {csrreg[`csr_timecmphi], csrreg[`csr_timecmplo]}; // latch the timecmp value

				ifetch <= 1'b0; // instruction fetch done

				cpustate <= cpudecode;
			end else begin
				// no data yet
				cpustate <= cpufetch;
			end
		end

		cpudecode: begin
			aluen <= 1'b1;

			// calculate base address for possible load and store instructions
			loadstoreaddress <= rval1 + immed;

			// latch branch decision
			branchr <= branchout;

			// update clock
			csrreg[`csr_timehi] <= clockcounter[63:32];
			csrreg[`csr_timelo] <= clockcounter[31:0];

			// set traps only if respective trap bit is set and we're not already handling a trap
			// this prevents re-entrancy in trap handlers.
			hwinterrupt <= (|irq) & miena & (~(|mip));
			illegalinstruction <= (~(|instronehot)) & msena & (~(|mip));
			timerinterrupt <= trq & mtena & (~(|mip));

			cpustate <= cpuexecute;
		end

		cpuexecute: begin
			// system operations
			ecall <= 1'b0;
			ebreak <= 1'b0;
			wfi <= 1'b0;
			mret <= 1'b0;

			// load
			if (instronehot[`o_h_float_madd] || instronehot[`o_h_float_msub] || instronehot[`o_h_float_nmsub] || instronehot[`o_h_float_nmadd] || instronehot[`o_h_float_op]) begin
				// TODO: After setting up the command strobe here,
				// write these values to successive 4 byte aligned FPU addresses:
				// frval1, frval2, frval3, rval1, strobe
				// Once strobe is written, result can be read back from any 4 byte aligned FPU mapped address.
				fpustrobe <= {
					instronehot[`o_h_float_madd],
					instronehot[`o_h_float_msub],
					instronehot[`o_h_float_nmsub],
					instronehot[`o_h_float_nmadd],
					(func7 == `f7_fadd),
					(func7 == `f7_fsub),
					(func7 == `f7_fmul),
					(func7 == `f7_fdiv),
					(func7 == `f7_fcvtsw) && (rs2==5'b00000) ? 1'b1:1'b0,			// signed
					(func7 == `f7_fcvtsw) && (rs2==5'b00001) ? 1'b1:1'b0,			// unsigned
					(func7 == `f7_fcvtws) && (rs2==5'b00000) ? 1'b1:1'b0,			// signed
					(func7 == `f7_fcvtws) && (rs2==5'b00001) ? 1'b1:1'b0,			// unsigned
					(func7 == `f7_fsqrt),
					(func7 == `f7_feq) && (func3==3'b010),							// eq
					(func7 == `f7_flt) && (func3==3'b001) || (func7 == `f7_fmax),	// lt
					(func7 == `f7_fle) && (func3==3'b000) };						// le
				fpuwritecount <= 5;
				cpustate <= cpufpuop;
			end else if (instronehot[`o_h_load] | instronehot[`o_h_float_ldw]) begin
				// set up address for load
				axi4if.araddr <= loadstoreaddress;
				axi4if.arvalid <= 1'b1;
				axi4if.rready <= 1'b1; // ready to accept
				cpustate <= cpuloadwait;
			end else if (instronehot[`o_h_store] | instronehot[`o_h_float_stw]) begin // store
				// byte selection/replication based on target address
				case (func3)
					3'b000: begin // 8 bit
						axi4if.wdata <= {rval2[7:0], rval2[7:0], rval2[7:0], rval2[7:0]};
						case (loadstoreaddress[1:0])
							2'b11: axi4if.wstrb <= 4'h8;
							2'b10: axi4if.wstrb <= 4'h4;
							2'b01: axi4if.wstrb <= 4'h2;
							2'b00: axi4if.wstrb <= 4'h1;
						endcase
					end
					3'b001: begin // 16 bit
						axi4if.wdata <= {rval2[15:0], rval2[15:0]};
						case (loadstoreaddress[1])
							1'b1: axi4if.wstrb <= 4'hc;
							1'b0: axi4if.wstrb <= 4'h3;
						endcase
					end
					3'b010: begin // 32 bit
						axi4if.wdata <= (instronehot[`o_h_float_stw]) ? frval2 : rval2;
						axi4if.wstrb <= 4'hf;
					end
					default: begin
						axi4if.wdata <= 32'd0;
						axi4if.wstrb <= 4'h0;
					end
				endcase

				// set up address for store...
				axi4if.awaddr <= loadstoreaddress;
				axi4if.awvalid <= 1'b1;
				// ...while also driving the data output and also assert ready
				axi4if.wvalid <= 1'b1;
				// ready for a response
				axi4if.bready <= 1'b1;
				cpustate <= cpustorewait;
			end else if (imathstart) begin
				// interger math operation pending
				cpustate <= cpuimathwait;
			end else begin
				case ({instronehot[`o_h_system], func3})
					4'b1_000: begin // sys
						case (func12)
							12'b0000000_00000: begin	// sys call
								ecall <= msena;
							end
							12'b0000000_00001: begin	// software breakpoint
								ebreak <= msena;
							end
							12'b0001000_00101: begin	// wait for interrupt
								wfi <= miena | msena | mtena;	// use individual interrupt enable bits, ignore global interrupt enable
							end
							12'b0011000_00010: begin	// return from interrupt
								mret <= 1'b1;
							end
							default: begin
								//
							end
						endcase
					end
					4'b1_010, // csrrs
					4'b1_110, // csrrsi
					4'b1_011, // cssrrc
					4'b1_111: begin // csrrci
						csrval <= csrreg[csrindex];
					end
					default: begin
						csrval <= 32'd0;
					end
				endcase
				cpustate <= cpuwback;
			end
		end

		cpuloadwait: begin
			if (axi4if.arready) begin
				axi4if.arvalid <= 1'b0; // address handshake complete
			end

			if (axi4if.rvalid) begin
				axi4if.rready <= 1'b0; // data read complete

				case (func3)
					3'b000: begin // byte with sign extension
						case (loadstoreaddress[1:0])
							2'b11: begin rdin <= {{24{axi4if.rdata[31]}}, axi4if.rdata[31:24]}; end
							2'b10: begin rdin <= {{24{axi4if.rdata[23]}}, axi4if.rdata[23:16]}; end
							2'b01: begin rdin <= {{24{axi4if.rdata[15]}}, axi4if.rdata[15:8]}; end
							2'b00: begin rdin <= {{24{axi4if.rdata[7]}},  axi4if.rdata[7:0]}; end
						endcase
					end
					3'b001: begin // word with sign extension
						case (loadstoreaddress[1])
							1'b1: begin rdin <= {{16{axi4if.rdata[31]}}, axi4if.rdata[31:16]}; end
							1'b0: begin rdin <= {{16{axi4if.rdata[15]}}, axi4if.rdata[15:0]}; end
						endcase
					end
					3'b010: begin // dword
						if (instronehot[`o_h_float_ldw]) begin
							frwe <= 1'b1;
							frdin <= axi4if.rdata[31:0];
						end else begin
							rdin <= axi4if.rdata[31:0];
						end
					end
					3'b100: begin // byte with zero extension
						case (loadstoreaddress[1:0])
							2'b11: begin rdin <= {24'd0, axi4if.rdata[31:24]}; end
							2'b10: begin rdin <= {24'd0, axi4if.rdata[23:16]}; end
							2'b01: begin rdin <= {24'd0, axi4if.rdata[15:8]}; end
							2'b00: begin rdin <= {24'd0, axi4if.rdata[7:0]}; end
						endcase
					end
					/*3'b101*/ default: begin // word with zero extension
						case (loadstoreaddress[1])
							1'b1: begin rdin <= {16'd0, axi4if.rdata[31:16]}; end
							1'b0: begin rdin <= {16'd0, axi4if.rdata[15:0]}; end
						endcase
					end
				endcase

				cpustate <= cpuwback;
			end else begin
				// no data yet
				cpustate <= cpuloadwait;
			end
		end

		cpustorewait: begin // might be able to get rid of this stage as we don't really need to wait until we have to read
			if (axi4if.awready) begin
				axi4if.awvalid <= 1'b0; // address handshake complete
			end

			if (axi4if.wready) begin
				axi4if.wvalid <= 1'b0;
				axi4if.wstrb <= 4'h0;
			end

			if (axi4if.bvalid) begin
				axi4if.bready <= 1'b0; // data write complete
				cpustate <= cpuwback;
			end else begin
				// didn't store yet
				cpustate <= cpustorewait;
			end
		end
		
		cpuimathwait: begin
			if (imathbusy) begin
				cpustate <= cpuimathwait;
			end else begin
				case (aluop)
					`alu_mul: begin
						mout <= product;
					end
					`alu_div: begin
						mout <= func3==`f3_div ? quotient : quotientu;
					end
					`alu_rem: begin
						mout <= func3==`f3_rem ? remainder : remainderu;
					end
					default: begin
						mout <= 32'd0;
					end
				endcase
				mwrite <= 1'b1;
				cpustate <= cpuwback;
			end
		end

		cpufpuop: begin
			// Some operations do not require the FPU
			cpustate <= cpuwback;
			case (func7)
				`f7_fsgnj: begin
					frwe <= 1'b1;
					case(func3)
						3'b000: begin // fsgnj
							frdin <= {frval2[31], frval1[30:0]}; 
						end
						3'b001: begin  // fsgnjn
							frdin <= {~frval2[31], frval1[30:0]};
						end
						3'b010: begin  // fsgnjx
							frdin <= {frval1[31]^frval2[31], frval1[30:0]};
						end
					endcase
				end
				`f7_fmvxw: begin
					rwren <= 1'b1;
					if (func3 == 3'b000) // fmvxw
						rdin <= frval1;
					else // fclass
						rdin <= 32'd0; // todo: classify the float
				end
				`f7_fmvwx: begin
					frwe <= 1'b1;
					frdin <= rval1;
				end
				default: begin
					if (fpuwritecount == 0) begin
						// Done, go to read result
						cpustate <= cpufpuread;
					end else begin
						// Not done yet, set up write request for next word
						axi4if.wstrb <= 4'hf;
						axi4if.awvalid <= 1'b1;
						axi4if.wvalid <= 1'b1;
						axi4if.bready <= 1'b1;
						cpustate <= cpufpuwritewait;
					end

					// Inputs for the FPU
					case (fpuwritecount)
						5: begin
							axi4if.awaddr <= 32'h20003000;
							axi4if.wdata <= frval1;
						end
						4: begin
							axi4if.awaddr <= 32'h20003004;
							axi4if.wdata <= frval2;
						end
						3: begin
							axi4if.awaddr <= 32'h20003008;
							axi4if.wdata <= frval3;
						end
						2: begin
							axi4if.awaddr <= 32'h2000300C;
							axi4if.wdata <= rval1;
						end
						1: begin
							axi4if.awaddr <= 32'h20003010;
							axi4if.wdata <= {16'd0, fpustrobe};
						end
						0: begin
							// done, we're going to read state now
						end
					endcase
					
					fpuwritecount <= fpuwritecount - 1;
				end
			endcase
		end
		
		cpufpuwritewait: begin
			if (axi4if.awready) begin
				axi4if.awvalid <= 1'b0;
			end
			if (axi4if.wready) begin
				axi4if.wvalid <= 1'b0;
				axi4if.wstrb <= 4'h0;
			end
			if (axi4if.bvalid) begin
				axi4if.bready <= 1'b0;
				cpustate <= cpufpuop;
			end else begin
				cpustate <= cpufpuwritewait;
			end
		end

		cpufpuread: begin
			axi4if.araddr <= 32'h20003000; // Any FPU address will do
			axi4if.arvalid <= 1'b1;
			axi4if.rready <= 1'b1;
			cpustate <= cpufpureadwait;
		end

		cpufpureadwait: begin
			if (axi4if.arready) begin
				axi4if.arvalid <= 1'b0;
			end
			if (axi4if.rvalid) begin
				axi4if.rready <= 1'b0;
				// Write FPU result back to destination register
				case (func7)
					default: begin
						frwe <= 1'b1;
						frdin <= axi4if.rdata;
					end
					`f7_fcvtws: begin
						rwren <= 1'b1;
						rdin <= axi4if.rdata;
					end
					`f7_feq: begin
						rwren <= 1'b1;
						rdin <= {31'd0, axi4if.rdata[0]};
					end
					`f7_fmin: begin
						frwe <= 1'b1;
						if (func3==3'b000) // fmin
							frdin <= axi4if.rdata[0] ? frval1 : frval2;
						else // fmax
							frdin <= axi4if.rdata[0] ? frval2 : frval1;
					end
				endcase
				cpustate <= cpuwback;
			end
		end

		default: begin // cpuwback
			case (1'b1)
				instronehot[`o_h_lui]:		rdin <= immed;
				instronehot[`o_h_jal],
				instronehot[`o_h_jalr],
				instronehot[`o_h_branch]:	rdin <= adjacentpc;
				instronehot[`o_h_op],
				instronehot[`o_h_op_imm],
				instronehot[`o_h_auipc]:	rdin <= mwrite ? mout : aluout;
				instronehot[`o_h_system]: begin
					rdin <= csrval;
					csrin <= csrval;
					csrwe <= 1'b1;
					case(func3)
						/*3'b000*/ default: begin
							csrwe <= 1'b0;
						end
						3'b001: begin // csrrw
							csrin <= rval1;
						end
						3'b101: begin // csrrwi
							csrin <= immed;
						end
						3'b010: begin // csrrs
							csrin <= csrval | rval1;
						end
						3'b110: begin // csrrsi
							csrin <= csrval | immed;
						end
						3'b011: begin // cssrrc
							csrin <= csrval & (~rval1);
						end
						3'b111: begin // csrrci
							csrin <= csrval & (~immed);
						end
					endcase
				end
			endcase

			rwren <= isrecordingform;
			csrindex_l <= csrindex;

			if (mret) begin // mret returns us to mepc
				pc <= csrreg[`csr_mepc];
				// clear handled bit with correct priority
				if (mip[2])
					csrreg[`csr_mip][11] <= 1'b0;
				else if(mip[1])
					csrreg[`csr_mip][3] <= 1'b0;
				else if(mip[0])
					csrreg[`csr_mip][7] <= 1'b0;
			end else /*if (ecall) begin
				// noop here
			end else*/ if (ebreak) begin
				// keep pc on same address, we'll be repeating this instuction
				// until software overwrites it with something else
				//pc <= pc;
			end else begin
				case (1'b1)
					instronehot[`o_h_jal],
					instronehot[`o_h_jalr]:		pc <= aluout;
					instronehot[`o_h_branch]:	pc <= branchr ? aluout : adjacentpc;
					default:					pc <= adjacentpc;
				endcase
			end

			if (wfi)
				cpustate <= cpuwfi;
			else
				cpustate <= cpuretire;
		end
	endcase
end

endmodule
