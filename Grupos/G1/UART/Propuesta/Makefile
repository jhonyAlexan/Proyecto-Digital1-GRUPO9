# =============================================================================
# Makefile del SoC FemtoRV + mando UART (empaquetador / uart_8n1 / desempaquetador)
# Laboratorio de RISC-V — Tang Nano 9K
#
# Uso básico (escriba "make help" para ver todo):
#   make sim                         compila el programa y simula el SoC
#   make sim_ctrl                    simula el mando (lazo cerrado de la UART)
#   make syn                         sintetiza el SoC para la Tang Nano 9K
#   make syn_ctrl                    sintetiza solo el mando para la Tang Nano 9K
#   make config                      configura la FPGA con el SoC
#   make config_ctrl                 configura la FPGA con el mando
#   make terminal                    abre la terminal serial (salir: Ctrl-a Ctrl-x)
#
# Variables que se pueden cambiar en la línea de comandos:
#   BOARD   colorlight | tangnano9k      (por defecto tangnano9k)
#   PROG    nombre del programa en firmware/, sin .c   (por defecto hola)
#   ARGS    opciones del testbench, ej. ARGS="+vcd +botones=1"
# =============================================================================
SHELL := /bin/bash
.ONESHELL:

BOARD ?= tangnano9k
PROG  ?= hola
ARGS  ?=

# --- Entorno de herramientas del curso -------------------------------------
# Si existe el lanzador del curso, se activa antes de cada comando.
ifneq ($(shell command -v digital-logic-design 2>/dev/null),)
RUN ?= source digital-logic-design activate >/dev/null &&
else
RUN ?=
endif

# --- Nombres de las herramientas -------------------------------------------
CROSS     ?= riscv64-unknown-elf-
YOSYS     ?= yosys
IVERILOG  ?= iverilog
VVP       ?= vvp
GTKWAVE   ?= gtkwave
NEXTPNR_ECP5  ?= nextpnr-ecp5
ECPPACK       ?= ecppack
NEXTPNR_GOWIN ?= nextpnr-himbaechel
GOWIN_PACK    ?= gowin_pack
LOADER    ?= openFPGALoader
RTL_GEN   ?= netlist2svg

# --- Archivos ---------------------------------------------------------------
B   := build
RTL := rtl/SOC.v rtl/chip_select.v rtl/cpu/femtorv32_quark.v rtl/memory/Memory.v \
       rtl/uart/perip_uart.v rtl/uart/uart.v rtl/mult/perip_mult.v rtl/mult/mult.v
# Semana 2: los periféricos nuevos que se pongan en rtl/ se agregan solos
RTL += $(filter-out $(RTL),$(wildcard rtl/perip_*.v))

# Mando UART (no se mezcla con el SoC; uart_8n1 evita chocar con el módulo "uart")
CTRL     := rtl/ctrl/empaquetador.v rtl/ctrl/uart_8n1.v rtl/ctrl/desempaquetador.v
CTRL_BIT := $(B)/ctrl.fs

RAM_PALABRAS := 8192

# Icarus Verilog 13 o más reciente (el de OSS CAD Suite) rechaza usar una señal
# antes de declararla, y el FemtoRV Quark lo hace. Si esta versión de iverilog
# acepta la opción para permitirlo, se usa; las versiones anteriores no la necesitan.
IV_RELAX := $(shell bash -c '$(RUN) $(IVERILOG) -gno-strict-declaration -E -o /dev/null /dev/null' >/dev/null 2>&1 && echo -gno-strict-declaration -Wno-declaration-after-use)
CFLAGS := -march=rv32i -mabi=ilp32 -Os -g -ffreestanding -nostdlib \
          -ffunction-sections -fdata-sections -Wall

.PHONY: help firmware sim sim_ctrl sim_com wave rtl syn syn_ctrl config config_ctrl config-flash terminal stats clean

help:
	@echo ""
	@echo "  make firmware            Compila firmware/$(PROG).c -> firmware.hex y build/firmware.lst"
	@echo "  make sim                 Compila y simula; muestra lo que el programa envía por la UART"
	@echo "  make sim ARGS=+vcd       Además guarda formas de onda; luego: make wave"
	@echo "  make sim_ctrl            Simula el mando: empaquetador -> UART -> desempaquetador"
	@echo "  make sim_com             Simula el top com.v (reset, UART, LEDs)"
	@echo "  make wave                Abre las formas de onda en GTKWave"
	@echo "  make rtl                 Diagrama RTL del SoC (build/SOC.svg)"
	@echo "  make syn BOARD=...       Síntesis, place & route y bitstream (colorlight | tangnano9k)"
	@echo "  make syn_ctrl            Síntesis del mando solo para la Tang Nano 9K"
	@echo "  make stats BOARD=...     Recursos usados y frecuencia máxima"
	@echo "  make config BOARD=...    Configura la FPGA (volátil: se pierde al apagar)"
	@echo "  make config_ctrl         Configura la Tang Nano 9K con el mando"
	@echo "  make config-flash ...    Configura la memoria flash (permanente)"
	@echo "  make terminal BOARD=...  Terminal serial a 115200 baudios (salir: Ctrl-a Ctrl-x)"
	@echo "  make clean               Borra los archivos generados"
	@echo ""
	@echo "  Otro programa:  make sim PROG=gpio    (usa firmware/gpio.c)"
	@echo ""

# =============================================================================
# 1. FIRMWARE: C -> código máquina RISC-V -> firmware.hex
# =============================================================================
firmware: firmware.hex

firmware.hex: firmware/$(PROG).c firmware/soc.h firmware/crt0.S firmware/linker.ld
	mkdir -p $(B)
	# Compilar y enlazar (crt0.S prepara la pila y llama a main)
	$(RUN) $(CROSS)gcc $(CFLAGS) -T firmware/linker.ld -Wl,--gc-sections \
	  -Wl,-Map=$(B)/firmware.map firmware/crt0.S firmware/$(PROG).c -lgcc -o $(B)/firmware.elf
	# Listado: cada línea de C con las instrucciones RISC-V que generó
	$(RUN) $(CROSS)objdump -d -S $(B)/firmware.elf > $(B)/firmware.lst
	# Binario puro y conversión a palabras de 32 bits para $$readmemh
	$(RUN) $(CROSS)objcopy -O binary $(B)/firmware.elf $(B)/firmware.bin
	python3 firmware/tools/bin2hex.py $(B)/firmware.bin firmware.hex $(RAM_PALABRAS)
	echo "$(PROG)" > $(B)/prog.txt

# Recompilar si cambia el programa elegido
ifneq ($(shell cat $(B)/prog.txt 2>/dev/null),$(PROG))
.PHONY: firmware.hex
endif

# =============================================================================
# 2. SIMULACIÓN
# =============================================================================
sim: firmware.hex
	mkdir -p $(B)
	# -DBENCH: en simulación, inicializa registros internos del CPU que en la FPGA arrancan en 0
	$(RUN) $(IVERILOG) -g2012 $(IV_RELAX) -DBENCH -o $(B)/tb_soc.vvp -s tb_soc sim/tb_soc.v $(RTL)
	$(RUN) $(VVP) -n $(B)/tb_soc.vvp $(ARGS) | grep -v "readmemh"

# Mando UART: lazo cerrado, no necesita firmware ni el SoC
sim_ctrl:
	mkdir -p $(B)
	$(RUN) $(IVERILOG) -g2012 -o $(B)/tb_ctrl.vvp -s tb_ctrl sim/tb_ctrl.v $(CTRL)
	$(RUN) $(VVP) -n $(B)/tb_ctrl.vvp $(ARGS)

# Top com.v (con reset automático y LEDs): se golpea uart_rx como lo haría el ESP32
sim_com:
	mkdir -p $(B)
	$(RUN) $(IVERILOG) -g2012 -o $(B)/tb_com.vvp -s tb_com sim/tb_com.v boards/tangnano9k/com.v rtl/ctrl/uart_8n1.v rtl/ctrl/desempaquetador.v
	$(RUN) $(VVP) -n $(B)/tb_com.vvp $(ARGS)

wave:
	$(RUN) $(GTKWAVE) $(B)/tb_soc.vcd &

rtl:
	mkdir -p $(B)
	$(RUN) $(YOSYS) -q -p "prep -top SOC; write_json $(B)/SOC.json" $(RTL)
	$(RUN) $(RTL_GEN) $(B)/SOC.json -o $(B)/SOC.svg
	@echo "Diagrama: $(B)/SOC.svg"

# =============================================================================
# 3. SÍNTESIS POR TARJETA
# =============================================================================
ifeq ($(BOARD),colorlight)
TOP       := top_colorlight
BITSTREAM := $(B)/colorlight.bit
PORT      ?= /dev/ttyUSB0
# JTAG con FT232RL, igual que en el repositorio: TDI:TDO:TCK:TMS = TXD:CTS:DTR:RXD
CABLE_PINES ?= 0:3:4:1

$(BITSTREAM): firmware.hex $(RTL) boards/colorlight/top_colorlight.v boards/colorlight/colorlight.lpf
	mkdir -p $(B)
	$(RUN) $(YOSYS) -p "synth_ecp5 -top $(TOP) -json $(B)/colorlight.json" \
	  $(RTL) boards/colorlight/top_colorlight.v -l $(B)/yosys.log > /dev/null
	$(RUN) $(NEXTPNR_ECP5) --25k --package CABGA256 --speed 6 --freq 25 \
	  --json $(B)/colorlight.json --lpf boards/colorlight/colorlight.lpf \
	  --textcfg $(B)/colorlight.config -l $(B)/nextpnr.log 2> /dev/null
	$(RUN) $(ECPPACK) $(B)/colorlight.config $(BITSTREAM)
	@$(MAKE) --no-print-directory stats BOARD=$(BOARD)

config:
	$(RUN) $(LOADER) -c ft232RL --pins=$(CABLE_PINES) --freq 3000000 -m $(BITSTREAM)
config-flash:
	$(RUN) $(LOADER) -c ft232RL --pins=$(CABLE_PINES) --freq 3000000 -f $(BITSTREAM) --unprotect-flash

else ifeq ($(BOARD),tangnano9k)
TOP       := top_tangnano9k
BITSTREAM := $(B)/tangnano9k.fs
# La Tang Nano crea dos puertos: el primero es JTAG, el segundo la UART
PORT      ?= /dev/ttyUSB1

$(BITSTREAM): firmware.hex $(RTL) boards/tangnano9k/top_tangnano9k.v boards/tangnano9k/tangnano9k.cst
	mkdir -p $(B)
	$(RUN) $(YOSYS) -p "synth_gowin -top $(TOP) -json $(B)/tangnano9k.json" \
	  $(RTL) boards/tangnano9k/top_tangnano9k.v -l $(B)/yosys.log > /dev/null
	$(RUN) $(NEXTPNR_GOWIN) --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C \
	  --vopt cst=boards/tangnano9k/tangnano9k.cst --freq 27 \
	  --json $(B)/tangnano9k.json --write $(B)/tangnano9k_pnr.json -l $(B)/nextpnr.log 2> /dev/null
	$(RUN) $(GOWIN_PACK) -d GW1N-9C -o $(BITSTREAM) $(B)/tangnano9k_pnr.json
	@$(MAKE) --no-print-directory stats BOARD=$(BOARD)

config:
	$(RUN) $(LOADER) -b tangnano9k $(BITSTREAM)
config-flash:
	$(RUN) $(LOADER) -b tangnano9k -f $(BITSTREAM)

else
$(error BOARD debe ser colorlight o tangnano9k)
endif

syn: $(BITSTREAM)
	@echo "Bitstream listo: $(BITSTREAM)  (si no cambió nada, make no vuelve a sintetizar)"

stats:
	@echo ""
	@echo "=== Recursos usados ($(BOARD)) ==="
	@grep -A40 "Device utilisation" $(B)/nextpnr.log | grep -E "LUT4|TRELLIS_COMB|TRELLIS_FF|DFF:|DP16KD|BSRAM|IOB:|TRELLIS_IO" | sed 's/Info://'
	@echo "=== Frecuencia máxima ==="
	@grep "Max frequency" $(B)/nextpnr.log | tail -1 | sed 's/Info://'

# =============================================================================
# 4. MANDO UART SOLO (Tang Nano 9K), independiente del SoC y del firmware
#    Top: boards/tangnano9k/com.v   Pines: boards/tangnano9k/com.cst
# =============================================================================
$(CTRL_BIT): $(CTRL) boards/tangnano9k/com.v boards/tangnano9k/com.cst
	mkdir -p $(B)
	$(RUN) $(YOSYS) -p "synth_gowin -top com -json $(B)/ctrl.json" \
	  $(CTRL) boards/tangnano9k/com.v -l $(B)/yosys_ctrl.log > /dev/null
	$(RUN) $(NEXTPNR_GOWIN) --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C \
	  --vopt cst=boards/tangnano9k/com.cst --freq 27 \
	  --json $(B)/ctrl.json --write $(B)/ctrl_pnr.json -l $(B)/nextpnr_ctrl.log 2> /dev/null
	$(RUN) $(GOWIN_PACK) -d GW1N-9C -o $(CTRL_BIT) $(B)/ctrl_pnr.json
	@echo "Bitstream listo: $(CTRL_BIT)"

syn_ctrl: $(CTRL_BIT)

config_ctrl: $(CTRL_BIT)
	$(RUN) $(LOADER) -b tangnano9k $(CTRL_BIT)

terminal:
	$(RUN) picocom -b 115200 $(PORT)

clean:
	rm -rf $(B) firmware.hex
