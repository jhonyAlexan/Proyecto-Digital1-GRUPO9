# G1 · UART V2 (respaldo del trabajo del G1)

Esta carpeta reúne todo lo que el G1 ha trabajado para la comunicación de los mandos (UART + enlace inalámbrico) en un solo lugar. **No cambia nada de lo que ya está en el repositorio**: `Propuesta/` (Cesar), `V1/` y `projecto/consola` quedan igual. Lo que aquí aparece corregido está corregido solo dentro de V2.

## Qué hay en cada subcarpeta

| Carpeta | Qué es | Origen |
| --- | --- | --- |
| [`propuesta_fix_minimo/`](propuesta_fix_minimo/) | El código de `Propuesta/` de Cesar **tal cual**, cambiando solo los parámetros que no compilaban (issue #20). Protocolo de pares dirección/valor de 2 bytes. | `Propuesta/rtl/ctrl`, `sim`, `boards` |
| [`propuesta_corregida/`](propuesta_corregida/) | La propuesta de Cesar llevada a la **trama de 8 bytes del G5**, con escudo, más el periférico `peripheral_mandos` para el SoC (`0x0047`) y los archivos que cambian en el SoC de la consola (`soc_consola/`). Es la versión que funciona con el juego del G6. Tiene su propio README con los cambios archivo por archivo. | corrección del 27-nov |
| [`mandos_v1/`](mandos_v1/) | Versión `g1_` del periférico (receptor UART, armado de trama, registros), prueba en Tang Nano 9K con LEDs y los programas de las ESP32 (mando y consola) con ESP-NOW. Incluye la variante para **ESP32-C3 Super Mini** (issue #21). | trabajo del 26-nov |
| [`documentacion/`](documentacion/) | Las etapas de diseño de la guía (A1–A9 de `uart.pdf` y B1–B8 de `uart-riscv.pdf`) para la trama de 8 bytes: caja negra, bloques, tiempos, flujo, ASMD, arquitectura, FSM, testbench, mapa de chip select, pines. Diagramas en `diagramas/` (con sus fuentes), RTL de referencia y bancos de prueba. La versión vieja de 4 bytes está en `anterior_trama_4bytes/`. | `docs_G1` |
| `Makefile` | Corre todas las simulaciones de V2 de una vez. | nuevo |

## Issue #20: parámetros que no compilaban

En `empaquetador.v` y `desempaquetador.v` los parámetros quedaron como `4'42`, `4'43` y `4'44`: les falta la base y `0x42` no cabe en 4 bits. Hay dos salidas, y V2 guarda las dos:

1. **Arreglo mínimo** (`propuesta_fix_minimo/`), lo que propuso el G5. Solo cambian esas tres líneas en cada archivo:

   | Dato | Código `PER` (4 bits) | Byte de dirección J1 | Byte de dirección J2 | Byte de valor |
   | --- | --- | --- | --- | --- |
   | X | `4'h1` | `0x11` | `0x12` | X con signo |
   | Y | `4'h2` | `0x21` | `0x22` | Y con signo |
   | Golpe (punch) | `4'h4` | `0x41` | `0x42` | `0x00` o `0x01` |
   | Escudo (comentado) | `4'h8` (libre) | `0x81` | `0x82` | `0x00` o `0x01` |

   El byte de dirección es `{PER, jugador}`. Los códigos 1, 2, 4 y 8 se diferencian en al menos 2 bits, así que un bit volteado no da otra dirección válida. En la consola estos valores irían a los mismos registros de `0x0047_0000` (J1) y `0x0047_0004` (J2) de la tabla de abajo.

2. **Trama de 8 bytes** (`propuesta_corregida/`). Ya no usa códigos `PER`: cada dato va en una posición fija de la trama que acordaron G5 y G6. Es la que recomienda el G1 porque es la que el juego ya lee.

   | Byte | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
   | --- | --- | --- | --- | --- | --- | --- | --- | --- |
   | Campo | `0xAA` | jugador (1/2) | secuencia | X (int8) | Y (int8) | escudo (bit 0) | golpe (bit 0) | XOR de 1 a 6 |

   | Dirección | Registro | Bits |
   | --- | --- | --- |
   | `0x0047_0000` | `JOY1_DATA` | `[7:0]` X, `[15:8]` Y, `[16]` escudo, `[17]` golpe, `[31:24]` secuencia |
   | `0x0047_0004` | `JOY2_DATA` | igual para el jugador 2 |
   | `0x0047_0008` | `STATUS` | `[0]` P1_VALID, `[1]` P2_VALID, `[2]` UART_ERROR, `[3]` CHECKSUM_ERROR |

## Issue #21: ESP32-C3 Super Mini

Los programas originales para ESP32 DevKit siguen en `mandos_v1/esp32_mando/` y `mandos_v1/esp32_consola/`. Las variantes nuevas son:

| Programa | Pines |
| --- | --- |
| `mandos_v1/esp32c3_mando/esp32c3_mando.ino` | X GPIO0 (ADC1), Y GPIO1 (ADC1), botón GPIO10, golpe del G3 GPIO3 (por confirmar), UART1 con la FPGA del mando RX GPIO20 / TX GPIO21 |
| `mandos_v1/esp32c3_consola/esp32c3_consola.ino` | UART1 con la FPGA de la consola: TX GPIO21 → `uart_rx_mando`, RX GPIO20 (opcional, para `?`) |

Respuestas propuestas a las preguntas del #21:

- **Tecnología:** ESP-NOW (sobre Wi-Fi). La C3 no tiene Bluetooth clásico y con ESP-NOW una sola ESP32 de la consola recibe a los dos mandos sin emparejar. Son 3 ESP32-C3: dos mandos y una en la consola.
- **Cómo se distinguen los mandos:** por el byte 1 de la trama (`#define JUGADOR 1` o `2` en cada mando). No hace falta escribir direcciones MAC.
- **FPGA ↔ ESP32 del mando:** 115200 8N1 por UART1 (GPIO20/21). El programa del mando tiene `MODO_PUENTE`: en `false` la C3 lee el joystick, envía la trama ~30 veces/s y responde a `?` (0x3F) con la última trama; en `true` reenvía por ESP-NOW las tramas válidas que le manda el empaquetador de la FPGA.
- **Quién empieza:** envío continuo (~30 tramas/s). Si se pierde una trama la corrige la siguiente. La consola también responde a `?` por si el G5 prefiere pedirlas.

## Pendientes (sin confirmar con el G4)

- **Pin de la UART de los mandos en la Tang Nano 9K:** se usa el **33** porque el G3 ocupa del 25 al 29 y el G5 el 28, pero el G4 también usa el 33. Se cambia en una sola línea de cada `.cst` (`IO_LOC "uart_mandos" 33;` en `propuesta_corregida/soc_consola/boards/tangnano9k/tangnano9k.cst`, `IO_LOC "uart_rx" 33;` en `boards/tangnano9k/com.cst` y en `mandos_v1/placa/tangnano9k_g1.cst`), sin tocar el RTL.
- **Reloj 27 MHz (Tang Nano) o 25 MHz (G4):** todo el RTL lo recibe como parámetro (`CLK_HZ` / `CLK_FREQ`, 27 MHz por defecto). El banco de `documentacion/sim` pasa en los dos casos (`make filas` y `make filas25`).

## Cómo probar

Con Icarus Verilog 12 o más reciente, desde esta carpeta:

```bash
make sim      # todo: minimo, corregida, soc, v1, docs
make clean
```

`make soc` copia `projecto/consola` a `build/consola` y le pone encima `propuesta_corregida/soc_consola/`, así que no modifica la consola del repositorio.

Resultados del 27-nov-2026 (Icarus Verilog 12.0):

| Objetivo | Resultado |
| --- | --- |
| `make minimo` | `tb_ctrl` TODO OK, `tb_com` TODO OK |
| `make corregida` | mando 26/26, `com.v` OK, periférico 17/17 |
| `make soc` | SoC completo con FemtoRV 6/6 |
| `make v1` | 15 OK, 0 fallos |
| `make docs` | 23/23 a 27 MHz y a 25 MHz, 5/5 mutantes detectados |

**No probado todavía:** los programas `.ino` (ni los originales ni los de la C3) no se han compilado ni cargado en una ESP32, y nada se ha probado en la placa real. Falta place & route con el pin definitivo.
