# blinky: binary counter on the 6 on-board LEDs, button on pin 4 resets
TOP      := blinky
SOURCES  := blinky.sv
CST      := tangnano9k.cst
TEST     := test_blinky
# Short counter for simulation only (WIDTH = 26 on hardware)
SIM_PARAMS := WIDTH=8
