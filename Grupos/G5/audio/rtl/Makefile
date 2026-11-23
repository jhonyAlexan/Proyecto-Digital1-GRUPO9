# Simulación del periférico de audio con Icarus Verilog y GTKWave.
#   make        compila y simula (imprime PASA o NO PASA)
#   make wave   abre las formas de onda en GTKWave
#   make clean  borra lo generado
RTL = peripheral_audio.v audio_regs.v audio_tiempos.v audio_nco.v i2s_tx.v
TB  = tb_audio.v

all: sim

tb_audio.vvp: $(RTL) $(TB)
	iverilog -g2012 -Wall -Wno-timescale -o $@ $(TB) $(RTL)

sim: tb_audio.vvp
	vvp -n tb_audio.vvp

wave: sim
	gtkwave tb_audio.vcd audio.gtkw &

clean:
	rm -f tb_audio.vvp tb_audio.vcd

.PHONY: all sim wave clean
