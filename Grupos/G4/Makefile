# =============================================================================
Makefile 9k y Primer 25k
# =============================================================================
SHELL := /bin/bash
.ONESHELL:

BOARD ?= tangprimer25k
PROG  ?= hola
ARGS  ?=

# --- Entorno de herramientas -----------------------------------------------
ifneq ($(shell command -v digital-logic-design 2>/dev/null),)
RUN ?= source digital-logic-design activate >/dev/null &&
else
RUN ?=
endif

# --- Nombres de herramientas -----------------------------------------------
CROSS         ?= riscv64-unknown-elf-
YOSYS         ?= yosys
IVERILOG      ?= iverilog
VVP           ?= vvp
GTKWAVE       ?= gtkwave
NEXTPNR_ECP5  ?= nextpnr-ecp5
ECPPACK       ?= ecppack
NEXTPNR_GOWIN ?= nextpnr-himbaechel
GOWIN_PACK    ?= gowin_pack
LOADER        ?= openFPGALoader
RTL_GEN       ?= netlist2svg

GOWIN_SH      ?= /home/tuklaptop/opt/gowin/IDE/bin/gw_sh

# --- Archivos ---------------------------------------------------------------
B   := build
RTL := rtl/SOC.v rtl/chip_select.v rtl/cpu/femtorv32_quark.v rtl/memory/Memory.v \
       rtl/uart/perip_uart.v rtl/uart/uart.v rtl/mult/perip_mult.v rtl/mult/mult.v \
       rtl/G4/peripheral_hub75.v rtl/G4/hub75_core.v
RTL += $(filter-out $(RTL),$(wildcard rtl/perip_*.v))

RAM_PALABRAS := 8192

IV_RELAX := $(shell bash -c '$(RUN) $(IVERILOG) -gno-strict-declaration -E -o /dev/null /dev/null' >/dev/null 2>&1 && echo -gno-strict-declaration -Wno-declaration-after-use)
CFLAGS   := -march=rv32i -mabi=ilp32 -Os -g -ffreestanding -nostdlib \
            -ffunction-sections -fdata-sections -Wall

.PHONY: help firmware sim wave rtl syn config config-flash clean-flash stats clean detect

help:
	@echo ""
	@echo "  make firmware            Compila firmware/$(PROG).c -> firmware.hex y build/firmware.lst"
	@echo "  make sim                 Compila y simula con Icarus Verilog"
	@echo "  make sim ARGS=+vcd       Guarda formas de onda; luego: make wave"
	@echo "  make wave                Abre las formas de onda en GTKWave"
	@echo "  make rtl                 Diagrama RTL del SoC (build/SOC.svg)"
	@echo "  make syn BOARD=...       Síntesis, place & route y bitstream"
	@echo "  make stats BOARD=...     Recursos usados y reporte de PnR"
	@echo "  make config BOARD=...    Configura la FPGA (SRAM volátil)"
	@echo "  make config-flash ...    Configura la memoria SPI Flash (Permanente)"
	@echo "  make clean-flash ...     Borra por completo la memoria SPI Flash"
	@echo "  make terminal BOARD=...  Terminal serial a 115200 baudios"
	@echo "  make clean               Borra la carpeta de compilación build/"
	@echo "  make detect              Detecta la tarjeta conectada por JTAG"
	@echo "  make sim-paso2           Simula el barrido HUB75 (paso 2)"
	@echo "  make sim-paso3           Simula configuracion del driver + barrido (paso 3)"
	@echo "  make sim-paso4           Simula el periferico completo por el bus (paso 4)"
	@echo "  make paso2               Prueba el barrido en la placa sin CPU"
	@echo ""

# =============================================================================
# 1. FIRMWARE
# =============================================================================
firmware: firmware.hex

firmware.hex: firmware/$(PROG).c firmware/soc.h firmware/crt0.S firmware/linker.ld
	mkdir -p $(B)
	$(RUN) $(CROSS)gcc $(CFLAGS) -T firmware/linker.ld -Wl,--gc-sections \
	  -Wl,-Map=$(B)/firmware.map firmware/crt0.S firmware/$(PROG).c -lgcc -o $(B)/firmware.elf
	$(RUN) $(CROSS)objdump -d -S $(B)/firmware.elf > $(B)/firmware.lst
	$(RUN) $(CROSS)objcopy -O binary $(B)/firmware.elf $(B)/firmware.bin
	python3 firmware/tools/bin2hex.py $(B)/firmware.bin firmware.hex $(RAM_PALABRAS)
	echo "$(PROG)" > $(B)/prog.txt

ifneq ($(shell cat $(B)/prog.txt 2>/dev/null),$(PROG))
.PHONY: firmware.hex
endif

# =============================================================================
# 2. SIMULACIÓN
# =============================================================================
sim: firmware.hex
	mkdir -p $(B)
	$(RUN) $(IVERILOG) -g2012 $(IV_RELAX) -DBENCH -o $(B)/tb_soc.vvp -s tb_soc sim/tb_soc.v $(RTL)
	$(RUN) $(VVP) -n $(B)/tb_soc.vvp $(ARGS) | grep -v "readmemh"

wave:
	$(RUN) $(GTKWAVE) $(B)/tb_soc.vcd &

rtl:
	mkdir -p $(B)
	$(RUN) $(YOSYS) -q -p "prep -top SOC; write_json $(B)/SOC.json" $(RTL)
	$(RUN) $(RTL_GEN) $(B)/SOC.json -o $(B)/SOC.svg
	@echo "Diagrama generado: $(B)/SOC.svg"

# =============================================================================
# 3. SÍNTESIS Y PROGRAMACIÓN
# =============================================================================
ifeq ($(BOARD),tangprimer25k)
TOP       := top_tangprimer25k
BITSTREAM := $(B)/impl/pnr/project.fs
PORT      ?= /dev/ttyUSB1

$(BITSTREAM): firmware.hex $(RTL) boards/tangprimer25k/top_tangprimer25k.v boards/tangprimer25k/tangprimer25k.cst
	mkdir -p $(B)
	cp firmware.hex $(B)/
	@echo "set_device GW5A-LV25MG121NC1/I0 -device_version A" > $(B)/run.tcl
	@echo "add_file ../boards/tangprimer25k/tangprimer25k.cst" >> $(B)/run.tcl
	@echo "add_file ../boards/tangprimer25k/top_tangprimer25k.v" >> $(B)/run.tcl
	@for f in $(RTL); do echo "add_file ../$$f" >> $(B)/run.tcl; done
	@echo "set_option -top_module $(TOP)" >> $(B)/run.tcl
	@echo "set_option -use_cpu_as_gpio 1" >> $(B)/run.tcl
	@echo "run all" >> $(B)/run.tcl
	cd $(B) && PATH=/usr/bin:/bin LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libfreetype.so.6 LD_LIBRARY_PATH="/home/tuklaptop/opt/gowin/IDE/lib" $(GOWIN_SH) run.tcl

config:
	$(RUN) $(LOADER) -b tangprimer25k -m $(BITSTREAM)

config-flash:
	$(RUN) $(LOADER) -b tangprimer25k -f $(BITSTREAM)

clean-flash:
	$(RUN) $(LOADER) -b tangprimer25k --bulk-erase

else ifeq ($(BOARD),colorlight)
TOP       := top_colorlight
BITSTREAM := $(B)/colorlight.bit
PORT      ?= /dev/ttyUSB0
CABLE_PINES ?= 0:3:4:1

$(BITSTREAM): firmware.hex $(RTL) boards/colorlight/top_colorlight.v boards/colorlight/colorlight.lpf
	mkdir -p $(B)
	$(RUN) $(YOSYS) -p "synth_ecp5 -top $(TOP) -json $(B)/colorlight.json" \
	  $(RTL) boards/colorlight/top_colorlight.v -l $(B)/yosys.log > /dev/null
	$(RUN) $(NEXTPNR_ECP5) --25k --package CABGA256 --speed 6 --freq 25 \
	  --json $(B)/colorlight.json --lpf boards/colorlight/colorlight.lpf \
	  --textcfg $(B)/colorlight.config -l $(B)/nextpnr.log 2> /dev/null
	$(RUN) $(ECPPACK) $(B)/colorlight.config $(BITSTREAM)

config:
	$(RUN) $(LOADER) -c ft232RL --pins=$(CABLE_PINES) --freq 3000000 -m $(BITSTREAM)

config-flash:
	$(RUN) $(LOADER) -c ft232RL --pins=$(CABLE_PINES) --freq 3000000 -f $(BITSTREAM) --unprotect-flash

clean-flash:
	$(RUN) $(LOADER) -c ft232RL --pins=$(CABLE_PINES) --erase

else ifeq ($(BOARD),tangnano9k)
TOP       := top_tangnano9k
BITSTREAM := $(B)/impl/pnr/project.fs
PORT      ?= /dev/ttyUSB1

$(BITSTREAM): firmware.hex $(RTL) boards/tangnano9k/top_tangnano9k.v boards/tangnano9k/tangnano9k.cst
	mkdir -p $(B)
	cp firmware.hex $(B)/
	@echo "set_device GW1NR-LV9QN88PC6/I5 -device_version C" > $(B)/run.tcl
	@echo "add_file ../boards/tangnano9k/tangnano9k.cst" >> $(B)/run.tcl
	@echo "add_file ../boards/tangnano9k/top_tangnano9k.v" >> $(B)/run.tcl
	@for f in $(RTL); do echo "add_file ../$$f" >> $(B)/run.tcl; done
	@echo "set_option -top_module $(TOP)" >> $(B)/run.tcl
	@echo "set_option -use_sspi_as_gpio 1" >> $(B)/run.tcl
	@echo "set_option -use_mspi_as_gpio 1" >> $(B)/run.tcl
	@echo "run all" >> $(B)/run.tcl
	cd $(B) && PATH=/usr/bin:/bin LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libfreetype.so.6 LD_LIBRARY_PATH="/home/tuklaptop/opt/gowin/IDE/lib" $(GOWIN_SH) run.tcl

config:
	$(RUN) $(LOADER) -b tangnano9k -m $(BITSTREAM)

config-flash:
	$(RUN) $(LOADER) -b tangnano9k -f $(BITSTREAM)

clean-flash:
	$(RUN) $(LOADER) -b tangnano9k --bulk-erase

else
$(error BOARD debe ser tangprimer25k, colorlight o tangnano9k)
endif

# =============================================================================
# 4. DIAGNÓSTICO
# =============================================================================
syn: $(BITSTREAM)
	@echo "Bitstream generado: $(BITSTREAM)"

stats:
	@echo ""
	@echo "=== Recursos usados ($(BOARD)) ==="
	@if [ -f $(B)/impl/pnr/project.rpt.txt ]; then \
	    grep -A 15 "Resource Usage Summary" $(B)/impl/pnr/project.rpt.txt 2>/dev/null || cat $(B)/impl/pnr/project.rpt.txt | head -n 30; \
	else \
	    echo "Ejecuta 'make syn' primero."; \
	fi

terminal:
	$(RUN) picocom -b 115200 $(PORT)

detect:
	$(RUN) $(LOADER) --detect

clean:
	rm -rf $(B) firmware.hex

# =============================================================================
# Prueba del paso 2 en placa (barrido sin CPU). 
#   make paso2      -> sintetiza top_paso2 y configura la FPGA
#   make sim-paso2  -> corre el testbench del barrido
# =============================================================================
P2     := build_paso2
P2_RTL := boards/tangprimer25k/top_paso2.v rtl/perip_hub75/hub75_tick.v \
          rtl/perip_hub75/hub75_framebuffer.v rtl/perip_hub75/hub75_barrido.v

.PHONY: paso2 sim-paso2 sim-paso3 sim-paso4
paso2:
	set -e
	mkdir -p $(P2)
	rm -f $(P2)/impl/pnr/project.fs
	echo "set_device GW5A-LV25MG121NC1/I0 -device_version A" > $(P2)/run.tcl
	echo "add_file ../boards/tangprimer25k/tangprimer25k.cst" >> $(P2)/run.tcl
	for f in $(P2_RTL); do echo "add_file ../$$f" >> $(P2)/run.tcl; done
	echo "set_option -top_module top_paso2" >> $(P2)/run.tcl
	echo "set_option -use_cpu_as_gpio 1" >> $(P2)/run.tcl
	echo "run all" >> $(P2)/run.tcl
	(cd $(P2) && PATH=/usr/bin:/bin LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libfreetype.so.6 LD_LIBRARY_PATH="/home/tuklaptop/opt/gowin/IDE/lib" $(GOWIN_SH) run.tcl)
	test -f $(P2)/impl/pnr/project.fs || { echo "*** La sintesis fallo: revisa los ERROR de arriba ***"; exit 1; }
	$(RUN) $(LOADER) -b tangprimer25k -m $(P2)/impl/pnr/project.fs

sim-paso2:
	mkdir -p $(B)
	$(RUN) $(IVERILOG) -g2012 -o $(B)/tb_paso2.vvp sim/tb_paso2.v rtl/perip_hub75/hub75_tick.v \
	  rtl/perip_hub75/hub75_framebuffer.v rtl/perip_hub75/hub75_barrido.v
	$(RUN) $(VVP) -n $(B)/tb_paso2.vvp

sim-paso3:
	mkdir -p $(B)
	$(RUN) $(IVERILOG) -g2012 -o $(B)/tb_paso3.vvp sim/tb_paso3.v rtl/perip_hub75/hub75_tick.v \
	  rtl/perip_hub75/hub75_framebuffer.v rtl/perip_hub75/hub75_barrido.v
	$(RUN) $(VVP) -n $(B)/tb_paso3.vvp

HUB75_RTL := rtl/perip_hub75/perip_hub75.v rtl/perip_hub75/hub75_csr.v rtl/perip_hub75/hub75_tick.v \
             rtl/perip_hub75/hub75_framebuffer.v rtl/perip_hub75/hub75_barrido.v

sim-paso4:
	mkdir -p $(B)
	$(RUN) $(IVERILOG) -g2012 -o $(B)/tb_paso4.vvp sim/tb_paso4.v $(HUB75_RTL)
	$(RUN) $(VVP) -n $(B)/tb_paso4.vvp
