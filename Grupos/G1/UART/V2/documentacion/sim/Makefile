# G1 - Comunicacion | Simulaciones de V2/documentacion
#   make filas        banco del periferico por el bus, 27 MHz (cobertura por fila)
#   make filas25      el mismo banco a 25 MHz (reloj que usa el G4)
#   make mutantes     5 fallas a proposito: el banco debe detectarlas todas
#   make soc (antes: cd V2 && make soc)   SoC completo con el FemtoRV32 (B.7) y VCD de B.6
#   make wave         GTKWave con las senales de los diagramas de tiempos

RTL = ../rtl/uart_8n1.v ../rtl/desempaquetador.v ../rtl/perip_mandos.v
TB  = tb_perip_mandos_filas.v
# La copia de la consola la arma "make soc" desde V2 (V2/build/consola)
CONSOLA ?= ../../build/consola

all: filas

filas:
	iverilog -g2012 -o filas.vvp $(RTL) $(TB)
	vvp -n filas.vvp

filas25:
	iverilog -g2012 -DCLK25 -o filas25.vvp $(RTL) $(TB)
	vvp -n filas25.vvp

mutantes:
	bash mutantes.sh

soc:
	cp tb_soc_mandos_tiempos.v $(CONSOLA)/sim/
	cd $(CONSOLA) && iverilog -g2012 -DBENCH -o build/tb_soc_mandos_tiempos.vvp -s tb_soc_mandos_tiempos \
	  sim/tb_soc_mandos_tiempos.v rtl/SOC.v rtl/chip_select.v rtl/cpu/femtorv32_quark.v rtl/memory/Memory.v \
	  rtl/uart/perip_uart.v rtl/uart/uart.v rtl/mult/perip_mult.v rtl/mult/mult.v \
	  rtl/mandos/uart_8n1.v rtl/mandos/desempaquetador.v rtl/perip_gpio.v rtl/perip_mandos.v && \
	  vvp -n build/tb_soc_mandos_tiempos.vvp | grep -v readmemh

wave: filas
	gtkwave tb_perip_mandos_filas.vcd tiempos_mandos.gtkw &

clean:
	rm -f *.vvp *.vcd

.PHONY: all filas filas25 mutantes soc wave clean
