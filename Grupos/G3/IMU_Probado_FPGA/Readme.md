# Desarrollo de los módulos – IMU BMI160 (Grupo 3)

## Índice
- [top.v](#topv)
- [spi_master.v](#spi_masterv)
- [detector_golpe.v](#detector_golpev)
- [periferico_imu_mmio.v](#periferico_imu_mmiov)

---

## top.v
### Descripción
El archivo `top.v` es el módulo principal del sistema. Conecta la IMU BMI160 con la FPGA
Tang Nano 9K y decide si ocurrió un golpe o giro brusco. Para eso:

1. Configura la IMU por SPI (modo 0): enciende el acelerómetro y el giroscopio.
2. Lee de forma periódica los 6 ejes (gx, gy, gz, ax, ay, az), recorriendo los
   registros `0x0C` a `0x17` con 12 lecturas de un byte.
3. Entrega las muestras al módulo `detector_golpe`, que calcula la energía del
   movimiento y activa `golpe_out` cuando supera el umbral.
4. Envía por UART (115200 baudios) un mensaje con la energía máxima y el estado
   del golpe, con el formato `E:XXXXX GOLPE:x`. Este canal sirve para transmitir
   los datos al ESP32.
5. Enciende los 6 LEDs de la placa mientras hay un golpe, para evidenciar
   visualmente los movimientos en la FPGA.
   
El módulo instancia tres bloques: `spi_master` (comunicación con la IMU),
`uart_tx` (telemetría) y `detector_golpe` (decisión), y los coordina con una
máquina de estados.

### Caja negra
![Caja negra del módulo top](img/caja_negra_top.png)

| Señal | Dirección | Ancho | Pin | Descripción |
| :--- | :--- | :---: | :---: | :--- |
| `clk` | Entrada | 1 | 52 | Reloj del sistema, 27 MHz |
| `btn_rst` | Entrada | 1 | 4 | Reset asíncrono, activo en bajo |
| `miso` | Entrada | 1 | 27 | Datos de la IMU hacia la FPGA |
| `sclk` | Salida | 1 | 25 | Reloj SPI (~964 kHz) |
| `mosi` | Salida | 1 | 26 | Datos de la FPGA hacia la IMU |
| `cs_n` | Salida | 1 | 28 | Chip select de la IMU, activo en bajo |
| `golpe_out` | Salida | 1 | 29 | 1 durante 150 ms al detectar un golpe, 0 en reposo |
| `uart_tx` | Salida | 1 | 17 | Serial a 115200 baudios hacia el ESP32 |
| `leds[5:0]` | Salida | 6 | 10 a 16 | LEDs de la placa, activos en bajo |


### Diagrama de flujo / FSM

### Datapath

### Observaciones

## spi_master.v
### Descripción
`spi_master.v` es el controlador físico del protocolo SPI en modo 0 (CPOL=0,
CPHA=0). Se encarga de comunicarse con la IMU BMI160 enviando y recibiendo una
trama de 16 bits por cada transacción:

- **Primer byte (bits 15 a 8):** comando. El bit 15 indica lectura (1) o
  escritura (0) y los otros 7 bits son la dirección del registro.
- **Segundo byte (bits 7 a 0):** en una escritura es el dato a escribir; en una
  lectura es un relleno (`00`) mientras la IMU responde por `miso`.

Funcionamiento:

1. En reposo mantiene `cs_n = 1` y `sclk = 0`.
2. Al recibir un pulso en `start`, baja `cs_n`, carga `tx_data` y coloca en
   `mosi` el bit más significativo.
3. Un divisor de reloj genera un tick cada 14 ciclos de `clk`, y en cada tick
   `sclk` cambia de nivel. Esto da un reloj SPI de 27 MHz / 28 ≈ 964 kHz.
4. En cada flanco de subida de `sclk` captura `miso`, pero solo guarda los
   últimos 8 bits, que corresponden a la respuesta de la IMU, en `rx_data`
   (primero el bit más significativo).
5. En cada flanco de bajada de `sclk` desplaza el siguiente bit hacia `mosi`.
6. Al terminar los 16 bits sube `cs_n` y genera un pulso de un ciclo en `done`.
   En ese momento `rx_data` tiene el byte recibido.

Una transacción completa dura 16 × 28 = 448 ciclos de reloj, unos 16,6 µs.

### Caja negra
![Caja negra del módulo spi_master](img/caja_negra_spi.png)

| Señal | Dirección | Ancho | Descripción |
| :--- | :--- | :---: | :--- |
| `clk` | Entrada | 1 | Reloj del sistema, 27 MHz |
| `rst_n` | Entrada | 1 | Reset asíncrono, activo en bajo |
| `start` | Entrada | 1 | Pulso que inicia una transacción |
| `tx_data` | Entrada | 16 | Trama a enviar: comando (8 bits) + dato (8 bits) |
| `miso` | Entrada | 1 | Datos de la IMU hacia la FPGA (pin 27) |
| `sclk` | Salida | 1 | Reloj SPI, ~964 kHz (pin 25) |
| `mosi` | Salida | 1 | Datos de la FPGA hacia la IMU (pin 26) |
| `cs_n` | Salida | 1 | Chip select, activo en bajo (pin 28) |
| `rx_data` | Salida | 8 | Byte recibido de la IMU, válido cuando `done = 1` |
| `done` | Salida | 1 | Pulso de un ciclo al terminar la transacción |

Los números de pin se asignan en `top.v` y en el archivo `tangnano9k.cst`.

### Diagrama de flujo / FSM

### Datapath

### Observaciones

## detector_golpe.v
### Descripción
Qué hace el módulo, en 2 o 3 líneas.

### Caja negra

### Diagrama de flujo / FSM

### Datapath

### Observaciones

## periferico_imu_mmio.v
### Descripción
Qué hace el módulo, en 2 o 3 líneas.

### Caja negra

### Diagrama de flujo / FSM

### Datapath

### Observaciones
