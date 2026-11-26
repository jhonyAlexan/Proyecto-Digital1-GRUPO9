// main.c - consola del juego de pelea (grupo negro)
#include "controles.h"
#include "hardware.h"
#include "juego.h"
#include "pantalla.h"

#define CICLOS_POR_CUADRO (FRECUENCIA_CPU / 60)  // 60 cuadros por segundo

juego_t juego;

int main(void) {
  iniciar_hardware();
  iniciar_controles();
  iniciar_juego(&juego);

  while (1) {
    uint32_t inicio = ciclos();

    leer_mandos();
    int son = actualizar_juego(&juego, boton_inicio());
    sonido(son);
    dibujar(&juego);
    enviar_pantalla(pantalla);

    // esperar a que se cumpla 1/60 s (16,7 ms) desde el inicio del cuadro
    while (ciclos() - inicio < CICLOS_POR_CUADRO) {
    }
  }
  return 0;
}
