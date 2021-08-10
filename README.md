# Verilog SPI

[![Regression Tests](https://github.com/schang412/verilog-spi/actions/workflows/regression-tests.yml/badge.svg)](https://github.com/schang412/verilog-spi/actions/workflows/regression-tests.yml)

GitHub repository: https://github.com/schang412/verilog-spi

## Introduction

This is a basic SPI to AXI Stream IP Core, written in Verilog with cocotb testbenches.

## Documentation

The main code for the core exists in the `rtl` subdirectory. The `spi_tx.sv` and `spi_rx.sv` contain the actual implementation while `spi_master.sv` instantiates the modules and makes internal connections.

The module has a MOSI pin for transmit and a MISO pin for receive. The modules take one parameter, `AXIS_DATA_WIDTH`, which specifies the width of the data bus. The length of a SPI word is determined by `spi_word_width`, which must take on a value of equal or less than `AXIS_DATA_WIDTH`. `spi_word_width` is latched on a transmit transaction. The `sclk_prescale` factor determines the frequency of `sclk` (calculated by Fclk/sclk_prescale) (the minimum value for `sclk_prescale` is 2). The `spi_mode` determines how the module samples data, shifts data, and the clock idle level.

The module provides a 'busy' signal that is high when the respective operation is taking place. The receiver also presents an overrun error signal that goes high when the data word currently in the tdata output register is not read before another word is received.

The main interface to the user design is an AXI4-Stream interface that consists of `tdata`, `tvalid`, and `tready` signals. `tready` flows in the opposite direction as `tdata` and `tvalid`. `tdata` is considered valid when `tvalid` is high. The destination will accept data only when `tready` is high. Data is transferred from the source to the destination when both `tvalid` and `tready` are high, otherwise the bus is stalled.

### Source Files

```
rtl/spi_master.sv  : Wrapper for the complete SPI interface
rtl/spi_rx.sv      : SPI receiver implementation
rtl/spi_tx.sv      : SPI transmitter implementation
```

### SPI Modes

| SPI Mode | CPOL | CPHA | Clock Idle Level | Data Shifting                                |
| -------- | ---- | ---- | ---------------- | -------------------------------------------- |
| 0        | 0    | 0    | 0                | Sample on rising edge, shift on falling edge |
| 1        | 0    | 1    | 0                | Sample on falling edge, shift on rising edge |
| 2        | 1    | 1    | 1                | Sample on falling edge, shift on rising edge |
| 3        | 1    | 0    | 1                | Sample on rising edge, shift on falling edge |

## Testing

Running the included testbenches requires [cocotb](https://github.com/cocotb/cocotb), [cocotbext-axi](https://github.com/alexforencich/cocotbext-axi), and [Icarus Verilog](http://iverilog.icarus.com/).  The testbenches can be run with pytest directly (requires [cocotb-test](https://github.com/themperek/cocotb-test)), pytest via tox, or via cocotb makefiles. This code requires at least iverilog v11.0 because of the SystemVerilog constructs.

## Other

The code structure and style is based upon [alexforencich/verilog-uart](https://github.com/alexforencich/verilog-uart).

