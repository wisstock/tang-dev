import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge

WIDTH = 8                # must match SIM_PARAMS in demo.mk
STEP = 2 ** (WIDTH - 6)  # the LED count advances every STEP cycles
LED_MASK = 0x3F


def lit(dut):
    """LEDs are active low: return the value the LEDs show (1 = lit)."""
    return ~int(dut.led.value) & LED_MASK


async def start(dut):
    """Start a 27 MHz clock and hold reset for 3 cycles."""
    cocotb.start_soon(Clock(dut.clk, 37, unit="ns").start())
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)


@cocotb.test()
async def test_reset_state(dut):
    """All LEDs are off (pins high) while in reset."""
    await start(dut)
    await ReadOnly()
    assert int(dut.led.value) == LED_MASK, f"led = {dut.led.value}, expected all ones"


@cocotb.test()
async def test_led_counts(dut):
    """After reset the LEDs show the top 6 counter bits."""
    await start(dut)
    dut.rst_n.value = 1
    for expected in range(1, 6):
        await ClockCycles(dut.clk, STEP)
        await ReadOnly()
        assert lit(dut) == expected, f"LEDs show {lit(dut)}, expected {expected}"


@cocotb.test()
async def test_sync_reset(dut):
    """Reset is synchronous: the counter clears on the next clock edge."""
    await start(dut)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 3 * STEP)
    dut.rst_n.value = 0
    await ReadOnly()
    assert lit(dut) == 3, "value must not change before the clock edge"
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert lit(dut) == 0, "counter must clear on the clock edge with rst_n = 0"
