`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// company: 
// engineer: 
// 
// create date: 07/27/2016 02:04:22 pm
// design name: 
// module name: debouncer
// project name: 
// target devices: 
// tool versions: 
// description: 
// 
// dependencies: 
// 
// revision:
// revision 0.01 - file created
// additional comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module debouncer(
    input clk,
    input i,
    output reg o
    );
    parameter count_max=255, count_width=8;
    reg [count_width-1:0] count;
    reg iv=0;
    always@(posedge clk)
        if (i == iv) begin
            if (count == count_max)
                o <= i;
            else
                count <= count + 1'b1;
        end else begin
            count <= 'b0;
            iv <= i;
        end
    
endmodule