// SPDX-License-Identifier: BSD-3-Clause
#ifndef __LINUX_SPI_AXIL32V_SPI_H
#define __LINUX_SPI_AXIL32V_SPI_H

/**
 * struct a32vspi_platform_data - Platform data of the 32-Bit AXIL Verilog Driver
 * @num_chipselect:     Number of chip select by the IP
 * @sclk_prescale:      The number to divide the system clock by to get sclk. (must be multiple of 4)
 * @devices:            Devices to add when the driver is probed.
 * @num_devices:        Number of devices in the device array.
 */
struct a32vspi_platform_data {
    u16 num_chipselect;
    u16 sclk_prescale;
    struct spi_board_info *devices;
    u8 num_devices;
};

#endif /* __LINUX_SPI_AXIL32V_SPI_H */
