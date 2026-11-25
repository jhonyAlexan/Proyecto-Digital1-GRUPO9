# Controlador IMU BMI160 por SPI y Detector de Golpes (Tang Nano 9K)
Grupo 3: Kennet, Jeimmy, Alexander.

En clase de laboratorio se probaron de nuevo los diferentes còdigos, se revisò que funcionara fìsicamente en la FPGA y se actualizaron en una nueva carpeta llamada_ IMU_Probado_FPGA.


## Características principales

- **SPI:** Comunicación con el BMI160 y lectura de 12 registros (`0x0C`–`0x17`).
- **Detector de golpes:** Procesamiento de acelerómetro y giroscopio mediante `detector_golpe.v`.
- **UART:** Transmisión serial 8N1 a 115200 baudios, e spara mirar en la consola y verificar que està mandando los datos, no es que tenga aplicaciòn obligatoria en el proyecto.
- **MMIO:** Interfaz síncrona para integración con FemtoRV.
- **LEDs:** Indicadores de estado y detección de golpes.


## Archivos principales

| Archivo | Descripción |
| :--- | :--- |
| `top.v` | Controlador principal del sistema |
| `spi_master.v` | Archivo que rige las reglas o el proceso de comunicación SPI |
| `detector_golpe.v` | Detector de impactos |
| `uart_tx.v` | Transmisor UART |
| `periferico_imu_mmio.v` | Interfaz MMIO |
| `tb_imu.v` | Testbench de SPI |
| `leer_imu.py` | Lectura y procesamiento de datos seriales |
| `tangnano9k.cst` | Asignación de pines FPGA |
| `Makefile` | Compilación y programación |


## Conexiones fìsicas:

| Pin Módulo BMI160 | Pin Tang Nano 9K | Señal | Descripción |
| :--- | :--- | :--- | :--- |
| **VCC / VIN** | `3V3` | Alimentación | Usar estrictamente 3.3V |
| **GND** | `GND` | Tierra | Tierra común del sistema |
| **SCL / SCK** | `Pin 25` | `sclk` | Reloj SPI (~964 kHz) |
| **SDA / SDI** | `Pin 26` | `mosi` | Datos de FPGA hacia IMU |
| **SDO / SAO** | `Pin 27` | `miso` | Datos de IMU hacia FPGA |
| **CS / CSB** | `Pin 28` | `cs_n` | Chip Select (activo en bajo) |

### Salidas de control 
* **Pin 29 (`golpe_out`):** Salida digital de 3.3V. Se mantiene en `1` durante **150 ms** cuando detecta un golpe y vuelve a `0`.
* **Pin 17 (`uart_tx`):** Salida serial a **115200 baudios** (conectada al USB-UART de la placa).
* **LEDs integrados:** Se encienden todos simultáneamente como indicador visual cada vez que `golpe_out = 1`.


## Verificación 

```bash
# Simulación SPI
make clean
make sim

# Compilación del periférico MMIO
iverilog -o test_mmio.vvp periferico_imu_mmio.v top.v spi_master.v detector_golpe.v uart_tx.v

# Síntesis y generación del bitstream
make

# Programación de la FPGA
make prog
