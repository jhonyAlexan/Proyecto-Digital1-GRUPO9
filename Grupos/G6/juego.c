// juego.c - logica del juego con reglas tipo Smash
// Fisica y reglas tomadas de la beta previa del grupo (Smash 8-bit),
// pasadas a C. Todo en punto fijo Q8.8: solo sumas, restas y desplazamientos.
//
// Entradas de cada mando:
//   joystick X      correr
//   joystick arriba saltar (doble salto)
//   movimiento = 1  golpe (el G3 manda 1 mientras el mando se mueve, 0 quieto)
//   boton           escudo (en las pantallas de inicio y fin: empezar)
#include "juego.h"
#include "controles.h"

#define ACELERACION     46
#define VEL_MAX        333   // 1.3 px por cuadro
#define SALTO         -691
#define GRAVEDAD        38   // +0.15 px por cuadro: saltos flotados como en Smash
#define CAIDA_MAX      512   // 2 px por cuadro: hay tiempo de volver
#define T_GOLPE         10   // el golpe pega en los cuadros 3 a 7
#define T_ESPERA         8   // pausa entre golpes si el mando sigue moviendose
#define DANO_GOLPE       7
#define EMPUJE_BASE    150   // con poco dano casi no lo mueve
#define EMPUJE_ESCUDO  120   // el escudo para el golpe pero lo corre un poco
#define T_ATURDIDO      14
#define T_INVULNERABLE 100
#define VIDAS            3
#define T_VOLVER_INICIO 120  // mantener el boton 2 s en la pantalla final

// dos a los lados y una mas alta en el centro
const plataforma_t plataformas[N_PLATAFORMAS] = {
    {11, 25, 36},
    {39, 53, 36},
    {24, 40, 24},
};

static void iniciar_luchador(luchador_t *l, int x, int dir, uint8_t color, uint8_t color2) {
  l->x = Q8(x);
  l->y = Q8(ISLA_Y);
  l->vx = 0;
  l->vy = 0;
  l->dir = dir;
  l->estado = QUIETO;
  l->dano = 0;
  l->vidas = VIDAS;
  l->saltos = 2;
  l->t_golpe = 0;
  l->t_espera = 0;
  l->t_aturdido = 0;
  l->t_invulnerable = 0;
  l->destello = 0;
  l->en_suelo = 1;
  l->arriba_antes = 1;
  l->ya_golpeo = 0;
  l->color = color;
  l->color2 = color2;
}

static void empezar_pelea(juego_t *g) {
  iniciar_luchador(&g->j[0], 12, 1, 1, 3);   // J1 robot: azul y cian
  iniciar_luchador(&g->j[1], 42, -1, 4, 5);  // J2 caballero: rojo y magenta
  g->estado = JUGANDO;
  g->tiempo = 0;
}

void iniciar_juego(juego_t *g) {
  empezar_pelea(g);  // deja a los luchadores en su sitio para la pantalla de inicio
  g->estado = INICIO;
  g->ganador = 0;
  g->boton_antes = 1;
  g->sostenido = 0;
}

// Mueve un luchador un cuadro segun su control
static void mover(luchador_t *l, control_t *c) {
  int izq = c->x < -40;
  int der = c->x > 40;
  int arriba = c->y > 40;
  int abajo = c->y < -40;  // bajar de una plataforma de arriba
  int salto_nuevo = arriba && !l->arriba_antes;  // empujar arriba, no mantener
  l->arriba_antes = arriba;

  // temporizadores
  if (l->t_golpe > 0) {
    l->t_golpe--;
    if (l->t_golpe == 0 && l->estado == GOLPE) {
      l->estado = l->en_suelo ? QUIETO : AIRE;
      l->t_espera = T_ESPERA;
    }
  }
  if (l->t_espera > 0) l->t_espera--;
  if (l->t_aturdido > 0) {
    l->t_aturdido--;
    if (l->t_aturdido == 0 && l->estado == ATURDIDO) l->estado = l->en_suelo ? QUIETO : AIRE;
  }
  if (l->t_invulnerable > 0) l->t_invulnerable--;
  if (l->destello > 0) l->destello--;

  int libre = (l->estado != GOLPE && l->estado != ATURDIDO);

  if (libre && c->boton) {
    // boton oprimido: escudo, se queda quieto
    l->estado = ESCUDO;
    libre = 0;
  } else if (l->estado == ESCUDO) {
    l->estado = l->en_suelo ? QUIETO : AIRE;
  }

  if (libre && c->ataque && l->t_espera == 0) {
    // el mando se esta moviendo: golpe
    l->estado = GOLPE;
    l->t_golpe = T_GOLPE;
    l->ya_golpeo = 0;
    libre = 0;
  }

  if (salto_nuevo && libre && l->saltos > 0) {  // doble salto
    l->vy = SALTO;
    l->saltos--;
    l->en_suelo = 0;
    l->estado = AIRE;
  }
  if (libre) {
    if (izq) {
      l->vx -= ACELERACION;
      l->dir = -1;
      if (l->en_suelo) l->estado = CORRER;
    } else if (der) {
      l->vx += ACELERACION;
      l->dir = 1;
      if (l->en_suelo) l->estado = CORRER;
    } else if (l->en_suelo) {
      l->estado = QUIETO;
    }
    // la velocidad maxima solo limita al que corre; el empuje de un golpe puede pasarla
    if (l->vx > VEL_MAX) l->vx = VEL_MAX;
    if (l->vx < -VEL_MAX) l->vx = -VEL_MAX;
  }

  // friccion en el suelo: vx * 0.75 sin multiplicar
  if (l->en_suelo && !(libre && (izq || der))) {
    l->vx = l->vx - (l->vx >> 2);
    if (l->vx < 4 && l->vx > -4) l->vx = 0;
  }
  // en el aire se frena poco a poco: vx * 0.94
  if (!l->en_suelo) l->vx -= l->vx >> 4;

  // gravedad y posicion
  l->vy += GRAVEDAD;
  if (l->vy > CAIDA_MAX) l->vy = CAIDA_MAX;
  l->x += l->vx;
  l->y += l->vy;

  // joystick abajo sobre una plataforma de arriba: la atraviesa
  if (abajo && l->en_suelo && (l->y >> 8) < ISLA_Y) l->y += Q8(5);

  // aterrizar (solo cayendo, desde arriba, con el centro de los pies)
  int px = (l->x >> 8) + (ANCHO >> 1);
  int py = l->y >> 8;
  int piso = -1;
  if (l->vy >= 0 && py >= ISLA_Y && py <= ISLA_Y + 4 && px >= ISLA_X0 && px <= ISLA_X1) piso = ISLA_Y;
  const plataforma_t *p = plataformas;
  for (int i = 0; i < N_PLATAFORMAS && !abajo; i++, p++) {
    if (l->vy >= 0 && py >= p->y && py <= p->y + 4 && px >= p->x0 && px <= p->x1) piso = p->y;
  }
  if (piso >= 0) {
    l->y = Q8(piso);
    l->vy = 0;
    l->saltos = 2;
    l->en_suelo = 1;
    if (l->estado == AIRE) l->estado = QUIETO;
  } else {
    l->en_suelo = 0;
    if (l->estado == QUIETO || l->estado == CORRER) l->estado = AIRE;
  }
}

// Revisa si el golpe de "a" toca a "d" (cajas AABB)
static int toca(luchador_t *a, luchador_t *d) {
  if (a->estado != GOLPE || a->ya_golpeo) return 0;
  if (a->t_golpe < 3 || a->t_golpe > 7) return 0;  // solo los cuadros activos
  if (d->t_invulnerable > 0) return 0;

  int ax = a->x >> 8, ay = a->y >> 8;
  int dx = d->x >> 8, dy = d->y >> 8;

  // caja del golpe: 8 x 5 pixeles delante del atacante, a la altura del brazo
  int g_x0, g_x1;
  if (a->dir > 0) { g_x0 = ax + ANCHO; g_x1 = ax + ANCHO + 8; }
  else            { g_x0 = ax - 8; g_x1 = ax; }
  int g_y0 = ay - 10, g_y1 = ay - 5;

  // caja del cuerpo del rival: ANCHO x ALTO pixeles
  if (g_x1 < dx || g_x0 > dx + ANCHO) return 0;
  if (g_y1 < dy - ALTO || g_y0 > dy) return 0;
  return 1;
}

static void aplicar_golpe(luchador_t *a, luchador_t *d) {
  a->ya_golpeo = 1;

  // con el escudo no sube el dano: solo lo corre un poco
  if (d->estado == ESCUDO) {
    d->vx = (a->dir > 0) ? EMPUJE_ESCUDO : -EMPUJE_ESCUDO;
    return;
  }

  d->dano += DANO_GOLPE;
  if (d->dano > 999) d->dano = 999;

  // mas dano, mas lejos sale
  int empuje = EMPUJE_BASE + (d->dano << 2);
  d->vx = (a->dir > 0) ? empuje : -empuje;
  d->vy = -350 - (d->dano << 1);  // tambien sale mas alto con mas dano
  if (d->vy < -900) d->vy = -900;
  d->estado = ATURDIDO;
  d->t_aturdido = T_ATURDIDO;
  d->en_suelo = 0;
  d->destello = 6;
}

// Zonas de muerte bien afuera de la pantalla: fuera de la isla todavia se
// puede volver con el doble salto. Si pasa el limite pierde una vida.
#define LIMITE_IZQ    -36
#define LIMITE_DER     90
#define LIMITE_ABAJO  120
#define LIMITE_ARRIBA -40

static int revisar_caida(luchador_t *l) {
  int px = l->x >> 8, py = l->y >> 8;
  if (px > LIMITE_IZQ && px < LIMITE_DER && py < LIMITE_ABAJO && py > LIMITE_ARRIBA) return 0;
  l->vidas--;
  l->dano = 0;
  l->x = Q8(27);
  l->y = Q8(14);
  l->vx = 0;
  l->vy = 0;
  l->estado = AIRE;
  l->saltos = 2;
  l->en_suelo = 0;
  l->t_golpe = 0;
  l->t_aturdido = 0;
  l->t_invulnerable = T_INVULNERABLE;
  return 1;
}

int actualizar_juego(juego_t *g, int boton) {
  int son = 0;
  contar_cuadro();
  g->tiempo++;

  // en las pantallas sirve el boton de cualquiera (y el de la consola)
  int b = control[0].boton || control[1].boton || boton;
  int pulsa = b && !g->boton_antes;
  g->boton_antes = b;

  if (g->estado == INICIO) {
    // solo empieza si los dos mandos estan mandando datos
    if (pulsa && conectado(0) && conectado(1)) {
      empezar_pelea(g);
      son = SON_MENU;
    }

  } else if (g->estado == JUGANDO) {
    luchador_t *j1 = &g->j[0], *j2 = &g->j[1];
    mover(j1, &control[0]);
    mover(j2, &control[1]);

    // se revisan los dos golpes antes de aplicarlos: nadie tiene ventaja
    int t1 = toca(j1, j2);
    int t2 = toca(j2, j1);
    if (t1) aplicar_golpe(j1, j2);
    if (t2) aplicar_golpe(j2, j1);
    if (t1 || t2) son = SON_GOLPE;

    if (revisar_caida(j1)) son = SON_CAIDA;
    if (revisar_caida(j2)) son = SON_CAIDA;

    if (j1->vidas == 0 || j2->vidas == 0) {
      g->ganador = (j2->vidas == 0) ? 1 : 2;
      g->estado = FIN;
      g->tiempo = 0;
      g->sostenido = -1;  // espera a que suelten el boton
      son = SON_FIN;
    }

  } else if (g->estado == FIN) {
    // pulsar = revancha; mantener 2 s = volver a la pantalla de inicio
    if (b) {
      if (g->sostenido >= 0) {
        g->sostenido++;
        if (g->sostenido >= T_VOLVER_INICIO) {
          iniciar_juego(g);
          son = SON_MENU;
        }
      }
    } else {
      if (g->sostenido > 0 && g->tiempo > 60) {
        empezar_pelea(g);
        son = SON_MENU;
      }
      g->sostenido = 0;
    }
  }
  return son;
}
