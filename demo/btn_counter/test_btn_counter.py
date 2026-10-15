import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly

DEBOUNCE = 8   # must match SIM_PARAMS in demo.mk
UP, DOWN = 0, 1
RELEASED = 0b11  # buttons are active low


def shown(dut):
    """LEDs are active low: return the value the LEDs show (1 = lit)."""
    return ~int(dut.led.value) & 0x3F


async def start(dut, clear=True):
    """27 MHz clock, buttons released, wait for the power-on reset to finish.

    All tests share one simulation, so power-on reset happens only once (first test).
    Later tests start from a known 0 by holding both buttons, as a user would.
    """
    cocotb.start_soon(Clock(dut.clk, 37, unit="ns").start())
    dut.btn_n.value = RELEASED
    await ClockCycles(dut.clk, 20)
    if clear:
        set_pressed(dut, {UP, DOWN})
        await ClockCycles(dut.clk, 3 * DEBOUNCE)
        set_pressed(dut, set())
        await ClockCycles(dut.clk, 3 * DEBOUNCE)


def set_pressed(dut, buttons):
    """Drive the buttons: `buttons` is a set of pressed button indices."""
    dut.btn_n.value = RELEASED & ~sum(1 << b for b in buttons)


async def press(dut, button, hold=3 * DEBOUNCE):
    """Press and release a button long enough to pass the debounce filter."""
    set_pressed(dut, {button})
    await ClockCycles(dut.clk, hold)
    set_pressed(dut, set())
    await ClockCycles(dut.clk, 3 * DEBOUNCE)


async def value(dut):
    await ReadOnly()
    v = shown(dut)
    await ClockCycles(dut.clk, 1)
    return v


@cocotb.test()
async def test_power_on_zero(dut):
    """After power-on reset all LEDs are off (value 0). Must stay the first test."""
    await start(dut, clear=False)
    assert await value(dut) == 0


@cocotb.test()
async def test_up_counts(dut):
    """Each press of button 0 adds 1."""
    await start(dut)
    for n in range(1, 6):
        await press(dut, UP)
        assert await value(dut) == n


@cocotb.test()
async def test_down_counts(dut):
    """Button 1 subtracts 1."""
    await start(dut)
    for _ in range(4):
        await press(dut, UP)
    await press(dut, DOWN)
    assert await value(dut) == 3


@cocotb.test()
async def test_wraparound(dut):
    """0 - 1 = 63 and 63 + 1 = 0."""
    await start(dut)
    await press(dut, DOWN)
    assert await value(dut) == 63
    await press(dut, UP)
    assert await value(dut) == 0


@cocotb.test()
async def test_hold_counts_once(dut):
    """Holding a button steps only once (no auto-repeat)."""
    await start(dut)
    await press(dut, UP, hold=50 * DEBOUNCE)
    assert await value(dut) == 1


@cocotb.test()
async def test_bounce_filtered(dut):
    """Contact bounce and short glitches do not add extra steps."""
    await start(dut)
    set_pressed(dut, {UP})
    await ClockCycles(dut.clk, DEBOUNCE // 2)
    set_pressed(dut, set())
    await ClockCycles(dut.clk, 3 * DEBOUNCE)
    assert await value(dut) == 0
    for level in [1, 0, 1, 0, 1, 1, 0, 1]:
        set_pressed(dut, {UP} if level else set())
        await ClockCycles(dut.clk, 2)
    await ClockCycles(dut.clk, 3 * DEBOUNCE)
    for level in [0, 1, 0, 1, 0, 0, 1, 0]:
        set_pressed(dut, {UP} if level else set())
        await ClockCycles(dut.clk, 2)
    await ClockCycles(dut.clk, 3 * DEBOUNCE)
    assert await value(dut) == 1


@cocotb.test()
async def test_both_buttons_clear(dut):
    """Holding both buttons clears the counter to 0."""
    await start(dut)
    for _ in range(5):
        await press(dut, UP)
    set_pressed(dut, {UP, DOWN})
    await ClockCycles(dut.clk, 3 * DEBOUNCE)
    set_pressed(dut, set())
    await ClockCycles(dut.clk, 3 * DEBOUNCE)
    assert await value(dut) == 0
