# Periférico: Pantalla RGB Matrix

## UART
### 1. Diagrama de caja negra

El periférico controla la matriz **Seengreat RGB Matrix P3.0-64 ×64** desde la FPGA de la Colorlight 5A-75B. El panel tiene 4096 píxeles con un LED rojo, uno verde y uno azul cada uno, se conecta por la interfaz paralela **HUB75** y usa barrido 1/32: solo hay dos filas encendidas a la vez, la fila r y la fila r +32. El panel no guarda la imagen; la debe refrescar continuamente el controlador, cientos de veces por segundo.
Para el resto de la consola el controlador es un periférico del SoC: el procesador le escribe registros por el bus estándar del curso y el periférico genera solo las señales del panel.

<img width="979" height="371" alt="image" src="https://github.com/user-attachments/assets/c42d1741-88e8-4f24-b0c8-e3228341c655" />

Figura 1: Vista externa del controlador. A la izquierda, las entradas del bus del procesador; a la derecha, la salida de lectura hacia el bus y las líneas del conector **HUB75** hacia el panel. Cada línea lleva una marca diagonal y un número que indica su ancho en bits.

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

La propuesta usa el reloj común ``clk`` de 50MHz. Como el generador de `baud_tick` de la UART, un generador de ticks produce pulsos de habilitación de un ciclo para el barrido; no es un reloj nuevo. La imagen vive en un framebuffer con un puerto de escritura para el procesador y uno de lectura para el barrido, de modo que ambos trabajan al mismo tiempo.

#### Señales de interfaz

| Señal | Descripción |
|-------------|-------------|
| `rst`                                        | Entrada común de reinicio de un bit, síncrona y activa en alto (contrato del curso). Lleva el barrido al reposo con el panel apagado; no borra la imagen. |
| `clk`                                        | Reloj común de todos los bloques, 50MHz en el SoC. |
| `d_in[31:0]`, `addr[4:0]`, `cs`, `rd`, `wr`  | Acceso del procesador. `cs` dura un ciclo por acceso; `addr` es el desplazamiento en bytes dentro de la ventana del periférico. |
| `_out[31:0]`                                 | Dato leído, combinacional mientras `cs` y `rd` estén activos. |
| `enable`                                     | Bit `EN` del registro `CONTROL`: 1 configura el panel y barre. |
| `fb_we`, `fb_waddr[11:0]`, `fb_wdata[2:0]`   | Escritura de un píxel: dirección {_y[5:0]_,_x[5:0]_} y color {_R_,_G_,_B_}. Ocurre en el mismo flanco del acceso a `PIXEL_DATA`. |
| `fb_raddr[10:0]`                             | Dirección de lectura fila[4:0],columna[5:0]}. |
| `top_q[2:0]`, `bot_q[2:0]`   | Píxel de la fila r y de la fila r + 32 en esa columna, leídos al mismo tiempo. |
| `tick`  | Habilitación de un ciclo de `clk` cada `CLK_DIV` ciclos. |

<img width="458" height="881" alt="image" src="https://github.com/user-attachments/assets/856dbdab-4da9-46f3-9d86-1fef25cabd87" />


### 3. 

### 4. Diagrama de flujo del transmisor

### 5. Fundamento: controlador y datapath

### 6. Propuesta de clasificaci´on del flujo de TX

### 7. ASMD:delflujoalastransferenciasporciclo

### 8. Propuesta de bloques de TX: control y datapath

### 9. Máquina de estados del transmisor

### 10. Organizaci´on de m´odulos e implementaci´on Verilog

### 11. Entorno de prueba: testbench, est´ımulos y observaci´on
