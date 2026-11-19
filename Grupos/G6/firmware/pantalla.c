// pantalla.c - dibuja el cuadro en un arreglo de 64x64
// cada byte es un LED con color de 3 bits {R,G,B} (8 colores, como la pantalla del G4)
#include "pantalla.h"
#include "controles.h"
#include "hardware.h"

uint8_t pantalla[64 * 64];

#define NEGRO    0
#define AZUL     1
#define VERDE    2
#define CIAN     3
#define ROJO     4
#define MAGENTA  5
#define AMARILLO 6
#define BLANCO   7

void rect(int x, int y, int w, int h, uint8_t color) {
  for (int j = y; j < y + h; j++) {
    for (int i = x; i < x + w; i++) {
      if (i >= 0 && i < 64 && j >= 0 && j < 64)
        pantalla[(j << 6) + i] = color;  // j*64 + i
    }
  }
  leer_uart();
}

// letras de 3x5: cada fila son 3 bits
static uint16_t letra(char c) {
  switch (c) {
    case 'A': return 0x2BED;  // 010 101 111 101 101
    case 'C': return 0x3923;  // 011 100 100 100 011
    case 'E': return 0x79A7;  // 111 100 110 100 111
    case 'G': return 0x396B;  // 011 100 101 101 011
    case 'H': return 0x5BED;  // 101 101 111 101 101
    case 'J': return 0x126A;  // 001 001 001 101 010
    case 'L': return 0x4927;  // 100 100 100 100 111
    case 'N': return 0x6B6D;  // 110 101 101 101 101
    case 'P': return 0x6BA4;  // 110 101 110 100 100
    case 'R': return 0x6BAD;  // 110 101 110 101 101
    case 'S': return 0x388E;  // 011 100 010 001 110
    case 'U': return 0x5B6F;  // 101 101 101 101 111
    case 'V': return 0x5B6A;  // 101 101 101 101 010
    case '0': return 0x7B6F;  // 111 101 101 101 111
    case '1': return 0x2C97;  // 010 110 010 010 111
    case '2': return 0x73E7;  // 111 001 111 100 111
    case '3': return 0x73CF;  // 111 001 111 001 111
    case '4': return 0x5BC9;  // 101 101 111 001 001
    case '5': return 0x79CF;  // 111 100 111 001 111
    case '6': return 0x79EF;  // 111 100 111 101 111
    case '7': return 0x7292;  // 111 001 010 010 010
    case '8': return 0x7BEF;  // 111 101 111 101 111
    case '9': return 0x7BCF;  // 111 101 111 001 111
    case '%': return 0x52A5;  // 101 001 010 100 101
    default:  return 0;
  }
}

void texto(int x, int y, const char *s, uint8_t color) {
  while (*s) {
    uint16_t bits = letra(*s);
    for (int fila = 0; fila < 5; fila++)
      for (int col = 0; col < 3; col++)
        if (bits & (1 << (14 - fila - fila - fila - col)))
          pantalla[((y + fila) << 6) + x + col] = color;
    x += 4;
    s++;
    leer_uart();
  }
}

// escribe el dano (0 a 999) seguido de %, sin dividir:
// las centenas y decenas salen restando 800, 400, 200, 100...
static void dano(int x, int y, int v, uint8_t color) {
  char t[5];
  int n = 0, c = 0, d = 0;
  if (v >= 800) { v -= 800; c += 8; }
  if (v >= 400) { v -= 400; c += 4; }
  if (v >= 200) { v -= 200; c += 2; }
  if (v >= 100) { v -= 100; c += 1; }
  if (v >= 80) { v -= 80; d += 8; }
  if (v >= 40) { v -= 40; d += 4; }
  if (v >= 20) { v -= 20; d += 2; }
  if (v >= 10) { v -= 10; d += 1; }
  if (c > 0) t[n++] = '0' + c;
  if (c > 0 || d > 0) t[n++] = '0' + d;
  t[n++] = '0' + v;
  t[n++] = '%';
  t[n] = 0;
  texto(x, y, t, color);
}

static void fondo(void) {
  for (int y = 0; y < 64; y++) {
    for (int x = 0; x < 64; x++) pantalla[(y << 6) + x] = NEGRO;
    leer_uart();  // la UART no tiene FIFO
  }
  // la isla
  rect(ISLA_X0, ISLA_Y, ISLA_X1 - ISLA_X0, 2, VERDE);
  rect(ISLA_X0 + 2, ISLA_Y + 2, ISLA_X1 - ISLA_X0 - 4, 4, AMARILLO);
  // las plataformas de arriba
  const plataforma_t *p = plataformas;
  for (int i = 0; i < N_PLATAFORMAS; i++, p++) rect(p->x0, p->y, p->x1 - p->x0, 2, CIAN);
}

// Dibujos de 10 x 14 mirando a la derecha. Cada letra es un color:
// . vacio, a azul, c cian, r rojo, m magenta, y amarillo, w blanco
static const char *const robot[ALTO] = {
  ".....r....",
  ".....w....",
  "...wwwww..",
  "...wwcwc..",
  "...wwwww..",
  "..aaaaaa..",
  ".wacaaaaw.",
  ".wacaaaaw.",
  ".waaaaaaw.",
  "..aaaaaa..",
  "..ww..ww..",
  "..ww..ww..",
  "..aa..aa..",
  "..aaa.aaa.",
};

static const char *const caballero[ALTO] = {
  "..mmm.....",
  ".mm.......",
  "..rrrrr...",
  "..rrrrrr..",
  "..rrrwww..",
  "..rrrrrr..",
  ".mmrrrrmm.",
  ".mryyyyrm.",
  ".mrrrrrrm.",
  "..yyyyyy..",
  "..rr..rr..",
  "..mm..mm..",
  "..rr..rr..",
  "..rrr.rrr.",
};

static uint8_t color_de(char c) {
  switch (c) {
    case 'a': return AZUL;
    case 'c': return CIAN;
    case 'r': return ROJO;
    case 'm': return MAGENTA;
    case 'y': return AMARILLO;
    case 'w': return BLANCO;
    default:  return NEGRO;  // vacio
  }
}

// copia el dibujo a la pantalla; si mira a la izquierda lo voltea
static void sprite(int x, int y, const char *const *dib, int dir, int blanco) {
  for (int f = 0; f < ALTO; f++) {
    int py = y - ALTO + f;
    const char *fila = dib[f];
    if (py >= 0 && py < 64) {
      for (int c = 0; c < ANCHO; c++) {
        char k = (dir > 0) ? fila[c] : fila[ANCHO - 1 - c];
        int px = x + c;
        if (k != '.' && px >= 0 && px < 64) pantalla[(py << 6) + px] = blanco ? BLANCO : color_de(k);
      }
    }
    leer_uart();
  }
}

static void dibujar_luchador(luchador_t *l, const char *const *dib) {
  // al reaparecer parpadea mientras es invulnerable
  if (l->t_invulnerable > 0 && ((l->t_invulnerable >> 2) & 1)) return;

  int x = l->x >> 8, y = l->y >> 8;

  // fuera de la pantalla: un marcador en el borde muestra por donde va
  if (x + ANCHO <= 0 || x >= 64 || y - ALTO >= 64 || y <= 0) {
    int mx = x + (ANCHO >> 1) - 1, my = y - (ALTO >> 1) - 1;
    if (mx < 0) mx = 0;
    if (mx > 61) mx = 61;
    if (my < 12) my = 12;  // debajo del marcador de dano
    if (my > 61) my = 61;
    rect(mx, my, 3, 3, l->color);
    pantalla[((my + 1) << 6) + mx + 1] = BLANCO;
    return;
  }

  sprite(x, y, dib, l->dir, l->destello > 0);  // en blanco si acaba de recibir un golpe

  // escudo: un marco blanco alrededor
  if (l->estado == ESCUDO) {
    rect(x - 2, y - ALTO - 2, ANCHO + 4, 1, BLANCO);
    rect(x - 2, y, ANCHO + 4, 1, BLANCO);
    rect(x - 2, y - ALTO - 2, 1, ALTO + 3, BLANCO);
    rect(x + ANCHO + 1, y - ALTO - 2, 1, ALTO + 3, BLANCO);
  }

  // el golpe se ve en sus cuadros activos: brazo y puno
  if (l->estado == GOLPE && l->t_golpe >= 3 && l->t_golpe <= 7) {
    if (l->dir > 0) {
      rect(x + ANCHO - 1, y - 8, 5, 2, l->color2);
      rect(x + ANCHO + 4, y - 10, 4, 5, BLANCO);
    } else {
      rect(x - 4, y - 8, 5, 2, l->color2);
      rect(x - 8, y - 10, 4, 5, BLANCO);
    }
  }
}

// dano y vidas de cada jugador arriba de la pantalla
static void marcador(juego_t *g) {
  luchador_t *j1 = &g->j[0], *j2 = &g->j[1];
  dano(2, 1, j1->dano, BLANCO);
  dano(46, 1, j2->dano, BLANCO);
  for (int i = 0; i < j1->vidas; i++) rect(2 + i + i + i, 8, 2, 2, j1->color);
  for (int i = 0; i < j2->vidas; i++) rect(46 + i + i + i, 8, 2, 2, j2->color);
}

void dibujar(juego_t *g) {
  int t = g->tiempo;
  fondo();
  dibujar_luchador(&g->j[0], robot);
  dibujar_luchador(&g->j[1], caballero);

  if (g->estado == INICIO) {
    texto(22, 3, "PELEA", AMARILLO);
    // cuadrito verde si el mando esta conectado
    texto(14, 10, "J1", BLANCO);
    rect(23, 10, 5, 5, conectado(0) ? VERDE : ROJO);
    texto(36, 10, "J2", BLANCO);
    rect(45, 10, 5, 5, conectado(1) ? VERDE : ROJO);
    if ((t >> 4) & 1) texto(22, 17, "PULSA", BLANCO);
    return;
  }

  marcador(g);
  if (g->estado == FIN) {
    texto(18, 12, "GANA", AMARILLO);
    if (g->ganador == 1) texto(38, 12, "J1", BLANCO);
    else texto(38, 12, "J2", BLANCO);
    if ((t >> 4) & 1) texto(17, 18, "REVANCHA", BLANCO);
    // barra mientras mantiene el boton: llena = volver al inicio
    if (g->sostenido > 0) rect(2, 60, g->sostenido >> 1, 2, AMARILLO);
  }
}
