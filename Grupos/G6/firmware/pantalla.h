// pantalla.h
#ifndef PANTALLA_H
#define PANTALLA_H

#include <stdint.h>
#include "juego.h"

extern uint8_t pantalla[64 * 64];

void dibujar(juego_t *g);

#endif
