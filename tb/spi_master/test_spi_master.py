
import itertools
import logging
import os
import sys

import configparser

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, Event
from cocotb.regression import TestFactory

from cocotbext.axi import AxiStreamSource, AxiStreamSink, AxiStreamBus
from cocotbext.spi import SpiSignals, SpiConfig
from cocotbext.spi.devices.generic import SpiSlaveLoopback

class TB(object):
    def __init__(self, dut, spi_mode, spi_word_width):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.fork(Clock(dut.clk, 4, units="ns").start())

        spi_signals = SpiSignals(
            sclk = dut.sclk,
            mosi = dut.mosi,
            miso = dut.miso,
            cs   = dut.bus_active,
            cs_active_low = False
        )

        spi_config = SpiConfig(
            word_width = spi_word_width,
            cpol = bool(spi_mode in [2, 3]),
            cpha = bool(spi_mode in [1, 2]),
            msb_first = True,
            frame_spacing_ns = 1
        )

        self.spi_loopback = SpiSlaveLoopback(spi_signals, spi_config)

        self.source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
        self.sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)


    async def reset(self):
        self.dut.rst.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst <= 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst <= 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)



async def run_test(dut, payload_data=None, payload_lengths=None, spi_mode=None, spi_word_width=None):
    tb = TB(dut, spi_mode, spi_word_width)
    await tb.reset()

    dut.sclk_prescale <= 4
    dut.spi_word_width <= spi_word_width
    dut.spi_mode <= spi_mode

    for test_data in [payload_data(x) for x in payload_lengths()]:
        await tb.source.write(test_data)

        rx_data = bytearray()

        while len(rx_data) < len(test_data):
            rx_data.extend(await tb.sink.read())

        assert rx_data[1:] == test_data[:-1]
        # assert tb.sink.empty()

        await Timer(2, units="us")

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

def size_list():
    return list(range(1,16)) + [128]

def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))

def spi_word_width_list():
    return list([x for x in [8, 16, 32] if x <= int(os.environ["PARAM_AXIS_DATA_WIDTH"])])

if cocotb.SIM_NAME:
    factory = TestFactory(run_test)
    factory.add_option("payload_lengths", [size_list])
    factory.add_option("payload_data", [incrementing_payload])
    # factory.add_option("spi_mode", [0, 1, 2, 3])
    factory.add_option("spi_mode", [1])
    factory.add_option("spi_word_width", spi_word_width_list())
    factory.generate_tests()



tests_dir = os.path.dirname(__file__)
rtl_dir = os.path.abspath(os.path.join(tests_dir, '../../rtl'))

@pytest.mark.parametrize("axis_data_width", [8, 16, 32])
def test_spi_tx(request, axis_data_width):
    dut = "spi_master"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_files = [
        f"{dut}.sv",
        "spi_rx.sv",
        "spi_tx.sv"
    ]
    verilog_sources = [os.path.join(rtl_dir, x) for x in verilog_files]

    # read the default parameters
    config = configparser.ConfigParser()
    config.read(os.path.join(tests_dir,"../parameters.ini"))
    parameters = config._sections['default']

    # replace the parametrized parameters
    parameters["AXIS_DATA_WIDTH"] = axis_data_width

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}

    sim_build = os.path.join(tests_dir, "sim_build",
        request.node.name.replace('[', '-').replace(']', ''))

    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        toplevel=toplevel,
        module=module,
        parameters=parameters,
        sim_build=sim_build,
        extra_env=extra_env,
    )


