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
        # self.axil_master.write_if.log.setLevel(logging.ERROR)
        # self.axil_master.read_if.log.setLevel(logging.ERROR)

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

A32V_SPI_ID                     = 0x294EC100
A32V_SPI_REV                    = 0x00000100

A32V_SPI_ID_OFFSET              = 0x00 # Interface ID Register
A32V_SPI_REV_OFFSET             = 0x04 # Interface Revision Register
A32V_SPI_PNT_OFFSET             = 0x08 # Interface Next Pointer Register
A32V_SPI_RESETR_OFFSET          = 0x10 # Interface Reset Register
A32V_SPI_RESET_VECTOR           = 0x0A # the value to write
A32V_SPI_CTR_OFFSET             = 0x20 # Control Register
A32V_SPI_CTR_LOOP               = 0x01
A32V_SPI_CTR_ENABLE             = 0x02
A32V_SPI_CTR_CPHA               = 0x04
A32V_SPI_CTR_CPOL               = 0x08
A32V_SPI_CTR_LSB_FIRST          = 0x10
A32V_SPI_CTR_MANUAL_SSELECT     = 0x20
A32V_SPI_CTR_MODE_MASK          = (A32V_SPI_CTR_CPHA | A32V_SPI_CTR_CPOL | A32V_SPI_CTR_LSB_FIRST | A32V_SPI_CTR_LOOP)

A32V_SPI_CTR_WORD_WIDTH_OFFSET  = 8
A32V_SPI_CTR_WORD_WIDTH_MASK    = (0xff << A32V_SPI_CTR_WORD_WIDTH_OFFSET)

A32V_SPI_CTR_CLKPRSCL_OFFSET    = 16
A32V_SPI_CTR_CLKPRSCL_MASK      = (0xffff << A32V_SPI_CTR_CLKPRSCL_OFFSET)

A32V_SPI_SR_OFFSET          = 0x28 # Status Register
A32V_SPI_SR_RX_EMPTY_MASK   = 0x01 # Received FIFO is empty
A32V_SPI_SR_RX_FULL_MASK    = 0x02 # Received FIFO is full
A32V_SPI_SR_TX_EMPTY_MASK   = 0x04 # Transmit FIFO is empty
A32V_SPI_SR_TX_FULL_MASK    = 0x08 # Transmit FIFO is full
A32V_SPI_SSR_OFFSET         = 0x2C # 32-bit Slave Select Register
A32V_SPI_TXD_OFFSET         = 0x30 # Data Transmit Register
A32V_SPI_RXD_OFFSET         = 0x34 # Data Receive Register


async def do_soft_rst(tb, baseaddr):
    await tb.axil_master.write_dword(baseaddr + A32V_SPI_RESETR_OFFSET, A32V_SPI_RESET_VECTOR)


async def get_buffer_size(tb, baseaddr):
    n_words = 0
    await do_soft_rst(tb, baseaddr)

    while True:
        await tb.axil_master.write_dword(baseaddr + A32V_SPI_TXD_OFFSET, 0x0000_0000)
        n_words += 1
        if await tb.axil_master.read_dword(baseaddr + A32V_SPI_SR_OFFSET) & A32V_SPI_SR_TX_FULL_MASK:
            break

    return n_words


async def run_test(dut, payload_data=None, spi_mode=None, spi_word_width=None, lsb_first=None, sclk_prescale=None, block_size=None):
    tb = TB(dut, spi_mode, spi_word_width, (not bool(lsb_first)))
    await tb.reset()

    baseaddr = int(os.environ["PARAM_AXIL_ADDR_BASE"])

    # check default config register
    default_ctrl_reg_contents = ((4 << A32V_SPI_CTR_CLKPRSCL_OFFSET)
                                    | (8 << A32V_SPI_CTR_WORD_WIDTH_OFFSET)
                                    | (A32V_SPI_CTR_MANUAL_SSELECT))
    ctrl_register_contents = await tb.axil_master.read_dword(baseaddr+A32V_SPI_CTR_OFFSET)
    assert ctrl_register_contents == default_ctrl_reg_contents

    # test config register update
    await tb.axil_master.write_dword(baseaddr+A32V_SPI_CTR_OFFSET, default_ctrl_reg_contents | A32V_SPI_CTR_LOOP)
    ctrl_register_contents = await tb.axil_master.read_dword(baseaddr+A32V_SPI_CTR_OFFSET)
    assert ctrl_register_contents == default_ctrl_reg_contents | A32V_SPI_CTR_LOOP

    # test software reset
    await do_soft_rst(tb, baseaddr)
    ctrl_register_contents = await tb.axil_master.read_dword(baseaddr+A32V_SPI_CTR_OFFSET)
    assert ctrl_register_contents == default_ctrl_reg_contents

    # test the buffer depth
    has_fifo = (int(os.environ["PARAM_FIFO_EXIST"]) == 1)
    buffer_size = await get_buffer_size(tb, baseaddr)
    if has_fifo:
        assert buffer_size == int(os.environ["PARAM_FIFO_DEPTH"]) + 2
    else:
        assert buffer_size == 1

    # configure module for data transfer
    ctrl_reg_config = 0
    ctrl_reg_config = ctrl_reg_config | sclk_prescale << A32V_SPI_CTR_CLKPRSCL_OFFSET
    ctrl_reg_config = ctrl_reg_config | ((spi_word_width & 0xff) << A32V_SPI_CTR_WORD_WIDTH_OFFSET)
    ctrl_reg_config = ctrl_reg_config | A32V_SPI_CTR_LSB_FIRST if lsb_first else ctrl_reg_config
    ctrl_reg_config = ctrl_reg_config | A32V_SPI_CTR_CPOL if spi_mode in [2,3] else ctrl_reg_config
    ctrl_reg_config = ctrl_reg_config | A32V_SPI_CTR_CPHA if spi_mode in [1,3] else ctrl_reg_config
    ctrl_reg_config = ctrl_reg_config | A32V_SPI_CTR_ENABLE
    await tb.axil_master.write_dword(baseaddr+A32V_SPI_CTR_OFFSET, ctrl_reg_config)

    bytes_per_word = int(spi_word_width/8)

    for test_data in [payload_data(block_size*bytes_per_word)]:
        tdata = []
        data_received = []
        payload_len = len(test_data)
        num_remaining_words = int(payload_len / (spi_word_width/8))

        # select the slave
        await tb.axil_master.write_dword(baseaddr+A32V_SPI_SSR_OFFSET, 0)

        while num_remaining_words:
            # determine how many words we can send at once
            n_words = min(num_remaining_words, buffer_size)
            tx_words = n_words
            for i in range(tx_words):
                if spi_word_width == 8:
                    await tb.axil_master.write(baseaddr+A32V_SPI_TXD_OFFSET, [test_data[0]])
                    tdata.append(test_data[0])
                    test_data = test_data[1:]
                elif spi_word_width == 16:
                    await tb.axil_master.write(baseaddr+A32V_SPI_TXD_OFFSET, test_data[0:2])
                    tdata.append((test_data[1] << 8) | (test_data[0]))
                    test_data = test_data[2:]
                elif spi_word_width == 32:
                    await tb.axil_master.write(baseaddr+A32V_SPI_TXD_OFFSET, test_data[0:4])
                    tdata.append((test_data[3] << 24) | (test_data[2] << 16) | (test_data[1] << 8) | (test_data[0]))
                    test_data = test_data[4:]
                else:
                    raise NotImplementedError("Only 8,16,32 bit words are supported")

            # read the words back
            sr = await tb.axil_master.read_dword(baseaddr+A32V_SPI_SR_OFFSET)
            rx_words = n_words

            while (rx_words):
                if ((sr & A32V_SPI_SR_TX_EMPTY_MASK) and (rx_words > 1)):
                    # we have transmitted everything, but we haven't read everything
                    data_received.append(await tb.axil_master.read_dword(baseaddr+A32V_SPI_RXD_OFFSET))
                    rx_words = rx_words - 1
                    continue
                sr = await tb.axil_master.read_dword(baseaddr+A32V_SPI_SR_OFFSET)
                if (not(sr & A32V_SPI_SR_RX_EMPTY_MASK)):
                    data_received.append(await tb.axil_master.read_dword(baseaddr+A32V_SPI_RXD_OFFSET))
                    rx_words = rx_words - 1

            # decrement the number of words we still have to send
            num_remaining_words = num_remaining_words - n_words

        # deassert slave
        await tb.axil_master.write_dword(baseaddr+A32V_SPI_SSR_OFFSET, 0xffff_ffff)
        await RisingEdge(dut.clk)

        # spi_loopback is delayed one cycle
        data_received.append(await tb.spi_loopback.get_contents())
        tdata = [0] + tdata
        assert data_received == tdata

    await Timer(2, units="us")
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))


if cocotb.SIM_NAME:
    factory = TestFactory(run_test)
    factory.add_option("spi_mode", [0, 1, 2, 3])
    factory.add_option("lsb_first", [0, 1])
    factory.add_option("spi_word_width", [8, 16, 32])
    factory.add_option("payload_data", [incrementing_payload])
    factory.add_option("sclk_prescale", [4, 16])
    factory.add_option("block_size", [1, 3])  # number of words to transmit per transaction
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
        f"{dut}.v",
        "spi_master.v",
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
