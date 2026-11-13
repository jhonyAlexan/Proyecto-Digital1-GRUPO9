# Periférico: Joystick

Una ESP32 lee un joystick analógico de dos ejes con botón y envía las lecturas por UART a la FPGA. El periférico recibe esos paquetes y guarda los valores en registros mapeados en memoria, que el procesador femtoRV32 lee por el bus del SoC.

> Estado de cada sección y preguntas abiertas: [README del equipo](../README.md).

## 1. Marco teórico

> **En progreso.** Listo cuando: los conceptos que el lector necesita (UART, periféricos mapeados en memoria, ADC de la ESP32) están explicados y con fuentes citadas.

Esta sección sigue el camino de la información, desde el joystick hasta el procesador: cómo un joystick produce una tensión (1.1), cómo la ESP32 la convierte en un número (1.2), cómo ese número llega a la FPGA por UART (1.3), cómo la FPGA recibe una señal que no está sincronizada con su reloj (1.4) y cómo el procesador lee el resultado (1.5). Las cifras tomadas de una fuente llevan su referencia entre corchetes. Las que calculó el equipo se marcan como *(cálculo propio)* y se pueden repetir con los datos del texto.

### 1.1 Joystick analógico: el potenciómetro como divisor de tensión

Un potenciómetro es una resistencia con un cursor (*wiper*) que la divide en dos tramos, R1 y R2. Si sus extremos se conectan a una fuente, la tensión en el pin central depende de la posición del cursor y sigue la relación del divisor de tensión [1]:

$$
V_{out} = V_{in}\,\frac{R_2}{R_1 + R_2}
$$

Con el cursor en el centro del recorrido la salida es la mitad de la entrada [1]. En un extremo la salida tiende a cero y, por la misma relación, en el otro tiende a la tensión de alimentación.

Un joystick analógico de pulgar contiene dos potenciómetros, uno por eje. Por ejemplo, el SparkFun Thumb Joystick tiene dos potenciómetros de 10 kΩ (ejes X e Y), un resorte que devuelve la palanca al centro al soltarla y un interruptor que se activa al presionar el cabezal [2]. El joystick entrega así dos tensiones analógicas continuas y un contacto digital.

El centro ideal es la mitad de la alimentación, pero el valor de reposo real de cada eje no se asume: se mide en el módulo que use el equipo.

### 1.2 Conversión analógica a digital en la ESP32

La FPGA y el procesador solo manejan valores digitales, así que las dos tensiones del joystick deben convertirse en números. De eso se encarga el convertidor analógico a digital (ADC) de la ESP32.

**Principio de funcionamiento (aproximaciones sucesivas, SAR).** Al iniciar una conversión, el circuito de muestreo y retención (*sample-and-hold*) congela la tensión de entrada y el DAC interno se fija a la mitad de la escala. Un comparador decide si la entrada está por encima o por debajo de la salida del DAC; el resultado es el bit más significativo y se guarda en el registro de aproximaciones sucesivas (SAR). El DAC pasa entonces a un cuarto o a tres cuartos de la escala, según ese bit, y el comparador decide el bit siguiente [3]. Una conversión de N bits toma N pasos [3].

**Resolución.** El paso de cuantización q es el cambio de tensión de entrada que corresponde a un código de diferencia. Para un rango de entrada V<sub>FS</sub> y un ADC de N bits vale:

$$
q = \frac{V_{FS}}{2^{N}}
$$

La ESP32 integra dos ADC de aproximaciones sucesivas, con 18 canales de medición en total, y sus resultados crudos en modo de lectura simple tienen 12 bits [4]: 4096 niveles, con códigos de 0 a 4095 *(cálculo propio)*. Para un rango ilustrativo de 3,3 V, el paso es de unos 0,81 mV *(cálculo propio)*.

**Rango medible y atenuación.** La ESP32 puede atenuar la entrada para ampliar el rango que mide. La documentación indica que los resultados más exactos se obtienen dentro de un *rango sugerido*, que depende de la atenuación [4]:

| Atenuación | Rango sugerido [4] |
|---|---|
| 0 dB | 100 a 950 mV |
| 2,5 dB | 100 a 1250 mV |
| 6 dB | 150 a 1750 mV |
| 12 dB | 150 a 2450 mV |

Para la máxima exactitud, Espressif recomienda usar las funciones de calibración y medir dentro de esos rangos [4]. El nombre de atenuación 11 dB figura como obsoleto y se comporta igual que 12 dB [4].

**Referencia y calibración.** Por diseño, la tensión de referencia del ADC es de 1100 mV, pero la real puede estar entre 1000 mV y 1200 mV según la ESP32 [4]. Por eso el paso de valor crudo a milivoltios se hace con las funciones de calibración de ESP-IDF [4, 5].

**Ruido y linealidad.** El ADC de la ESP32 puede ser sensible al ruido, con grandes discrepancias entre lecturas. Para minimizarlo, la documentación indica que se puede conectar al pad de entrada un condensador de desacople (por ejemplo, cerámico de 100 nF), y que el multimuestreo mitiga aún más sus efectos [4]. Espressif también reporta, para la ESP32 original, error de no linealidad en el rango alto de tensión y un rango limitado al inicio y al final por el error de offset; con la calibración *Line Fitting* de la ESP32, el error calibrado en su medición fue en general menor que 30 mV, salvo por la pérdida de lecturas en esos extremos [6]. La resolución (el paso q) no es lo mismo que la exactitud.

**ADC1 y ADC2.** La unidad ADC2 también la usa el Wi-Fi, y su uso simultáneo puede bloquear la lectura o hacerla fallar [4, 5]. Si el programa de la ESP32 llegara a usar Wi-Fi, los ejes del joystick deberían leerse en canales de ADC1 *(criterio derivado de [4])*.

**Consecuencia para este diseño** *(cálculo propio, a partir de [4] y de 1.1)*. Si el módulo se alimenta a 3,3 V (por confirmar en 3.2), el centro del recorrido queda cerca de 1,65 V, dentro de los rangos sugeridos de 6 dB y de 12 dB, pero el tramo por encima de 2450 mV queda fuera incluso del rango sugerido más amplio. Las lecturas cerca de los extremos son las menos exactas, así que los umbrales de dirección deben definirse con los valores de reposo y de extremos medidos en el módulo.

### 1.3 UART: comunicación serie asíncrona

La UART transmite bytes por una sola línea, sin reloj compartido: ambos extremos deben transmitir a la misma velocidad, pactada de antemano, para tener la misma temporización de bit [7]. Cada byte viaja dentro de una trama:

| Elemento de la trama | Nivel | Descripción [7] |
|---|---|---|
| Reposo | Alto | Sin datos, la línea se mantiene en alto |
| Bit de inicio | Bajo | Transición del reposo (alto) a bajo |
| Bits de datos | Según el dato | De 5 a 9 bits (7 u 8 son lo más común), normalmente con el menos significativo primero |
| Paridad | Opcional | Un bit para detectar errores |
| Bit de parada | Alto | Marca el fin de los datos; un segundo bit de parada es posible pero poco común |

La notación 8N1 significa 8 bits de datos, sin paridad (*none*) y un bit de parada; una trama 8N1 ocupa 10 tiempos de bit *(cálculo propio)*. El tiempo de bit es el inverso de la velocidad:

$$
T_{bit} = \frac{1}{\mathrm{baud}}
$$

A 115200 baudios, una de las velocidades comunes [7], resulta:

$$
T_{bit} = \frac{1}{115\,200\ \mathrm{baud}} \approx 8{,}68\ \mu\mathrm{s}
$$

Una trama 8N1 dura entonces unos 86,8 µs *(cálculo propio)*.

**Recepción.** Sin reloj compartido, el receptor detecta el flanco de bajada del bit de inicio y muestrea cada bit en su punto medio [8]. Maxim describe un receptor con un reloj 16 veces mayor que la velocidad de datos: tras el flanco de bajada espera 8 ciclos para llegar al centro del bit de inicio y luego 16 ciclos para cada punto medio siguiente [8].

**Tolerancia de velocidad.** Un desajuste entre las velocidades del emisor y del receptor desplaza el punto de muestreo a lo largo de la trama. Maxim calcula que el desajuste admisible es de ±3,3 % en un caso normal (el bit se puede muestrear dentro del 75 % central de su duración) y de ±2 % en un caso «nasty» (muestreo confiable solo en el 50 % central, como en un enlace largo y capacitivo) [8]. Ese margen se comparte entre transmisor y receptor, en cualquier proporción [8].

**Velocidad a partir del reloj de la FPGA.** Contar N ciclos de reloj por bit genera la temporización:

$$
N = \frac{f_{clk}}{\mathrm{baud}}
$$

Como N debe ser entero, la velocidad real difiere de la pedida. Con el reloj de 27 MHz de la placa de pruebas y 115200 baudios *(cálculo propio)*:

$$
N = \frac{27\,000\,000}{115\,200} = 234{,}375 \;\Rightarrow\; N = 234
$$

$$
\mathrm{baud}_{real} = \frac{27\,000\,000}{234} \approx 115\,385 \qquad e = \frac{115\,385 - 115\,200}{115\,200} \approx +0{,}16\,\%
$$

Un error de +0,16 % es mucho menor que el margen de ±3,3 % de [8]. El reloj y los baudios son parámetros del diseño (ver el [README del equipo](../README.md)), de modo que este cálculo se repite si cambia la placa.

**Qué transporta la UART.** Solo bytes: el significado de cada byte (el formato del paquete) lo define el equipo en 3.2. El documento de la fase de diseño contempla el joystick analógico con ADC simple y, para un mando propio, pide un protocolo simple (UART, I2C o SPI) documentado byte por byte en ambos extremos [9].

### 1.4 Entradas asíncronas: metaestabilidad y sincronizador de dos flip-flops

La línea RX llega desde la ESP32, que genera la señal con su propio reloj: sus flancos pueden aparecer en cualquier instante respecto del reloj de la FPGA. Es un cruce entre dos dominios de reloj, y el registro que captura la señal puede quedar en un estado metaestable: cualquier estado que no es alto ni bajo, sino intermedio, como durante una transición [10]. Cuanto más cerca del punto medio está ese estado, más tarda en resolverse y menos seguro es su valor final [10].

El circuito estándar para recibir un bit de otro dominio es el sincronizador: una cadena de dos (o más) registros, sin lógica entre ellos, con el reloj del receptor. El primero recibe el bit sincronizado con el reloj del emisor y el segundo entrega una versión sincronizada con el reloj del receptor [10]. Una segunda metaestabilidad «es exponencialmente menos probable que la primera» [10]. Sus propiedades, según [10]:

- La latencia es impredecible desde el reloj emisor y va de 1 a 3 ciclos.
- Solo se puede sincronizar un bit a la vez en un mismo cruce de dominios.
- No elimina el problema: es imposible diseñar circuitos libres de metaestabilidad, porque implicarían transiciones de estado instantáneas. El sincronizador solo reduce la probabilidad de falla.

**Aplicación a este diseño.** RX es un solo bit, así que cumple la condición de un bit a la vez. La variación de latencia de 1 a 3 ciclos son 2 ciclos de incertidumbre; con 234 ciclos por bit, eso es el 0,85 % de un tiempo de bit *(cálculo propio)*, pequeño frente a la zona central del bit en la que se puede muestrear con seguridad [8].

### 1.5 Periféricos mapeados en memoria

En un sistema con periféricos mapeados en memoria, el procesador controla el hardware leyendo y escribiendo direcciones: cada periférico ocupa una ventana del mapa de memoria. El manual de RISC-V indica que distintos rangos del espacio de direcciones pueden contener memoria principal o uno o más dispositivos de E/S, y que las lecturas y escrituras a dispositivos de E/S pueden tener efectos secundarios visibles, mientras que los accesos a memoria principal no [11]. El documento de la fase de diseño fija esta arquitectura para la consola: un solo bus de memoria y periféricos mapeados en memoria (MMIO) [9].

En el SoC del curso el bus es Wishbone y cada periférico se conecta mediante un adaptador (`WishbonePeripheral`). Cuando el firmware accede a la ventana de un periférico, el adaptador le entrega durante un ciclo las señales de acceso (en una escritura, `cs`, `wr`, `addr` y `d_in`) y responde `ack` al bus [12]. La interfaz completa, con `rd` y `d_out` para las lecturas, está en el [README del equipo](../README.md).

**Aplicación al joystick.** El procesador solo ve registros: lee la posición de cada eje y el estado del botón con una lectura a la dirección del registro correspondiente. La recepción por UART y la sincronización ocurren en hardware, sin intervención del procesador. Esto plantea dos preguntas de diseño para 3.2 *(razonamiento propio a partir de [11])*:

- Si leer un registro tiene efectos secundarios (por ejemplo, borrar un aviso de dato nuevo), el mapa de registros debe documentarlo.
- El hardware puede actualizar los registros mientras el procesador los lee, así que hay que definir cuándo los valores de un mismo paquete son coherentes entre sí.

### 1.6 De los conceptos a las decisiones de diseño

| Concepto | Decisión de diseño que condiciona | Se usa en |
|---|---|---|
| 1.1 Divisor de tensión | Alimentación del módulo; valores de reposo y de extremos medidos | 3.2 |
| 1.2 ADC de la ESP32 | Atenuación, calibración y canal de ADC; formato del valor dentro del paquete | 3.2 y programa de la ESP32 (`esp32/`) |
| 1.3 UART | Baudios, divisor del reloj, trama 8N1 y muestreo a mitad de bit | 3.2, 3.3, 3.6 y 4.1 |
| 1.4 Sincronizador | Cómo entra la línea RX a la FPGA | 3.3 y 4.1 |
| 1.5 MMIO | Mapa de registros y coherencia de las lecturas | 3.2 |

## 2. Fundamento

> **Pendiente.** Listo cuando: el principio de funcionamiento del periférico cabe en uno o dos párrafos claros.

## 3. Etapa de diseño

### 3.1 Diagrama de caja negra

> **Pendiente.** Listo cuando: todas las entradas y salidas tienen nombre, sin mostrar nada del interior.

### 3.2 Características de la interfaz

> **Pendiente.** Listo cuando: cada señal tiene nombre, dirección y ancho; están el protocolo UART con la ESP32, el formato del paquete, el mapa de registros, los pines y los voltajes.

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

[1] SparkFun Electronics, «Voltage Dividers», SparkFun Learn. Disponible en: https://learn.sparkfun.com/tutorials/voltage-dividers (consultado el 12 de noviembre de 2026).

[2] SparkFun Electronics, «Thumb Joystick» (SKU COM-09032). Disponible en: https://www.sparkfun.com/thumb-joystick.html (consultado el 12 de noviembre de 2026).

[3] W. Kester, «ADC Architectures II: Successive Approximation ADCs», Analog Devices, tutorial MT-021. Copia consultada en: https://web.eng.fiu.edu/watsonh/eel4730/Appendix/MT-021.pdf (consultado el 12 de noviembre de 2026).

[4] Espressif Systems, «Analog to Digital Converter (ADC)», ESP-IDF Programming Guide v4.4.7, ESP32. Disponible en: https://docs.espressif.com/projects/esp-idf/en/v4.4.7/esp32/api-reference/peripherals/adc.html (consultado el 12 de noviembre de 2026).

[5] Espressif Systems, «Analog to Digital Converter (ADC) Oneshot Mode Driver», ESP-IDF Programming Guide v5.3.2, ESP32. Disponible en: https://docs.espressif.com/projects/esp-idf/en/v5.3.2/esp32/api-reference/peripherals/adc_oneshot.html (consultado el 12 de noviembre de 2026).

[6] Espressif Systems, «Comparing ADC Performance of Espressif SoCs», Espressif Developer Portal, 26 de agosto de 2025. Disponible en: https://developer.espressif.com/blog/2025/08/adc-performance/ (consultado el 12 de noviembre de 2026).

[7] Rohde & Schwarz, «Understanding UART». Disponible en: https://www.rohde-schwarz.com/us/_254524.html (consultado el 12 de noviembre de 2026).

[8] Maxim Integrated (hoy parte de Analog Devices), «Determining Clock Accuracy Requirements for UART Communications», 7 de agosto de 2003. Disponible en: https://www.analog.com/en/resources/technical-articles/determining-clock-accuracy-requirements-for-uart-communications.html (consultado el 12 de noviembre de 2026).

[9] Documento de la fase de diseño del curso, «Fase de Diseño. Proyecto: Consola de Videojuegos en FPGA»: apartados «1.2 Núcleo de procesador», «1.4 Entradas (controles)» y «Entregable E: Selección y justificación de periféricos» (subsección «Entradas»).

[10] C. E. LaForest, «A Primer on Clock Domain Crossing (CDC) Theory», FPGA Design Elements, fpgacpu.ca (sin fecha visible). Disponible en: https://fpgacpu.ca/fpga/cdc.html (consultado el 12 de noviembre de 2026).

[11] RISC-V International, «The RISC-V Instruction Set Manual», volumen de instrucciones base no privilegiadas, capítulo «Introduction», sección «Memory». Copia del repositorio del manual consultada en: https://mirror.iscas.ac.cn/riscv-toolchains/git/riscv/riscv-isa-manual.git/tree/src/intro.adoc (consultado el 12 de noviembre de 2026).

[12] Plantilla del curso, `template/diagramas/README.md`, sección «Flujo de una operación de firmware sobre un periférico».
