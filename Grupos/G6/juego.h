// juego.h - reglas tipo Smash (de la beta previa del grupo), en C
#ifndef JUEGO_H
#define JUEGO_H

#include <stdint.h>

// estados del juego
#define INICIO  0  // pantalla de inicio
#define JUGANDO 1
#define FIN     2

// estados del luchador
#define QUIETO   0
#define CORRER   1
#define AIRE     2
#define GOLPE    3
#define ATURDIDO 4
#define ESCUDO   5  // mantiene el boton: se cubre

// codigos de sonido (los mismos del documento)
#define SON_MENU   1
#define SON_GOLPE  4
#define SON_CAIDA  8
#define SON_FIN    9

// punto fijo Q8.8: 256 = 1 pixel
#define Q8(n) ((n) << 8)

// la isla: se pisa desde arriba entre ISLA_X0 e ISLA_X1
#define ISLA_Y  48
#define ISLA_X0 5
#define ISLA_X1 59

// plataformas de arriba: se atraviesan desde abajo y con el joystick abajo
typedef struct {
  int x0, x1, y;
} plataforma_t;
#define N_PLATAFORMAS 3
extern const plataforma_t plataformas[N_PLATAFORMAS];

// tamano del dibujo de cada luchador (y de su caja del cuerpo)
#define ANCHO 10
#define ALTO  14

typedef struct {
  int x, y;          // esquina izquierda y pies, en Q8.8
  int vx, vy;        // velocidad en Q8.8 por cuadro
  int dir;           // 1 = derecha, -1 = izquierda
  int estado;
  int dano;          // porcentaje de dano acumulado (0 a 999)
  int vidas;
  int saltos;        // saltos que le quedan (doble salto)
  int t_golpe;       // cuadros que le quedan al golpe (10 a 0)
  int t_espera;      // cuadros antes de poder golpear otra vez
  int t_aturdido;
  int t_invulnerable;
  int destello;      // cuadros en blanco despues de recibir un golpe
  int en_suelo;
  int arriba_antes;  // para detectar cuando se empuja el joystick hacia arriba
  int ya_golpeo;     // un golpe solo pega una vez
  uint8_t color, color2;
} luchador_t;

typedef struct {
  int estado;
  int tiempo;
  int ganador;
  int boton_antes;
  int sostenido;     // cuadros con el boton oprimido en la pantalla final
  luchador_t j[2];
} juego_t;

void iniciar_juego(juego_t *g);
int actualizar_juego(juego_t *g, int boton);  // devuelve el sonido

#endif
