

TOPLEVEL_LANG = verilog

SIM ?= icarus
WAVES ?= 1

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

DUT      = spi_master_axil
TOPLEVEL = $(DUT)
MODULE   = test_$(DUT)

RTL_DIR = $(shell pwd)/../../rtl

VERILOG_FILES = $(DUT).sv
VERILOG_FILES += spi_master.sv
VERILOG_FILES += axis_fifo.v

VERILOG_SOURCES = $(patsubst %, $(RTL_DIR)/%, $(VERILOG_FILES))

export PARAM_NUM_SS_BITS ?= 1
export PARAM_FIFO_EXIST ?= 0
export PARAM_FIFO_DEPTH ?= 16
export PARAM_AXIL_ADDR_WIDTH ?= 16
export PARAM_AXIL_ADDR_BASE ?= 0

ifeq ($(SIM), icarus)
	PLUSARGS += -fst

	COMPILE_ARGS += -P $(TOPLEVEL).NUM_SS_BITS=$(PARAM_NUM_SS_BITS)
	COMPILE_ARGS += -P $(TOPLEVEL).FIFO_EXIST=$(PARAM_FIFO_EXIST)
	COMPILE_ARGS += -P $(TOPLEVEL).FIFO_DEPTH=$(PARAM_FIFO_DEPTH)
	COMPILE_ARGS += -P $(TOPLEVEL).AXIL_ADDR_WIDTH=$(PARAM_AXIL_ADDR_WIDTH)
	COMPILE_ARGS += -P $(TOPLEVEL).AXIL_ADDR_BASE=$(PARAM_AXIL_ADDR_BASE)

	ifeq ($(WAVES), 1)
		VERILOG_SOURCES += iverilog_dump.v
		COMPILE_ARGS += -s iverilog_dump
	endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

iverilog_dump.v:
	echo 'module iverilog_dump();' > $@
	echo 'initial begin' >> $@
	echo '    $$dumpfile("$(TOPLEVEL).fst");' >> $@
	echo '    $$dumpvars(0, $(TOPLEVEL));' >> $@
	echo 'end' >> $@
	echo 'endmodule' >> $@

clean::
	@rm -rf iverilog_dump.v
	@rm -rf dump.fst $(TOPLEVEL).fst
	@rm -rf results.xml
