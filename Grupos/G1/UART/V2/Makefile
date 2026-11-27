# =============================================================================
# G1 - UART V2 | Todas las simulaciones de esta carpeta (Icarus Verilog 12+)
#
#   make sim          corre todo lo de abajo y termina en error si algo falla
#   make minimo       propuesta_fix_minimo: código de Cesar con 4'h1/4'h2/4'h4 (issue #20)
#   make corregida    propuesta_corregida: mando, com.v y periférico (trama de 8 bytes)
#   make soc          SoC de la consola (FemtoRV + 0x0047) con un programa hecho a mano
#   make v1           mandos_v1: periférico g1_mandos_mmio
#   make docs         documentacion: banco por filas a 27 y 25 MHz y mutantes
#
# No modifica nada fuera de V2: para "make soc" copia projecto/consola del repo a
# build/consola y le pone encima los archivos de propuesta_corregida/soc_consola.
# =============================================================================
SHELL := /bin/bash
B     := build
REPO  ?= ../../../..
CONSOLA_REPO := $(REPO)/projecto/consola

all: sim
sim: minimo corregida soc v1 docs
	@echo "=== V2: todas las simulaciones pasaron ==="

minimo:
	@mkdir -p $(B)
	cd propuesta_fix_minimo && iverilog -g2012 -o ../$(B)/min_ctrl.vvp -s tb_ctrl sim/tb_ctrl.v rtl/ctrl/*.v
	vvp -n $(B)/min_ctrl.vvp | tee $(B)/min_ctrl.log | grep "TODO OK"; grep -q "TODO OK" $(B)/min_ctrl.log
	cd propuesta_fix_minimo && iverilog -g2012 -o ../$(B)/min_com.vvp -s tb_com sim/tb_com.v boards/tangnano9k/com.v rtl/ctrl/uart_8n1.v rtl/ctrl/desempaquetador.v
	vvp -n $(B)/min_com.vvp | tee $(B)/min_com.log | grep "TODO OK"; grep -q "TODO OK" $(B)/min_com.log

corregida:
	@for t in sim_ctrl sim_com sim_mandos; do \
	  $(MAKE) -s -C propuesta_corregida $$t > $(B)/$$t.log 2>&1 || { cat $(B)/$$t.log; exit 1; }; \
	  grep "TODO OK" $(B)/$$t.log || { cat $(B)/$$t.log; exit 1; }; done

soc:
	@test -d $(CONSOLA_REPO) || { echo "No encuentro $(CONSOLA_REPO); use make soc REPO=<raiz del repo>"; exit 1; }
	rm -rf $(B)/consola && mkdir -p $(B) && cp -r $(CONSOLA_REPO) $(B)/consola
	cp -r propuesta_corregida/soc_consola/. $(B)/consola/
	$(MAKE) -s -C $(B)/consola sim_mandos | tee $(B)/soc.log | tail -2; grep -q "TODO OK" $(B)/soc.log

v1:
	$(MAKE) -s -C mandos_v1/sim test | tee $(B)/v1.log | grep Resultado; grep -q " 0 FALLOS" $(B)/v1.log

docs:
	$(MAKE) -s -C documentacion/sim filas filas25 | grep RESULTADO
	$(MAKE) -s -C documentacion/sim mutantes | tail -1

clean:
	rm -rf $(B) propuesta_corregida/build $(B)
	$(MAKE) -s -C mandos_v1/sim clean
	$(MAKE) -s -C documentacion/sim clean

.PHONY: all sim minimo corregida soc v1 docs clean
