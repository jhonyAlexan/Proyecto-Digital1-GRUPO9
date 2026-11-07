# Periférico: Pantalla RGB Matrix

## UART
### 1. Diagrama de caja negra

El periférico controla la matriz **Seengreat RGB Matrix P3.0-64 × 64** desde la FPGA de la Colorlight 5A-75B. El panel tiene 4096 píxeles con un LED rojo, uno verde y uno azul cada uno, se conecta por la interfaz paralela **HUB75** y usa barrido 1/32: solo hay dos filas encendidas a la vez, la fila r y la fila r + 32. El panel no guarda la imagen; la debe refrescar continuamente el controlador, cientos de veces por segundo. 

Para el resto de la consola el controlador es un periférico del SoC: el procesador le escribe registros por el bus estándar del curso y el periférico genera solo las señales del panel.

<img width="979" height="371" alt="image" src="https://github.com/user-attachments/assets/c42d1741-88e8-4f24-b0c8-e3228341c655" />

Figura 1: Vista externa del controlador. A la izquierda, las entradas del bus del procesador; a la derecha, la salida de lectura hacia el bus y las líneas del conector **HUB75** hacia el panel. Cada línea lleva una marca diagonal y un número que indica su ancho en bits.

#### Características iniciales
- Un panel de 64×64 píxeles RGB (1R1G1B), barrido 1/32.
- Seis líneas de color en paralelo: `R1` `G1` `B1` para las filas 0–31 y `R2` `G2` `B2` para las filas 32–63.
- Cinco líneas de dirección de fila `A B C D E` (32 pares de filas).
- Tres líneas de control: `CLK` (desplazamiento), `LAT` (latch) y `OE` (encendido, activo en bajo).
- Las 14 líneas son salidas: la placa no permite leer nada del panel.
- Color de un bit por canal (RGB111): ocho colores.
- La imagen se guarda dentro del periférico (4096 píxeles); el procesador escribe píxeles y el periférico refresca el panel por su cuenta.
- Interfaz con el procesador según el contrato del curso: `clk`, `rst`, `d_in[31:0]`, `cs`, `addr`, `rd`, `wr` y `d_out[31:0]`.
- Configuración del chip driver del panel al habilitar el periférico.
- Brillo ajustable y contador de cuadros mostrados.

Los 64 píxeles de cada fila se envían secuencialmente, uno por pulso de `CLK` y por seis líneas a la vez; no existe un bus de 64 líneas hacia el panel.

#### Aspectos pendientes
La vista de caja negra muestra únicamente las líneas externas. En la siguiente sección se propone la división interna. Quedan pendientes la frecuencia de `CLK`, el tiempo de cada fila y la frecuencia de refresco, que se fijan en el análisis temporal. El reloj y el reset los impone el contrato del curso: `clk` del SoC (50 MHz) y `rst` síncrono activo en alto. El orden de colores (variante normal o GBR del panel) y la orientación de la imagen se confirman con el panel real; no cambian el diseño, solo la asignación de pines.

### 2. Diagrama de bloques

La propuesta usa el reloj común `clk` de 50 MHz. Como el generador de `baud_tick` de la UART, un generador de ticks produce pulsos de habilitación de un ciclo para el barrido; no es un reloj nuevo. La imagen vive en un framebuffer con un puerto de escritura para el procesador y uno de lectura para el barrido, de modo que ambos trabajan al mismo tiempo.

#### Señales de la interfaz

| Señal | Descripción |
|---|---|
| `rst` | Entrada común de reinicio de un bit, síncrona y activa en alto (contrato del curso). Lleva el barrido al reposo con el panel apagado; no borra la imagen. |
| `clk` | Reloj común de todos los bloques, 50 MHz en el SoC. |
| `d_in[31:0]`, `addr[4:0]`, `cs`, `rd`, `wr` | Acceso del procesador. `cs` dura un ciclo por acceso; `addr` es el desplazamiento en bytes dentro de la ventana del periférico. |
| `d_out[31:0]` | Dato leído, combinacional mientras `cs` y `rd` estén activos. |
| `enable` | Bit `EN` del registro `CONTROL`: 1 configura el panel y barre. |
| `brightness[9:0]` | Ticks de cada fila con el panel encendido. |
| `fb_we`, `fb_waddr[11:0]`, `fb_wdata[2:0]` | Escritura de un píxel: dirección `{y[5:0], x[5:0]}` y color `{R, G, B}`. Ocurre en el mismo flanco del acceso a `PIXEL_DATA`. |
| `fb_raddr[10:0]` | Dirección de lectura `{fila[4:0], columna[5:0]}`. |
| `top_q[2:0]`, `bot_q[2:0]` | Píxel de la fila r y de la fila r + 32 en esa columna, leídos al mismo tiempo. |
| `tick` | Habilitación de un ciclo de `clk` cada `CLK_DIV` ciclos. |
| `frame_count[31:0]` | Cuadros completos mostrados; el juego lo usa para sincronizar. |
| `hub75_rgb0[2:0]`, `hub75_rgb1[2:0]` | Líneas R1 G1 B1 y R2 G2 B2. |
| `hub75_row[4:0]` | Líneas EDCBA (bit 0 = A). |
| `hub75_clk`, `hub75_lat`, `hub75_oe` | CLK, LAT y OE del panel; OE es activo en bajo. |

<img width="458" height="881" alt="image" src="https://github.com/user-attachments/assets/856dbdab-4da9-46f3-9d86-1fef25cabd87" />

Figura 2: Diagrama de bloques con entradas a la izquierda, salidas a la derecha, `rst` por arriba y `clk` por debajo. El contorno punteado agrupa los bloques del periférico. Las señales con el mismo nombre representan una conexión común. Las señales del bus y del panel cruzan el contorno. `tick` (en rojo) es una habilitación, no un reloj. Cada línea lleva una marca diagonal y un número que indica su ancho en bits.

#### Mapa de registros propuesto

| Offset | Acceso | Registro | Función |
|---|---|---|---|
| 0x00 | RW | `CONTROL` | Bit 0 EN: 1 configura el panel y barre; 0 apaga al terminar la fila |
| 0x04 | RW | `BRIGHT` | `[9:0]` ticks con OE activo por fila (reset 512) |
| 0x08 | RW | `PIXEL_ADDR` | `[5:0] = x`, `[11:6] = y` del próximo píxel |
| 0x0C | W | `PIXEL_DATA` | `[2:0] = {R,G,B}` escribe el píxel e incrementa `PIXEL_ADDR` |
| 0x10 | R | `FRAME` | Cuadros completos mostrados |

#### Revisión y aspectos pendientes
Todos los bloques usan `clk`. A diferencia de la UART, aquí la división del reloj puede ser entera: con `CLK_DIV = 2` se obtiene un tick cada 40 ns sin error de frecuencia, porque el panel no exige una velocidad exacta.

El framebuffer se divide en dos memorias de 2048 × 3 bits, una por mitad del panel, porque en cada pulso de `CLK` el panel necesita un píxel de cada mitad. Para que la síntesis use los bloques de RAM de la ECP5, la lectura será síncrona: el dato llega un ciclo después de la dirección. El análisis temporal debe garantizar que esté listo antes de enviarlo al panel.

El procesador puede escribir mientras se barre. Si cambia la imagen a mitad de un barrido se verá un cuadro mezclado; se decidirá si basta con sincronizar el dibujo con `FRAME` o si hace falta un segundo framebuffer.

### 3. Análisis temporal del barrido

Antes de definir los bloques internos del barrido se describe el envío de un par de filas. Como ejemplo se usa la fila r = 1 (y su pareja, la fila 33) de la imagen de prueba: borde blanco, diagonal roja y cuadros de colores. El envío empieza por la columna 0.

| Columna | c0 | c1 | c2 | ... | c62 | c63 |
|---|---|---|---|---|---|---|
| **Fila 1** (R1 G1 B1) | 111 blanco | 100 rojo | 000 negro | ... | 111 blanco | 111 blanco |
| **Fila 33** (R2 G2 B2) | 111 blanco | 100 rojo | 100 rojo | ... | 011 cian | 111 blanco |

Cada par de filas pasa por tres fases: desplazar las 64 columnas (SHIFT), copiarlas a las salidas del panel (LATCH) y mostrarlas (DISPLAY). La unidad de tiempo es el tick: con `clk = 50 MHz` y `CLK_DIV = 2`, un tick ocurre cada 40 ns.

<img width="898" height="607" alt="Captura de pantalla 2026-11-07 002549" src="https://github.com/user-attachments/assets/a83577d7-1b8d-4135-a5e2-54df7a6a2f9c" />


Figura 3: Secuencia funcional del barrido del par de filas 1/33, con `BRIGHT = 4` para que se vea. Los pulsos de tick se ensanchan para hacerlos visibles; en realidad duran un ciclo de `clk`. Las marcas oblicuas indican tiempo omitido (columnas c3 a c61 y parte de DISPLAY). L = LATCH.

#### Secuencia de envío
1. **Punto de partida.** Termina la visualización de la fila anterior (fila 0): `OE = 1` (apagado), `CLK = 1`, `LAT = 0`, `ROW = 0`. En t_s empieza el desplazamiento de la fila 1.
2. **Desplazamiento.** Cada columna usa dos ticks. El primero presenta en `hub75_rgb0` el color de (1, c) y en `hub75_rgb1` el de (33, c), y baja `CLK`. El segundo sube `CLK`: en ese flanco el panel captura las seis líneas. Para el ejemplo: c0 = 111/111, c1 = 100/100, c2 = 000/100, c63 = 111/111. Dos columnas seguidas del mismo color no producen transición en esas líneas. Tras 64 pulsos, 128 ticks después de t_s, el panel tiene la fila completa en sus registros internos, pero todavía no la muestra.
3. **Latch.** En t_L, con el panel apagado, un tick sube `LAT` y cambia `ROW` a 1. El panel copia las 64 columnas a sus salidas.
4. **Visualización.** En t_on, el tick siguiente baja `LAT` y activa `OE`. El panel queda encendido durante `BRIGHT` ticks y apagado el resto de la fase, que dura siempre `DISPLAY_TICKS` ticks.
5. **Siguiente fila.** En t_s + T_fila empieza el desplazamiento de la fila 2 con `OE = 1`. Después de mostrar la fila 31 se vuelve a la 0 y se cuenta un cuadro en `FRAME`.

#### Configuración del driver al habilitar
Los ejemplos del fabricante (rutina `Reginit()` para Arduino y Raspberry Pi Pico) escriben dos registros del chip driver antes de mostrar imágenes. El driver distingue un latch de datos de una escritura de registro por el número de pulsos de `CLK` que recibe con `LAT` alto: 0 para datos, 11 para el registro 1 y 12 para el registro 2. Las seis líneas de color llevan el mismo bit.

| Registro | Bit enviado en la columna c | LAT alto en | Pulsos con LAT |
|---|---|---|---|
| 1 | C12[c mod 16] = 0, 1, 1, ..., 1 | c = 53 ... 63 | 11 |
| 2 | C13[c mod 16]: solo c mód 16 = 9 vale 1 | c = 52 ... 63 | 12 |

<img width="909" height="362" alt="image" src="https://github.com/user-attachments/assets/0cfb0427-93eb-48d4-89e3-194ba9b3b285" />

Figura 4: Configuración del driver: dos palabras de 64 pulsos antes del primer barrido. `LAT` sube con el dato de la columna 53 (registro 1) o 52 (registro 2) y baja con el primer dato de la palabra siguiente.

#### Relación entre tiempos
Con `clk = 50 MHz`, `CLK_DIV = 2` y `DISPLAY_TICKS = 1024`:
- T_tick = CLK_DIV * T_clk = 2 * 20 ns = 40 ns
- T_shift = 64 * 2 * T_tick = 128 * T_tick = 5,12 µs
- T_display = DISPLAY_TICKS * T_tick = 1024 * 40 ns = 40,96 µs
- f_CLK = 1 / (2 * T_tick) = 12,5 MHz
- T_latch = T_tick = 40 ns
- T_fila = (128 + 1 + 1024) * T_tick = 1153 * 40 ns = 46,12 µs
- T_cuadro = 32 * T_fila = 1,476 ms => f_refresco ≈ 678 Hz
- T_config = 2 * 128 * T_tick = 10,24 µs (una sola vez)
- Fracción encendida = BRIGHT / 1153 (0 a 88,7%)

Los pulsos de tick duran un ciclo de `clk` (20 ns), no un tick completo; los diagramas son funcionales y no representan esa escala. `tick` se comprueba como nivel alto en un flanco de subida de `clk`; no se usa su flanco como reloj. El generador funciona siempre: habilitar el periférico no lo reinicia.

Criterios: por encima de unos 100-200 Hz no se percibe parpadeo, y 678 Hz deja margen. Un `CLK` de 12,5 MHz es moderado para el cable plano y los buffers 74HC245 de la placa; si el panel real muestra ruido, se sube `CLK_DIV` sin cambiar nada más (con 4: 6,25 MHz y ≈ 640 Hz). El brillo no cambia el refresco: DISPLAY siempre dura lo mismo. Para la prueba en placa sin procesador, con el reloj de 25 MHz de la tarjeta, todos los tiempos se duplican (≈ 339 Hz).

La figura 5 muestra una columna a escala de `clk`: entre el cambio de columna y el tick que presenta el dato pasan `CLK_DIV` ciclos, y la memoria entrega el dato un ciclo después de recibir la dirección.

<img width="927" height="395" alt="image" src="https://github.com/user-attachments/assets/1b38dff5-4934-4023-bfa3-58e59a09e489" />

Figura 5: Detalle de tres columnas con `CLK_DIV = 2`. La columna avanza cuando sube `hub75_clk`; el dato leído llega un ciclo después y el siguiente tick lo presenta.

#### Condiciones para el diseño interno
- La imagen se lee del framebuffer con la dirección `{fila, columna}` y el dato llega un ciclo después. Por eso `CLK_DIV >= 2`; con 1 se presentaría el dato de la columna anterior.
- `hub75_clk` descansa en 1. En cada columna, el tick con `CLK = 1` presenta el dato y baja el reloj; el tick con `CLK = 0` lo sube y avanza la columna. El propio nivel de `CLK` indica la fase, sin un registro adicional.
- `OE` debe estar inactivo mientras sube `CLK`, mientras `LAT = 1` y cuando cambia `ROW`; solo se activa en DISPLAY.
- Las 14 salidas al panel salen directamente de registros, para evitar pulsos espurios por retardos combinacionales, y cambian en el mismo flanco que la transición, sin un ciclo de retraso.
- La configuración del driver ocurre cada vez que el periférico sale del reposo; así se puede reconfigurar el panel si se alimentó después de la FPGA.
- Si `EN` baja, se termina la fila en curso y se apaga; no se corta un pulso a la mitad.
- El reset (síncrono, activo en alto) deja `OE = 1`, `CLK = 1`, `LAT = 0` y la fila en 0, y no borra la imagen.
- El procesador puede escribir píxeles en cualquier ciclo; para no mezclar cuadros, el juego espera a que cambie `FRAME`. No se presupone doble framebuffer.

Estas reglas se formalizan en el diagrama de flujo, el ASMD y la máquina de estados de los pasos siguientes.

---

### Referencias
- Seengreat, RGB-Matrix-P3.0-64x64 (y variante GBR), repositorio en GitHub, organización seengreat.
- q3k, chubby75: 5a-75b/hardware_V8.0.md (pines de la Colorlight 5A-75B).
- LiteX Boards: litex_boards/platforms/colorlight_5a_75b.py.
- C. Ababei, FSM, ASM, FSMD, ASMD, Lecture 4, Marquette University.
