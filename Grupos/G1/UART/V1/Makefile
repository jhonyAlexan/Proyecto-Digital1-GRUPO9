#Variables de programa
top    ?= top
tb     ?= $(top)_tb.v

# Todos los archivos Verilog del diseño (todo .v de la carpeta menos los testbench)
# Para este proyecto: top.v, selector_notas.v, nota.v y multiplexor.v
SRCS    = $(filter-out %_tb.v, $(wildcard *.v))
TBN     = $(basename $(notdir $(tb)))

# Placa y chip (Tang Nano 9K)
BOARD  ?= tangnano9k
DEVICE ?= GW1NR-LV9QN88PC6/I5
FAMILY ?= GW1N-9C
PIN    ?= $(top).cst

# Frecuencia del reloj de la placa en MHz (nextpnr la usa para revisar el timing)
FREQ   ?= 27

# Programa que hace el "place and route" (ubica y conecta el diseño dentro del chip)
NEXTPNR ?= yowasp-nextpnr-gowin

# Archivos de carga
DIR_BUILD = build
JSON      = $(DIR_BUILD)/$(top).json
PNR       = $(DIR_BUILD)/$(top)_pnr.json
BITSTREAM = $(DIR_BUILD)/$(top).fs
RTL_SVG   = $(DIR_BUILD)/$(top)_rtl.svg

# Lo que se ejecuta al escribir solo "make"
all: syn

#Ayuda
help:
	@echo "Uso: make <comando> [variable=valor]"
	@echo ""
	@echo "Comandos:"
	@echo "  help    Muestra esta ayuda"
	@echo "  detect  Detecta la placa por JTAG (openFPGALoader --detect)"
	@echo "  test    Compila y corre el testbench (iverilog + vvp)"
	@echo "  wave    Corre el test y abre las ondas en GTKWave"
	@echo "  syn     Genera el bitstream (yosys -> nextpnr -> gowin_pack)"
	@echo "  config  Carga el bitstream en SRAM (se pierde al apagar)"
	@echo "  flash   Graba el bitstream en la flash (permanente)"
	@echo "  rtl     Genera un diagrama RTL en SVG (yosys show)"
	@echo "  clean   Borra las carpetas build/ y sim/"
	@echo ""
	@echo "Variables actuales (se pueden cambiar, ej: make syn top=otro):"
	@echo "  top     = $(top)"
	@echo "  tb      = $(tb)"
	@echo "  SRCS    = $(SRCS)"
	@echo "  BOARD   = $(BOARD)"
	@echo "  NEXTPNR = $(NEXTPNR)"


#Placa
detect:
	openFPGALoader -b $(BOARD) --detect


# Simulación y prueba
test:
	mkdir -p sim
	iverilog -o sim/$(TBN) -s $(TBN) $(SRCS) $(tb)
	vvp sim/$(TBN)

wave: test
	gtkwave sim/$(TBN).vcd


#Síntesis
syn: $(BITSTREAM)

$(JSON): $(SRCS)
	mkdir -p $(DIR_BUILD)
	yosys -p "read_verilog $(SRCS); synth_gowin -top $(top) -json $@"

$(PNR): $(JSON) $(PIN)
ifeq ($(NEXTPNR),nextpnr-himbaechel)
	$(NEXTPNR) --json $< --write $@ --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(PIN) --freq $(FREQ)
else
	$(NEXTPNR) --json $< --write $@ --device $(DEVICE) --family $(FAMILY) --cst $(PIN) --freq $(FREQ)
endif

$(BITSTREAM): $(PNR)
	gowin_pack -d $(FAMILY) -o $@ $<

#Diagrama RTL
rtl: $(SRCS)
	mkdir -p $(DIR_BUILD)
	yosys -q -p "read_verilog $(SRCS); prep -top $(top); flatten; opt; show -stretch -format svg -prefix $(DIR_BUILD)/$(top)_rtl $(top)"
	xdg-open $(RTL_SVG)

# Programar FPGA
# config: carga en SRAM (se pierde al apagar)
config: $(BITSTREAM)
	openFPGALoader -b $(BOARD) $<

# flash: queda grabado de forma permanente
flash: $(BITSTREAM)
	openFPGALoader -b $(BOARD) -f $<

#Limpieza
clean:
	rm -rf $(DIR_BUILD) sim

.PHONY: all detect test wave syn config flash clean help rtl
