`timescale 1ns / 1ps
`default_nettype none

// Mechanical push button: synchronise to clk, debounce, and emit a pulse on press.
// The button (active high) counts as pressed once the input is stable for STABLE_CYCLES cycles.
module button_conditioner #(
    parameter int STABLE_CYCLES = 270_000   // 10 ms at 27 MHz
) (
    input  wire logic clk,
    input  wire logic rst,        // synchronous reset, active high
    input  wire logic btn_in,     // raw button signal from the pin (active high)
    output      logic pressed,    // debounced level: 1 while the button is held
    output      logic press_pulse // one cycle at the moment of the press
);
    localparam int CW = $clog2(STABLE_CYCLES + 1);

    // Two synchroniser flip-flops: the input is asynchronous to clk
    logic [1:0]    sync;
    logic [CW-1:0] cnt;

    always_ff @(posedge clk) begin
        if (rst) begin
            sync        <= '0;
            cnt         <= '0;
            pressed     <= 1'b0;
            press_pulse <= 1'b0;
        end else begin
            sync        <= {sync[0], btn_in};
            press_pulse <= 1'b0;
            if (sync[1] == pressed) begin
                cnt <= '0;                       // input matches the state: bouncing is over
            end else if (cnt == CW'(STABLE_CYCLES - 1)) begin
                cnt         <= '0;
                pressed     <= sync[1];          // the new state held for STABLE_CYCLES cycles
                press_pulse <= sync[1];
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
