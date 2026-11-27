# G1 v1 - simulacion y sintesis
RTL   = ../rtl/g1_uart_rx.v ../rtl/g1_trama_rx.v ../rtl/g1_mandos_mmio.v
TB    = tb_g1_mandos.v
TOP   = top_prueba_tangnano9k
PLACA = ../placa/$(TOP).v
CST   = ../placa/tangnano9k_g1.cst

DEVICE ?= GW1NR-LV9QN88PC6/I5
FAMILY ?= GW1N-9C
NEXTPNR ?= nextpnr-himbaechel

all: test

test:
	iverilog -g2012 -o tb_g1_mandos.vvp -s tb_g1_mandos $(RTL) $(TB)
	vvp tb_g1_mandos.vvp

wave: test
	gtkwave tb_g1_mandos.vcd

build/$(TOP).json: $(RTL) $(PLACA)
	mkdir -p build
	yosys -p "read_verilog $(RTL) $(PLACA); synth_gowin -top $(TOP) -json $@"

build/$(TOP)_pnr.json: build/$(TOP).json $(CST)
	$(NEXTPNR) --json $< --write $@ --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(CST) --freq 27

build/$(TOP).fs: build/$(TOP)_pnr.json
	gowin_pack -d $(FAMILY) -o $@ $<

syn: build/$(TOP).fs

config: build/$(TOP).fs
	openFPGALoader -b tangnano9k $<

clean:
	rm -rf build *.vvp *.vcd

.PHONY: all test wave syn config clean
