// controles.c - arma los paquetes que llegan por la UART
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
    control[j].sin_datos = 100;
  }
}

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

  control[j].x = paquete[3];
  control[j].y = paquete[4];
  control[j].boton = paquete[5] & 1;
  control[j].ataque = paquete[6] & 1;
  control[j].sin_datos = 0;
}

void contar_cuadro(void) {
  for (int j = 0; j < 2; j++)
    if (control[j].sin_datos < 100) control[j].sin_datos++;
}

// conectado si mando algo en el ultimo segundo (60 cuadros)
int conectado(int j) { return control[j].sin_datos < 60; }
