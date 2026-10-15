# btn_counter: 6-bit counter on the LEDs, button pin 3 = +1, pin 4 = -1, both = clear
TOP      := btn_counter
SOURCES  := button_conditioner.sv btn_counter.sv
CST      := tangnano9k.cst
TEST     := test_btn_counter
# Short debounce for simulation only (10 ms = 270000 cycles on hardware)
SIM_PARAMS := DEBOUNCE_CYCLES=8
