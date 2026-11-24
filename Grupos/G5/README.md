# G5: Sonido y Joystick

Carpeta del equipo G5 dentro del proyecto **Consola de videojuegos sobre FPGA** (Diseño Digital 1, UNAL). El equipo diseña dos periféricos del SoC: el **joystick**, que el procesador lee, y el **audio**, que el procesador escribe.

| Integrantes |
|---|
| Andrés Alejandro González Vargas |
| James Velasquez Boyaca |
| Juan Esteban Castañeda |

## Contenido de la carpeta

```
G5/
├── README.md         Este archivo: resumen, decisiones, estado y registro de avances
├── joystick/
│   ├── README.md     Documentación del periférico, en el orden del flujo de diseño
│   ├── diagramas/    Caja negra, bloques, flujo y máquinas de estado
│   ├── rtl/          Verilog, testbench, Makefile y configuración de GTKWave
│   ├── firmware/     Driver en C para el procesador femtoRV32
│   └── esp32/        Programa de prueba que lee el joystick con el ADC de la ESP32
└── audio/
    ├── README.md     Documentación del periférico, en el orden del flujo de diseño
    ├── diagramas/
    ├── rtl/
    └── firmware/
```

Cada periférico sigue la estructura `cores/<periferico>/` de la plantilla del curso (`template/`), para que la integración en el repositorio general sea directa. La carpeta `joystick/esp32/` es la única adición: el programa de la ESP32 corre fuera de la FPGA y no debe mezclarse con el firmware del procesador.

## Los dos periféricos

| Periférico | Sentido | Funcionamiento general |
|---|---|---|
| Joystick | El procesador **lee** | Cada jugador tiene un mando inalámbrico: una FPGA lee el joystick, a través del ADC de un Arduino, y la IMU, y envía los datos a la consola. El periférico recibe los paquetes y deja los valores en registros que el procesador lee por el bus. |
| Audio | El procesador **escribe** | El procesador escribe en registros la frecuencia y el volumen del tono, y el periférico lo envía por I2S al amplificador MAX98357A, que maneja el parlante. |

Los dos son **periféricos mapeados en memoria**: el procesador solo lee y escribe direcciones, y cada periférico ocupa una ventana propia del mapa de memoria. El mapa de registros de cada uno es el contrato con el resto de la consola: quien programe el juego solo necesita ese mapa, no el circuito interno.

## Interfaz común con el procesador

Los dos periféricos usan las mismas señales hacia el bus:

| Señal | Descripción |
|---|---|
| `clk` | Reloj común del SoC |
| `rst` | Reinicio síncrono, activo en alto |
| `cs` | Selección del periférico, activa durante un ciclo por acceso |
| `addr[3:0]` | Desplazamiento en bytes dentro de la región del periférico |
| `rd`, `wr` | Tipo de acceso: lectura o escritura |
| `d_in[31:0]` | Dato que escribe el procesador |
| `d_out[31:0]` | Dato que lee el procesador, registrado |
| `ack` | Vale 1 el ciclo siguiente a `cs`: marca el ciclo en que `d_out` es válido |

`ack` no está en el contrato base del curso. Los dos periféricos lo agregan porque `d_out` es registrado; si el adaptador del SoC ya espera un ciclo en cada lectura, puede dejarlo sin conectar.

Cada periférico ocupa una región del mapa de memoria, y `cs` sale de `mem_addr[31:16]`:

| Periférico | Región | Registros |
|---|---|---|
| Audio | `0x0043` | `FREQ` (`0x0043_0000`), `VOL` (`0x0043_0004`), `CONTROL` (`0x0043_0008`) |
| Joystick | `0x0047` | `JOY1_DATA` (`0x0047_0000`), `JOY2_DATA` (`0x0047_0004`), `STATUS` (`0x0047_0008`); se amplían cuando se defina la IMU |

## Placas

El destino final es la consola tipo Game Boy del profesor. La Tang Nano 9K es la placa de prueba del equipo: lo que se diseña en ella debe funcionar en la consola cambiando solo parámetros, pines y el módulo superior.

| Placa | Uso | FPGA | Reloj de la placa |
|---|---|---|---|
| Consola tipo Game Boy del profesor | Destino final | La define el profesor | Entra como parámetro |
| Tang Nano 9K | Pruebas del G5 | Gowin GW1NR-9 | 27 MHz |

Para que el diseño sea portable:

- **El núcleo del periférico** (`rtl/`) no conoce la placa. El reloj y los baudios entran como parámetros, la interfaz es el contrato de bus del curso y no se usan bloques propios de un fabricante.
- **Lo que depende de la placa** (módulo superior de prueba, asignación de pines, generación de reloj) va en una subcarpeta por placa, por ejemplo `rtl/placas/tangnano9k/`.
- **La simulación** no depende de ninguna placa: un periférico que pasa su testbench se comporta igual en todas.

## Orden de la documentación

La documentación de cada periférico sigue el **diseño descendente**: de lo más abstracto a lo más concreto. Cada sección responde una pregunta más precisa que la anterior, así que no se avanza a una sección sin haber cerrado la previa.

## Estado de la documentación

Estados posibles: `Pendiente`, `En progreso`, `Hecho`. Una sección está `Hecho` cuando su contenido está completo en el README del periférico.

| # | Sección | Joystick | Audio |
|---|---|---|---|
| 1 | Marco teórico | Hecho | Hecho |
| 2 | Fundamento | Hecho | Hecho |
| 3.1 | Diagrama de caja negra | Hecho | Hecho |
| 3.2 | Características de la interfaz | Hecho | Hecho |
| 3.3 | Diagrama de bloques | Hecho | Hecho |
| 3.4 | Diagrama de flujo | Hecho | Hecho |
| 3.5 | Clasificación del flujo | Hecho | Hecho |
| 3.6 | Máquinas de estado | Hecho | Hecho |
| 4.1 | Organización de módulos e implementación Verilog | Pendiente | Hecho |
| 5.1 | Testbench, estímulos y observación | Pendiente | Hecho |
| 6 | Implementación | Pendiente | Pendiente |

## Decisiones del equipo

| Tema | Decisión |
|---|---|
| Reloj | 27 MHz, el de la Tang Nano 9K. Los dos periféricos lo reciben como parámetro, así que también funcionan con 25 MHz o con el reloj de la consola final. |
| Lugar de trabajo | Directamente en `Grupos/G5`, una carpeta por periférico. |
| Clasificación del flujo | Separación de cada diseño en ruta de datos y unidad de control. |
| Joystick: mandos | Requisito del profesor: dos mandos inalámbricos. En cada mando, una FPGA recibe el joystick desde el ADC de un Arduino por UART y la IMU por I2C, y envía los datos a la consola. Están en definición el enlace inalámbrico, el módulo de IMU y el formato del paquete. |
| Audio | I2S hacia el amplificador MAX98357A, con tonos de onda cuadrada de frecuencia y volumen programables. |
| Consola final | Se integra cambiando parámetros, pines y el módulo superior; el núcleo de cada periférico no depende de la placa. |

## Convenciones del equipo

- Nombres de carpetas y archivos sin espacios ni tildes: los Makefile y la terminal fallan con ellos.
- Las señales se llaman igual en los diagramas, en el Verilog y en la documentación.
- Cada aporte queda en el registro de avances, con su fecha y su autor.

## Registro de avances y aportes

Esta sección registra los avances, implementaciones, pruebas y aportes del equipo, en orden de fecha.

| Fecha | Integrante(s) | Descripción del aporte | Estado |
|---|---|---|---|
| 2026-11-09 | James Velásquez | Joystick · Crear la estructura de carpetas y el README del joystick. (`289c081`) | Hecho |
| 2026-11-12 | jcastanedacr | Joystick · Agregar el fundamento inicial del joystick. (`eb45462`) | Hecho |
| 2026-11-12 | jcastanedacr | Joystick · Integrar el fundamento en main mediante el PR #5. (`7d829f5`) | Hecho |
| 2026-11-13 | James Velásquez | Joystick · Documentar el marco teórico con referencias. (`52b65c8`) | Hecho |
| 2026-11-17 | James Velásquez | Joystick · Agregar la caja negra y el programa de lectura inicial en ESP32. (`4dd0bf9`) | Hecho |
| 2026-11-17 | James _E | Joystick · Retirar la marca «En progreso» del marco teórico. (`b4c2937`) | Hecho |
| 2026-11-19 | jcastanedacr | Joystick · Documentar la interfaz UART, el paquete y el mapa de registros. (`7d9c9f9`) | Hecho |
| 2026-11-19 | jcastanedacr | Joystick · Agregar el diagrama de bloques y describir sus funciones. (`a7ec1e3`) | Hecho |
| 2026-11-19 | jcastanedacr | Joystick · Agregar el diagrama de flujo de adquisición y recepción. (`9da7cb4`) | Hecho |
| 2026-11-19 | jcastanedacr | Joystick · Eliminar un encabezado duplicado de la interfaz. (`9aeb6ca`) | Hecho |
| 2026-11-19 | jcastanedacr | Joystick · Ampliar el fundamento e ilustrar el recorrido de la señal. (`b70bddf`) | Hecho |
| 2026-11-23 | James Velasquez Boyaca | Audio: etapa de diseño (3.1 a 3.6) con ocho figuras; sección 2 ajustada a 512 ciclos por trama. | Hecho |
| 2026-11-23 | James Velasquez Boyaca | Audio: Verilog del periférico (4.1), un módulo por bloque. | Hecho |
| 2026-11-23 | James Velasquez Boyaca | Audio: testbench con 7 casos, Makefile y vista de GTKWave (5.1); pasa con 25 y 27 MHz. | Hecho |
| 2026-11-23 | James Velásquez | Joystick · Clasificar el flujo en ruta de datos y unidad de control. (`6431614`) | Hecho |
| 2026-11-23 | James Velásquez | Joystick · Documentar las máquinas de estado UART y de paquetes con dos diagramas. (`a84131f`) | Hecho |
| 2026-11-24 | James Velasquez Boyaca | Audio: ASMD dibujado a mano con tabla de transferencias, arquitectura de control y ruta de datos, conexión al SoC, 27 MHz como reloj principal y testbench con cobertura de T0 a T8. | Hecho |
| 2026-11-24 | James Velasquez Boyaca | Audio: la caja negra de Andrés González se redibujó como figura 5 con las señales rd, d_out y ack; su versión original queda en el historial del repositorio. | Hecho |
| 2026-11-24 | James Velasquez Boyaca | Equipo: README al día con el contrato común, las regiones del mapa, las decisiones del equipo y los requisitos de los mandos; fórmulas de audio que GitHub no dibujaba. | Hecho |

## Uso de herramientas de IA

El equipo usa asistentes de IA (Claude y ChatGPT) como apoyo para redactar, dibujar figuras y proponer código. Cada aporte lo revisa y lo sube un integrante, que responde por su contenido. Algunos commits del 23 de noviembre lo indican con la línea `Co-Authored-By`; desde el 24 de noviembre la declaración queda solo en esta sección.
