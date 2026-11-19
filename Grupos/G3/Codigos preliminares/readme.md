# Controlador IMU BMI160 por SPI y Detector de Golpes (Tang Nano 9K)
Grupo 3: Kennet, Jeimy, Alexander.

Còdigo en Verilog para leer aceleración y velocidad angular desde una IMU **BMI160** mediante protocolo SPI (Modo 0) en una FPGA **Tang Nano 9K**, la idea es que el sistema calcule la intensidad del movimiento en tiempo real y entrega una señal digital (`1` o `0`) ante golpes o giros bruscos.
La direcciòn del golpe o giro es indiferente.

Se analizó el diagrama de flujo del protocolo SPI para enviar una trama de 6 bytes con el profesor, luego se hizo uso de la IA como apoyo para la generación del código en verilog, se debe verificar su consistencia y funcionamiento.

## Estructura del Proyecto y Ubicación de Archivos

Los archivos se organizan asi:

```text
IMU_Proyecto/
├── Makefile                    # Automatiza síntesis, ruteo y carga en la FPGA
├── tangnano9k.cst               # Asignación física de pines (SPI, reloj, LEDs y salida)
├── .gitignore                   # Ignora archivos temporales (.fs, .json, .vcd, .vvp)
├── rtl/                         # Código fuente sintetizable en Verilog
│   ├── spi_master.v             # Controlador físico SPI Modo 0 (16 bits)
│   ├── detector_golpe.v         # Cálculo de energía del movimiento y filtro anti-rebote
│   ├── uart_tx.v                # Transmisor serial para depuración en consola (115200 baudios)
│   ├── top.v                    # Módulo principal autónomo (Pruebas + LEDs + Pin 29)
│   └── periferico_imu_simple.v  # Adaptador MMIO de 1 bit para conectar al bus del FemtoRV
└── sim/                         # Archivos exclusivos de simulación
    └── tb_imu.v                 # Testbench para verificar ondas SPI en GTKWave
```


## 1. Conexiones Físicas (Pinout)

Conectar la IMU directamente a los pines de 3.3V de la Tang Nano 9K:

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


## 2. Probarlo usando la Suite usada en el curso

Con **OSS CAD Suite** activado en Linux, ejecutar dentro de la carpeta raíz:

1. **Compilar y cargar en memoria volátil (SRAM):**
   ```bash
   make prog
   ```
2. **Grabar de forma permanente en la Flash:**
   ```bash
   openFPGALoader -b tangnano9k -f top.fs
   ```
3. **Ver datos en la consola**
   ```bash
   stty -F /dev/ttyUSB1 115200 raw -echo && cat /dev/ttyUSB1
   ```
   *(Si no muestra datos, cambiar `/dev/ttyUSB1` por `/dev/ttyUSB0`).*

4. **Ajustar sensibilidad:** Modificar el parámetro `UMBRAL_GOLPE` en `rtl/detector_golpe.v` (valor actual: `45000 o 65000 no me acuerdo`). Subir el valor exige golpes más fuertes; bajarlo lo hace más sensible.

---

## 3. Para el grupo que hace lo del UART y Bluetooth

Para integrar este módulo en el procesador RISC-V mediante Memory-Mapped I/O (MMIO), pueden revisar `rtl/periferico_imu_simple.v`.

### Instanciación en el SoC (`SOC.v`)
Conectar la señal de selección del decodificador de direcciones a `sel` y el bus de lectura de 32 bits a `rdata`:

```verilog
wire [31:0] imu_rdata;
wire        imu_sel = isIO && (mem_addr == 32'h4000_0010); // Ajustar según mapa de memoria

periferico_imu_simple u_imu_perif (
    .clk(clk),
    .resetn(resetn),
    .sel(imu_sel),
    .rdata(imu_rdata),
    .sclk(imu_sclk),
    .mosi(imu_mosi),
    .miso(imu_miso),
    .cs_n(imu_cs_n),
    .golpe_bit(golpe_pin),
    .leds(leds)
);
```

### Lectura desde código en C (Firmware FemtoRV)
El **Bit 0** de la dirección asignada contiene el estado del golpe (`1` = golpe activo, `0` = reposo):

```c
#include <stdint.h>

#define IMU_STATUS_REG ((volatile uint32_t *)0x40000010)

void verificar_golpe(void) {
    uint32_t estado = *IMU_STATUS_REG;
    if (estado & 0x01) {
        // Acción al detectar golpe (ej. enviar carácter por UART hacia Bluetooth)
    }
}
```
