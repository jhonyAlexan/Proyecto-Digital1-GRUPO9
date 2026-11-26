// controles.c - estado de los dos mandos
#include "controles.h"

control_t control[2];

static uint8_t paquete[8];
static int n = 0;  // cuantos bytes llevamos del paquete

void iniciar_controles(void) {
  for (int j = 0; j < 2; j++) {
    control[j].x = 0;
    control[j].y = 0;
    control[j].boton = 0;
    control[j].ataque = 0;
    control[j].secuencia = -1;
    control[j].sin_datos = 100;
  }
}

// Recibe el registro de un jugador. Si la secuencia cambio, llego una trama nueva.
void actualizar_control(int j, uint32_t dato) {
  control_t *c = j ? &control[1] : &control[0];
  c->x = (int8_t)(dato & 0xFF);
  c->y = (int8_t)((dato >> 8) & 0xFF);
  c->boton = (dato >> 16) & 1;
  c->ataque = (dato >> 17) & 1;
  int sec = (dato >> 24) & 0xFF;
  if (sec != c->secuencia) {
    c->secuencia = sec;
    c->sin_datos = 0;
  }
}

// Lo mismo que hace el periferico del G5, pero en software: lo usa la beta,
// que manda las tramas byte por byte.
void recibir_byte(uint8_t b) {
  if (n == 0 && b != 0xAA) return;  // esperar el inicio
  paquete[n] = b;
  n++;
  if (n < 8) return;
  n = 0;

  // revisar el checksum
  uint8_t x = paquete[1] ^ paquete[2] ^ paquete[3] ^ paquete[4] ^ paquete[5] ^ paquete[6];
  if (x != paquete[7]) return;

  int j;
  if (paquete[1] == 1) j = 0;
  else if (paquete[1] == 2) j = 1;
  else return;

  uint32_t dato = paquete[3] | ((uint32_t)paquete[4] << 8) | ((uint32_t)(paquete[5] & 1) << 16) |
                  ((uint32_t)(paquete[6] & 1) << 17) | ((uint32_t)paquete[2] << 24);
  actualizar_control(j, dato);
}

void contar_cuadro(void) {
  for (int j = 0; j < 2; j++)
    if (control[j].sin_datos < 100) control[j].sin_datos++;
}

// conectado si llego una trama en el ultimo segundo (60 cuadros)
int conectado(int j) { return control[j].sin_datos < 60; }
