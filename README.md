# Verilog SPI

[![Regression Tests](https://github.com/schang412/verilog-spi/actions/workflows/regression-tests.yml/badge.svg)](https://github.com/schang412/verilog-spi/actions/workflows/regression-tests.yml)

GitHub repository: https://github.com/schang412/verilog-spi

## Introduction

This is a basic SPI to AXI Stream IP Core, written in Verilog with cocotb testbenches.

## Documentation

The main code for the core exists in the `rtl` subdirectory. The` spi_tx.sv` and `spi_rx.sv` contain the actual implementation while `spi_master.sv` instantiates the modules and makes internal connections.

### SPI Modes

| SPI Mode | CPOL | CPHA | Clock Idle Level | Data Shifting                                |
| -------- | ---- | ---- | ---------------- | -------------------------------------------- |
| 0        | 0    | 0    | 0                | Sample on rising edge, shift on falling edge |
| 1        | 0    | 1    | 0                | Sample on falling edge, shift on rising edge |
| 2        | 1    | 1    | 1                | Sample on falling edge, shift on rising edge |
| 3        | 1    | 0    | 1                | Sample on rising edge, shift on falling edge |

### Source Files

```
rtl/spi_master.sv  : Wrapper for the complete SPI interface
rtl/spi_rx.sv      : SPI receiver implementation
rtl/spi_tx.sv      : SPI transmitter implementation
```

## Testing

Running the included testbenches requires [cocotb](https://github.com/cocotb/cocotb), [cocotbext-axi](https://github.com/alexforencich/cocotbext-axi), and [Icarus Verilog](http://iverilog.icarus.com/).  The testbenches can be run with pytest directly (requires [cocotb-test](https://github.com/themperek/cocotb-test)), pytest via tox, or via cocotb makefiles. This code requires at least iverilog v11.0 because of the SystemVerilog constructs.

## Other

The code structure and style is based upon [alexforencich/verilog-uart](https://github.com/alexforencich/verilog-uart).

