// SPDX-License-Identifier: BSD-3-Clause

/*
 * Verilog 32-Bit AXIL SPI Controller Driver (master only)
 *
 * Author: Spencer Chang
 *    spencer@sycee.xyz
 *
 */

#include <linux/clk.h>
#include <linux/module.h>
#include <linux/interrupt.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/spi/spi.h>
#include <linux/spi/spi_bitbang.h>
#include "axil32-verilog_spi.h"
#include <linux/io.h>

#define AXIL32_VERILOG_SPI_MAX_CS       32

#define AXIL32_VERILOG_SPI_NAME         "axil32-verilog_spi"

#define A32V_SPI_ID                     0x294EC100
#define A32V_SPI_REV                    0x00000100

#define A32V_SPI_ID_OFFSET              0x00 // Interface ID Register
#define A32V_SPI_REV_OFFSET             0x04 // Interface Revision Register
#define A32V_SPI_PNT_OFFSET             0x08 // Interface Next Pointer Register

#define A32V_SPI_RESETR_OFFSET          0x10 // Interface Reset Register
#define A32V_SPI_RESET_VECTOR           0x0A // the value to write

#define A32V_SPI_CTR_OFFSET             0x20 // Control Register
#define A32V_SPI_CTR_LOOP               0x01
#define A32V_SPI_CTR_ENABLE             0x02
#define A32V_SPI_CTR_CPHA               0x04
#define A32V_SPI_CTR_CPOL               0x08
#define A32V_SPI_CTR_LSB_FIRST          0x10
#define A32V_SPI_CTR_MANUAL_SSELECT     0x20
#define A32V_SPI_CTR_MODE_MASK          (A32V_SPI_CTR_CPHA | A32V_SPI_CTR_CPOL | A32V_SPI_CTR_LSB_FIRST | A32V_SPI_CTR_LOOP)

#define A32V_SPI_CTR_WORD_WIDTH_OFFSET  8
#define A32V_SPI_CTR_WORD_WIDTH_MASK    (0xff << A32V_SPI_CTR_WORD_WIDTH_OFFSET)

#define A32V_SPI_CTR_CLKPRSCL_OFFSET    16
#define A32V_SPI_CTR_CLKPRSCL_MASK      (0xffff << A32V_SPI_CTR_CLKPRSCL_OFFSET)

#define A32V_SPI_SR_OFFSET          0x28 // Status Register
#define A32V_SPI_SR_RX_EMPTY_MASK   0x01 // Received FIFO is empty
#define A32V_SPI_SR_RX_FULL_MASK    0x02 // Received FIFO is full
#define A32V_SPI_SR_TX_EMPTY_MASK   0x04 // Transmit FIFO is empty
#define A32V_SPI_SR_TX_FULL_MASK    0x08 // Transmit FIFO is full

#define A32V_SPI_SSR_OFFSET         0x2C // 32-bit Slave Select Register

#define A32V_SPI_TXD_OFFSET         0x30 // Data Transmit Register
#define A32V_SPI_RXD_OFFSET         0x34 // Data Receive Register

struct axil32v_spi {
    struct spi_bitbang bitbang;
    struct completion done;
    void __iomem    *regs;

    struct device *dev;

    u8 *rx_ptr;
    const u8 *tx_ptr;

    u32 base_freq;

    u8 bytes_per_word;
    int sclk_prescale;
    int buffer_size;  /* buffer size in words */
    u32 cs_inactive;  /* level of the CS pins when inactive */
    u32 (*read_fn)(void __iomem *);
    void (*write_fn)(u32, void __iomem *);
};

static void a32v_spi_write32(u32 val, void __iomem *addr)
{
    iowrite32(val, addr);
}

static u32 a32v_spi_read32(void __iomem *addr)
{
    return ioread32(addr);
}

static void a32v_spi_write32_be(u32 val, void __iomem *addr)
{
    iowrite32be(val, addr);
}

static u32 a32v_spi_read32_be(void __iomem *addr)
{
    return ioread32be(addr);
}

static void a32v_spi_tx(struct axil32v_spi *a32v_spi)
{
    u32 data = 0;
    if (!a32v_spi->tx_ptr) {
        a32v_spi->write_fn(0, a32v_spi->regs + A32V_SPI_TXD_OFFSET);
        return;
    }

    // to transfer non-byte aligned words, we have to use multiple word-size bursts
    // for example a 9 bit word will use two bytes adjacent bytes in the tx buffer
    switch(a32v_spi->bytes_per_word) {
        case 1:
            data = *(u8 *)(a32v_spi->tx_ptr);
            break;
        case 2:
            data = *(u16 *)(a32v_spi->tx_ptr);
            break;
        case 4:
            data = *(u32 *)(a32v_spi->tx_ptr);
            break;
    }

    // transmit the data
    a32v_spi->write_fn(data, a32v_spi->regs + A32V_SPI_TXD_OFFSET);

    // move the pointer
    a32v_spi->tx_ptr += a32v_spi->bytes_per_word;
}

static void a32v_spi_rx(struct axil32v_spi *a32v_spi)
{
    u32 data = a32v_spi->read_fn(a32v_spi->regs + A32V_SPI_RXD_OFFSET);

    if (!a32v_spi->rx_ptr)
        return;

    // similar to transmit, we use multiple words to hold non-byte aligned words
    // a 24 bit word will use 4 adjacent bytes in the rx buffer
    switch(a32v_spi->bytes_per_word) {
        case 1:
            *(u8 *)(a32v_spi->rx_ptr) = data;
            break;
        case 2:
            *(u16 *)(a32v_spi->rx_ptr) = data;
            break;
        case 4:
            *(u32 *)(a32v_spi->rx_ptr) = data;
            break;
    }

    // move the pointer
    a32v_spi->rx_ptr += a32v_spi->bytes_per_word;
}

static void a32v_spi_init_hw(struct axil32v_spi *a32v_spi)
{
    void __iomem *regs_base = a32v_spi->regs;
    u32 cr;

    /* Reset the SPI device */
    dev_info(a32v_spi->dev, "Resetting IP..");
    a32v_spi->write_fn(A32V_SPI_RESET_VECTOR,
        regs_base + A32V_SPI_RESETR_OFFSET);

    /* Deselect the slave (if selected) */
    a32v_spi->write_fn(0xffff, regs_base + A32V_SPI_SSR_OFFSET);

    // setup the clock frequency
    cr = 0;
    cr |= a32v_spi->sclk_prescale << A32V_SPI_CTR_CLKPRSCL_OFFSET;
    cr |= a32v_spi->bytes_per_word << (A32V_SPI_CTR_WORD_WIDTH_OFFSET + 3);
    cr |= A32V_SPI_CTR_MANUAL_SSELECT;
    cr |= A32V_SPI_CTR_ENABLE;

    /* Enable the Interface, Enable Manual Slave Select Assertion */
    a32v_spi->write_fn(cr, regs_base + A32V_SPI_CTR_OFFSET);
}

static void a32v_spi_chipselect(struct spi_device *spi, int is_on)
{
    struct axil32v_spi *a32v_spi = spi_master_get_devdata(spi->master);
    u32 control_reg;
    u32 cs;

    // if the spi device is not active, deselect it
    if (is_on == BITBANG_CS_INACTIVE) {
        a32v_spi->write_fn(a32v_spi->cs_inactive, a32v_spi->regs + A32V_SPI_SSR_OFFSET);
        return;
    }

    // get the current control register (and only change what needs changing)
    control_reg = a32v_spi->read_fn(a32v_spi->regs + A32V_SPI_CTR_OFFSET) & ~A32V_SPI_CTR_MODE_MASK;
    if (spi->mode & SPI_CPHA)
        control_reg |= A32V_SPI_CTR_CPHA;
    if (spi->mode & SPI_CPOL)
        control_reg |= A32V_SPI_CTR_CPOL;
    if (spi->mode & SPI_LSB_FIRST)
        control_reg |= SPI_LSB_FIRST;
    if (spi->mode & SPI_LOOP)
        control_reg |= A32V_SPI_CTR_LOOP;
    a32v_spi->write_fn(control_reg, a32v_spi->regs + A32V_SPI_CTR_OFFSET);

    // activate the chip select
    cs = a32v_spi->cs_inactive;
    cs ^= BIT(spi->chip_select);
    a32v_spi->write_fn(cs, a32v_spi->regs + A32V_SPI_SSR_OFFSET);
}

static int a32v_spi_bytes_per_word(const int bits_per_word)
{
    if (bits_per_word <= 8)
        return 1;
    else if (bits_per_word <= 16)
        return 2;
    else
        return 4;
}

static int a32v_spi_setup_transfer(struct spi_device *spi, struct spi_transfer *t)
{
    struct axil32v_spi *a32v_spi = spi_master_get_devdata(spi->master);
    u32 control_reg;

    if (!t)
        return 0;

    // define the bits per word for the transaction
    a32v_spi->bytes_per_word = a32v_spi_bytes_per_word(t->bits_per_word);
    control_reg = a32v_spi->read_fn(a32v_spi->regs + A32V_SPI_CTR_OFFSET) & ~A32V_SPI_CTR_WORD_WIDTH_MASK;
    control_reg |= (t->bits_per_word) << A32V_SPI_CTR_WORD_WIDTH_OFFSET;
    a32v_spi->write_fn(control_reg, a32v_spi->regs + A32V_SPI_CTR_OFFSET);

    return 0;
}

static int a32v_spi_txrx_bufs(struct spi_device *spi, struct spi_transfer *t)
{
    struct axil32v_spi *a32v_spi = spi_master_get_devdata(spi->master);
    int remaining_words;

    // note that we don't send unless we have a full word
    a32v_spi->tx_ptr = t->tx_buf;
    a32v_spi->rx_ptr = t->rx_buf;
    remaining_words = t->len / a32v_spi->bytes_per_word;

    while (remaining_words) {
        int n_words, tx_words, rx_words;
        u32 sr;
        int stalled;

        // either fill the tx fifo, or write all the words we have
        n_words = min(remaining_words, a32v_spi->buffer_size);
        tx_words = n_words;
        while(tx_words--)
            a32v_spi_tx(a32v_spi);

        // check the status register
        sr = a32v_spi->read_fn(a32v_spi->regs + A32V_SPI_SR_OFFSET);

        // read the data from the rx fifo
        rx_words = n_words;
        stalled = 10*a32v_spi->sclk_prescale;
        while (rx_words) {
            // if we haven't received and sent any words for 10 clock cycles, timeout
            if (rx_words == n_words && !(stalled--) &&
                !(sr & A32V_SPI_SR_TX_EMPTY_MASK) && (sr & A32V_SPI_SR_RX_EMPTY_MASK)) {
                dev_err(&spi->dev, "Detected stall. Check SPI MODE and SPI MEMORY\n");
		        // reset the device
                a32v_spi_init_hw(a32v_spi);
                return -EIO;
            }

            // if we have sent everything by using the FIFO, but haven't read all our words
            // note this means that the rx fifo is not empty (because we cannot transmit faster than receiving)
            if ((sr & A32V_SPI_SR_TX_EMPTY_MASK) && (rx_words > 1)) {
                a32v_spi_rx(a32v_spi);
                rx_words--;
                continue; // we don't need to check anything else, we should read again as soon as we can
            }

            // read the register, then check if we have something in the fifo (if so read it)
            sr = a32v_spi->read_fn(a32v_spi->regs + A32V_SPI_SR_OFFSET);
            if (!(sr & A32V_SPI_SR_RX_EMPTY_MASK)) {
                a32v_spi_rx(a32v_spi);
                rx_words--;
            }
        }

        remaining_words -= n_words;
    }
    return t->len;
}

static int a32v_spi_find_buffer_size(struct axil32v_spi *a32v_spi)
{
    u8 sr;
    int n_words = 0;

    // reset the ip to ensure empty buffers
    a32v_spi->write_fn(A32V_SPI_RESET_VECTOR, a32v_spi->regs + A32V_SPI_RESETR_OFFSET);

    // fill the tx fifo with as many words as possible
    do {
        a32v_spi->write_fn(0, a32v_spi->regs + A32V_SPI_TXD_OFFSET);
        sr = a32v_spi->read_fn(a32v_spi->regs + A32V_SPI_SR_OFFSET) & 0xff;
        n_words++;
    } while (!(sr & A32V_SPI_SR_TX_FULL_MASK));

    return n_words;
}

static int a32v_spi_verify_idrev(struct axil32v_spi *a32v_spi)
{
    u32 idr;
    u32 revr; 

    idr = a32v_spi->read_fn(a32v_spi->regs + A32V_SPI_ID_OFFSET);
    if (idr != A32V_SPI_ID) {
        dev_err(a32v_spi->dev, "IP ID (%d) does not match expected ID (%d)", idr, A32V_SPI_ID);
        return 1;
    }
    revr = a32v_spi->read_fn(a32v_spi->regs + A32V_SPI_REV_OFFSET);
    if (revr != A32V_SPI_REV) {
        dev_warn(a32v_spi->dev, "IP Revision (%d) does not match driver revision (%d)", revr, A32V_SPI_REV);
    } else {
        dev_info(a32v_spi->dev, "IP ID and Revision matches driver.");
    }
    
    return 0;
}

static const struct of_device_id axil32v_spi_of_match[] = {
    { .compatible = "axil32verilog,spi-0.1.0", },
    {}
};
MODULE_DEVICE_TABLE(of, axil32v_spi_of_match);

static int a32v_spi_probe(struct platform_device *pdev)
{
    struct axil32v_spi *a32v_spi;
    struct a32vspi_platform_data *pdata;
    struct resource *res;

    int ret, num_cs = 0, sclk_prescale = 0, freq = 0;
    struct spi_master *master;
    struct clk *spi_parent_clk;
    
    u32 tmp;
    u8 i;

    pdata = dev_get_platdata(&pdev->dev);
    if (pdata) {
        num_cs = pdata->num_chipselect;
        sclk_prescale = pdata->sclk_prescale;
    } else {
        of_property_read_u32(pdev->dev.of_node, "num-ss-bits", &num_cs);
        of_property_read_u32(pdev->dev.of_node, "sclk-prescale", &sclk_prescale);
    }

    if (!sclk_prescale) {
        dev_err(&pdev->dev, "Missing slave select configuration data\n");
        return -EINVAL;
    }
    if (sclk_prescale % 4 != 0) {
        dev_err(&pdev->dev, "Invalid sclk prescale value (must be divisible by 4)\n");
        return -EINVAL;
    }

    if (!num_cs) {
        dev_err(&pdev->dev, "Missing slave select configuration data\n");
        return -EINVAL;
    }
    if (num_cs > AXIL32_VERILOG_SPI_MAX_CS) {
        dev_err(&pdev->dev, "Invalid number of spi slaves\n");
        return -EINVAL;
    }

    // get the parent clock and compute the operating frequency
    spi_parent_clk = devm_clk_get(&pdev->dev, "parent-clk");
    if (IS_ERR(spi_parent_clk)) {
	dev_err(&pdev->dev, "Failed to get parent-clk");
	ret = PTR_ERR(spi_parent_clk);
    	goto fail;
    }
    freq = clk_get_rate(spi_parent_clk);

    master = spi_alloc_master(&pdev->dev, sizeof(struct axil32v_spi));
    if (!master)
        return -ENODEV;

    // the mode bits understood by this driver
    master->mode_bits = SPI_CPOL | SPI_CPHA | SPI_LSB_FIRST | SPI_LOOP;

    // allow end user to have word widths from 1 to 32.
    master->bits_per_word_mask = SPI_BPW_RANGE_MASK(1,32);

    // configure the master
    master->bus_num = pdev->id;
    master->dev.of_node = pdev->dev.of_node;
    master->num_chipselect = num_cs;
    master->min_speed_hz = freq / sclk_prescale;
    master->max_speed_hz = freq / sclk_prescale;

    // point to the function calls for a transfer
    a32v_spi = spi_master_get_devdata(master);
    a32v_spi->cs_inactive = 0xffffffff;
    a32v_spi->base_freq = freq;
    a32v_spi->sclk_prescale = sclk_prescale;
    a32v_spi->bitbang.master = master;
    a32v_spi->bitbang.chipselect = a32v_spi_chipselect;
    a32v_spi->bitbang.setup_transfer = a32v_spi_setup_transfer;
    a32v_spi->bitbang.txrx_bufs = a32v_spi_txrx_bufs;
    init_completion(&a32v_spi->done);

    // save the device object for printing purposes
    a32v_spi->dev = &pdev->dev;

    // get the base address of the IP
    res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
    a32v_spi->regs = devm_ioremap_resource(&pdev->dev, res);
    if (IS_ERR(a32v_spi->regs)) {
        ret = PTR_ERR(a32v_spi->regs);
        goto fail;
    }
    dev_info(&pdev->dev, "at %pR", res);
    
    /**
     * Detect endianess on the IP by setting a bit in the control register.
     * Detection must be done before reset is sent, otherwise the reset
     * value is incorrect.
     */
    a32v_spi->read_fn = a32v_spi_read32;
    a32v_spi->write_fn = a32v_spi_write32;

    a32v_spi->write_fn(A32V_SPI_CTR_LOOP, a32v_spi->regs + A32V_SPI_CTR_OFFSET);
    tmp = a32v_spi->read_fn(a32v_spi->regs + A32V_SPI_CTR_OFFSET);
    tmp &= A32V_SPI_CTR_LOOP;
    if (tmp != A32V_SPI_CTR_LOOP) {
        a32v_spi->read_fn = a32v_spi_read32_be;
        a32v_spi->write_fn = a32v_spi_write32_be;
        dev_info(&pdev->dev, "Determined bit order to be big endian.");
    } else {
        dev_info(&pdev->dev, "Determined bit order to be little endian.");
    }

    // get the buffer size
    a32v_spi->buffer_size = a32v_spi_find_buffer_size(a32v_spi);
    dev_info(&pdev->dev, "Determined buffer size to be %d", a32v_spi->buffer_size);

    ret = a32v_spi_verify_idrev(a32v_spi);
    if (ret) {
        dev_err(&pdev->dev, "stopping driver (unmatched ip/driver id)");
        goto fail;
    }

    // initialize the SPI Controller
    a32v_spi_init_hw(a32v_spi);

    ret = spi_bitbang_start(&a32v_spi->bitbang);
    if (ret) {
        dev_err(&pdev->dev, "spi_bitbang_start FAILED\n");
        goto fail;
    }

    if (pdata) {
        for (i = 0; i < pdata->num_devices; i++)
            spi_new_device(master, pdata->devices + i);
    }

    platform_set_drvdata(pdev, master);
    return 0;

fail:
    spi_master_put(master);
    return ret;
}

static int a32v_spi_remove(struct platform_device *pdev)
{
    struct spi_master *master = platform_get_drvdata(pdev);
    struct axil32v_spi *a32v_spi = spi_master_get_devdata(master);

    spi_bitbang_stop(&a32v_spi->bitbang);

    spi_master_put(a32v_spi->bitbang.master);

    dev_info(&pdev->dev, " platform remove");

    return 0;
}

/* work with hotplug and coldplug */
MODULE_ALIAS("platform:" AXIL32_VERILOG_SPI_NAME);

static struct platform_driver axil32v_spi_driver = {
    .probe = a32v_spi_probe,
    .remove = a32v_spi_remove,
    .driver = {
        .name = AXIL32_VERILOG_SPI_NAME,
        .of_match_table = axil32v_spi_of_match,
    },
};
module_platform_driver(axil32v_spi_driver);

MODULE_DESCRIPTION("32-Bit AXIL SPI Driver");
MODULE_AUTHOR("Spencer Chang");
MODULE_LICENSE("Dual BSD/GPL");
