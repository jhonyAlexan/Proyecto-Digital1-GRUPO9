# Periférico: Joystick

Una ESP32 lee un joystick analógico de dos ejes con botón y envía las lecturas por UART a la FPGA. El periférico recibe esos paquetes y guarda los valores en registros mapeados en memoria, que el procesador femtoRV32 lee por el bus del SoC.

> Estado de cada sección y preguntas abiertas: [README del equipo](../README.md).

## 1. Marco teórico

> **Pendiente.** Listo cuando: los conceptos que el lector necesita (UART, periféricos mapeados en memoria, ADC de la ESP32) están explicados y con fuentes citadas.

## 2. Fundamento

El joystick analógico permite detectar movimientos en dos ejes (X e Y) y la pulsación de un botón. La ESP32 recibe las señales de los ejes, las convierte en valores digitales mediante su conversor analógico-digital (ADC) y lee el estado del botón. Posteriormente, transmite esta información a la FPGA mediante comunicación serial UART. De esta manera, la ESP32 se encarga de adquirir las señales del joystick, mientras que la FPGA recibe los datos digitales.

Dentro de la FPGA, el periférico del joystick procesa la información recibida y almacena los valores de los ejes y del botón en registros mapeados en memoria. El procesador femtoRV32 puede consultar estos registros a través del bus del sistema para conocer la posición del joystick y utilizarla como entrada de control de la consola. Así, el joystick se integra al sistema sin que el procesador tenga que realizar directamente la conversión de las señales analógicas.
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

> Se agregan a medida que se usan.
