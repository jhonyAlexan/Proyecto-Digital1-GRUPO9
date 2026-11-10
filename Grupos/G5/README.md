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
├── README.md         Este archivo: resumen, estado de la documentación y preguntas abiertas
├── joystick/
│   ├── README.md     Documentación del periférico, en el orden del flujo de diseño
│   ├── diagramas/    Caja negra, bloques, flujo y máquinas de estado
│   ├── rtl/          Verilog, testbench, Makefile y configuración de GTKWave
│   ├── firmware/     Driver en C para el procesador femtoRV32
│   └── esp32/        Programa de la ESP32 que lee el joystick y envía las lecturas por UART
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
| Joystick | El procesador **lee** | Una ESP32 lee el joystick analógico (dos ejes y un botón) y envía las lecturas por UART a la FPGA. El periférico recibe los paquetes y deja los valores en registros que el procesador lee por el bus. |
| Audio | El procesador **escribe** | El procesador escribe en registros qué sonido generar y el periférico produce la señal hacia el parlante. Método de generación por definir. |

Los dos son **periféricos mapeados en memoria**: el procesador solo lee y escribe direcciones, y cada periférico ocupa una ventana propia del mapa de memoria. El mapa de registros de cada uno es el contrato con el resto de la consola: quien programe el juego solo necesita ese mapa, no el circuito interno.

## Interfaz común con el procesador

Según el contrato del curso (ver `template/diagramas/`), todo periférico se conecta al bus con estas señales:

| Señal | Descripción |
|---|---|
| `clk` | Reloj común del SoC |
| `rst` | Reinicio síncrono, activo en alto |
| `cs` | Selección del periférico, activa durante un ciclo por acceso |
| `addr` | Desplazamiento en bytes dentro de la ventana del periférico |
| `rd`, `wr` | Tipo de acceso: lectura o escritura |
| `d_in[31:0]` | Dato que escribe el procesador |
| `d_out[31:0]` | Dato que lee el procesador |

## Placas

El destino final es la consola tipo Game Boy del profesor. La Tang Nano 9K es la placa de prueba del equipo: lo que se diseña en ella debe funcionar en la consola cambiando solo parámetros, pines y el módulo superior.

| Placa | Uso | FPGA | Reloj de la placa |
|---|---|---|---|
| Consola tipo Game Boy del profesor | Destino final | Por identificar | Por identificar |
| Tang Nano 9K | Pruebas del G5 | Gowin GW1NR-9 | 27 MHz |

Para que el diseño sea portable:

- **El núcleo del periférico** (`rtl/`) no conoce la placa. El reloj y los baudios entran como parámetros, la interfaz es el contrato de bus del curso y no se usan bloques propios de un fabricante.
- **Lo que depende de la placa** (módulo superior de prueba, asignación de pines, generación de reloj) va en una subcarpeta por placa, por ejemplo `rtl/placas/tangnano9k/`.
- **La simulación** no depende de ninguna placa: un periférico que pasa su testbench se comporta igual en todas.

## Orden de la documentación

La documentación de cada periférico sigue el **diseño descendente**: de lo más abstracto a lo más concreto. Cada sección responde una pregunta más precisa que la anterior, así que no se avanza a una sección sin haber cerrado la previa.

## Estado de la documentación

Estados posibles: `Pendiente`, `En progreso`, `Hecho`. Una sección está `Hecho` solo cuando cumple el criterio escrito en el README del periférico.

| # | Sección | Joystick | Audio |
|---|---|---|---|
| 1 | Marco teórico | Pendiente | Pendiente |
| 2 | Fundamento | Pendiente | Pendiente |
| 3.1 | Diagrama de caja negra | Pendiente | Pendiente |
| 3.2 | Características de la interfaz | Pendiente | Pendiente |
| 3.3 | Diagrama de bloques | Pendiente | Pendiente |
| 3.4 | Diagrama de flujo | Pendiente | Pendiente |
| 3.5 | Clasificación del flujo | Pendiente | Pendiente |
| 3.6 | Máquinas de estado | Pendiente | Pendiente |
| 4.1 | Organización de módulos e implementación Verilog | Pendiente | Pendiente |
| 5.1 | Testbench, estímulos y observación | Pendiente | Pendiente |
| 6 | Implementación | Pendiente | Pendiente |

## Preguntas abiertas

Dudas que deben resolverse con las guías o con el profesor. Se marcan al quedar resueltas y la respuesta se anota debajo.

**Sobre la documentación**
- [ ] "Etapas de complementación": ¿significa implementación (síntesis y carga en la FPGA)?
- [ ] "Clasificación del flujo": ¿es la separación entre ruta de datos y unidad de control?
- [ ] ¿El equipo trabaja directamente en esta carpeta o en un repositorio propio que luego se integra al general, como describe el README raíz?

**Sobre el SoC**
- [ ] Modelo exacto de la consola tipo Game Boy del profesor: FPGA, herramienta de síntesis, pines disponibles y voltajes.
- [ ] ¿La consola ya trae botones, cruceta, parlante o salida de audio? Si los trae, cambia el plan del joystick (ESP32) y del audio.
- [ ] Frecuencia de `clk` del SoC en la consola; de ella depende el divisor de la UART del joystick.
- [ ] ¿Quién define la plataforma final y el reloj del SoC?
- [ ] Dirección base de cada periférico. `template/diagramas/` menciona `interfaces/memory_map.yml`, que aún no está en el repositorio.
- [ ] Ancho de `addr` asignado a la ventana de cada periférico.

**Sobre el joystick**
- [ ] ¿El periférico tiene su propio receptor UART en Verilog, o se reutiliza la UART del SoC? La del SoC ya se usa como consola.
- [ ] Voltaje del banco de pines que recibe la línea RX de la ESP32 (la ESP32 trabaja a 3,3 V).
- [ ] Formato definitivo del paquete y frecuencia de envío, según lo que necesite el software del juego.

**Sobre el audio**
- [ ] Hardware de salida: parlante, amplificador y método de generación (PWM, DAC u otro).
- [ ] Qué necesita el juego: tonos simples, notas, efectos o volumen.
- [ ] Registros que escribe el procesador.

## Convenciones del equipo

- Nombres de carpetas y archivos sin espacios ni tildes: los Makefile y la terminal fallan con ellos.
- Las señales se llaman igual en los diagramas, en el Verilog y en la documentación.
- Ningún cambio se sube sin que otro integrante lo revise.

## Registro de avances y aportes

En esta sección se documentarán los principales avances, implementaciones, pruebas y contribuciones realizadas por el Grupo 5.

| Fecha | Integrante(s) | Descripción del aporte | Estado |
|---|---|---|---|
| | | | En desarrollo |