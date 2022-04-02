SUMMARY = "32-Bit AXIL SPI Driver Kernel Module"
SECTION = "kernel"
LICENSE = "MIT"

LIC_FILES_CHKSUM = " \
    file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit module

SRC_URI = " \
    file://axil32-verilog-spi \
"

S = "${WORKDIR}/axil32-verilog-spi"