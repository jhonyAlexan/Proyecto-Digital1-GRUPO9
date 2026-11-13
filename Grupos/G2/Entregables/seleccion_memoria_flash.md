# Selección y caracterización de la memoria Flash externa



## 1. Introducción



En el proyecto de Arquitectura Hardware y Sistema de Memorias del grupo G2 se contempla la utilización de una memoria Flash externa para almacenar información no volátil requerida por el videojuego. Entre los datos previstos se encuentran los sprites de los personajes, los escenarios, las tablas de sonido y la persistencia de las puntuaciones más altas (*High Scores*).



La memoria seleccionada teóricamente por el grupo es la W25Q64, fabricada por Winbond. Esta memoria pertenece a la tecnología Flash NOR serial y utiliza una interfaz de comunicación SPI, lo que permite conectarla al sistema mediante un controlador implementado en la FPGA.



## 2. Identificación de la memoria



La W25Q64 es una memoria Flash NOR serial con una densidad de almacenamiento de 64 Mbit, equivalente a 8 MiB (8 388 608 bytes).



Para la caracterización inicial se toma como referencia la familia W25Q64JV de Winbond. La variante exacta y el encapsulado deberán confirmarse antes de realizar el diseño eléctrico definitivo.



### 2.1. Características principales



| Característica | Especificación |

|---|---|

| Fabricante | Winbond |

| Familia | W25Q64 |

| Referencia de estudio | W25Q64JV |

| Tecnología | Flash NOR serial |

| Capacidad | 64 Mbit (8 MiB) |

| Alimentación | 2,7 V a 3,6 V |

| Interfaces | SPI, Dual SPI y Quad SPI |

| Frecuencia STR máxima publicada | 133 MHz |

| Tipo de almacenamiento | No volátil |



Las características eléctricas y de interfaz deben verificarse con la hoja de datos correspondiente al número de parte completo que finalmente se seleccione.



## 3. Fundamento de la selección



La elección de una memoria Flash externa responde a la necesidad de ampliar la capacidad de almacenamiento del sistema sin consumir una cantidad adicional de recursos de memoria interna de la FPGA.



La capacidad de 64 Mbit permite almacenar los recursos gráficos y de sonido previstos para el videojuego. Al tratarse de una memoria no volátil, la información permanece almacenada incluso cuando se interrumpe la alimentación.



Adicionalmente, la interfaz SPI permite establecer una comunicación serial mediante un número reducido de señales. Esto facilita la implementación de un controlador digital en Verilog y su integración con la arquitectura del sistema.



La familia W25Q64JV también contempla modos de comunicación Dual y Quad SPI, que ofrecen posibilidades de ampliación del ancho de transferencia si posteriormente se requiere mejorar el rendimiento.



## 4. Interfaz de comunicación SPI



SPI (Serial Peripheral Interface) es un protocolo de comunicación serial síncrono que permite intercambiar información entre un dispositivo maestro y uno o varios dispositivos esclavos.



En la arquitectura propuesta, la FPGA controla las operaciones de la memoria Flash. Para el modo SPI estándar se utilizan cuatro señales principales:



| Señal | Dirección respecto a la memoria | Función |

|---|---|---|

| CS# | Entrada | Selecciona la memoria cuando se encuentra en nivel bajo. |

| SCLK | Entrada | Recibe la señal de reloj generada por el controlador. |

| DI / MOSI | Entrada | Recibe los comandos, direcciones y datos enviados por la FPGA. |

| DO / MISO | Salida | Transmite hacia la FPGA los datos solicitados. |



La memoria también dispone de señales de alimentación y de funciones adicionales:



- **VCC:** alimentación positiva.

- **GND:** referencia de tierra.

- **WP#:** entrada de protección de escritura, con función alternativa en los modos de mayor cantidad de líneas.

- **HOLD#:** permite suspender temporalmente la comunicación en el modo correspondiente; también tiene una función alternativa como línea de datos.



Las señales WP# y HOLD# deben conectarse de acuerdo con las recomendaciones de la hoja de datos y con el modo de funcionamiento seleccionado.



### 4.1. Funcionamiento de una operación de lectura



Una operación de lectura convencional puede describirse mediante los siguientes pasos:



1\. El controlador coloca CS# en nivel bajo para seleccionar la memoria.

2\. Envía el comando de lectura estándar por la línea MOSI.

3\. Transmite la dirección de memoria desde la cual se desea comenzar la lectura.

4\. La memoria entrega los datos solicitados por la línea MISO, sincronizados con SCLK.

5\. Al finalizar la transferencia, el controlador coloca CS# en nivel alto para terminar la operación.



Las operaciones de escritura y borrado requieren comandos adicionales y respetar las condiciones indicadas por el fabricante. En particular, la programación de datos requiere habilitar previamente la escritura y considerar la organización interna de páginas y sectores.



## 5. Integración en la arquitectura del proyecto



De acuerdo con el README del grupo G2, la memoria Flash externa se contempla dentro del mapa de memoria del sistema en el rango:



`0x3000_0000 - 0x3000_FFFF`



Este rango corresponde al espacio de registros del controlador de memoria Flash dentro del mapa MMIO del sistema; no representa la capacidad física ni las direcciones internas de almacenamiento de la memoria W25Q64.



La integración propuesta contempla los siguientes elementos:



- **Procesador FemtoRV:** solicita las operaciones de lectura o escritura mediante los registros de control del sistema.

- **Controlador Flash SPI:** interpreta las solicitudes y genera las señales necesarias para comunicarse con la memoria.

- **Memoria W25Q64:** almacena los recursos no volátiles del videojuego.

- **Sistema de visualización y sonido:** recibe los datos recuperados para utilizarlos en el funcionamiento del videojuego.



### 5.1. Controlador propuesto



El README del grupo plantea implementar el controlador mediante una máquina de estados finitos con camino de datos (FSMD).



La unidad de control contempla cinco estados:



| Estado | Función |

|---|---|

| IDLE | Espera una solicitud de operación. |

| LOAD_CMD | Prepara y transmite el comando correspondiente. |

| SEND_ADDR | Envía la dirección de memoria. |

| XFER_BYTE | Realiza la transferencia de datos. |

| STOP | Finaliza la operación y libera la selección del dispositivo. |



El camino de datos debe incorporar los elementos necesarios para generar el reloj SPI, desplazar los datos de entrada y salida y controlar la cantidad de bits transferidos.



La implementación definitiva deberá considerar los tiempos, comandos, modos SPI y condiciones de operación establecidos en la hoja de datos del componente.



## 6. Relación con el diagrama de caja negra



El diagrama de caja negra elaborado para el grupo representa las conexiones principales de una memoria Flash SPI.



Para que la representación sea técnicamente correcta, se deben tener en cuenta las siguientes precisiones:



- MOSI/DI representa la entrada serial de datos.

- MISO/DO representa la salida serial de datos.

- SCLK corresponde a la entrada de reloj.

- CS# es la señal de selección activa en bajo.

- VCC y GND son conexiones independientes de alimentación y referencia.

- SO significa *Serial Output*, no una señal independiente de estado.

- WP# y HOLD# son señales adicionales que deben contemplarse en el diseño eléctrico.



El estado interno de la memoria se consulta mediante comandos de lectura de registros de estado, transmitidos a través de la interfaz serial.



## 7. Conclusiones



La memoria W25Q64 constituye una alternativa adecuada para el almacenamiento externo de recursos del videojuego, debido a su capacidad de 64 Mbit, su naturaleza no volátil y su interfaz serial SPI.



Su integración mediante un controlador desarrollado en Verilog permite separar las solicitudes del procesador de las operaciones físicas de comunicación con la memoria. Además, el uso de almacenamiento externo permite reservar los recursos BRAM internos de la FPGA para las funciones de ejecución y visualización definidas en la arquitectura.



La implementación final requiere verificar la variante exacta del componente, sus condiciones eléctricas, la distribución de pines y los tiempos de comunicación establecidos por el fabricante.



## 8. Referencias



\[1] Winbond Electronics Corporation, “W25Q-JV Series — Serial Flash Memory”, información y documentación técnica del fabricante. Disponible en: https://www.winbond.com/hq/product/code-storage-flash/qspi-nor/w25q-jv/



\[2] Winbond Electronics Corporation, “Winbond SpiFlash Memory Selection Guide”, guía de selección de memorias Flash seriales. Disponible en: https://www.winbond.com/export/sites/winbond/product-selection-guide/file/2025-Product-Selection-Guide-Winbond-Code-Storage-Flash-Memory.pdf



\[3] Grupo G2, “Arquitectura Hardware y Sistema de Memorias”, README del repositorio Proyecto-Digital1-GRUPO9, Universidad Nacional de Colombia.

