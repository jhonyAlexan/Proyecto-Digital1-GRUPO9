// controles.h - trama de 8 bytes que manda cada control
//  [0] 0xAA  [1] jugador  [2] secuencia  [3] joy X  [4] joy Y
//  [5] boton del joystick (bit 0, sirve de inicio)
//  [6] ataque (bit 0 = giro brusco, lo calcula el G3): es el golpe
//  [7] XOR de 1 a 6
// Cada control la manda cada 33 ms (30 por segundo)
#ifndef CONTROLES_H
#define CONTROLES_H

#include <stdint.h>

typedef struct {
  int8_t x, y;
  uint8_t boton;
  uint8_t ataque;  // giro brusco detectado en el mando
  int sin_datos;  // cuadros sin recibir nada
} control_t;

extern control_t control[2];

void iniciar_controles(void);
void recibir_byte(uint8_t b);
void contar_cuadro(void);
int conectado(int j);

#endif
