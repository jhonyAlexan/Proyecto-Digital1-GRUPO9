# Pantalla

## UART
### 1. Diagrama de caja negra

El periférico controla la matriz **Seengreat RGB Matrix P3.0-64 ×64** desde la FPGA de la Colorlight 5A-75B. El panel tiene 4096 píxeles con un LED rojo, uno verde y uno azul cada uno, se conecta por la interfaz paralela HUB75 y usa barrido 1/32: solo hay dos filas encendidas a la vez, la fila r y la fila r +32. El panel no guarda la imagen; la debe refrescar continuamente el controlador, cientos de veces por segundo.
Para el resto de la consola el controlador es un periférico del SoC: el procesador le escribe registros por el bus estándar del curso y el periférico genera solo las señales del panel.

<img width="979" height="371" alt="image" src="https://github.com/user-attachments/assets/c42d1741-88e8-4f24-b0c8-e3228341c655" />

Figura 1: Vista externa del controlador. A la izquierda, las entradas del bus del procesador; a la derecha, la salida de lectura hacia el bus y las líneas del conector HUB75 hacia el panel. Cada línea lleva una marca diagonal y un número que indica su ancho en bits.

####  Características iniciales

- Un panel de 64×64 píxeles RGB (1R1G1B), barrido 1/32.
- Seis líneas de color en paralelo: `R1` `G1` `B1` para las filas `0–31` y `R2` `G2` `B2` para las filas `32–63`.
- Cinco líneas de dirección de fila `A B C D E` (32 pares de filas).
- Tres líneas de control: `CLK` (desplazamiento), `LAT` (latch) y `OE`` (encendido, activo en bajo).
- Las 14 líneas son salidas: la placa no permite leer nada del panel.
- Color de un bit por canal (RGB111): ocho colores.
- La imagen se guarda dentro del periférico (4096 píxeles); el procesador escribe píxeles y el periférico refresca el panel por su cuenta.
- Interfaz con el procesador según el contrato del curso: `CLK`, `rst`, `d_in[31:0]`, `cs`, `addr`, `rd`, `wr` y `d_out[31:0]`.
- Configuración del chip driver del panel al habilitar el periférico.
- Brillo ajustable y contador de cuadros mostrados.
Los 64 píxeles de cada fila se envían secuencialmente, uno por pulso de `CLK` y por seis líneas a la vez; no existe un bus de 64 líneas hacia el panel.

#### Aspectos pendientes
La vista de caja negra muestra únicamente las líneas externas. En la siguiente sección se propone la división interna. Quedan pendientes la frecuencia de `CLK`, el tiempo de cada fila y la frecuencia de refresco, que se fijan en el análisis temporal. El reloj y el reset los impone el contrato del curso: `CLK` del SoC (50MHz) y rst síncrono activo en alto. El orden de colores (variante normal o GBR del panel) y la orientación de la imagen se confirman con el panel real; no cambian el diseño, solo la asignación de pines.

### 2. Diagrama de bloques

La propuesta usa el reloj común ``CLK`` de 50MHz. Como el generador de `baud_tick` de la UART, un generador de ticks produce pulsos de habilitación de un ciclo para el barrido; no es un reloj nuevo. La imagen vive en un framebuffer con un puerto de escritura para el procesador y uno de lectura para el barrido, de modo que ambos trabajan al mismo tiempo.



´´´bash´´´´
sadsa

`git status`}}``





### 3. 

### 4. Diagrama de flujo del transmisor

### 5. Fundamento: controlador y datapath

### 6. Propuesta de clasificaci´on del flujo de TX

### 7. ASMD:delflujoalastransferenciasporciclo

### 8. Propuesta de bloques de TX: control y datapath

### 9. Máquina de estados del transmisor

### 10. Organizaci´on de m´odulos e implementaci´on Verilog

### 11. Entorno de prueba: testbench, est´ımulos y observaci´on
