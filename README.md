# Consola de videojuegos sobre FPGA — Repositorio general (Diseño Digital 1)

Contiene lo **compartido por el curso**: arquitectura, construcción base del SoC LiteX,
interfaces, mapa de memoria e integración. Cada equipo trabaja en **su propio repositorio**: recibe de aquí
las actualizaciones comunes y devuelve aquí sus resultados validados.

## Estructura
```
template/
    .github/ISSUE_TEMPLATE/     # Formulario de tareas para GitHub
    planificacion/              # Configuración y uso de GitHub Projects
    diagramas/                    # Diagramas generales de flujo y de bloques del sistema
    cores/                        # Un directorio por periférico
        <periferico>/
            diagramas/            # Diagramas de flujo, bloques y estados del módulo
            rtl/                  # Código Verilog y archivos de simulación
                Makefile          # Construcción y prueba del módulo
                module.v          # Componentes RTL del módulo
                module_TB.v       # Testbench de cada componente
                module_sim.gtkw   # Configuración de señales para GTKWave
            firmware/             # Driver y rutinas C para controlar el módulo
    firmware/                     # Juego y programas C de integración/prueba

diagrama_soc_digital1_v3.svg
README.md
```
