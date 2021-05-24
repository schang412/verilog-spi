
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

from cocotbext.axi import AxiStreamSource, AxiStreamBus

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from buffer import BufferSink

class TB(object):
    def __init__(self, dut, spi_mode=0):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.fork(Clock(dut.clk, 4, units="ns").start())

        spi_mode_cpha_map = {
            0: 0,
            1: 1,
            2: 1,
            3: 0
        }

        self.source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
        self.sink = BufferSink(dut.sclk, dut.txd, bits=int(os.environ["PARAM_DATA_WIDTH"]), sclk_phase=spi_mode_cpha_map[spi_mode])

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



async def run_test(dut, payload_data=None, payload_lengths=None, sclk_prescale=None, spi_mode=None):
    tb = TB(dut, spi_mode)
    await tb.reset()


    dut.sclk_prescale <= sclk_prescale
    dut.spi_mode <= spi_mode

    for test_data in [payload_data(x) for x in payload_lengths()]:
        await tb.source.send(test_data)
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

if cocotb.SIM_NAME:
    factory = TestFactory(run_test)
    factory.add_option("payload_lengths", [size_list])
    factory.add_option("payload_data", [incrementing_payload])
    factory.add_option("sclk_prescale", [2, 4])
    factory.add_option("spi_mode", [0, 1, 2, 3])
    factory.generate_tests()



tests_dir = os.path.dirname(__file__)
rtl_dir = os.path.abspath(os.path.join(tests_dir, '../../rtl'))

@pytest.mark.parametrize("data_width", [8, 16, 32])
def test_spi_tx(request, data_width):
    dut = "spi_tx"
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
    parameters["DATA_WIDTH"] = data_width

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


