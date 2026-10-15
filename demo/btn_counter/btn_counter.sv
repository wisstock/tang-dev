`timescale 1ns / 1ps
`default_nettype none

// Tang Nano 9K: 6-bit binary counter on the LEDs driven by the two on-board buttons.
//   btn_n[0] (pin 3): +1     btn_n[1] (pin 4): -1     both held: clear to 0
// The counter wraps (63 + 1 = 0, 0 - 1 = 63). Holding a button steps only once.
module btn_counter #(
    parameter int DEBOUNCE_CYCLES = 270_000   // 10 ms at 27 MHz
) (
    input  wire logic       clk,     // 27 MHz
    input  wire logic [1:0] btn_n,   // buttons, active low (internal pull-up)
    output      logic [5:0] led      // LEDs, active low
);
    // Power-on reset: no reset button is left, so hold reset for 16 cycles after configuration.
    // Flip-flops start at 0 after configuration; the initial block makes simulation match.
    // Plain always (not always_ff): IEEE 1800 forbids writing an always_ff variable from initial.
    logic [3:0] por_cnt;
    logic       rst;
    initial por_cnt = '0;
    always @(posedge clk) if (rst) por_cnt <= por_cnt + 1'b1;
    assign rst = ~&por_cnt;

    logic up_pulse, down_pulse, up_level, down_level;

    button_conditioner #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_btn_up (
        .clk, .rst, .btn_in(~btn_n[0]), .pressed(up_level), .press_pulse(up_pulse)
    );

    button_conditioner #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_btn_down (
        .clk, .rst, .btn_in(~btn_n[1]), .pressed(down_level), .press_pulse(down_pulse)
    );

    logic [5:0] value;

    always_ff @(posedge clk) begin
        if (rst || (up_level && down_level)) value <= '0;
        else if (up_pulse && !down_pulse)   value <= value + 1'b1;
        else if (down_pulse && !up_pulse)   value <= value - 1'b1;
    end

    // LEDs are active low
    assign led = ~value;
endmodule

`default_nettype wire
