# Cómo comprobar en GTKWave los diagramas de tiempos (3a, 3b, 3c)

Los diagramas `diagramas/03a/b/c_*.svg` se dibujaron leyendo el archivo `uart_rx_g1_TB.vcd` que produce la simulación. Si abren ese mismo VCD en GTKWave, deben ver **las mismas formas de onda, los mismos valores y los mismos tiempos** que aparecen en la tabla de abajo.

## 1. Generar el VCD

```bash
cd Grupos/G1/UART/V2/documentacion/sim
make sim                  # iverilog + vvp; debe terminar con "TODAS LAS PRUEBAS PASARON"
```

Esto crea `uart_rx_g1_TB.vcd` en la misma carpeta.

## 2. Abrir GTKWave con las señales de cada diagrama ya puestas

```bash
gtkwave uart_rx_g1_TB.vcd tiempos_3a_byte.gtkw              # diagrama 3a
gtkwave uart_rx_g1_TB.vcd tiempos_3b_trama.gtkw             # diagrama 3b
gtkwave uart_rx_g1_TB.vcd tiempos_3c_resincronizacion.gtkw  # diagrama 3c
```

Cada `.gtkw` carga las señales en el mismo orden que el diagrama. Para encuadrar la ventana de tiempo, escriban los valores en las casillas **From** y **To** de la barra superior de GTKWave (o usen *Time → Zoom → Zoom Best Fit* y luego acerquen):

| Diagrama | From | To |
|---|---|---|
| 3a Un byte | `17 us` | `108 us` |
| 3b Trama completa | `17 us` | `375 us` |
| 3c Resincronización | `1120 us` | `2110 us` |

Los estados aparecen como números: `estado` del byte 0 = IDLE, 1 = START, 2 = DATA, 3 = STOP; `estado` de la trama 0 = B0, 1 = B1, 2 = B2, 3 = B3, 4 = PUB.

## 3. Puntos de control (pongan el cursor y comparen)

Hagan clic en la forma de onda para poner el cursor; el tiempo sale arriba y el valor de cada señal en la columna de valores. Los tiempos pueden variar unos nanosegundos según el redondeo.

### 3a: un byte (`0x11`)

| Tiempo | Qué debe verse |
|---|---|
| 17,731 µs | `uart_rx` baja (bit de start) |
| ~17,8 µs | `estado` pasa a 1 (START), 2 ciclos después porque `rx_in` va retrasada por el sincronizador |
| 22,167 µs | `estado` pasa a 2 (DATA): se confirmó el start a mitad de bit |
| 30,797 µs | primer pulso de `desplazar`; `rx_byte` = `80` |
| 39,46 / 48,13 / 56,80 / 65,47 / 74,13 / 82,80 / 91,47 µs | pulsos siguientes de `desplazar` (uno cada 8,67 µs = 1 bit); `idx` sube de 1 a 7 |
| 91,502 µs | `rx_byte` = `11`, `estado` pasa a 3 (STOP) |
| 100,132 µs | pulso de `byte_listo` (stop = 1) |

Comprobación rápida: la distancia entre dos pulsos de `desplazar` debe ser **8,67 µs ≈ 1/115200 s** (234 ciclos de 37 ns).

### 3b: trama completa C1 (`0x1123ABC1`)

| Tiempo | `estado` trama | `sr` | Otros |
|---|---|---|---|
| 100,13 µs | 0 → 1 | `00000011` | 1.er `byte_listo` + `cargar` |
| 186,91 µs | 1 → 2 | `00001123` | 2.º `byte_listo` |
| 273,73 µs | 2 → 3 | `001123AB` | 3.er `byte_listo` |
| 360,55 µs | 3 → 4 (PUB) | `1123ABC1` | 4.º `byte_listo` |
| 360,58 µs | 4 → 0 | | `publicar` = 1 |
| 360,62 µs | | | `valido` = 1 (1 ciclo), `x` = `ABC`, `y` = `123`, `atk` = 1 |

### 3c: resincronización (caso C4)

| Tiempo | Qué debe verse |
|---|---|
| 1220,90 µs | `byte_listo` del byte suelto `1F`: `estado` 0 → 1 |
| 1307,72 µs | `byte_listo` del byte `FF`: `estado` 1 → 2, `sr` = `80011FFF` |
| 1307 → 1481 µs | `clr_tmo` = 0 (el contador de silencio corre) |
| 1481,09 µs | pulso de `timeout`: `estado` vuelve a 0 **sin** `valido` |
| 1828,55 / 1915,37 / 2002,18 / 2088,96 µs | 4 `byte_listo` de la trama buena: `estado` 1, 2, 3, 4 |
| 2089,04 µs | `valido` = 1 con `x` = 100, `y` = 200 |

La resta 1481,09 − 1307,72 = 173,4 µs = 4680 ciclos × 37,04 ns, que es el `TIMEOUT` del diseño.

## 4. Cómo demostrarlo (evidencia para el informe)

1. **Captura lado a lado:** en GTKWave, *File → Grab To File* (o una captura de pantalla) con la misma ventana de tiempo, y péguenla junto al SVG del diagrama. Deben coincidir flanco por flanco.
2. **Mediciones con marcadores:** pongan el marcador principal (clic) y un segundo marcador (clic central o *Markers → Drop Named Marker*) en dos pulsos de `desplazar`; GTKWave muestra la diferencia (`Delta`) = 8,67 µs. Hagan lo mismo entre el último `byte_listo` y `timeout` en 3c = 173 µs.
3. **Salida de consola:** la salida de `make sim` (`OK C1 ... TODAS LAS PRUEBAS PASARON`) demuestra que los valores publicados son los esperados.
4. **Contraprueba:** compilar el testbench con el `fpga1_uart_rx.v` original (arreglando solo la sintaxis) da `FALLA` en los 9 casos. Eso demuestra que el testbench detecta errores reales.
