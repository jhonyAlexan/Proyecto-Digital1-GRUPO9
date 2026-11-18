// hardware_web.c - reemplaza hardware.c para probar en el navegador
#include "../firmware/controles.h"
#include "../firmware/hardware.h"
#include "../firmware/juego.h"
#include "../firmware/pantalla.h"

#define EXPORTAR(n) __attribute__((export_name(n)))

static juego_t juego;

void leer_uart(void) {}
void enviar_pantalla(uint8_t *p) {}
void sonido(int efecto) {}
uint32_t ciclos(void) { return 0; }
int boton_inicio(void) { return 0; }
void iniciar_hardware(void) {}

EXPORTAR("iniciar") void iniciar(void) {
  iniciar_controles();
  iniciar_juego(&juego);
}

EXPORTAR("byte") void byte(uint8_t b) { recibir_byte(b); }

EXPORTAR("cuadro") int cuadro(int boton) {
  int son = actualizar_juego(&juego, boton);
  dibujar(&juego);
  return son;
}

EXPORTAR("leds") uint8_t *leds(void) { return pantalla; }
EXPORTAR("estado") int estado(void) { return juego.estado; }

// para la pagina: datos de cada jugador (0 = x, 1 = y, 2 = dano, 3 = vidas, 4 = estado)
EXPORTAR("info") int info(int j, int campo) {
  luchador_t *l = &juego.j[j];
  if (campo == 0) return l->x >> 8;
  if (campo == 1) return l->y >> 8;
  if (campo == 2) return l->dano;
  if (campo == 3) return l->vidas;
  return l->estado;
}

// 1 o 2 cuando alguien gana
EXPORTAR("ganador") int ganador(void) { return juego.ganador; }
