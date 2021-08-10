
SUBDIRS = spi_tx spi_rx spi_master

.PHONY: all clean

all clean:
	for dir in $(SUBDIRS); do \
		$(MAKE) -C $$dir -f Makefile $@; \
	done
