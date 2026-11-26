#!/bin/sh
# Simula pruebas.hex (o el juego) en el procesador del curso (femtorv32_quark.v)
# con Icarus Verilog y modelos de los perifericos.
# Uso: sh correr.sh RUTA/femtorv32_quark.v          -> pruebas
#      sh correr.sh RUTA/femtorv32_quark.v juego    -> juego (firmware.hex, tarda unos minutos)
# Deja los cuadros guardados como .txt (un digito por pixel) y muestra los sonidos.
set -e
CPU=${1:?falta la ruta de femtorv32_quark.v}
FW=../../firmware
if [ "$2" = "juego" ]; then
  make -s -C $FW
  cp $FW/firmware.hex juego.hex
  iverilog -g2012 -o sim -DHEX='"juego.hex"' -DFRAME_CYC=200000 -DTRAMA_NS=1780000 \
    -DESCENARIO='"escenario_juego.vh"' tb_consola.v "$CPU"
else
  CC="riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -O2 -ffreestanding -fno-builtin -fno-pic -I$FW"
  # reloj y tiempos cortos para que la simulacion no tarde horas
  SIM="-DCPU_HZ=600000 -DCUADROS_POR_EFECTO=4 -DCUADROS_CAMBIO=6"
  riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -c $FW/crt0.S -o crt0.o
  $CC $SIM -c ../pruebas.c -o pruebas.o
  $CC -c $FW/controles.c -o controles.o
  riscv64-unknown-elf-ld -m elf32lriscv --no-relax -T $FW/linker.ld crt0.o pruebas.o controles.o -o sim.elf
  riscv64-unknown-elf-objcopy -O binary sim.elf sim.bin
  python3 $FW/tools/bin2hex.py sim.bin pruebas.hex 8192
  iverilog -g2012 -o sim tb_consola.v "$CPU"
fi
vvp -n sim
