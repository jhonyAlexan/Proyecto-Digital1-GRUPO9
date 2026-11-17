# Esto es un propuesta de sistema de comunicaciones
## Caja negra

<img width="1552" height="408" alt="image" src="https://github.com/user-attachments/assets/5e1016f6-19c6-4187-ab39-5a44f1bde5ec" />


Esto consta de tres modulos

- UART
- Empaquetador
- Desempaquetador

  La arquitectura propuesta es la siguiente, donde el lado izquierdo representa un control y el derecho la comunicación en la consola

<img width="5524" height="2284" alt="image" src="https://github.com/user-attachments/assets/6b331879-1b03-4858-99a7-b30cecb67fb5" />



## UART
Envía paqueteds de 8 bits y avisa cunado esta recibiendo, enviando o la información esta lista.

## Empaquetador
Se encarga de administrar los envíos de la informacion
## Desempaquetador
Se encarga de recibir la información procesarla y almacenarla en el registro adecuado

### Como se envían los datos?
La información consta de dos partes, la dirección (addr) y su valor (value). primero llega la dirección para que el desempaquetador se prepare para almacenar y luego la información perse.
