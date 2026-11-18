# Firmware de la consola - juego de pelea (grupo negro)
CROSS   = riscv64-unknown-elf
CC      = $(CROSS)-gcc
LD      = $(CROSS)-ld
OBJCOPY = $(CROSS)-objcopy

# solo RV32I, igual que el ejemplo del curso
CFLAGS  = -march=rv32i -mabi=ilp32 -O2 -ffreestanding -fno-builtin -fno-pic
LDFLAGS = -m elf32lriscv --no-relax -T linker.ld

OBJS = crt0.o main.o juego.o controles.o pantalla.o hardware.o

all: firmware.hex

%.o: %.c *.h
	$(CC) $(CFLAGS) -c $< -o $@

crt0.o: crt0.S
	$(CC) -march=rv32i -mabi=ilp32 -c $< -o $@

firmware.elf: $(OBJS)
	$(LD) $(LDFLAGS) $(OBJS) -o $@

firmware.hex: firmware.elf
	$(OBJCOPY) -O binary $< firmware.bin
	python3 tools/bin2hex.py firmware.bin $@ 8192

# beta para el navegador
web: ../web/juego.wasm

../web/juego.wasm: juego.c controles.c pantalla.c ../web/hardware_web.c *.h
	clang --target=wasm32 -O2 -nostdlib -I. -Wl,--no-entry -Wl,--export-dynamic \
	  -o $@ juego.c controles.c pantalla.c ../web/hardware_web.c

clean:
	rm -f *.o *.elf *.bin firmware.hex ../web/juego.wasm
