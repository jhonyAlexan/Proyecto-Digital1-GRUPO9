# Periférico: Audio

El procesador femtoRV32 escribe en registros mapeados en memoria qué sonido generar, y el periférico produce la señal que llega al parlante. El método de generación y el hardware de salida están por definir.

> Estado de cada sección y preguntas abiertas: [README del equipo](../README.md).

## 1. Marco teórico

> **En progreso.** Listo cuando: los conceptos que el lector necesita (generación digital de tonos, método de salida elegido, periféricos mapeados en memoria) están explicados y con fuentes citadas.

Esta sección sigue el camino del sonido: qué frecuencia corresponde a cada nota (1.1), cómo un circuito digital genera un tono (1.2), cómo ese tono llega al parlante con cada uno de los dos métodos que propone el documento de la fase de diseño, PWM e I2S (1.3), y cómo el procesador controla el periférico (1.4). El equipo todavía no ha elegido el método de salida (ver el [README del equipo](../README.md)); por eso se explican los dos con los mismos criterios, para poder compararlos. Las cifras tomadas de una fuente llevan su referencia entre corchetes. Las que calculó el equipo se marcan como *(cálculo propio)* y se pueden repetir con los datos del texto.

### 1.1 Frecuencia de las notas

Una nota musical corresponde a una frecuencia. En la afinación temperada, con A4 fijada por convención en 440 Hz [1], la frecuencia de la nota con número MIDI m es:

$$
f_m = 440 \cdot 2^{\frac{m-69}{12}}\ \mathrm{Hz}
$$

El número MIDI de A4 es 69 [1]. Cada semitono multiplica la frecuencia por una constante fija y doce semitonos, una octava, la duplican. Por ejemplo, el do central (C4, número MIDI 60) corresponde a 261,63 Hz *(cálculo propio)*.

### 1.2 Generación digital de un tono

Un circuito digital puede generar una onda cuadrada invirtiendo una salida cada N ciclos del reloj del sistema. El período de la onda es de 2N ciclos, de modo que la frecuencia obtenida y el valor de N que da una frecuencia deseada son *(derivación propia)*:

$$
f_{out} = \frac{f_{clk}}{2N} \qquad\Longleftrightarrow\qquad N = \frac{f_{clk}}{2\,f_{out}}
$$

Como N es entero, la frecuencia real difiere un poco de la pedida. El error relativo máximo es medio ciclo sobre N, por lo que es menor en las notas graves (N grande) que en las agudas *(derivación propia)*. Con el reloj de 27 MHz de la placa de pruebas y la nota A4 *(cálculo propio)*:

$$
N = \frac{27\,000\,000}{2 \cdot 440} = 30\,681{,}8 \;\Rightarrow\; N = 30\,682 \qquad f_{real} = \frac{27\,000\,000}{2 \cdot 30\,682} \approx 439{,}997\ \mathrm{Hz}
$$

La frecuencia real queda 0,0006 % por debajo de la pedida.

La onda cuadrada tiene solo dos niveles. Su ciclo de trabajo, la fracción del período en nivel alto, es del 50 % si la salida se invierte siempre cada N ciclos. Como ejemplo de hardware de sonido de una consola portátil, la Game Boy tiene cuatro canales: dos ondas cuadradas con ciclo de trabajo ajustable (12,5 %, 25 %, 50 % o 75 %), una tabla de onda programable y un generador de ruido. Cada canal tiene su propio DAC, y las salidas de los canales se suman y pasan a los controles de volumen maestro [2]. Un diseño con más de un canal puede combinarlos de esa misma forma, sumándolos.

### 1.3 Del tono digital al parlante: PWM e I2S

El documento de la fase de diseño propone dos métodos de salida de audio: «Audio por PWM a un parlante pequeño (simple, sin DAC)» y «Audio por I2S hacia un DAC externo (más fiel, más pines y más estudio)», y pide elegir «la más adecuada para su juego» y justificar «por qué esa y no otra» [3].

#### 1.3.1 PWM

La modulación por ancho de pulso (PWM) es una señal digital de frecuencia fija cuyo ciclo de trabajo D, la fracción del período en nivel alto, se modula. El ciclo de trabajo determina la amplitud de la forma de onda analógica: un ciclo del 50 % da una señal analógica con la mitad de la tensión de alimentación [4]. En general, por definición de valor medio de una señal periódica:

$$
\bar{V} = D \cdot V_{DD}, \qquad 0 \le D \le 1
$$

donde V<sub>DD</sub> es la tensión del nivel alto. Para obtener la señal analógica se usa un filtro pasa bajos, por ejemplo uno RC pasivo simple, que elimina la frecuencia base del PWM y deja pasar la señal [4]. El punto de -3 dB de un filtro RC se relaciona con sus componentes así [5]:

$$
RC = \frac{1}{2\pi f}
$$

donde f es la frecuencia de corte. El ancho de banda de la señal deseada, F<sub>bw</sub>, debe ser mucho menor que la frecuencia del PWM, F<sub>PWM</sub> [5]:

$$
F_{bw} \ll F_{PWM}
$$

Si la señal analógica va a una entrada de baja impedancia, como un parlante, debe conectarse un amplificador buffer entre la salida del filtro y la carga [4].

La frecuencia del PWM depende del reloj y del número de bits B del contador. Si el contador avanza un paso por ciclo de reloj y un período de PWM es una vuelta completa del contador *(derivación propia)*:

$$
F_{PWM} = \frac{f_{clk}}{2^{B}}
$$

Con 27 MHz, un contador de 8 bits da 105,5 kHz y uno de 10 bits da 26,4 kHz *(cálculo propio)*. Con el mismo reloj, más bits dan más niveles de amplitud pero una frecuencia de PWM más baja, y esa frecuencia debe seguir muy por encima del ancho de banda de la señal [5].

El documento del curso describe el audio por PWM como un parlante pequeño conectado directamente a un pin con PWM generado por hardware o por software [3]. Si solo se necesitan tonos, la señal de ese pin puede ser la misma onda cuadrada de 1.2, sin variar el ciclo de trabajo; el PWM con filtro hace falta para reproducir formas de onda con más de dos niveles *(razonamiento propio)*.

#### 1.3.2 I2S

I2S (*Inter-IC Sound*) es un bus serie para transmitir audio digital entre circuitos integrados. Su especificación define tres líneas: un reloj serie continuo (SCK), una selección de palabra (WS) y los datos serie (SD) [6]. Algunas hojas de datos las llaman BCLK y LRCLK, como la del MAX98357A [7]. Las reglas que importan en este documento, según [6]:

- El dispositivo que genera SCK y WS es el maestro.
- WS en nivel bajo indica el canal izquierdo y en nivel alto el derecho.
- Los datos van en complemento a dos, con el bit más significativo (MSB) primero.
- El transmisor envía el MSB de la palabra siguiente un período de reloj después de que cambia WS.
- El receptor captura el dato en el flanco de subida de SCK; el transmisor puede cambiarlo en cualquiera de los dos flancos.

La especificación [6] no fija una relación entre la frecuencia de SCK y la de muestreo. Con dos canales por trama y N<sub>slot</sub> bits por canal, la relación es *(derivación propia)*:

$$
f_{BCLK} = 2 \cdot N_{slot} \cdot f_s
$$

donde f<sub>s</sub> es la frecuencia de muestreo. Con 48 kHz y palabras de 32 bits, BCLK es de 3,072 MHz *(cálculo propio)*. En la placa de pruebas el cociente entre 27 MHz y 3,072 MHz no es entero *(cálculo propio)*, así que la frecuencia de muestreo real depende del divisor elegido. Un amplificador con entrada I2S puede aceptar un intervalo de frecuencias de muestreo en lugar de un valor único: el MAX98357A, por ejemplo, acepta de 8 kHz a 96 kHz [7].

La frecuencia de muestreo también limita las frecuencias que se pueden representar: debe ser al menos el doble de la mayor frecuencia de la señal; si es menor, ocurre aliasing y la señal aparece con una frecuencia más baja [8]:

$$
f_s \ge 2\,f_{max}
$$

I2S solo transporta muestras digitales: hace falta un DAC externo para obtener la señal analógica [3]. Existen circuitos que integran el DAC y el amplificador. El MAX98357A, por ejemplo, es un amplificador clase D con entrada digital PCM, que no necesita señal MCLK, exige que BCLK sea 32, 48 o 64 veces LRCLK y opera con datos de 16, 24 o 32 bits en I2S [7]. Su variante A usa I2S y la B, datos justificados a la izquierda [7].

#### 1.3.3 Comparación de los dos métodos

| Criterio | PWM | I2S |
|---|---|---|
| Descripción en el documento del curso [3] | «simple, sin DAC» | «más fiel, más pines y más estudio» |
| Pines de salida de la FPGA | 1 [3] | 3: SCK, WS y SD [6] |
| Hardware externo | Parlante pequeño conectado al pin [3]; filtro RC y buffer si se quiere señal analógica [4, 5] | DAC externo [3], que puede venir integrado en un amplificador, como el MAX98357A [7] |
| Frecuencia de la señal más rápida, con reloj de 27 MHz | PWM de 26,4 kHz con contador de 10 bits (c. p.) | BCLK de 3,072 MHz con 48 kHz y 32 bits (c. p.) |
| Compromiso principal | Bits del contador frente a frecuencia de PWM (c. p.) | Frecuencia de muestreo y ancho de palabra frente a un divisor entero del reloj (c. p.) |

c. p.: cálculo propio, desarrollado en 1.3.1 y 1.3.2.

La elección del método y su justificación, que el documento del curso exige [3], se documentan en las secciones siguientes; esta sección solo da los criterios para compararlos.

### 1.4 Periféricos mapeados en memoria

En un sistema con periféricos mapeados en memoria, el procesador controla el hardware leyendo y escribiendo direcciones: cada periférico ocupa una ventana del mapa de memoria. El manual de RISC-V indica que distintos rangos del espacio de direcciones pueden contener memoria principal o uno o más dispositivos de E/S, y que las lecturas y escrituras a dispositivos de E/S pueden tener efectos secundarios visibles, mientras que los accesos a memoria principal no [9]. El documento de la fase de diseño fija esta arquitectura para la consola: un solo bus de memoria y periféricos mapeados en memoria (MMIO) [3].

En el SoC del curso el bus es Wishbone y cada periférico se conecta mediante un adaptador (`WishbonePeripheral`). Cuando el firmware escribe en la ventana de un periférico, el adaptador le entrega durante un ciclo las señales `cs`, `wr`, `addr` (el desplazamiento dentro de la ventana) y `d_in` (el valor escrito), y responde `ack` al bus [10]. La interfaz completa está en el [README del equipo](../README.md).

**Aplicación al audio.** El procesador solo escribe registros que dicen qué sonido generar; el periférico produce la señal por sí mismo. Como `d_in` es válido solo durante un ciclo [10], el periférico debe guardar el valor en un registro propio en ese ciclo y generar el tono de forma autónoma a partir de él *(razonamiento propio)*. Así el procesador no tiene que invertir el pin al ritmo de la nota.

### 1.5 De los conceptos a las decisiones de diseño

| Concepto | Decisión de diseño que condiciona | Se usa en |
|---|---|---|
| 1.1 Frecuencia de las notas | Divisor N de cada nota que use el juego | 3.2 |
| 1.2 Generación digital de un tono | Ancho del registro de divisor y error de frecuencia aceptable | 3.2, 3.3 y 4.1 |
| 1.3 PWM o I2S | Método de salida, pines y hardware externo | 3.2 y 3.3 |
| 1.4 MMIO | Mapa de registros y escritura en un ciclo | 3.2 y 3.6 |

## 2. Fundamento

> **Pendiente.** Listo cuando: el principio de funcionamiento del periférico cabe en uno o dos párrafos claros.

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

[1] J. Wolfe, «Note names, MIDI numbers and frequencies», University of New South Wales. Disponible en: https://newt.phys.unsw.edu.au/jw/notes.html (consultado el 12 de noviembre de 2026).

[2] GbdevWiki, «Gameboy sound hardware». Disponible en: https://gbdev.gg8.se/wiki/articles/Gameboy_sound_hardware (consultado el 12 de noviembre de 2026).

[3] Documento de la fase de diseño del curso, «Fase de Diseño. Proyecto: Consola de Videojuegos en FPGA»: apartados «1.2 Núcleo de procesador», «1.5 Salidas» y «Entregable E: Selección y justificación de periféricos» (subsección «Salidas»).

[4] Microchip Technology, «AVR131: Using the AVR's High-speed PWM», sección 2.2 «Analog Waveform Generation from PWM Signal», documentación en línea (sin fecha de publicación visible). Disponible en: https://onlinedocs.microchip.com/oxy/GUID-15F56EF1-EBFF-405A-9412-E41CC95BAACF-en-US-2/GUID-34AC5DDB-B9AE-4272-842B-E2A1CEE69B6B.html (consultado el 12 de noviembre de 2026).

[5] A. Palacherla, «Using PWM to Generate Analog Output», Microchip Technology, nota de aplicación AN538 (DS00538C), noviembre de 1999. Copia consultada en: https://rose-hulman.edu/Class/ee/radu/ece333/Labs/an538_pwm.pdf (consultado el 12 de noviembre de 2026).

[6] Philips Semiconductors, «I2S bus specification». Copia consultada en: https://www.fdi.ucm.es/profesor/mendias/PSyD/docs/I2SBUS.pdf (consultado el 12 de noviembre de 2026).

[7] Maxim Integrated, hoja de datos «MAX98357A/MAX98357B», Rev. 13, julio de 2019. Copia consultada en: https://www.makerguides.com/wp-content/uploads/2026/01/Datasheet_MAX98357A.pdf (consultado el 12 de noviembre de 2026).

[8] W. Kester, «What the Nyquist Criterion Means to Your Sampled Data System Design», Analog Devices, tutorial MT-002. Copia consultada en: https://wcm-cce.cldnet.analog.com/media/en/training-seminars/tutorials/mt-002.pdf (consultado el 12 de noviembre de 2026).

[9] RISC-V International, «The RISC-V Instruction Set Manual», volumen de instrucciones base no privilegiadas, capítulo «Introduction», sección «Memory». Copia del repositorio del manual consultada en: https://mirror.iscas.ac.cn/riscv-toolchains/git/riscv/riscv-isa-manual.git/tree/src/intro.adoc (consultado el 12 de noviembre de 2026).

[10] Plantilla del curso, `template/diagramas/README.md`, sección «Flujo de una operación de firmware sobre un periférico».
