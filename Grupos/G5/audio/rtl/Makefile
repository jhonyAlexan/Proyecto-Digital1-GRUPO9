# Simulación del periférico de audio con Icarus Verilog y GTKWave.
#   make         simula con clk = 27 MHz (CICLOS_BCLK = 18) e imprime PASA o NO PASA
#   make sim25   lo mismo con clk = 25 MHz (CICLOS_BCLK = 16)
#   make wave    abre las formas de onda en GTKWave
#   make clean   borra lo generado
RTL = peripheral_audio.v audio_regs.v audio_tiempos.v audio_nco.v i2s_tx.v
TB  = tb_audio.v
IVERILOG = iverilog -g2012 -Wall -Wno-timescale

all: sim

tb_audio.vvp: $(RTL) $(TB)
	$(IVERILOG) -o $@ $(TB) $(RTL)

tb_audio25.vvp: $(RTL) $(TB)
	$(IVERILOG) -P tb_audio.CICLOS_BCLK=16 -P tb_audio.T_CLK=40000 -o $@ $(TB) $(RTL)

sim: tb_audio.vvp
	vvp -n tb_audio.vvp

sim25: tb_audio25.vvp
	vvp -n tb_audio25.vvp

wave: sim
	gtkwave tb_audio.vcd audio.gtkw &

clean:
	rm -f tb_audio.vvp tb_audio25.vvp tb_audio.vcd

.PHONY: all sim sim25 wave clean
