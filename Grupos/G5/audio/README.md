# Periférico: Audio

El procesador femtoRV32 escribe en registros mapeados en memoria qué sonido generar, y el periférico produce la señal que llega al parlante. El periférico genera tonos de onda cuadrada con muestras de 8 bits y las envía por I2S al amplificador MAX98357A, que maneja el parlante.

![Del procesador al parlante](diagramas/fig1_cadena_audio.png)

*Figura 1. Recorrido de la señal. Cada número indica la subsección de la sección 1 que explica esa parte.*

El documento sigue el diseño descendente: teoría (1), funcionamiento (2), diseño (3), Verilog (4), simulación (5) e implementación en placa (6). El estado de cada sección está en el [README del equipo](../README.md).

## 1. Marco teórico

> **Hecho.** Listo cuando: los conceptos que el lector necesita (generación digital de tonos, método de salida elegido, periféricos mapeados en memoria) están explicados y con fuentes citadas.

Esta sección sigue el camino del sonido, como en la figura 1: cómo se digitaliza (1.1), cómo un circuito genera un tono (1.2), cómo la muestra viaja por I2S (1.3) hasta el amplificador (1.4), cómo se ajusta a 8 bits y a la memoria disponible (1.5) y cómo el procesador controla el periférico (1.6). La 1.7 explica por qué se eligió I2S y no el PWM que propone el curso, y la 1.8 reúne las decisiones. Lo que lleva un número entre corchetes viene de la fuente con ese número en las referencias; las demás cifras las calculamos nosotros con los datos del texto, y se pueden repetir.

### 1.1 Muestreo y cuantización

Un sonido digital es una secuencia de muestras tomadas a una frecuencia fs. Por el teorema de Nyquist solo se representan frecuencias menores que fs/2; si la señal tiene componentes por encima de ese límite hay aliasing, y esas componentes aparecen como una frecuencia más baja [1].

Cada muestra se cuantiza con N bits; con N = 8 hay 256 niveles. La relación señal-ruido ideal de un convertidor de N bits, con una senoidal de escala completa, es [2]:

$$
\mathrm{SNR} = 6{,}02\,N + 1{,}76\ \mathrm{dB}
$$

Con 8 bits resultan 49,9 dB y con 16 bits, 98,1 dB. Para tonos y efectos de un juego alcanza; para música de alta fidelidad, no.

### 1.2 Generación de tonos: acumulador de fase

Un registro de fase de 16 bits aumenta en `FREQ` en cada muestra, y la muestra de salida depende de su bit más significativo:

$$
\mathrm{fase}[n+1] = \left(\mathrm{fase}[n] + \mathrm{FREQ}\right) \bmod 2^{16}
$$

$$
\mathrm{muestra}[n] =
\begin{cases}
{+}\mathrm{VOL} & \text{si } \mathrm{fase}_{15}[n] = 1 \\
{-}\mathrm{VOL} & \text{si } \mathrm{fase}_{15}[n] = 0
\end{cases}
$$

El registro da una vuelta completa cada 2<sup>16</sup>/FREQ muestras, y en cada vuelta el bit 15 completa un ciclo. La frecuencia de salida es entonces:

$$
f_{\mathrm{salida}} = \frac{\mathrm{FREQ} \cdot f_s}{2^{16}}
$$

Como la amplitud ±VOL es simétrica, la salida no tiene componente continua. La figura 2 lo muestra con un ejemplo.

![Acumulador de fase](diagramas/fig2_acumulador_fase.png)

*Figura 2. Con FREQ = 8192 el registro da una vuelta cada 8 muestras, y el bit 15 forma la onda cuadrada de ±VOL.*

La resolución en frecuencia es lo que cambia la salida por cada unidad de `FREQ`, es decir fs/2<sup>16</sup>: con fs = 48 828 Hz, unos 0,75 Hz. Como `FREQ` es entero, el error máximo de una nota es la mitad, unos 0,37 Hz. Cada bit más en el registro de fase reduce la resolución a la mitad, y cuanto mayor es fs, más grueso es cada paso.

Para una nota de número MIDI m, con A4 (m = 69) fijada por convención en 440 Hz [3], la frecuencia en afinación temperada es:

$$
f_m = 440 \cdot 2^{\frac{m-69}{12}}\ \mathrm{Hz}
$$

y el valor que se escribe en `FREQ` es el entero más cercano a:

$$
\mathrm{FREQ} = \mathrm{round}\left(\frac{f_m \cdot 2^{16}}{f_s}\right)
$$

Con fs = 48 828,125 Hz, A4 da `FREQ` = 591 (440,33 Hz) y el do central, C4 (m = 60, 261,63 Hz), da `FREQ` = 351 (261,52 Hz). Esos valores suponen HCLK = 25 MHz y 512 ciclos por trama; con otro reloj cambia fs (1.4) y `FREQ` se recalcula con la misma fórmula.

### 1.3 El bus I2S

I2S transmite audio con tres líneas. La especificación original las llama SCK, WS y SD [4]; el datasheet del MAX98357A las llama BCLK, LRCLK y DIN [5], que son los nombres de este documento. BCLK es el reloj de bit, con un pulso por cada bit de dato. LRCLK elige el canal (0 izquierdo, 1 derecho) y marca el comienzo de cada palabra. DIN lleva los datos en serie, con el bit más significativo (MSB) primero y en complemento a dos [4].

La especificación deja libre el flanco en el que el transmisor cambia las señales y pide que el receptor capture DIN en el flanco de subida de BCLK [4]. Aquí el transmisor cambia DIN y LRCLK en el flanco de bajada, de modo que DIN llega estable al flanco de subida. El MSB de cada palabra aparece un período de BCLK después del cambio de LRCLK [4], y esa es la característica del modo I2S. Cada trama contiene un slot izquierdo y uno derecho, y dura 1/fs.

Con dos slots de N<sub>slot</sub> bits por trama, el reloj de bit debe valer:

$$
f_{\mathrm{BCLK}} = 2 \cdot N_{\mathrm{slot}} \cdot f_s
$$

Con N<sub>slot</sub> = 16, BCLK vale 32 veces fs, una de las relaciones que admite el amplificador (1.4).

### 1.4 El amplificador MAX98357A

El MAX98357A es un amplificador clase D con entrada digital PCM [5]. Recibe LRCLK, BCLK y DIN sin necesitar MCLK y no requiere filtro de salida [5], así que la FPGA no necesita conversor ni filtro externos. Acepta datos de 16, 24 o 32 bits por slot en modo I2S; la variante A espera I2S estándar y la B, datos justificados a la izquierda [5]. El canal se elige con el pin SD_MODE, que también lo apaga, y la ganancia, de 3 a 15 dB, con el pin GAIN_SLOT. Los dos son pines de configuración física, no registros, y sus valores están en 2.2 [5, 6].

Lo que más condiciona el diseño es que el amplificador no acepta cualquier frecuencia de muestreo. El datasheet indica que LRCLK solo admite 8, 16, 32, 44,1, 48, 88,2 y 96 kHz, y que 11,025, 12, 22,05 y 24 kHz no están soportadas [5]. Su tabla de características eléctricas da cuatro intervalos de LRCLK: de 7,6 a 8,4 kHz, de 15,2 a 16,8 kHz, de 30,4 a 50,4 kHz y de 83,8 a 100,8 kHz [5]. Además, BCLK debe valer 32, 48 o 64 veces LRCLK y estar entre 0,2432 y 25,804 MHz [5].

Con BCLK igual a 32 veces LRCLK y k ciclos de HCLK por cada BCLK, la frecuencia de muestreo es:

$$
f_s = \frac{\mathrm{HCLK}}{32 \cdot k}
$$

La tabla muestra qué ocurre con los dos relojes del proyecto, 25 MHz y 27 MHz (el de la Tang Nano 9K):

| HCLK | Ciclos por trama | k | fs | Intervalo del datasheet |
|---|---|---|---|---|
| 25 MHz | 512 | 16 | 48 828 Hz | fS3 (1,7 % sobre 48 kHz): elegido |
| 25 MHz | 1024 | 32 | 24 414 Hz | ninguno |
| 27 MHz | 576 | 18 | 46 875 Hz | fS3 (2,3 % bajo 48 kHz): elegido |
| 27 MHz | 512 | 16 | 52 734 Hz | ninguno, supera 50,4 kHz |
| 27 MHz | 1024 | 32 | 26 367 Hz | ninguno |

Por eso el diseño tiene un parámetro, `CICLOS_TRAMA`, que vale 512 con HCLK = 25 MHz y 576 con 27 MHz. Con 25 MHz, 512 es potencia de 2 y basta un contador libre de 9 bits (2.3.3); con 27 MHz hacen falta dos contadores encadenados. Para cualquier otro reloj se elige el k entero que deje fs dentro de un intervalo. El resto de los requisitos se cumple con el diseño: BCLK de 1,5625 MHz con 25 MHz y de 1,5 MHz con 27 MHz, 16 bits por slot, formato I2S y sin MCLK. Como el fabricante declara no soportada una LRCLK fuera de los intervalos, fs queda siempre dentro de uno de ellos.

### 1.5 Muestras de 8 bits y uso de memoria

La interfaz del MAX98357A acepta 16, 24 o 32 bits por slot, no 8 [5]. Por eso se usa un slot de 16 bits con la muestra de 8 bits (con signo, de −128 a 127) en los bits 15:8; el transmisor fuerza a cero los bits 7:0 y esos ocho ceros no se almacenan. Cada muestra se envía en ambos slots, así el sonido es el mismo con SD_MODE en izquierdo, derecho o mezcla. Si el contenido viniera de audio de 8 bits sin signo, como el WAV, bastaría invertir el MSB (`XOR 0x80`) para pasarlo a complemento a dos.

Usar 8 bits busca ocupar poca memoria. La RAM del SoC es de 26 212 bytes y compite con el código y con la pila (1024 B), así que el diseño no almacena audio: genera tonos.

| Método | Memoria de datos | Observación |
|---|---|---|
| Generador de tonos (acumulador de fase) | 0 bytes de RAM | Elegido; solo usa registros (`FREQ`, `VOL`, fase y contador) |
| PCM de 8 bits a fs = 48 828 Hz | 48 828 B por segundo (186 % de la RAM) | No cabe |
| PCM de 8 bits con cada muestra repetida 6 veces (8,138 kHz) | 8 138 B por segundo (31 % de la RAM) | Cabe, pero no se usa |

Con ondas cuadradas la muestra solo toma dos valores, +VOL y −VOL, así que más resolución no mejora el timbre. Con 16 bits la relación señal-ruido ideal sería de 98,1 dB en lugar de 49,9 dB, pero con PCM la memoria se duplicaría: un segundo a 8,138 kHz pasaría de 8 138 B a 16 276 B. Como el transmisor ya envía palabras de 16 bits, pasar a 16 bits más adelante solo exige ensanchar VOL y la muestra y cargar los bits 7:0 en lugar de ceros; el bus y la temporización no cambian.

### 1.6 Periférico mapeado en memoria

El procesador accede al periférico con cargas y almacenamientos a direcciones fijas (MMIO), sin instrucciones especiales. La estructura (decodificador local, control de registros y núcleo) sigue la de UART8N1, descrita en la sección 12 de su guía [7]. A diferencia de la UART, aquí no hay protocolo de aceptación (START/BUSY/DONE): los registros fijan el sonido y el hardware lo mantiene hasta que se cambien.

Esta es la arquitectura del curso: un solo bus de memoria con periféricos mapeados en memoria [8]. El manual de RISC-V explica que unos rangos de direcciones pueden ser memoria principal y otros, dispositivos de E/S, y que un acceso a un dispositivo puede tener efectos secundarios visibles, a diferencia de un acceso a memoria [9]. En el SoC, cuando el firmware escribe en la ventana de un periférico, el adaptador del bus (`WishbonePeripheral`) le entrega durante un ciclo `cs`, `wr`, `addr` (el desplazamiento dentro de la ventana) y `d_in` (el valor escrito), y responde `ack` al bus [10]. Como `d_in` solo es válido ese ciclo, el periférico guarda el valor en un registro propio y genera el sonido por sí mismo a partir de él. Por eso `FREQ`, `VOL` y `CONTROL` son registros, con el mapa de 2.4.

### 1.7 Por qué I2S y no PWM

El documento de la fase de diseño propone dos métodos de salida de audio: PWM a un parlante pequeño («simple, sin DAC») o I2S hacia un DAC externo («más fiel, más pines y más estudio»), y pide justificar «por qué esa y no otra» [8]. Usamos I2S. Para justificar la elección hay que entender primero cómo funciona el PWM.

El PWM es una señal digital de frecuencia fija cuyo ciclo de trabajo D, la fracción del período en alto, se modula. El ciclo de trabajo fija la amplitud de la señal analógica: con 50 % se obtiene la mitad de la tensión de alimentación [11]. El valor medio de la salida es:

$$
\bar{V} = D \cdot V_{DD}, \qquad 0 \le D \le 1
$$

Para recuperar la señal analógica se usa un filtro pasa bajos, por ejemplo un RC pasivo, que elimina la frecuencia base del PWM [11]. Eso exige que el ancho de banda de la señal, F<sub>bw</sub>, sea mucho menor que la frecuencia del PWM, F<sub>PWM</sub> [12]:

$$
F_{bw} \ll F_{PWM}
$$

Si la señal va a una entrada de baja impedancia, como un parlante, hace falta además un buffer entre el filtro y la carga [11]. La frecuencia del PWM depende del reloj y de los bits B del contador: si el contador avanza un paso por ciclo de reloj y un período es una vuelta completa,

$$
F_{PWM} = \frac{f_{clk}}{2^{B}}
$$

Con 27 MHz, 8 bits dan 105,5 kHz y 10 bits, 26,4 kHz. Más bits dan más niveles de amplitud pero bajan la frecuencia del PWM, que debe seguir muy por encima del ancho de banda de la señal [12].

| | PWM | I2S con MAX98357A |
|---|---|---|
| Pines de la FPGA | 1 [8] | 3: BCLK, LRCLK y DIN [4] |
| Conversión a analógico | Filtro pasa bajos y, para un parlante, buffer [11] | La hace el amplificador, sin filtro de salida [5] |
| Qué limita la resolución | Los bits B del contador frente a la frecuencia del PWM | Los bits por slot del amplificador: 16, 24 o 32 [5] |
| Condición del reloj | F<sub>bw</sub> mucho menor que F<sub>PWM</sub> [12] | BCLK de 32, 48 o 64 veces LRCLK y LRCLK dentro de los intervalos de 1.4 [5] |

Elegimos I2S por tres razones. La primera es la integración: el amplificador recibe la muestra digital y entrega la salida para el parlante sin filtro externo [5], mientras que con PWM hay que armar filtro y buffer [11]. La segunda es que resolución y reloj son independientes: en PWM compiten por el mismo reloj, y en I2S los bits por muestra y fs se eligen por separado, con las condiciones de 1.4. La tercera es el crecimiento: la muestra de 8 bits cabe en un slot de 16 y pasar a 16 bits no cambia el bus (1.5). El costo es el que anticipa el curso: tres pines en vez de uno y más estudio, porque hay que diseñar el transmisor I2S y cumplir su temporización [8]. Para una onda cuadrada de dos niveles bastaría un pin que alterne a la frecuencia del tono, pero ese camino cierra la puerta a más niveles de amplitud.

### 1.8 Decisiones de diseño

| Tema | Decisión | Se aplica en |
|---|---|---|
| Salida | I2S hacia el MAX98357A con BCLK, LRCLK y DIN, sin MCLK | 2.2 y 3.2 |
| Frecuencia de muestreo | `CICLOS_TRAMA` = 512 con 25 MHz y 576 con 27 MHz; BCLK = 32 × LRCLK | 2.3, 3.3 y 3.6 |
| Tono | Acumulador de fase de 16 bits y onda cuadrada de ±VOL | 2.4 y 3.3 |
| Muestra | 8 bits con signo en los bits 15:8 de un slot de 16, repetida en ambos slots; no se almacena audio | 2.1 y 3.3 |
| Registros | `FREQ`, `VOL` y `CONTROL` desde `0x00430000`; los valores se aplican en la siguiente muestra | 2.4 y 3.2 |
| Configuración del módulo | GAIN sin conectar (9 dB); SD queda como viene en el módulo y el silencio se hace con `CONTROL.ENABLE` = 0 | 2.2 |

## 2. Fundamento

> **Hecho.** Listo cuando: el principio de funcionamiento del periférico cabe en uno o dos párrafos claros.

### 2.1 Principio de funcionamiento

El CPU no produce el audio muestra a muestra. Solo escribe `FREQ`, `VOL` y `ENABLE`, y el periférico genera el sonido por sí mismo. Un generador de tonos (acumulador de fase) calcula una muestra de 8 bits con signo una vez por trama, cada 512 ciclos de HCLK (20,48 µs, fs = 48 828 Hz).

Un transmisor I2S coloca esa muestra en los 8 bits altos de una palabra de 16, la repite en los slots izquierdo y derecho y la serializa por DIN. BCLK vale HCLK/16 = 1,5625 MHz y LRCLK vale HCLK/512. El MAX98357A recibe la muestra y maneja el parlante con su salida clase D. Todas las salidas son registradas y salen de un único contador libre, de modo que BCLK, LRCLK y DIN quedan alineados sin generador de ticks separado.

Las cifras de esta sección son las de HCLK = 25 MHz, con `CICLOS_TRAMA` = 512. Con 27 MHz el parámetro vale 576, cada BCLK dura 18 ciclos de HCLK y fs = 46 875 Hz.

### 2.2 Conexiones del módulo MAX98357A

El FPGA actúa como maestro I2S: BCLK, LRCLK y DIN son salidas del FPGA y entradas del módulo, y las tres trabajan a 3,3 V. El módulo no devuelve datos.

```
FPGA (peripheral_audio)              Módulo MAX98357A
audio_bclk   ─────────────────────►  BCLK   reloj de bit, 1,5625 MHz
audio_lrclk  ─────────────────────►  LRC    reloj de trama, 48,828 kHz (0 = izq., 1 = der.)
audio_din    ─────────────────────►  DIN    datos en serie, MSB primero
3V3 o 5V     ─────────────────────►  VIN    alimentación (3,3 a 5 V)
GND          ─────────────────────►  GND    tierra común
(sin conectar)                       GAIN   ganancia por cableado (9 dB)
(sin conectar)                       SD     apagado y selección de canal
                                     + / −  parlante de 4 a 8 Ω, salida en puente
```

| Pin | Qué representa | Notas |
|---|---|---|
| VIN | Alimentación (3,3 a 5 V) | El clase D toma picos de corriente; con 5 V suena más fuerte. |
| GND | Referencia común de tierra | Obligatorio. Sin tierra común, BCLK, LRC y DIN no tienen referencia. |
| BCLK | Reloj de bit | Marca cuándo leer DIN. |
| LRC | Reloj de trama (LRCLK) | 0 = izquierdo, 1 = derecho. Su frecuencia es fs. |
| DIN | Datos de audio | Bits de la muestra, MSB primero. |
| GAIN | Ganancia, fija por cableado | Ver abajo. No la controla el FPGA. |
| SD | Apagado y selección de canal | Ver abajo. |
| + / − | Salida al parlante (4 a 8 Ω) | La salida es en puente: ningún terminal se conecta a GND. |

**GAIN** (Tabla 8 del datasheet [5], con los mismos valores que el módulo DFRobot [6]): GAIN a GND por 100 kΩ → 15 dB; GAIN a GND → 12 dB; sin conectar → 9 dB; GAIN a VDD → 6 dB; GAIN a VDD por 100 kΩ → 3 dB. Se deja sin conectar (9 dB).

**SD** (Tabla 5 del datasheet [5]): por debajo de 0,16 V el amplificador se apaga. Con 0,16 a 0,77 V sale la mezcla izquierdo/derecho; con 0,77 a 1,4 V el canal derecho; sobre 1,4 V el izquierdo. SD no se conecta al FPGA y queda como viene en el módulo. Como se envía la misma muestra en ambos slots, cualquier selección suena igual, y para silenciar el parlante se usa `CONTROL.ENABLE` = 0.

Los pines físicos de BCLK, LRCLK y DIN se asignan en 3.2.

### 2.3 Diagrama de tiempos

Parámetros: HCLK = 25 MHz, 16 HCLK por BCLK, 16 BCLK por slot y 32 BCLK por trama.

| Magnitud | Valor |
|---|---|
| Período de BCLK | 16 HCLK = 640 ns (1,5625 MHz) |
| Período de trama = 1/fs | 512 HCLK = 20,48 µs (fs = 48 828,125 Hz) |
| Duración de un slot | 16 BCLK = 256 HCLK |
| Frecuencia máxima representable | fs/2 ≈ 24,4 kHz |

Con HCLK = 27 MHz, cada BCLK dura 18 HCLK y la trama, 576 HCLK; la estructura es la misma.

#### 2.3.1 Trama completa

![Trama I2S completa](diagramas/fig3_trama_i2s.png)

*Figura 3. LRCLK y DIN en los slots izquierdo y derecho de una trama.*

La figura 3 muestra una trama completa. La misma muestra de 8 bits se envía en el slot izquierdo y en el derecho. En cada slot, los 8 bits de la muestra ocupan los bits 15:8 de la palabra y los bits 7:0 son ceros. Cada palabra de DIN comienza un BCLK después del cambio de LRCLK.

#### 2.3.2 Detalle en el cambio de LRCLK

![Detalle del cambio de LRCLK](diagramas/fig4_detalle_lrclk.png)

*Figura 4. BCLK, LRCLK y DIN alrededor del cambio de LRCLK.*

La figura 4 amplía el instante en que cambia LRCLK. LRCLK y DIN cambian en los flancos de bajada de BCLK, y el receptor muestrea en los flancos de subida (flechas). `r1` y `r0` son los dos últimos bits de la palabra anterior (slot derecho). LRCLK baja en la mitad de P0; en el flanco de subida de P1 el receptor todavía lee `r0`, y `s7` (el MSB) se muestrea recién en P2. Después de `s0` siguen ocho ceros hasta completar los 16 bits del slot.

#### 2.3.3 Relación con HCLK

Dos contadores marcan el tiempo. `cnt_bclk` cuenta de 0 a `CICLOS_BCLK` − 1 dentro de cada período de BCLK (16 ciclos con 25 MHz, 18 con 27 MHz), y `cnt_bit` cuenta los 32 períodos de BCLK de la trama (0…31). De ellos salen todas las señales:

| Señal | Cómo se obtiene |
|---|---|
| `audio_bclk` | Vale 0 en la primera mitad de `cnt_bclk` y 1 en la segunda |
| `tick_bajada` | Vale 1 cuando `cnt_bclk` = `CICLOS_BCLK` − 1: el siguiente flanco de HCLK es el de bajada de BCLK |
| `cnt_bit` | Avanza en cada `tick_bajada`; es el índice del bit que se está enviando |

LRCLK y DIN solo se actualizan con `tick_bajada`, por eso cambian siempre en el flanco de bajada de BCLK. Así el mismo diseño sirve con 25 MHz y con 27 MHz, cambiando solo `CICLOS_BCLK`. Los bloques y la máquina de estados que usan estos contadores están en 3.3 y 3.6.

### 2.4 Mapa de registros

Los registros ocupan la región global libre `0x0043` (base `0x00430000`). Al conectar el periférico, `chip_select` y el mux de lectura del SoC incluyen esa región.

| Dirección | Registro | Bits | Función |
|---|---|---|---|
| `0x00430000` | FREQ | 15:0 | Incremento de fase; f = FREQ·fs/65536 |
| `0x00430004` | VOL | 6:0 | Amplitud de la onda cuadrada (0…127) |
| `0x00430008` | CONTROL | 0 | ENABLE: 1 = sonido, 0 = silencio (muestra 0) |

Los valores se aplican en la siguiente muestra. Escribirlos mientras suena es seguro, porque la fase no se reinicia. Los demás bits se leen como cero y las escrituras fuera de estos offsets se ignoran, igual que en UART8N1.

### 2.5 Criterios de comprobación

- BCLK tiene período de 16 HCLK y ciclo de trabajo 50 %.
- LRCLK vale 0 durante 16 BCLK y 1 durante 16 BCLK; la trama dura 512 HCLK.
- El MSB aparece un BCLK después del cambio de LRCLK. DIN solo cambia en flancos de bajada de BCLK.
- Los bits 7:0 de cada slot son cero. Ambos slots llevan la misma muestra.
- Con `FREQ = 591` y `VOL = 64`, la salida alterna ±64 con frecuencia 440,33 Hz ± la resolución de la medición.
- Con `ENABLE = 0`, DIN vale 0 en todos los bits.
- Reset síncrono activo alto: BCLK, LRCLK y DIN quedan en reposo.

## 3. Etapa de diseño

### 3.1 Diagrama de caja negra

> **Hecho.** Listo cuando: todas las entradas y salidas tienen nombre, sin mostrar nada del interior.

La caja negra muestra el periférico desde afuera. A la izquierda llegan las señales del bus del procesador; a la derecha salen la respuesta al bus y las tres líneas I2S hacia el MAX98357A.

![Caja negra de peripheral_audio](diagramas/fig5_caja_negra.png)

*Figura 5. Entradas y salidas de `peripheral_audio`.*

### 3.2 Características de la interfaz

> **Hecho.** Listo cuando: cada señal tiene nombre, dirección y ancho; están el mapa de registros, la salida hacia el parlante, los pines y los voltajes.

**Señales.** Los nombres son los mismos del Verilog.

| Señal | Dirección | Bits | Lado | Descripción |
|---|---|---|---|---|
| `clk` | Entrada | 1 | Bus | Reloj del SoC (HCLK): 25 MHz en la consola y 27 MHz en la Tang Nano 9K |
| `rst` | Entrada | 1 | Bus | Reinicio síncrono, activo en alto |
| `cs` | Entrada | 1 | Bus | Selección del periférico, un ciclo por acceso |
| `rd` | Entrada | 1 | Bus | Acceso de lectura |
| `wr` | Entrada | 1 | Bus | Acceso de escritura |
| `addr` | Entrada | 4 | Bus | Desplazamiento en bytes; se usan `addr[3:2]` |
| `d_in` | Entrada | 32 | Bus | Dato que escribe el procesador |
| `d_out` | Salida | 32 | Bus | Registro leído; los bits sin uso valen 0 |
| `ack` | Salida | 1 | Bus | Vale 1 el ciclo siguiente a `cs`: el acceso terminó |
| `audio_bclk` | Salida | 1 | I2S | Reloj de bit: HCLK / `CICLOS_BCLK` |
| `audio_lrclk` | Salida | 1 | I2S | Canal: 0 izquierdo, 1 derecho; su frecuencia es fs |
| `audio_din` | Salida | 1 | I2S | Muestra en serie, MSB primero |

**Parámetro.** `CICLOS_BCLK` vale 16 con 25 MHz y 18 con 27 MHz. La trama dura 32 × `CICLOS_BCLK` ciclos de HCLK (512 o 576), con los valores de 2.3.

**Registros.** Son los de 2.4, y además se pueden leer. Desde el firmware se usan así:

```c
#define AUDIO_FREQ    (*(volatile unsigned int *) 0x00430000)
#define AUDIO_VOL     (*(volatile unsigned int *) 0x00430004)
#define AUDIO_CONTROL (*(volatile unsigned int *) 0x00430008)

AUDIO_FREQ = 591;     /* La4: 440,33 Hz con fs = 48 828 Hz */
AUDIO_VOL = 64;       /* amplitud ±64 */
AUDIO_CONTROL = 1;    /* ENABLE = 1: suena */
```

**Conexión eléctrica.**

| FPGA | MAX98357A | Nivel |
|---|---|---|
| `audio_bclk` | BCLK | 3,3 V (LVCMOS33) |
| `audio_lrclk` | LRC | 3,3 V (LVCMOS33) |
| `audio_din` | DIN | 3,3 V (LVCMOS33) |
| 5 V de la placa | VIN | Alimentación del amplificador |
| GND | GND | Tierra común |
| Sin conectar | GAIN, SD | 9 dB; silencio con `CONTROL.ENABLE` = 0 (2.2) |
| Parlante de 4 a 8 Ω | + / − | Salida en puente, ningún terminal a GND |

Las tres salidas van en un banco de 3,3 V. El número de pin de cada una queda en el archivo de restricciones de la placa, dentro de `rtl/placas/` (sección 6).

### 3.3 Diagrama de bloques

> **Hecho.** Listo cuando: cada bloque interno tiene su función y las señales usan los mismos nombres que en Verilog.

![Bloques internos de peripheral_audio](diagramas/fig6_bloques.png)

*Figura 6. Los cuatro bloques del periférico. Azul: lado del procesador; naranja: lado I2S.*

| Bloque (módulo) | Qué hace | Entradas | Salidas |
|---|---|---|---|
| `audio_regs` | Decodifica `addr[3:2]`, guarda FREQ, VOL y CONTROL en las escrituras y entrega el registro pedido en las lecturas | `cs`, `rd`, `wr`, `addr`, `d_in` | `freq[15:0]`, `vol[6:0]`, `enable`, `d_out`, `ack` |
| `audio_tiempos` | Cuenta `cnt_bclk` y `cnt_bit`, genera BCLK y avisa el flanco de bajada y el fin de trama | `clk`, `rst` | `audio_bclk`, `tick_bajada`, `cnt_bit[4:0]`, `carga` |
| `audio_nco` | Suma FREQ a la fase en cada `carga` y calcula la muestra: +VOL si el bit 15 de la fase es 1, −VOL si es 0, y 0 si `enable` = 0 | `freq`, `vol`, `enable`, `carga` | `muestra[7:0]` |
| `i2s_tx` | Máquina IZQ/DER que produce LRCLK, y registro de 32 bits que saca la muestra por DIN | `muestra`, `carga`, `tick_bajada`, `cnt_bit` | `audio_lrclk`, `audio_din` |

`carga` vale 1 durante un ciclo de HCLK, cuando `tick_bajada` = 1 y `cnt_bit` = 31. Ese es el instante en que termina una trama y empieza la siguiente.

### 3.4 Diagrama de flujo

> **Hecho.** Listo cuando: usa símbolos ISO 5807, cada decisión tiene salidas Sí y No, y no hay terminal de Fin en procesos cíclicos.

La figura 7 muestra lo que hace el periférico en cada ciclo de HCLK. Primero atiende una escritura del procesador, si la hay. Después, solo en los flancos de bajada de BCLK, carga una muestra nueva al final de la trama o desplaza un bit, y cambia de canal en los bits 14 y 30.

![Diagrama de flujo](diagramas/fig7_flujo.png)

*Figura 7. Diagrama de flujo con símbolos ISO 5807: terminal, proceso y decisión.*

### 3.5 Clasificación del flujo

> **Hecho.** Listo cuando: los pasos están separados en ruta de datos y unidad de control.

| Ruta de datos (guarda y transforma valores) | Unidad de control (decide cuándo) |
|---|---|
| Registros FREQ, VOL y CONTROL | Decodificación de `cs`, `wr` y `addr[3:2]` |
| Acumulador de fase de 16 bits | Contadores `cnt_bclk` y `cnt_bit` |
| Cálculo de la muestra (±VOL o 0) | Señales `tick_bajada` y `carga` |
| Registro de desplazamiento de 32 bits | Máquina de estados IZQ/DER |
| Multiplexor de lectura hacia `d_out` | Generación de `ack` |

El flujo es síncrono, porque todo cambia en el flanco de subida de HCLK, y continuo, porque cada trama se repite sola cada 512 ciclos sin esperar al procesador. El procesador solo cambia los valores con los que trabaja la ruta de datos.

### 3.6 Máquinas de estado

> **Hecho.** Listo cuando: cada máquina tiene estado de reset, transiciones con su condición y las salidas de cada estado.

El periférico tiene una sola máquina de estados, dentro de `i2s_tx`. Sus dos estados son los dos canales de la trama, y la salida de cada estado es directamente LRCLK, así que es una máquina de Moore.

![Máquina de estados de la trama](diagramas/fig8_fsm_trama.png)

*Figura 8. Máquina de estados de la trama. El reset la deja en IZQ con `cnt_bit` = 31, para que el primer flanco de bajada cargue una muestra.*

| Estado | `audio_lrclk` | Pasa a | Condición | Acción |
|---|---|---|---|---|
| IZQ (reset) | 0 | DER | `tick_bajada` y `cnt_bit` = 14 | Con `carga` = 1 carga la muestra nueva; en cada `tick_bajada` desplaza un bit |
| DER | 1 | IZQ | `tick_bajada` y `cnt_bit` = 30 | En cada `tick_bajada` desplaza un bit |

LRCLK cambia en los bits 14 y 30, un BCLK antes del MSB de cada palabra (bits 0 y 16), como pide I2S (figura 4). El lado del bus no necesita máquina de estados: cada acceso dura un ciclo y `ack` es solo `cs` retrasado un ciclo.

## 4. Etapa de descripción en HDL

### 4.1 Organización de módulos e implementación en Verilog

> **Hecho.** Listo cuando: hay un módulo por bloque, un módulo superior que los une, parámetros declarados y nombres iguales a los diagramas. Código en [`rtl/`](rtl/).

Cada bloque de la figura 6 es un módulo, y `peripheral_audio` los une. Todos son síncronos, con reset síncrono activo en alto, y las señales se llaman igual que en las figuras 6 a 8.

| Archivo | Bloque | Contenido |
|---|---|---|
| [`peripheral_audio.v`](rtl/peripheral_audio.v) | Módulo superior | Instancia los cuatro bloques y declara el parámetro `CICLOS_BCLK` |
| [`audio_regs.v`](rtl/audio_regs.v) | `audio_regs` | FREQ, VOL y CONTROL; escritura y lectura según `addr[3:2]`; `ack` un ciclo después de `cs` |
| [`audio_tiempos.v`](rtl/audio_tiempos.v) | `audio_tiempos` | Contadores `cnt_bclk` y `cnt_bit`, salida `audio_bclk`, avisos `tick_bajada` y `carga` |
| [`audio_nco.v`](rtl/audio_nco.v) | `audio_nco` | Fase de 16 bits que avanza FREQ en cada `carga`; muestra ±VOL o 0 |
| [`i2s_tx.v`](rtl/i2s_tx.v) | `i2s_tx` | Máquina IZQ/DER (salida `audio_lrclk`) y registro de 32 bits (salida `audio_din`) |

La única diferencia entre placas es el parámetro. En el SoC el periférico se instancia así:

```verilog
peripheral_audio #(.CICLOS_BCLK(16)) audio (   // 16 con clk = 25 MHz; 18 con 27 MHz
    .clk(clk), .rst(rst), .cs(cs_audio), .rd(rd), .wr(wr), .addr(addr[3:0]),
    .d_in(d_in), .d_out(d_out_audio), .ack(ack_audio),
    .audio_bclk(audio_bclk), .audio_lrclk(audio_lrclk), .audio_din(audio_din)
);
```

La muestra se calcula con la fase del mismo ciclo en que se guarda (`fase + FREQ`). Por eso la muestra nueva entra al registro de desplazamiento sin un ciclo de retraso. El testbench que comprueba los criterios de 2.5 está en 5.1.

## 5. Etapa de simulación

### 5.1 Entorno de prueba: testbench, estímulos y observación

> **Hecho.** Listo cuando: se prueban casos normales y de borde, y las formas de onda de GTKWave están explicadas con resultado esperado contra obtenido.

El testbench [`tb_audio.v`](rtl/tb_audio.v) prueba el periférico completo con un reloj de 25 MHz. No hay que mirar las ondas para saber si funciona: incluye un receptor I2S de referencia que lee DIN igual que el MAX98357A, revisa solo los criterios de 2.5 y al final imprime `PASA` o `NO PASA`.

```bash
cd Grupos/G5/audio/rtl
make        # compila con Icarus Verilog y simula
make wave   # abre GTKWave con las señales ya ordenadas (audio.gtkw)
```

| # | Caso | Estímulo | Esperado | Obtenido |
|---|---|---|---|---|
| 1 | Reset | `rst` = 1 | BCLK, LRCLK y DIN en 0 | Igual |
| 2 | Registros | Escribe FREQ = 591, VOL = 64 y CONTROL = 1; lee los tres y el offset `0xC` | Se leen los valores escritos, `0xC` se lee 0 y `ack` llega un ciclo después de `cs` | Igual |
| 3 | Tiempos | Todos los flancos de la simulación | BCLK de 16 ciclos al 50 %; trama de 512 ciclos; 16 bits por slot; LRCLK y DIN cambian solo en la bajada de BCLK | Igual en todos los flancos |
| 4 | Tono de 440 Hz | FREQ = 591 y VOL = 64 durante 1200 tramas | Muestras de +64 o −64; f = 440,33 Hz | +64 o −64; 110,90 tramas por período, f = 440,29 Hz |
| 5 | Borde | VOL = 127 y FREQ = 32768 | La muestra alterna +127 y −127 en cada trama | Igual (figura 9) |
| 6 | Silencio | CONTROL = 0 | DIN en 0 en todos los bits | Igual |
| 7 | Reset a mitad de trama | `rst` = 1 con el tono sonando | Las salidas vuelven al reposo | Igual |

Resultado: 93 613 comprobaciones, 0 fallas. Con `CICLOS_BCLK` = 18 (reloj de 27 MHz) el mismo testbench también pasa.

En el caso 4, la diferencia entre 440,29 Hz y 440,33 Hz viene de la medición, no del diseño. El testbench cuenta tramas enteras entre subidas de la onda, y en 10 períodos eso da una resolución cercana a 0,4 Hz.

![Simulación de dos tramas](diagramas/fig9_simulacion.png)

*Figura 9. Dos tramas del caso 5, tomadas de `tb_audio.vcd`. Cada `carga` mete una muestra nueva en el registro de desplazamiento: +127 (`0x7F`) sale por DIN como `0111 1111` y −127 (`0x81`) como `1000 0001`, seguidos de ocho ceros. LRCLK cambia un BCLK antes del primer bit de cada slot.*

Para ver lo mismo en GTKWave, abre `make wave`, busca la escritura de FREQ = 32768 hacia el final de la simulación y amplía dos tramas. La vista `audio.gtkw` agrupa las señales en cuatro bloques: bus, registros y muestra, tiempos y control, y salida I2S.

## 6. Etapa de implementación

> **Pendiente.** Listo cuando: la síntesis no da errores, hay archivo de asignación de pines, reporte de recursos y prueba en placa con evidencia (foto, video u osciloscopio).

## Referencias

[1] W. Kester, «What the Nyquist Criterion Means to Your Sampled Data System Design», Analog Devices, tutorial MT-002. Copia consultada en: https://wcm-cce.cldnet.analog.com/media/en/training-seminars/tutorials/mt-002.pdf (consultado el 12 de noviembre de 2026).

[2] W. Kester, «Taking the Mystery out of the Infamous Formula, "SNR = 6.02N + 1.76dB," and Why You Should Care», Analog Devices, tutorial MT-001, rev. A, octubre de 2008. Copia consultada en: https://forums.parallax.com/discussion/download/130098/MT-001.pdf (consultado el 13 de noviembre de 2026).

[3] J. Wolfe, «Note names, MIDI numbers and frequencies», University of New South Wales. Disponible en: https://newt.phys.unsw.edu.au/jw/notes.html (consultado el 12 de noviembre de 2026).

[4] Philips Semiconductors, «I2S bus specification», 1986, revisada el 5 de junio de 1996. Copia consultada en: https://www.fdi.ucm.es/profesor/mendias/PSyD/docs/I2SBUS.pdf (consultado el 12 de noviembre de 2026).

[5] Maxim Integrated (hoy Analog Devices), «MAX98357A/MAX98357B: PCM Input Class D Audio Power Amplifiers», hoja de datos, Rev. 13, julio de 2019. Página del fabricante: https://www.analog.com/en/MAX98357A/datasheet. Copia consultada en: https://www.makerguides.com/wp-content/uploads/2026/01/Datasheet_MAX98357A.pdf (consultado el 13 de noviembre de 2026).

[6] DFRobot, «MAX98357A I2S Digital Amplifier Module (DFR0954)», wiki. Disponible en: https://wiki.dfrobot.com/SKU_DFR0954_MAX98357_I2S_Amplifier_Module (valores de GAIN y SD del módulo).

[7] Guía UART 8N1 del proyecto, secciones 5.4 (método por transferencias entre registros) y 12 (integración MMIO).

[8] Documento de la fase de diseño del curso, «Fase de Diseño. Proyecto: Consola de Videojuegos en FPGA»: apartados «1.2 Núcleo de procesador», «1.5 Salidas» y «Entregable E: Selección y justificación de periféricos» (subsección «Salidas»).

[9] RISC-V International, «The RISC-V Instruction Set Manual», volumen de instrucciones base no privilegiadas, capítulo «Introduction», sección «Memory». Copia del repositorio del manual consultada en: https://mirror.iscas.ac.cn/riscv-toolchains/git/riscv/riscv-isa-manual.git/tree/src/intro.adoc (consultado el 12 de noviembre de 2026).

[10] Plantilla del curso, `template/diagramas/README.md`, sección «Flujo de una operación de firmware sobre un periférico».

[11] Microchip Technology, «AVR131: Using the AVR's High-speed PWM», sección 2.2 «Analog Waveform Generation from PWM Signal», documentación en línea (sin fecha de publicación visible). Disponible en: https://onlinedocs.microchip.com/oxy/GUID-15F56EF1-EBFF-405A-9412-E41CC95BAACF-en-US-2/GUID-34AC5DDB-B9AE-4272-842B-E2A1CEE69B6B.html (consultado el 12 de noviembre de 2026).

[12] A. Palacherla, «Using PWM to Generate Analog Output», Microchip Technology, nota de aplicación AN538 (DS00538C), noviembre de 1999. Copia consultada en: https://rose-hulman.edu/Class/ee/radu/ece333/Labs/an538_pwm.pdf (consultado el 12 de noviembre de 2026).
