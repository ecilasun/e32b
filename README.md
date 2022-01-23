# E32B

E32B is a small scale 32 bit RISC-V SoC implementation which contains:
- A single RV32IMFZicsr HART (integer math, floating point math, CSR registers)
- An internal UART fixed at 115200 bauds
- An SPI Master to act as SDCard interface
- 64 Kbytes of block RAM
- 16 Kbytes of scratchpad RAM
- AXI4-Lite bus for the connected peripherals
- External hardware interrupts on UART input
- Simple crossbar / address decoder to route traffic between peripherals and the CPU
- HDMI output using the on-board HDMI port
- DDR3 memory mapped to top of address space
- A very simple graphics module with memory mapped palette and a single frame buffer
- PS/2 keyboard input via onboard HID

The project is built using a Nexsys Video board from Digilent, but should fit onto other boards as well.

The CPU takes several stages per instruction. The longest of these are the LOAD/WFI and STORE instructions, which have one or more additional wait/control stages.

## State machine flow
The stages will always follow the following sequence from startup time, where the curly braces is the looping part, and Reset happens once at startup of the board. The CPU will always start from a Retire stage after the first Reset to ensure the initial instruction address read setup takes place.

General flow is to cycle through Retire->Fetch->Decode->Execute->WBack stages, but for LOAD/STORE there is a bus wait stage, and for WFI there's an interrupt wait stage. Certain instructions in the floating point family and integer math family also have their respective wait stages which can take one or more cycles.

# Default ROM behavior

After the board is programmed with this SoC's bin or bit file, you can connect to the Arty board using a terminal program such as PuTTY. By default, the Arty board serial device comes up on the device list as COM4 (on USB). Set your terminal program to use 115200 baud / 1 stop bit / no parity and you should be able to see messages displayed by the board.

The default ROM image that ships with this SoC will display startup message when the reset button is pressed (if the SoC image is in the persistent memory), or when programmed in dynamic mode. The ROM code will then sit at a WFI instruction, waiting for any external interrupts to be triggered. The interrupt handler, upon receiving hardware input or a timer interrupt, will execute the proper action (trap and echo back any character sent to it or show the one-time timer test message).

Initially, there's a 2 second timer that will trigger a reminder message on the UART port for the user to type 'help' upon which the available commands will be listed.

All input is accepted through the onboard HID and the UART port will only echo back the input, and nothing else. In the future the UART port will only talk to
the debugger and should not be considered a valid I/O device for regular use.

# Changing the ROM image

To use a different ROM image, you'll need to head over to https://github.com/ecilasun/riscvtool and sync the depot.
After that, you'll need to install the RISC-V toolchain (as instructed in the README.md file).
Once you have a working RISC-V toolchain, you can then go to e32/ROMs/ directory in the project root, make changes to the ROM.cpp file, type 'make' and you'll have a .coe file generated for you. You can then replace the contents of the ROM.coe file found in the source/ip folder with the contents of this file. Once that is done, you'll need to remove the generated files for the block RAM 'SRAMBOOTRAMDevice' in the project by right clicking and selecting 'Reset Output Products'. Next step is to synthesize/implement the design which will now have your own ROM image embedded in it.

The memory addresses for the ROM (which is also your RAM) start from 0x10000000 and reach up to 0x1000FFFF, which are hard-coded. You could expand the address range by using more block ram and increasing the bit counts fed to the block ram (S-RAM) device in the design. This would also require changes to the linker script to adjust the 'max size' of your programs, and a few more changes to the rvcrt0.h file in the ROMs directory to move the stack pointer accordingly.

The default stack address is set to 0x8002F000 by the startup code in rvcrt0.h file in the ROMs directory, and the default heap_start/heap_end are set to 0x08000000 and 0x0FFF0000 (in DDR3 memory) respectively. The heap setup can be found in the core.c file in the SDK directory, under the names heap_start and heap_end.

# About the UART / UART FIFO

The SoC uses the built-in USB/UART pins to communicate with the outside world. The problem here is that there are only two pins exposed to the FPGA (TX/RX) and no flow control pins are taken into account. Therefore, the device will currently simply drop the incoming data if the input FIFO is full, as it doesn't have any means to stop the data flow from sender. However, future ROM can implement XON(0x11)/XOFF(0x13) flow control so that the software layer might tell the remote device to stop before the FIFO is filled up.

# SPI Master device

There's an SPI master attached onto the bus at address 20001000. This device is controlled by software to read SDCard data attached to the built in SDCard slot on the under side of the Nexsys Video board. Since it's software controlled, the SPI device can be utilized in other ways if needed, and no hardcoded SDCard specific optimizations / modifications are made to the device. The SPI master device is based on MTI licensed code found at https://github.com/nandland/spi-master

Each write to this address _must_ be accompanied by a tightly coupled read to ensure correct operation. This means one needs to use SPI access as a pair operation, as shown in the following example:

```
// SPI read/write port
volatile uint8_t *IO_SPIRXTX = (volatile uint8_t* )20001000;

// Transmit+receive function
uint8_t SPITxRx(const uint8_t outbyte)
{
   *IO_SPIRXTX = outbyte;
   uint8_t incoming = *IO_SPIRXTX;
   return incoming;
}

// To use in code:
response = SPITxRx(outbyte);
```

# CSR registers

E32B currently has a minimal set of CSR registers supported to do basic exception / interrupt / timer handling, and only machine level versions.
The 15 CSR registers currently in the design (all read/write access for now) are:

```
MSTATUS : Machine status
MIE : Machine interrupt enable
MTVEC : Machine trap vector
MEPC : Machine return program counter
MCAUSE : Machine cause (cause of trap)
MTVAL : Machine trap value (exception specific information)
MIP : Machine interrupt pending
CYCLELO / CYCLEHI : HART cycle counter
RETILO / RETIHI : HART retired instruction counter 
TIMELO / TIMEHI : Wall clock timer
TIMECMPLO / TIMECMPHI : Time compare value against wall clock timer (custom CSR register)
```

# System bus

E32 uses an AXI4 Lite bus, and there are several devices mapped to different memory addresses on the bus. Here's a small list for reference. You can check the axi4chain.sv file for more detail on these devices.

```
DDR3 0x00000000-0x20000000 - Main user program memory and heap
B-RAM 0x80000000-0x8000ffff - Boot ROM and RAM
S-RAM 0x80010000-0x8002ffff - Scratchpad/Shared RAM
UART 0x20000000 - UART
SPIMaster 0x20001000 - SPI Master
PS2 keyboard 0x20002000 - HID interface
FPU 0x20003000 - unused
BUTTONS 0x20004000 - 5 hardware buttons on the device
FB0 0x40000000 - first frame buffer
FB1 0x40020000 - unused
PAL 0x40040000 - color palette (256 word (XRGB) entries)
CTL 0x40080000 - unused
```

# TODO

- Expose the PMOD / LED pins as a GPIO device
- Audio output
- PWM fan control
- Onboard LCD