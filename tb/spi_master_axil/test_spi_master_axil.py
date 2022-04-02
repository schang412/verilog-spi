# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2022 Spencer Chang

import itertools
import logging
import os
import sys

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, Event
from cocotb.regression import TestFactory

from cocotbext.axi import AxiLiteMaster, AxiLiteBus
from cocotbext.spi import SpiSignals, SpiConfig
from cocotbext.spi.devices.generic import SpiSlaveLoopback


class TB(object):
    def __init__(self, dut, spi_mode, spi_word_width, msb_first):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        spi_signals = SpiSignals(
            sclk=dut.spi_sclk_o,
            mosi=dut.spi_mosi_o,
            miso=dut.spi_miso,
            cs=dut.spi_ncs_o,
            cs_active_low=True
        )

        spi_config = SpiConfig(
            word_width=spi_word_width,
            cpol=bool(spi_mode in [2, 3]),
            cpha=bool(spi_mode in [1, 3]),
            msb_first=msb_first,
            frame_spacing_ns=1
        )

        self.spi_loopback = SpiSlaveLoopback(spi_signals, spi_config)

        self.axil_master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst)

    async def reset(self):
        self.dut.rst.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)


async def run_test(dut, spi_mode=None, spi_word_width=None, lsb_first=None):
    tb = TB(dut, spi_mode, spi_word_width, (not bool(lsb_first)))
    await tb.reset()

    baseaddr = int(os.environ["PARAM_AXIL_ADDR_BASE"])

    # check default config register
    default_ctrl_reg_contents = (4 << 16) | (8 << 8) | (1 << 5)
    ctrl_register_contents = await tb.axil_master.read_dword(baseaddr+0x20)
    assert ctrl_register_contents == default_ctrl_reg_contents

    # test config register update
    await tb.axil_master.write(baseaddr+0x20, (default_ctrl_reg_contents | 1).to_bytes(4, byteorder='little'))
    ctrl_register_contents = await tb.axil_master.read_dword(baseaddr+0x20)
    assert ctrl_register_contents == default_ctrl_reg_contents | 1

    # test software reset
    await tb.axil_master.write(baseaddr+0x10, (0x0000_000A).to_bytes(4, byteorder='little'))
    ctrl_register_contents = await tb.axil_master.read_dword(baseaddr+0x20)
    assert ctrl_register_contents == default_ctrl_reg_contents

    has_fifo = (int(os.environ["PARAM_FIFO_EXIST"]) == 1)

    # configure module for data transfer
    ctrl_reg_config = 0
    ctrl_reg_config = ctrl_reg_config | 4 << 16
    ctrl_reg_config = ctrl_reg_config & ~(0xff << 8)
    ctrl_reg_config = ctrl_reg_config | ((spi_word_width & 0xff) << 8)
    ctrl_reg_config = ctrl_reg_config & ~(1 << 5) if has_fifo else ctrl_reg_config
    ctrl_reg_config = ctrl_reg_config | (1 << 4) if lsb_first else ctrl_reg_config
    ctrl_reg_config = ctrl_reg_config | (1 << 3) if spi_mode in [2,3] else ctrl_reg_config
    ctrl_reg_config = ctrl_reg_config | (1 << 2) if spi_mode in [1,3] else ctrl_reg_config
    ctrl_reg_config = ctrl_reg_config | (1 << 1)
    await tb.axil_master.write(baseaddr+0x20, ctrl_reg_config.to_bytes(4, byteorder='little'))

    test_data = [
        0x8888_8888,
        0x9999_9999,
        0xAAAA_AAAA,
        0xBBBB_BBBB,
        0xCCCC_CCCC,
        0xDDDD_DDDD,
        0xEEEE_EEEE,
        0xFFFF_FFFF,
        0x1234_4321
    ]

    if has_fifo:
        # when fifo is there, we will test automatic slave select
        # select the slave
        await tb.axil_master.write(baseaddr+0x2C, (0b0).to_bytes(4, byteorder='little'))

        for d in test_data:
            await tb.axil_master.write_dword(baseaddr+0x30, d)

        # wait for all the bits to be written
        # num tx * num bits per tx * sclk_prescale * clk_period (there is also a register to poll)
        # multiply above by 2 for a bigger time buffer
        await Timer(len(test_data)*spi_word_width*4*4*2, units='ns')

        data_received = []
        for _ in test_data:
            data_received.append(await tb.axil_master.read_dword(baseaddr+0x34))

        assert data_received[1:] == [(x & ((2**spi_word_width)-1)) for x in test_data[:-1]]

    else:
        data_received = []

        for d in test_data:
            # select the slave
            await tb.axil_master.write(baseaddr+0x2C, (0b0).to_bytes(4, byteorder='little'))
            await tb.axil_master.write_dword(baseaddr+0x30, d)

            # wait for the bits to be written (there is also a register we can poll)
            await Timer(spi_word_width*4*4*2, units='ns')

            data_received.append(await tb.axil_master.read_dword(baseaddr+0x34))

            # deselect the slave
            await tb.axil_master.write(baseaddr+0x2C, (0b1).to_bytes(4, byteorder='little'))
            await RisingEdge(dut.clk)

        assert data_received[1:] == [(x & ((2**spi_word_width)-1)) for x in test_data[:-1]]

    await Timer(2, units="us")
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


if cocotb.SIM_NAME:
    factory = TestFactory(run_test)
    factory.add_option("spi_mode", [0, 1, 2, 3])
    factory.add_option("lsb_first", [0, 1])
    factory.add_option("spi_word_width", [8, 16, 32])
    factory.generate_tests()


tests_dir = os.path.dirname(__file__)
rtl_dir = os.path.abspath(os.path.join(tests_dir, '../../rtl'))


@pytest.mark.parametrize("fifo_exist", [0, 1])
@pytest.mark.parametrize("baseaddr", [0, 0xff00])
def test_spi_master_axil(request, fifo_exist, baseaddr):
    dut = "spi_master_axil"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_files = [
        f"{dut}.sv",
        "spi_master.sv",
        "axis_fifo.v"
    ]
    verilog_sources = [os.path.join(rtl_dir, x) for x in verilog_files]

    # replace the parametrized parameters
    parameters = {}
    parameters["NUM_SS_BITS"] = 1
    parameters["FIFO_EXIST"] = fifo_exist
    parameters["FIFO_DEPTH"] = 16
    parameters["AXIL_ADDR_WIDTH"] = 16
    parameters["AXIL_ADDR_BASE"] = baseaddr

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
