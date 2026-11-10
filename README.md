# Consola de videojuegos sobre FPGA — Repositorio general (Diseño Digital 1)

Contiene lo **compartido por el curso**: arquitectura, construcción base del SoC LiteX,
interfaces, mapa de memoria e integración. Cada equipo trabaja en **un unico repositorio general**.

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

## Grupos  
G1 -   
G2 - ramon santiago castro c, juan vasquez, sofia michelle  
G3 - Alexander Calderón Piedrahita, Jeimmy Pinto Aconcha y Kennet Cruz Machuca.  
G4 - Carol Sánchez, William Niño, Juan Pablo Barrera, Juan Hernández.    
G5 - Andrés Alejandro González Vargas, James Velázquez Boyaca y Juan Esteban Castañeda.    
G6 - Juan Esteban Salazar Cabra, Juan Diego Vega Ramírez, Andrés Camilo Bermúdez Molina.  

## Designación de Tareas.  
G1 - Comunicación de FPGA.   
G2 - Arquitectura Hardware.  
G3 - IMU BMI160 (Giro y aceleración).  
G4 - Pantalla.   
G5 - Sonido y Joystick.   
G6 - Arquitectura del Juego.
