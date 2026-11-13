# Periférico: Audio

El procesador femtoRV32 escribe en registros mapeados en memoria qué sonido generar, y el periférico produce la señal que llega al parlante. El periférico genera tonos de onda cuadrada con muestras de 8 bits y las envía por I2S al amplificador MAX98357A, que convierte a analógico y maneja el parlante.

---
 
## 1. Marco teórico
 
### 1.1 Audio digital: muestreo y cuantización
 
Un sonido digital es una secuencia de muestras tomadas a una frecuencia fs. Por el teorema de Nyquist, solo se representan frecuencias menores que fs/2. Cada muestra se cuantiza con N bits; con N = 8 hay 256 niveles y una relación señal-ruido ideal de 6,02·N + 1,76 ≈ 49,9 dB. Es suficiente para efectos y tonos de un juego, no para música de alta fidelidad.
 
### 1.2 Generación digital de tonos: acumulador de fase
 
Un registro de fase de 16 bits aumenta en `FREQ` en cada muestra. Su bit más significativo alterna entre 0 y 1 y forma una onda cuadrada:
 
    fase[n+1] = fase[n] + FREQ        (módulo 2^16)
    f_salida  = FREQ · fs / 2^16
    muestra   = fase[15] ? +VOL : −VOL
 
Con fs ≈ 24 414 Hz la resolución de frecuencia es ≈ 0,37 Hz. Ejemplo: La4 (440 Hz) usa FREQ = 1181, que produce 439,97 Hz. La amplitud ±VOL es simétrica, así que no hay componente continua.
 
### 1.3 El bus I2S
 
I2S transmite audio con tres líneas:
 
| Línea | Función |
|---|---|
| BCLK | Reloj de bit; un pulso por cada bit de dato |
| LRCLK | Selección de canal y marca de palabra: 0 = izquierdo, 1 = derecho |
| DIN | Datos en serie, MSB primero, complemento a dos |
 
Reglas de temporización:
 
- El transmisor cambia DIN y LRCLK en el flanco de bajada de BCLK. El receptor muestrea DIN en el flanco de subida.
- El MSB aparece un período de BCLK después del cambio de LRCLK. Esa es la característica distintiva del modo I2S.
- Cada trama contiene un slot izquierdo y uno derecho, y dura 1/fs.
### 1.4 El amplificador MAX98357A
 
Es un amplificador clase D con entrada digital. Contiene el DAC, así que el FPGA no necesita filtro ni conversor externo. Se alimenta con LRCLK, BCLK y DIN, sin MCLK. Según el datasheet acepta frecuencias de muestreo de 8 kHz a 96 kHz y datos de 16, 24 o 32 bits en modo I2S. La variante A espera I2S estándar. El canal se elige con SD_MODE, que también sirve para apagarlo, y la ganancia (3 a 15 dB) se fija con GAIN_SLOT. Ambos son pines de configuración física, no registros.
 
### 1.5 Muestras de 8 bits y uso de memoria
 
La interfaz del MAX98357A acepta 16, 24 o 32 bits por slot, no 8. Se usa un slot de 16 bits con la muestra de 8 bits (con signo, −128…127) en los bits 15:8; el hardware fuerza a cero los bits 7:0. Esos ocho ceros se generan en el transmisor y no se almacenan.
 
Si el contenido viene de audio de 8 bits sin signo (como WAV), hay que invertir el MSB (`XOR 0x80`) para pasarlo a complemento a dos. Cada muestra se envía en ambos slots, para que el sonido sea el mismo con SD_MODE en izquierdo, derecho o mezcla.
 
La restricción de 8 bits busca minimizar la memoria que ocupa el sonido. La RAM del SoC es de 26 212 bytes y compite con el código y la pila (1024 B), por lo que se prefiere una arquitectura que no almacene audio:
 
| Método | Memoria de datos | Observación |
|---|---|---|
| Generador de tonos (acumulador de fase) | 0 bytes de RAM; ≈ 40 flip-flops | Método elegido |
| PCM de 8 bits a fs = 24,414 kHz | 24 414 B por segundo (≈ 93 % de la RAM) | Inviable |
| PCM de 8 bits con muestra repetida ×3 (≈ 8,138 kHz) | 8 138 B por segundo (≈ 31 % de la RAM) | Opcional, con contador de repetición |
 
**Por qué no 16 bits.** Con ondas cuadradas la muestra solo toma dos valores (+VOL y −VOL), por lo que más resolución no mejora el timbre. Con el generador de tonos el audio no se guarda, y pasar a 16 bits solo ensancharía unos pocos flip-flops; con PCM duplicaría la memoria (1 s a 8,138 kHz pasaría de 8 138 B a 16 276 B). Como el transmisor I2S ya envía palabras de 16 bits, una ampliación posterior solo requiere ensanchar VOL y la muestra y cargar los bits 7:0 en vez de ceros, sin rediseñar el bus ni la temporización.
 
| | 8 bits | 16 bits |
|---|---|---|
| Relación señal-ruido ideal | ≈ 49,9 dB | ≈ 98 dB |
| Niveles | 256 | 65 536 |
| Memoria del generador de tonos | 0 B | 0 B |
| 1 s de PCM a 8,138 kHz | 8 138 B | 16 276 B |
| Cambios en el transmisor I2S | Ninguno | Ninguno |
 
### 1.6 Periférico mapeado en memoria
 
El CPU accede al periférico con cargas y almacenamientos a direcciones fijas (MMIO), sin instrucciones especiales. La estructura sigue la de UART8N1: decodificador local, control de registros y core, descrita en la sección 12 de la guía de la UART. A diferencia de la UART, aquí no hay protocolo de aceptación (START/BUSY/DONE): los registros fijan el sonido y el hardware lo mantiene hasta que se cambien.
 
### Fuentes
 
- Maxim/Analog Devices. *MAX98357A/MAX98357B: PCM Input Class D Audio Power Amplifiers*, datasheet. https://www.analog.com/en/MAX98357A/datasheet
- Philips Semiconductors. *I2S bus specification*, 1986, rev. 5 jun 1996. **(verificar enlace)**
- DFRobot. *MAX98357A I2S Digital Amplifier Module (DFR0954)*, wiki. https://wiki.dfrobot.com/SKU_DFR0954_MAX98357_I2S_Amplifier_Module (valores de GAIN y SD del módulo; verificar contra la placa usada)
- Guía UART 8N1 del proyecto, secciones 5.4 (método por transferencias entre registros) y 12 (integración MMIO).

## 2. Fundamento
 
### 2.1 Principio de funcionamiento
 
El CPU no produce el audio muestra a muestra. Solo escribe `FREQ`, `VOL` y `ENABLE`, y el periférico genera el sonido por sí mismo. Un generador de tonos (acumulador de fase) calcula una muestra de 8 bits con signo una vez por trama, cada 1024 ciclos de HCLK (40,96 µs, fs ≈ 24,414 kHz).
 
Un transmisor I2S coloca esa muestra en los 8 bits altos de una palabra de 16, la repite en los slots izquierdo y derecho y la serializa por DIN. BCLK vale HCLK/32 = 781,25 kHz y LRCLK vale HCLK/1024. El MAX98357A hace la conversión digital-analógica y la amplificación clase D. Todas las salidas son registradas y salen de un único contador libre, de modo que BCLK, LRCLK y DIN quedan alineados sin generador de ticks separado.
 
### 2.2 Conexiones del módulo MAX98357A
 
El FPGA actúa como maestro I2S: BCLK, LRCLK y DIN son salidas del FPGA y entradas del módulo. El módulo no devuelve datos.
 
```
FPGA (peripheral_audio)              Módulo MAX98357A
audio_bclk   ─────────────────────►  BCLK   reloj de bit, 781,25 kHz
audio_lrclk  ─────────────────────►  LRC    reloj de trama, 24,414 kHz (0 = izq., 1 = der.)
audio_din    ─────────────────────►  DIN    datos en serie, MSB primero
3V3 o 5V     ─────────────────────►  VIN    alimentación (3,3–5 V)
GND          ─────────────────────►  GND    tierra común
(sin conectar o a GND/VIN)           GAIN   ganancia por cableado (3–15 dB)
(sin conectar, 3V3 o GPIO)           SD     apagado y selección de canal
                                     + / −  parlante de 4–8 Ω, salida en puente
```
 
| Pin | Qué representa | Notas |
|---|---|---|
| VIN | Alimentación (3,3–5 V) | Rotulado parcialmente en la esquina de la placa; confirmar en la placa física. El clase D toma picos de corriente; con 5 V suena más fuerte. |
| GND | Referencia común de tierra | Obligatorio. Sin tierra común, BCLK, LRC y DIN no tienen referencia. |
| BCLK | Reloj de bit | Marca cuándo leer DIN. |
| LRC | Reloj de trama (LRCLK) | 0 = izquierdo, 1 = derecho. Su frecuencia es fs. |
| DIN | Datos de audio | Bits de la muestra, MSB primero. |
| GAIN | Ganancia, fija por cableado | Ver abajo. No la controla el FPGA. |
| SD | Apagado y selección de canal | Ver abajo. |
| + / − | Salida al parlante (4–8 Ω) | La salida es en puente: ningún terminal se conecta a GND. |
 
**GAIN** (valores del módulo DFRobot; verificar contra la placa): GAIN a GND por 100 kΩ → 15 dB; GAIN a GND → 12 dB; sin conectar → 9 dB; GAIN a VDD → 6 dB; GAIN a VDD por 100 kΩ → 3 dB. Se recomienda empezar sin conectar (9 dB).
 
**SD:** por debajo de 0,16 V el amplificador se apaga. Con 0,16–0,77 V sale la mezcla izquierdo/derecho; con 0,77–1,4 V el canal derecho; sobre 1,4 V el izquierdo. Muchas placas fijan esto con resistencias; revisar la placa usada. Como se envía la misma muestra en ambos slots, cualquier selección suena igual. SD también puede manejarse con un GPIO para silenciar el parlante.
 
Pendiente: asignación de pines físicos y verificación de las resistencias de SD y GAIN de la placa concreta.
 
### 2.3 Diagrama de tiempos
 
Parámetros **(propuesta)**: HCLK = 25 MHz, 32 HCLK por BCLK, 16 BCLK por slot, 32 BCLK por trama.
 
| Magnitud | Valor |
|---|---|
| Período de BCLK | 32 HCLK = 1,28 µs (781,25 kHz) |
| Período de trama = 1/fs | 1024 HCLK = 40,96 µs (fs = 24 414,0625 Hz) |
| Duración de un slot | 16 BCLK = 512 HCLK |
| Frecuencia máxima representable | fs/2 ≈ 12,2 kHz |
 
#### 2.3.1 Figura 1. Trama completa
 
```
         |<------ Slot izquierdo (16 BCLK) ------>|<------ Slot derecho (16 BCLK) ------>|
LRCLK  ‾‾|________________________________________|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|__
DIN       [ s7 … s0 | 0 0 0 0 0 0 0 0 ]            [ s7 … s0 | 0 0 0 0 0 0 0 0 ]
          ^ misma muestra de 8 bits en ambos slots            |<---- 1024 HCLK ---->|
```
 
#### 2.3.2 Figura 2. Detalle en el cambio de LRCLK
 
Cada período Pn dura 4 caracteres; el flanco de subida de BCLK está al inicio y el de bajada en la mitad. LRCLK y DIN cambian en los flancos de bajada.
 
```
          P0  P1  P2  P3  P4  P5  P6  P7  P8  P9
BCLK      ‾‾__‾‾__‾‾__‾‾__‾‾__‾‾__‾‾__‾‾__‾‾__‾‾__
LRCLK     ‾‾______________________________________
DIN       r1|r0 |s7 |s6 |s5 |s4 |s3 |s2 |s1 |s0 |0
muestreo  ^   ^   ^   ^   ^   ^   ^   ^   ^   ^
              r0          s7 (primer bit de la muestra, un BCLK después de LRCLK)
```
 
`r1`, `r0` son los dos últimos bits de la palabra anterior (slot derecho). LRCLK baja en la mitad de P0. En el flanco de subida de P1 el receptor todavía lee `r0`, y `s7` se muestrea recién en P2. Después de `s0` siguen ocho ceros hasta completar los 16 bits del slot.
 
#### 2.3.3 Figura 3. Relación con HCLK
 
Contador libre `cnt[9:0]`, que cuenta 0…1023 en HCLK:
 
```
cnt[4:0]  0 ......... 15 16 ........ 31 | 0 ...      BCLK = cnt[4]  (32 HCLK)
cnt[8:5]  índice de bit dentro del slot (0…15)
cnt[9]    slot: 0 izquierdo, 1 derecho                LRCLK desplazado 1 BCLK respecto al MSB
```
 
Las salidas BCLK, LRCLK y DIN se cargan en registros en el flanco de HCLK donde `cnt[4:0]` pasa de 31 a 0, que equivale al flanco de bajada de BCLK. El ASMD y las transferencias exactas se definen en el siguiente paso del método.
 
### 2.4 Mapa de registros (propuesta)
 
Región global libre: `0x0043` (base `0x00430000`). Hay que actualizar `chip_select` y el mux de lectura al conectarlo.
 
| Dirección | Registro | Bits | Función |
|---|---|---|---|
| `0x00430000` | FREQ | 15:0 | Incremento de fase; f = FREQ·fs/65536 |
| `0x00430004` | VOL | 6:0 | Amplitud de la onda cuadrada (0…127) |
| `0x00430008` | CONTROL | 0 | ENABLE: 1 = sonido, 0 = silencio (muestra 0) |
 
Los valores se aplican en la siguiente muestra. Escribirlos mientras suena es seguro, porque la fase no se reinicia. Los demás bits se leen como cero y las escrituras fuera de estos offsets se ignoran, igual que en UART8N1.
 
### 2.5 Criterios de comprobación
 
- BCLK tiene período de 32 HCLK y ciclo de trabajo 50 %.
- LRCLK vale 0 durante 16 BCLK y 1 durante 16 BCLK; la trama dura 1024 HCLK.
- El MSB aparece un BCLK después del cambio de LRCLK. DIN solo cambia en flancos de bajada de BCLK.
- Los bits 7:0 de cada slot son cero. Ambos slots llevan la misma muestra.
- Con `FREQ = 1181` y `VOL = 64`, la salida alterna ±64 con frecuencia 439,97 Hz ± la resolución de la medición.
- Con `ENABLE = 0`, DIN vale 0 en todos los bits.
- Reset síncrono activo alto: BCLK, LRCLK y DIN quedan en reposo.

### 2.6 Pendiente
 
- Relación BCLK/LRCLK admitida para 16 bits y límites de temporización del datasheet.
- Asignación de pines BCLK, LRCLK y DIN, y nivel eléctrico (3,3 V).
- Configuración física de SD y GAIN.
- ASMD, tabla de transferencias, bloques (control y datapath) y RTL del transmisor I2S.
 

## 3. Etapa de diseño

### 3.1 Diagrama de caja negra

> **Pendiente.** Listo cuando: todas las entradas y salidas tienen nombre, sin mostrar nada del interior.

### 3.2 Características de la interfaz

> **Pendiente.** Listo cuando: cada señal tiene nombre, dirección y ancho; están el mapa de registros, la salida hacia el parlante, los pines y los voltajes.

### 3.3 Diagrama de bloques

> **Pendiente.** Listo cuando: cada bloque interno tiene su función y las señales usan los mismos nombres que en Verilog.

### 3.4 Diagrama de flujo

> **Pendiente.** Listo cuando: usa símbolos ISO 5807, cada decisión tiene salidas Sí y No, y no hay terminal de Fin en procesos cíclicos.

### 3.5 Clasificación del flujo

> **Pendiente.** Listo cuando: los pasos están separados en ruta de datos y unidad de control (por confirmar con la guía).

### 3.6 Máquinas de estado

> **Pendiente.** Listo cuando: cada máquina tiene estado de reset, transiciones con su condición y las salidas de cada estado.

## 4. Etapa de descripción en HDL

### 4.1 Organización de módulos e implementación en Verilog

> **Pendiente.** Listo cuando: hay un módulo por bloque, un módulo superior que los une, parámetros declarados y nombres iguales a los diagramas. Código en [`rtl/`](rtl/).

## 5. Etapa de simulación

### 5.1 Entorno de prueba: testbench, estímulos y observación

> **Pendiente.** Listo cuando: se prueban casos normales y de borde, y las formas de onda de GTKWave están explicadas con resultado esperado contra obtenido.

## 6. Etapa de implementación

> **Pendiente.** Listo cuando: la síntesis no da errores, hay archivo de asignación de pines, reporte de recursos y prueba en placa con evidencia (foto, video u osciloscopio).

## Referencias

> Se agregan a medida que se usan.
