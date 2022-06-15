# Verilog SPI

[![Regression Tests](https://github.com/schang412/verilog-spi/actions/workflows/regression-tests.yml/badge.svg)](https://github.com/schang412/verilog-spi/actions/workflows/regression-tests.yml)

GitHub repository: https://github.com/schang412/verilog-spi

## Introduction

SPI interface components written in Verilog-2005 with cocotb testbenches.

## Documentation

### spi_master module

#### Parameters
- AXIS_DATA_WIDTH: the bit width of the axis stream interface
- PRESCALE_WIDTH: the bit of the clock prescale value

#### Signals
- lsb_first: clock out the lowest bit first
- spi_mode: determines the idle clock polarity and how the module sample snad shift data
- sclk_prescale: the number to divide the clock cycles by (should be divisible by 4)
- spi_word_width: how many bits are transmitted in a SPI transaction
- rx_overrun_error: received another word before the current word has been read
- bus_active: active high when the bus is currently in use (should be inverted to get n_cs)

The mode, sclk_prescale, and word_width are sampled at the beginning of an SPI transaction, which is initiated by the AXIS input.

### spi_master_axil module

#### Parameters

- NUM_SS_BITS: the number of slave select lines (1-32)
- FIFO_EXIST: declares that a FIFO buffer should exist between the AXIL register and spi_master module.
- FIFO_DEPTH: the depth of the FIFO queue
- AXIL_ADDR_WIDTH: the address width of the AXIL interface (16, 32, 64)
- AXIL_ADDR_BASE: the base address that the contents are offset from

### Source Files

```
rtl/spi_master.v       : SPI master module
rtl/spi_master_axil.v  : SPI master module (32-bit AXI lite slave)
```

### SPI Modes

The following CPOL and CPHA definitons are identical to the ones used by the Linux Kernel and Wikipedia. When CPHA=0, we
should sample on the first edge that we see, while when CPHA=1, we should sample on the second edge. This means that the
edge that we sample on changes depending on the idle clock polarity.

| SPI Mode | CPOL | CPHA | Clock Idle Level | Data Shifting                                |
| -------- | ---- | ---- | ---------------- | -------------------------------------------- |
| 0        | 0    | 0    | 0                | Sample on rising edge, shift on falling edge |
| 1        | 0    | 1    | 0                | Sample on falling edge, shift on rising edge |
| 2        | 1    | 0    | 1                | Sample on falling edge, shift on rising edge |
| 3        | 1    | 1    | 1                | Sample on rising edge, shift on falling edge |

## Testing

Running the included testbenches requires [cocotb](https://github.com/cocotb/cocotb), [cocotbext-axi](https://github.com/alexforencich/cocotbext-axi), and [Icarus Verilog](http://iverilog.icarus.com/).  The testbenches can be run with pytest directly (requires [cocotb-test](https://github.com/themperek/cocotb-test)), pytest via tox, or via cocotb makefiles. This code requires at least iverilog v11.0 because of the SystemVerilog constructs.

## Other

The code structure and style is based upon [alexforencich/verilog-uart](https://github.com/alexforencich/verilog-uart).

