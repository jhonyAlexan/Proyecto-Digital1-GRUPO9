// controles.h - lo que manda cada mando
// La ESP32 de cada mando envia 30 tramas por segundo de 8 bytes:
//  [0] 0xAA  [1] jugador  [2] secuencia  [3] joy X  [4] joy Y
//  [5] boton del joystick (bit 0)  [6] ataque (bit 0 = el mando se mueve, G3)
//  [7] XOR de 1 a 6
// En la consola, el periferico de mandos del G5 recibe la trama y la deja en un
// registro por jugador: [7:0] X, [15:8] Y, [16] boton, [17] ataque, [31:24] secuencia.
#ifndef CONTROLES_H
#define CONTROLES_H

#include <stdint.h>

typedef struct {
  int8_t x, y;
  uint8_t boton;
  uint8_t ataque;  // 1 mientras el mando se mueve
  int secuencia;   // ultima secuencia recibida (-1 = ninguna)
  int sin_datos;   // cuadros sin una trama nueva
} control_t;

extern control_t control[2];

void iniciar_controles(void);
void actualizar_control(int j, uint32_t dato);  // dato con el formato del registro
void recibir_byte(uint8_t b);                    // arma la trama byte por byte (beta)
void contar_cuadro(void);
int conectado(int j);

#endif
