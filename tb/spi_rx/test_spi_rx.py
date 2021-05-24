
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

from cocotbext.axi import AxiStreamSink, AxiStreamBus

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from buffer import BufferSource

class TB(object):
    def __init__(self, dut, spi_mode, spi_word_width):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.fork(Clock(dut.clk, 4, units="ns").start())

        spi_mode_cpol_map = {
            0: 0,
            1: 0,
            2: 1,
            3: 1
        }

        spi_mode_cpha_map = {
            0: 0,
            1: 1,
            2: 1,
            3: 0
        }

        self.source = BufferSource(dut.clk, dut.sclk, dut.rxd, bits=spi_word_width, sclk_pol=spi_mode_cpol_map[spi_mode], sclk_phase=spi_mode_cpha_map[spi_mode])
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

    dut.spi_word_width <= spi_word_width
    dut.spi_mode <= spi_mode

    for test_data in [payload_data(x) for x in payload_lengths()]:
        await tb.source.write(test_data)

        rx_data = bytearray()

        while len(rx_data) < len(test_data):
            rx_data.extend(await tb.sink.read())

        assert rx_data == test_data
        assert tb.sink.empty()

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
    factory.add_option("spi_mode", [0])
    factory.add_option("spi_word_width", spi_word_width_list())
    factory.generate_tests()



tests_dir = os.path.dirname(__file__)
rtl_dir = os.path.abspath(os.path.join(tests_dir, '../../rtl'))

@pytest.mark.parametrize("axis_data_width", [8, 16, 32])
def test_spi_tx(request, axis_data_width):
    dut = "spi_rx"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_files = [
        f"{dut}.sv"
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


