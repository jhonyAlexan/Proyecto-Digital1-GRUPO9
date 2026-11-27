# G1 v1: comunicación de los mandos compatible con G5 y G6

Esta versión cambia el protocolo del G1 para que coincida con el que ya usan el G5 (periférico de mandos) y el G6 (juego). Con ella el juego del G6 lee los dos mandos sin cambiar su código.

Los archivos originales del proyecto anterior (Control y Consola con trama de 4 bytes) no se tocaron. En V2 esta carpeta se llama `mandos_v1/`; la documentación está en `../documentacion/`.

## Cómo viaja un dato

```
Joystick + botón ──► ESP32 mando J1 ──┐
golpe_out (G3) ───►  (trama 8 bytes)  │  ESP-NOW (inalámbrico, 2,4 GHz)
                                      ├──► ESP32 consola ──UART 115200──► FPGA consola ──► registros 0x0047 ──► juego (G6)
Joystick + botón ──► ESP32 mando J2 ──┘    (valida y reenvía)  GPIO17 → pin 33
golpe_out (G3) ───►
```

## Trama (la misma del G5 y del G6)

115200 baudios, 8N1, unas 30 tramas por segundo por mando.

| Byte | Campo | Valor |
| --- | --- | --- |
| 0 | Inicio | `0xAA` |
| 1 | Jugador | 1 o 2 |
| 2 | Secuencia | 0 a 255, sube en cada trama |
| 3 | Eje X | −127 a 127 (derecha positivo) |
| 4 | Eje Y | −127 a 127 (arriba positivo) |
| 5 | Botón | bit 0: 1 = oprimido |
| 6 | Ataque | bit 0: 1 = golpe del G3 |
| 7 | Checksum | XOR de los bytes 1 a 6 |

## Registros en la consola (región `0x0047`)

| Dirección | Registro | Bits |
| --- | --- | --- |
| `0x0047_0000` | `JOY1_DATA` | `[7:0]` X, `[15:8]` Y, `[16]` botón, `[17]` ataque, `[31:24]` secuencia |
| `0x0047_0004` | `JOY2_DATA` | igual para el jugador 2 |
| `0x0047_0008` | `STATUS` | `[0]` P1_VALID, `[1]` P2_VALID, `[2]` UART_ERROR, `[3]` CHECKSUM_ERROR |

El bus es el del curso: `clk`, `rst` síncrono activo en alto, `cs`, `rd`, `wr`, `addr[3:0]` en bytes, `d_in`, `d_out` registrado y `ack` un ciclo después de `cs`.

## Archivos

| Carpeta | Archivo | Qué hace |
| --- | --- | --- |
| `esp32_mando/` | `esp32_mando.ino` | Lee el joystick (GPIO34, GPIO35, botón GPIO13) y el ataque del G3 (GPIO27), calibra el centro al encender, pasa los ejes a 8 bits con signo y envía la trama. Se configura con `#define JUGADOR 1` o `2`. |
| `esp32_consola/` | `esp32_consola.ino` | Recibe las tramas de los dos mandos, revisa el checksum y las reenvía por GPIO17. También responde a la solicitud `?` del montaje del G5. |
| `rtl/` | `g1_uart_rx.v` | Receptor UART 8N1 con sincronizador. |
| `rtl/` | `g1_trama_rx.v` | Arma la trama, revisa el checksum y el jugador, y descarta tramas incompletas después de 1 ms. |
| `rtl/` | `g1_mandos_mmio.v` | Periférico completo con los tres registros y el bus del curso. |
| `placa/` | `top_prueba_tangnano9k.v`, `tangnano9k_g1.cst` | Prueba en la Tang Nano 9K sin procesador: muestra en los LEDs lo que llega. |
| `sim/` | `tb_g1_mandos.v`, `Makefile` | Testbench y comandos (`make test`, `make syn`, `make config`). |

Todos los módulos empiezan con `g1_` para no chocar con `uart`, `uart_tx` ni `top` de los otros grupos.

## Pruebas hechas

- **Simulación** (`cd sim && make test`, Icarus Verilog 12): 15 de 15 casos pasan. Cubre tramas válidas de J1 y J2, `0xAA` dentro de los datos, checksum malo, jugador inválido, basura y trama cortada con resincronización, error de bit de parada, dirección reservada y reset.
- **Síntesis y place & route** para la GW1NR-9 con Yosys y nextpnr: sin errores. Ocupa 624 de 8640 SLICE (7 %) y cierra a 104 MHz, con 27 MHz pedidos.
- **No probado:** los dos `.ino` no se compilaron ni se cargaron en una ESP32, y nada se probó en la placa real.

## LEDs de la prueba en placa

| LED | Se enciende cuando |
| --- | --- |
| 0 | Llegó una trama de J1 en los últimos 100 ms |
| 1 | Llegó una trama de J2 en los últimos 100 ms |
| 2 | Botón de J1 oprimido |
| 3 | Ataque de J1 activo |
| 4 | Joystick de J1 fuera del centro (más de 40) |
| 5 | Hubo un error de UART o de checksum |

## Conexiones

| Desde | Hacia | Nota |
| --- | --- | --- |
| Joystick VRx, VRy, SW | ESP32 mando GPIO34, GPIO35, GPIO13 | Igual que el G5; joystick a 3,3 V |
| `golpe_out` del G3 (pin 29 de su Tang Nano) | ESP32 mando GPIO27 | Sin G3 conectado el ataque vale 0 (pull-down) |
| ESP32 consola GPIO17 (TX2) | Tang Nano consola pin 33 | GND común |
| ESP32 consola GPIO16 (RX2) | Pin TX de la FPGA, si se usa `?` | Opcional |
| ESP32 mando GPIO17 | Pin 33 de la FPGA | Solo para probar por cable, sin inalámbrico |

## Supuestos de esta versión

1. **El enlace inalámbrico es ESP-NOW, no Bluetooth clásico.** Con `BluetoothSerial`, una ESP32 solo se conecta a un mando a la vez, y se necesitan dos jugadores. ESP-NOW recibe de los dos mandos sin emparejar. Usa Wi-Fi, que comparte el ADC2, así que los ejes quedan en el ADC1 (GPIO34 y GPIO35), como ya recomienda el G5.
2. Los mandos envían a la dirección de difusión, así que no hay que escribir direcciones MAC en el código. La consola solo acepta tramas con `0xAA`, jugador 1 o 2 y checksum correcto.
3. El ataque viene del G3 por un cable al GPIO27. El botón del joystick va aparte, en el byte 5.
4. Se usa el pin 33 de la Tang Nano para la UART del mando porque los pines 25 a 29 los usa el G3 y el G5 usa el 28.
5. El ADC de Y crece hacia abajo, por eso se niega para que arriba sea positivo. Si en el módulo queda al revés, se cambia con `INVERTIR_Y` (lo mismo para X).

## Qué falta acordar con cada grupo

| Grupo | Punto |
| --- | --- |
| G5 | Quién instancia el periférico en el SoC: este `g1_mandos_mmio.v` o el suyo. Los dos tienen el mismo mapa. Si el envío es continuo o por `?` (la consola soporta ambos). El pin de la FPGA: 33 o 28. |
| G6 | Confirmar el sentido de X e Y con su pantalla de pruebas, y que la tasa de 30 tramas/s les sirve. |
| G2 | Añadir `0x0047` al decodificador del SoC y sacar los mandos de la RAM (palabras 42 a 47) y de `0x0042`. |
| G3 | Confirmar que `golpe_out` puede ir a la ESP32 del mando y si 150 ms de pulso alcanzan para el golpe del juego. |
| Curso | Si se acepta ESP-NOW en lugar de Bluetooth para el enlace inalámbrico. |

## Cómo conectarlo al SoC (para el G2)

En `projecto/consola/rtl/chip_select.v`, el decodificador hoy solo cubre `0x0040` a `0x0045`. Hay que agregar una línea para `0x0047` y conectar:

```verilog
g1_mandos_mmio u_mandos (
    .clk(clk), .rst(~resetn),
    .cs(cs_mandos), .rd(mem_rstrb), .wr(|mem_wmask),
    .addr(mem_addr[3:0]), .d_in(mem_wdata), .d_out(mandos_dout), .ack(),
    .uart_rx(uart_rx_mando),
    .joy1_data(), .joy2_data(), .status(), .trama_ok());
```
