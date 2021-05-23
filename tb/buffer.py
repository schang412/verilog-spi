import logging
from collections import deque

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event, First

class BufferSource:
    def __init__(self, clk, sclk, dout, bits=8, sclk_div=4, sclk_pol=False, sclk_phase=False):
        self.log = logging.getLogger(f"cocotb.{clk._path}")
        self._clk = clk
        self._sclk = sclk
        self._dout = dout

        # size of a transfer
        self._bits = bits
        self._sclk_div = sclk_div
        self._sclk_pol = sclk_pol
        self._sclk_phase = sclk_phase

        self.queue = deque()
        self.sync = Event()

        self._idle = Event()
        self._idle.set()

        self._sclk.setimmediatevalue(int(self._sclk_pol))
        self._dout.setimmediatevalue(1)

        self._run_cr = None
        self._restart()

    def _restart(self):
        if self._run_cr is not None:
            self._run_cr.kill()
        self._run_cr = cocotb.fork(self._run(self._clk, self._sclk, self._dout, self._bits, self._sclk_div, self._sclk_pol, self._sclk_phase))

    async def write(self, data):
        self.write_nowait(data)

    def write_nowait(self, data):
        for b in data:
            self.queue.append(int(b))
        self.sync.set()
        self._idle.clear()

    def count(self):
        return len(self.queue)

    def empty(self):
        return not self.queue

    def idle(self):
        return self.empty()

    def clear(self):
        self.queue.clear()

    async def wait(self):
        await self._idle.wait()

    async def _run(self, clk, sclk, dout, bits, sclk_div, sclk_pol, sclk_phase):
        while True:
            while not self.queue:
                sclk <= int(sclk_pol)
                self._idle.set()
                self.sync.clear()
                await self.sync.wait()

            b = self.queue.popleft()

            self.log.info("Write byte 0x%02x", b)

            if sclk_phase != sclk_pol:
                sclk <= int(sclk_phase)

            for k in range(bits):
                dout <= bool(b & (1 << (bits - 1 - k)))

                # do sclk
                for i in range(sclk_div):
                    await RisingEdge(clk)
                sclk <= int(not sclk_phase)

                for i in range(sclk_div):
                    await RisingEdge(clk)
                sclk <= int(sclk_phase)



class BufferSink:
    def __init__(self, clk, din, bits=8, sclk_phase=False):
        self.log = logging.getLogger(f"cocotb.{clk._path}")
        self._clk = clk
        self._din = din

        # size of a transfer
        self._bits = bits
        self._sclk_phase = sclk_phase

        self.queue = deque()
        self.sync = Event()

        self._run_cr = None
        self._restart()

    def _restart(self):
        if self._run_cr is not None:
            self._run_cr.kill()
        self._run_cr = cocotb.fork(self._run(self._clk, self._din, self._bits, self._sclk_phase))

    async def read(self, count=-1):
        while self.empty():
            self.sync.clear()
            await self.sync.wait()
        return self.read_nowait(count)

    def read_nowait(self, count=-1):
        if count < 0:
            count = len(self.queue)
        if self._bits == 8:
            data = bytearray()
        else:
            data = []
        for k in range(count):
            data.append(self.queue.popleft())
        return data

    def count(self):
        return len(self.queue)

    def empty(self):
        return not self.queue

    def clear(self):
        self.queue.clear()

    async def wait(self, timeout=0, units='ns'):
        if not self.empty():
            return
        self.sync.clear()
        if timeout:
            await First(self.sync.wait(), Timer(timeout, units))
        else:
            await self.sync.wait()

    async def _run(self, clk, din, bits, sclk_phase):
        while True:
            rx_byte = 0
            for k in range(bits):
                if (not sclk_phase):
                    await RisingEdge(clk)
                else:
                    await FallingEdge(clk)
                rx_byte |= bool(din.value.integer) << (bits-1-k)

            self.log.info("Read byte 0x%02x", rx_byte)

            self.queue.append(rx_byte)
            self.sync.set()
