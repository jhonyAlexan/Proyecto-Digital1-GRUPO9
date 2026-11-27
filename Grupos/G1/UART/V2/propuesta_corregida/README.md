# Corrección del código de Cesar para el SoC del G2

Esta carpeta trae el código de Cesar Jaramillo (`Grupos/G1/UART/Propuesta`) corregido para que funcione con el SoC de la consola (`projecto/consola`, decodificador del G2) y con el juego del G6. Se respetaron sus módulos, nombres y estructura (`uart_8n1`, `empaquetador`, `desempaquetador`, `com`), así que Cesar puede subirlo con su usuario.

Base revisada: repositorio `jhonyAlexan/Proyecto-Digital1-GRUPO9`, rama `main`, commit `19f8a9b` (26 nov 2026).

## Cómo está en V2

En V2 esta carpeta es una copia de respaldo y **no se copia encima de nada**: la `Propuesta/` original de Cesar y `projecto/consola` quedan como están en el repositorio.

| Carpeta en V2 | Corresponde a |
| --- | --- |
| `propuesta_corregida/` (esta) | `Grupos/G1/UART/Propuesta/` corregida |
| `propuesta_corregida/soc_consola/` | archivos que cambian o son nuevos en `projecto/consola/` |

Para probar el SoC completo sin tocar `projecto/consola`, desde `V2/` se corre `make soc`: copia la consola a `V2/build/consola` y le pone encima `soc_consola/`.

`cambios.patch` tiene todo junto, por si Cesar o el G2 deciden llevarlo a sus carpetas (`git apply cambios.patch` desde la raíz del repo, sobre `main` 19f8a9b). En este PR **no** se aplicó.

## Por qué no funcionaba

1. **No compilaba.** En el último commit los parámetros quedaron como `4'42`, `4'43` y `4'44`. A eso le falta la base (`h`, `d`...) y además `0x42` no cabe en 4 bits. Icarus y Yosys lo rechazan.
2. **El protocolo no era el acordado.** La propuesta mandaba pares dirección/valor de 2 bytes. El G5, el G6 y el decodificador del G2 ya trabajan con la trama de 8 bytes del G5. El juego del G6 lee los mandos en `0x0047_0000`, así que con pares dirección/valor no le llegaba nada.
3. **No había periférico para el SoC.** El `chip_select.v` del G2 ya decodifica `0x0047` en `cs[7]`, pero ningún módulo respondía ahí. Además, `SOC.v` declara `cs` de 7 bits, así que el bit 7 se perdía y `chip7_dout` quedaba sin conectar. Icarus avisa: `Port 10 (cs) of chip_select expects 8 bits, got 7`.
4. **Faltaba el escudo.** El commit "Preparando para boton de Shield" lo dejó comentado.

## La trama acordada (G5)

115200 baudios, 8N1, unas 30 tramas por segundo por mando.

| Byte | Campo | Valor |
| --- | --- | --- |
| 0 | Cabecera | `0xAA` |
| 1 | Jugador | 1 o 2 |
| 2 | Secuencia | 0 a 255, sube en cada trama |
| 3 | X | con signo, −127 a 127 |
| 4 | Y | con signo, −127 a 127 |
| 5 | Shield (botón) | bit 0 |
| 6 | Punch (ataque) | bit 0 |
| 7 | Checksum | XOR de los bytes 1 a 6 |

Registros en el SoC:

| Dirección | Registro | Bits |
| --- | --- | --- |
| `0x0047_0000` | `JOY1_DATA` | `[7:0]` X, `[15:8]` Y, `[16]` shield, `[17]` punch, `[31:24]` secuencia |
| `0x0047_0004` | `JOY2_DATA` | igual para el jugador 2 |
| `0x0047_0008` | `STATUS` | `[0]` P1_VALID, `[1]` P2_VALID, `[2]` UART_ERROR, `[3]` CHECKSUM_ERROR |

Es el mismo mapa que tiene el G6 en `firmware/hardware.h`.

## Cambios archivo por archivo

### `Propuesta/rtl/ctrl/desempaquetador.v` (cambiado)
- Se quitan los parámetros `PER_X`, `PER_Y` y `PER_PUNCH`, que eran los del error `4'42`. Ahora los parámetros son `CABECERA = 8'hAA`, `JUG_P1 = 1`, `JUG_P2 = 2` y `T_MAX_CICLOS`.
- La FSM sigue la idea del diagrama Package_Manager, pero por posición en la trama. `S_DIR` espera `0xAA`, `S_VAL` guarda los bytes 1 a 6 mientras acumula el XOR, y `S_CHK` revisa el checksum.
- La muestra de un jugador se copia completa en un solo flanco, y solo si el checksum está bien. Así el CPU nunca lee una X nueva con una Y vieja.
- Salidas nuevas: `p1_shield`, `p2_shield`, `p1_seq`, `p2_seq`, y los pulsos `p1_nuevo` y `p2_nuevo`.
- `dir_err` ahora indica un jugador distinto de 1 y 2. `val_err` indica un checksum malo.
- Resincronización: si llega `rx_frame_err`, o si pasa 1 ms sin bytes con una trama a medias, la trama se descarta y vuelve a buscar `0xAA`.
- Se mantiene el reset asíncrono activo en bajo (`rst_n`), como en el original.

### `Propuesta/rtl/ctrl/empaquetador.v` (cambiado)
- Arma la misma trama de 8 bytes. Tiene la entrada `shield` que estaba comentada.
- Lleva el contador de secuencia y calcula el XOR.
- Manda una trama cada `PERIODO` ciclos (por defecto 1/30 s a 27 MHz) con la muestra congelada al inicio de la trama.
- Se conserva la FSM `S_SCAN → S_ADDR → S_ADDR_W` y el manejo de `tx_busy`.
- Se quitó `SOLO_CAMBIOS`. El G5 espera envío continuo, y así una trama perdida se corrige con la siguiente.

### `Propuesta/rtl/ctrl/uart_8n1.v` (cambio pequeño)
- Si el bit de parada llega en 0, ahora espera a que la línea vuelva a 1 (estado `R_ESPERA`) antes de buscar otro bit de inicio. Antes, un cable suelto o un reinicio de la ESP32 generaba bytes falsos. El transmisor no cambia.

### `Propuesta/rtl/ctrl/perip_mandos.v` (nuevo)
- Es el módulo `peripheral_mandos`, con el mismo bus que `peripheral_mult` y `peripheral_uart`: `clk`, `reset`, `d_in`, `cs`, `addr`, `rd`, `wr`, `d_out`.
- Por dentro usa `uart_8n1` y el `desempaquetador` de Cesar.
- Entrega los tres registros de la tabla. Las banderas de `STATUS` quedan en 1 hasta el reset, como pide el G5. Los registros son de solo lectura.

### `Propuesta/boards/tangnano9k/com.v` (cambiado)
- Se ajustan los puertos del nuevo `desempaquetador`. `led[2]` ahora se enciende con cada trama válida y no con cada byte.
- `com.cst` no cambia: sigue el pin 33 para la UART del mando.

### `Propuesta/sim/` (testbenches)
- `tb_ctrl.v` (cambiado) prueba el lazo completo `empaquetador → UART → UART → desempaquetador`. Luego prueba errores a mano: basura, checksum malo, jugador 3, `0xAA` dentro de los datos, trama cortada (vence el plazo) y error de UART.
- `tb_com.v` (cambiado) manda tramas reales al top `com`.
- `tb_perip_mandos.v` (nuevo) lee los registros por el bus, como lo hace el FemtoRV.

### `Propuesta/Makefile` (cambiado)
- Se agregan la variable `MANDOS` y el objetivo `make sim_mandos`.

### `projecto_consola/` (conexión al SoC del G2)
- `rtl/SOC.v` (cambiado):
  - `wire [7:0] cs` (antes `[6:0]`) y `cs_mandos = cs[7]`.
  - Nuevo puerto `RX_MANDOS` y nuevo parámetro `BAUD_MANDOS = 115200`.
  - `.chip7_dout(mandos_dout)` en `chip_select`, y la instancia `peripheral_mandos` (sección 7 del archivo).
- `rtl/perip_mandos.v` (nuevo): el mismo de `Propuesta`. El Makefile ya toma solo los `rtl/perip_*.v`.
- `rtl/mandos/uart_8n1.v` y `rtl/mandos/desempaquetador.v` (nuevos): copias de los de Cesar.
- `Makefile` (cambiado): agrega `rtl/mandos/*.v` a `RTL` y el objetivo `make sim_mandos`.
- `boards/tangnano9k/top_tangnano9k.v` y `tangnano9k.cst` (cambiados): nueva entrada `uart_mandos` en el pin 33.
- `boards/colorlight/top_colorlight.v` y `sim/tb_soc.v` (cambiados): `RX_MANDOS` se deja en 1, que es la línea en reposo.
- `sim/tb_soc_mandos.v` y `sim/mandos_prueba.hex` (nuevos): prueba del SoC completo. El FemtoRV corre un programa de 8 instrucciones hecho a mano (no hace falta el compilador RISC-V), lee `0x0047_0000`, `0x0047_0004` y `0x0047_0008`, y copia los valores en la RAM.
- `chip_select.v` no se tocó: el cambio que ya hizo el G2 sirve tal cual.

### Cómo queda la conexión en `SOC.v`

```verilog
  wire [7:0] cs;
  wire cs_mandos = cs[7]; // 0x0047_xxxx  mandos (G1)
  wire [31:0] mandos_dout;

  chip_select chip_select (
      ...
      .chip6_dout(RAM_rdata),
      .chip7_dout(mandos_dout),   // 0x0047_xxxx  mandos
      .cs        (cs),
      .mem_rdata (mem_rdata)
  );

  peripheral_mandos #(.CLK_HZ(CLK_FREQ), .BAUD(BAUD_MANDOS)) mandos (
      .clk(clk), .reset(!resetn),
      .d_in(mem_wdata), .cs(cs_mandos), .addr(mem_addr),
      .rd(rd), .wr(wr), .d_out(mandos_dout),
      .uart_rx(RX_MANDOS),
      .joy1_data(), .joy2_data(), .status());
```

### Lectura desde C (como en `hardware.h` del G6)

```c
uint32_t j1 = *(volatile uint32_t *)(0x00470000);
int8_t   x  = (int8_t)(j1 & 0xFF);
int8_t   y  = (int8_t)((j1 >> 8) & 0xFF);
int shield  = (j1 >> 16) & 1;
int punch   = (j1 >> 17) & 1;
```

## Pruebas hechas (Icarus Verilog 12)

| Comando | Resultado |
| --- | --- |
| `cd Grupos/G1/UART/Propuesta && make sim_ctrl` | TODO OK (26 pruebas) |
| `cd Grupos/G1/UART/Propuesta && make sim_com` | TODO OK |
| `cd Grupos/G1/UART/Propuesta && make sim_mandos` | TODO OK (17 pruebas) |
| `cd projecto/consola && make sim_mandos` | TODO OK (6 pruebas): el CPU lee bien J1, J2 y STATUS |
| `yosys synth_gowin` del top `com` y del `top_tangnano9k` con mandos | Sin errores |

**No probado:** place & route con nextpnr, la placa real y las ESP32. La ESP32 de la consola debe mandar esta trama por GPIO17. Los sketches de la carpeta `../mandos_v1` ya lo hacen.

## Pendiente de acordar

- **G5:** quién instancia el periférico en el SoC, si este `peripheral_mandos` o el suyo. Los dos usan el mismo mapa, así que no deben ir los dos a la vez en `0x0047`.
- **G2:** que acepte el cambio de `SOC.v`, es decir el `cs` de 8 bits y el puerto `RX_MANDOS`.
