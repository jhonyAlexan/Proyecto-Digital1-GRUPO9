# Periférico: Audio

El procesador femtoRV32 escribe en registros mapeados en memoria qué sonido generar, y el periférico produce la señal que llega al parlante. El periférico genera tonos de onda cuadrada con muestras de 8 bits y las envía por I2S al amplificador MAX98357A, que convierte a analógico y maneja el parlante.
 
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

> Se agregan a medida que se usan.
