# Pantalla

## UART
### 1.

El periférico controla la matriz Seengreat RGB Matrix P3.0-64 ×64 desde la FPGA de la Colorlight 5A-75B. El panel tiene 4096 píxeles con un LED rojo, uno verde y uno azul cada uno, se conecta por la interfaz paralela HUB75 y usa barrido 1/32: solo hay dos filas encendidas a la vez, la fila r y la fila r +32. El panel no guarda la imagen; la debe refrescar continuamente el controlador, cientos de veces por segundo.
Para el resto de la consola el controlador es un periférico del SoC: el procesador le escribe registros por el bus estándar del curso y el periférico genera solo las señales del panel.

### 2.

### 3. 

### 4. Diagrama de flujo del transmisor

### 5. Fundamento: controlador y datapath

### 6. Propuesta de clasificaci´on del flujo de TX

### 7. ASMD:delflujoalastransferenciasporciclo

### 8. Propuesta de bloques de TX: control y datapath

### 9. Máquina de estados del transmisor

### 10. Organizaci´on de m´odulos e implementaci´on Verilog

### 11. Entorno de prueba: testbench, est´ımulos y observaci´on
