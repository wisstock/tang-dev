`timescale 1ns / 1ps
`default_nettype none

// Tang Nano 9K: 27 MHz clock, button on pin 4 as reset (active low), 6 LEDs (active low).
// The top 6 bits of a free-running counter are shown on the LEDs as a binary count.
module blinky #(
    parameter int WIDTH = 26   // on hardware led[5] toggles every 2^25 cycles (~1.24 s)
) (
    input  wire logic       clk,
    input  wire logic       rst_n,
    output      logic [5:0] led
);
    logic [WIDTH-1:0] counter;

    // Synchronous reset; the button has an internal pull-up
    always_ff @(posedge clk) begin
        if (!rst_n) counter <= '0;
        else        counter <= counter + 1'b1;
    end

    // LEDs are active low: invert so that 1 in the counter lights the LED
    assign led = ~counter[WIDTH-1 -: 6];
endmodule

`default_nettype wire
