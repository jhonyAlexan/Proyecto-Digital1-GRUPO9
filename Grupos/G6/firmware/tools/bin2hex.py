#!/usr/bin/env python3
# Convierte firmware.bin en firmware.hex (una palabra de 32 bits por linea)
# para cargarlo en la RAM del SoC con $readmemh.
# Uso: python3 bin2hex.py firmware.bin firmware.hex 8192
import sys

datos = open(sys.argv[1], "rb").read()
palabras = int(sys.argv[3])
datos += b"\0" * (-len(datos) % 4)
n = len(datos) // 4
if n > palabras:
    sys.exit("el programa no cabe en la RAM")

with open(sys.argv[2], "w") as f:
    for i in range(palabras):
        if i < n:
            w = int.from_bytes(datos[4 * i:4 * i + 4], "little")
        else:
            w = 0
        f.write("%08x\n" % w)

print(sys.argv[2], ":", n * 4, "bytes de programa")
