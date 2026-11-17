# Esto es un propuesta de sistema de comunicaciones
## Caja negra

<img width="1552" height="408" alt="image" src="https://github.com/user-attachments/assets/5e1016f6-19c6-4187-ab39-5a44f1bde5ec" />


Esto consta de tres modulos

- UART
- Empaquetador
- Desempaquetador

Estos módulos se conectan asi
<img width="2928" height="624" alt="image" src="https://github.com/user-attachments/assets/3cc26793-8aad-4936-bf65-9fd30d6c5b5c" />


  La arquitectura propuesta es la siguiente, donde el lado izquierdo representa un control y el derecho la comunicación en la consola

<img width="5524" height="2284" alt="image" src="https://github.com/user-attachments/assets/6b331879-1b03-4858-99a7-b30cecb67fb5" />



## UART
Envía paqueteds de 8 bits y avisa cunado esta recibiendo, enviando o la información esta lista.

## Empaquetador
Se encarga de administrar los envíos de la informacion

Diagrama de flujo:
<img width="1960" height="3612" alt="image" src="https://github.com/user-attachments/assets/831496eb-86bf-4ecb-9971-666e87ec93ca" />


## Desempaquetador
Se encarga de recibir la información procesarla y almacenarla en el registro adecuado
Diagrama de flujo:
<img width="2600" height="3576" alt="image" src="https://github.com/user-attachments/assets/1e8fe6f4-bc88-46b9-888a-d374a693be0b" />


### Como se envían los datos?
La información consta de dos partes, la dirección (addr) y su valor (value). primero llega la dirección para que el desempaquetador se prepare para almacenar y luego la información perse.
