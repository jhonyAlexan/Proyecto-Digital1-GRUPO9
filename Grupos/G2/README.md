# Subgrupo G2 — Arquitectura Hardware y Sistema de Memorias

**Integrantes:** Juan Sebastián Vásquez, Santiago Castro, Michael  
**Curso:** Electrónica Digital 1 — Grupo 9  

---

## 1. Selección y Justificación de Tecnologías de Memoria (Entregable E)

Para cumplir con las restricciones del proyecto (recursos escasos de BRAM y flujo abierto Yosys), se seleccionó una arquitectura jerárquica de almacenamiento:

![Selección de Memorias](img/image_30bfe0.png)

- **BRAM Interna (58.5 KB):** Destinada al ejecutable en C del FemtoRV (32 KB) y al Framebuffer gráfico dual-port de 64x64 píxeles (16 KB).
- **Flash SPI Externa (W25Q64 - 8 MB):** Almacenamiento no volátil de sprites de peleadores, escenarios, tablas de sonido y persistencia de High-Scores.

---

## 2. Diagrama de Bloques e Integración al Bus MMIO (Entregable D)

El sistema utiliza una arquitectura Von Neumann con bus unificado. El decodificador de direcciones asigna rangos específicos para memoria interna, registros MMIO y controlador SPI:

![Arquitectura de Integración](img/image_30bfb9.png)

### Mapa de Memoria MMIO
- `0x0000_0000 - 0x0000_7FFF`: BRAM Memoria de Programa / Datos (32 KB)
- `0x1000_0000 - 0x1000_002C`: Registros de Periféricos MMIO (Mando, HUB75, Audio, UART)
- `0x2000_0000 - 0x2000_3FFF`: Framebuffer BRAM Dual-Port (16 KB)
- `0x3000_0000 - 0x3000_FFFF`: Controlador de Memoria Flash SPI Externa

---

## 3. Flujo Funcional de Envío de Datos (Entregables B.2 y C)

Secuencia comportamental del movimiento de datos desde la Flash externa hasta la matriz LED:

![Flujo de Datos](img/image_30bcf5.png)

---

## 4. Controlador de Memoria Flash SPI — FSMD (Guía de Diseño)

Para evitar dependencias de IP cores propietarias, se diseñó un controlador SPI en Verilog separado en Unidad de Control (FSM de 5 estados) y Camino de Datos (Datapath):

![Controlador SPI FSMD](img/image_30bcb9.png)

- **Unidad de Control (FSM):** Gestiona los estados `IDLE`, `LOAD_CMD`, `SEND_ADDR`, `XFER_BYTE` y `STOP`.
- **Camino de Datos (Datapath):** Contiene el divisor de reloj (`SCLK`), el registro de desplazamiento PISO/SIPO y el contador de bits.

---

## 5. Inferencia y Manejo de BRAM Dual-Port (Framebuffer V-SYNC)

La BRAM interna se infiere en Verilog mediante sintaxis síncrona compatible con Yosys, permitiendo el acceso simultáneo del CPU (escritura en Back Buffer) y del panel HUB75 (lectura del Front Buffer):

![Inferencia BRAM Dual-Port](img/image_30bc5b.png)
