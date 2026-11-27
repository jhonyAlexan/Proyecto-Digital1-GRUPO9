# G1 - Comunicacion | Simulacion del receptor UART de trama de 32 bits
#   make sim   -> compila y corre el testbench (iverilog + vvp)
#   make wave  -> abre las formas de onda en GTKWave
#   make clean -> borra archivos generados

RTL = ../rtl/uart_rx_dp.v ../rtl/uart_rx_ctrl.v ../rtl/trama_dp.v \
      ../rtl/trama_ctrl.v ../rtl/uart_rx_g1.v
TB  = uart_rx_g1_TB.v
OUT = uart_rx_g1_TB.vvp
VCD = uart_rx_g1_TB.vcd

all: sim

sim: $(OUT)
	vvp -n $(OUT)

$(OUT): $(RTL) $(TB)
	iverilog -g2005 -Wall -o $(OUT) $(RTL) $(TB)

wave: sim
	gtkwave $(VCD) uart_rx_g1_sim.gtkw &

clean:
	rm -f $(OUT) $(VCD)

.PHONY: all sim wave clean
