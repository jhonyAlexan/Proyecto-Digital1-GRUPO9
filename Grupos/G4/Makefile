# =============================================================================
# Makefile de G4 (Pantalla HUB75)
#
#   make sim-core     banco del core (tabla de transferencias)
#   make sim-regs     banco de los registros MMIO
#   make wave-core    simula el core guardando el VCD y abre GTKWave
#   make wave-regs    simula los registros y abre el handshake del bus en GTKWave
#   make syn BOARD=tangprimer25k      prueba sin CPU en la Tang Primer 25K (Gowin)
#   make config BOARD=tangprimer25k   carga esa prueba en la FPGA (SRAM)
#   make clean
# =============================================================================
B        := build
IVERILOG ?= iverilog
VVP      ?= vvp
GTKWAVE  ?= gtkwave
LOADER   ?= openFPGALoader
BOARD    ?= tangprimer25k
GOWIN_SH ?= /home/tuklaptop/opt/gowin/IDE/bin/gw_sh

GOWIN_ENV ?= PATH=/usr/bin:/bin LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libfreetype.so.6 LD_LIBRARY_PATH="/home/tuklaptop/opt/gowin/IDE/lib"

CORE := rtl/hub75_core.v
PERIF := rtl/peripheral_hub75.v

.PHONY: sim-core sim-regs wave-core wave-regs syn config clean

sim-core:
	mkdir -p $(B)
	$(IVERILOG) -g2012 -o $(B)/tb_hub75_core.vvp rtl/tb/tb_hub75_core.v $(CORE)
	$(VVP) -n $(B)/tb_hub75_core.vvp

sim-regs:
	mkdir -p $(B)
	$(IVERILOG) -g2012 -o $(B)/tb_peripheral_hub75.vvp rtl/tb/tb_peripheral_hub75.v $(PERIF) $(CORE)
	$(VVP) -n $(B)/tb_peripheral_hub75.vvp

wave-core:
	mkdir -p $(B)
	$(IVERILOG) -g2012 -o $(B)/tb_hub75_core.vvp rtl/tb/tb_hub75_core.v $(CORE)
	$(VVP) -n $(B)/tb_hub75_core.vvp +vcd
	$(GTKWAVE) $(B)/tb_hub75_core.vcd sim/core.gtkw &

wave-regs:
	mkdir -p $(B)
	$(IVERILOG) -g2012 -o $(B)/tb_peripheral_hub75.vvp rtl/tb/tb_peripheral_hub75.v $(PERIF) $(CORE)
	$(VVP) -n $(B)/tb_peripheral_hub75.vvp +vcd
	$(GTKWAVE) $(B)/tb_peripheral_hub75.vcd sim/regs.gtkw &

# --- Síntesis y programación (mismo estilo que el Makefile del curso) ---------
#   make clean && make syn BOARD=tangprimer25k && make config BOARD=tangprimer25k
ifeq ($(BOARD),tangprimer25k)
TOP       := top_hub75_tangprimer25k
BITSTREAM := $(B)/impl/pnr/project.fs

syn:
	mkdir -p $(B)
	rm -f $(BITSTREAM)
	echo "set_device GW5A-LV25MG121NC1/I0 -device_version A" > $(B)/run.tcl
	echo "add_file ../board/tangprimer25k_hub75.cst" >> $(B)/run.tcl
	echo "add_file ../board/top_hub75_tangprimer25k.v" >> $(B)/run.tcl
	echo "add_file ../rtl/hub75_core.v" >> $(B)/run.tcl
	echo "set_option -top_module $(TOP)" >> $(B)/run.tcl
	echo "set_option -use_cpu_as_gpio 1" >> $(B)/run.tcl
	echo "run all" >> $(B)/run.tcl
	cd $(B) && $(GOWIN_ENV) $(GOWIN_SH) run.tcl
	test -f $(BITSTREAM) || { echo "*** La sintesis fallo: revisa los ERROR de arriba ***"; exit 1; }
	@echo "Bitstream generado: $(BITSTREAM)"

config:
	$(LOADER) -b tangprimer25k -m $(BITSTREAM)

else
syn config:
	@echo "Usa BOARD=tangprimer25k"; exit 1
endif

clean:
	rm -rf $(B)
