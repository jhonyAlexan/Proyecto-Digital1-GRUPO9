# Firmware de pruebas de la consola en la FPGA (G6)
# Usa los registros y la lectura de los mandos del juego (../firmware).
#   make                 genera pruebas.hex para el reloj de 27 MHz del SoC (Tang Nano 9K)
#   make CPU_HZ=25000000 si el SoC corre a otra frecuencia
CROSS   = riscv64-unknown-elf
CC      = $(CROSS)-gcc
LD      = $(CROSS)-ld
OBJCOPY = $(CROSS)-objcopy
FW      = ../firmware
CPU_HZ ?= 27000000

CFLAGS  = -march=rv32i -mabi=ilp32 -O2 -ffreestanding -fno-builtin -fno-pic -I$(FW) -DCPU_HZ=$(CPU_HZ)
LDFLAGS = -m elf32lriscv --no-relax -T $(FW)/linker.ld

all: pruebas.hex

crt0.o: $(FW)/crt0.S
	$(CC) -march=rv32i -mabi=ilp32 -c $< -o $@

pruebas.o: pruebas.c $(FW)/hardware.h $(FW)/controles.h
	$(CC) $(CFLAGS) -c $< -o $@

controles.o: $(FW)/controles.c $(FW)/controles.h
	$(CC) $(CFLAGS) -c $< -o $@

pruebas.elf: crt0.o pruebas.o controles.o
	$(LD) $(LDFLAGS) $^ -o $@

pruebas.hex: pruebas.elf
	$(OBJCOPY) -O binary $< pruebas.bin
	python3 $(FW)/tools/bin2hex.py pruebas.bin $@ 8192

clean:
	rm -f *.o *.elf *.bin pruebas.hex
