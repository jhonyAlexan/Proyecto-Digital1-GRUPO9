# Joystick, lado FPGA del mando: simulación y prueba en la Tang Nano 9K.
#   make           simula el mando con un modelo de la ESP32 e imprime PASA o NO PASA
#   make wave      abre las formas de onda en GTKWave
#   make syn       sintetiza, ubica y empaqueta: build/tangnano9k.fs
#   make recursos  muestra los recursos usados y la frecuencia máxima
#   make config    carga el diseño en la tarjeta (se pierde al desconectarla)
#   make clean     borra lo generado
# La síntesis usa el mismo flujo del laboratorio FemtoRV: yosys, nextpnr-himbaechel,
# gowin_pack y openFPGALoader.
RTL = joystick_mando.v joystick_solicitud.v joystick_uart_tx.v joystick_uart_rx.v \
      joystick_rx_sync.v joystick_ensamblador.v joystick_validador.v joystick_registros_xy.v
TB  = tb_joystick_mando.v
IVERILOG = iverilog -g2012 -Wall -Wno-timescale
PLACA = placas/tangnano9k
B = build

# Activa el entorno del curso si está instalado (igual que en el laboratorio FemtoRV)
ifneq ($(shell command -v digital-logic-design 2>/dev/null),)
RUN ?= source digital-logic-design activate >/dev/null &&
else
RUN ?=
endif
SHELL := /bin/bash

all: sim

tb_joystick_mando.vvp: $(RTL) $(TB)
	$(IVERILOG) -o $@ $(TB) $(RTL)

sim: tb_joystick_mando.vvp
	vvp -n tb_joystick_mando.vvp

wave: sim
	gtkwave tb_joystick_mando.vcd &

$(B)/tangnano9k.fs: $(RTL) $(PLACA)/top_joystick_tangnano9k.v $(PLACA)/tangnano9k.cst
	mkdir -p $(B)
	$(RUN) yosys -q -p "synth_gowin -top top_joystick_tangnano9k -json $(B)/tangnano9k.json" \
	  $(RTL) $(PLACA)/top_joystick_tangnano9k.v -l $(B)/yosys.log
	$(RUN) nextpnr-himbaechel --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C \
	  --vopt cst=$(PLACA)/tangnano9k.cst --freq 27 \
	  --json $(B)/tangnano9k.json --write $(B)/tangnano9k_pnr.json -l $(B)/nextpnr.log 2> /dev/null \
	  || { echo "nextpnr falló: mira $(B)/nextpnr.log"; exit 1; }
	$(RUN) gowin_pack -d GW1N-9C -o $@ $(B)/tangnano9k_pnr.json

syn: $(B)/tangnano9k.fs

recursos: $(B)/tangnano9k.fs
	@grep -A 30 "Device utilisation" $(B)/nextpnr.log | grep -E "IOB|LUT4|ALU|DFF|BSRAM" | grep -v ": *0/"
	@grep "Max frequency" $(B)/nextpnr.log | tail -1

config: $(B)/tangnano9k.fs
	$(RUN) openFPGALoader -b tangnano9k $(B)/tangnano9k.fs

clean:
	rm -rf tb_joystick_mando.vvp tb_joystick_mando.vcd $(B)

.PHONY: all sim wave syn recursos config clean
