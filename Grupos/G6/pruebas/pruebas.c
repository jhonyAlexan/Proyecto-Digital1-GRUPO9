// pruebas.c - firmware de pruebas de la consola en la FPGA
//
// Corre en el femtoRV32 en vez del juego y prueba las entradas y las salidas
// con el hardware real, sin PC. El boton 1 de la consola (GPIO) cambia de prueba
// (si no esta conectado, se mantiene 2 s el boton de J1):
//   1 PANTALLA  barras de los 8 colores, marco, esquinas y un cuadro que se mueve
//   2 ENTRADAS  joystick, boton y movimiento de J1 y J2, los 4 botones de la
//               consola y los errores del periferico de mandos
//   3 SONIDO    los tonos de los efectos 1, 4, 8 y 9, uno por segundo
// El LED de la placa parpadea si el procesador esta corriendo y se queda
// prendido mientras se oprime cualquier boton (sirve aunque no haya pantalla).
// Los LEDs del GPIO muestran los 4 botones de la consola.
//
// Usa los mismos registros que el juego (../firmware/hardware.h) y la misma
// lectura de los mandos (../firmware/controles.c).
#include <stdint.h>
#include "hardware.h"
#include "controles.h"

#ifndef CPU_HZ
#define CPU_HZ 27000000  // reloj del SoC (Tang Nano 9K); cambiar con make CPU_HZ=...
#endif
#define CICLOS_POR_CUADRO (CPU_HZ / 60)
#ifndef CUADROS_CAMBIO
#define CUADROS_CAMBIO 120      // 2 s con el boton de J1 = siguiente prueba
#endif
#ifndef CUADROS_POR_EFECTO
#define CUADROS_POR_EFECTO 60  // 1 s por efecto de sonido
#endif

#define NEGRO    0
#define AZUL     1
#define VERDE    2
#define CIAN     3
#define ROJO     4
#define MAGENTA  5
#define AMARILLO 6
#define BLANCO   7

// ---------------------------------------------------------------- registros
#define LEER(dir) (*(volatile uint32_t *)(dir))
#define ESCRIBIR(dir, v) (*(volatile uint32_t *)(dir) = (v))
#define UART_CONTROL_SOC 0x00400010  // bit 2 = LED de la placa (UART del SoC)

static uint32_t reloj(void) {
  uint32_t c;
  __asm__ volatile("rdcycle %0" : "=r"(c));
  return c;
}

uint8_t pantalla[64 * 64];
static uint32_t estado_mandos;  // banderas del periferico de mandos

// registros del periferico de mandos (G5), igual que leer_mandos() del juego
static void leer_entradas(void) {
  estado_mandos = LEER(MANDOS_BASE + MANDOS_ESTADO);
  if (estado_mandos & 1) actualizar_control(0, LEER(MANDOS_BASE + MANDO_J1));
  if (estado_mandos & 2) actualizar_control(1, LEER(MANDOS_BASE + MANDO_J2));
}

static void led(int prendido) { ESCRIBIR(UART_CONTROL_SOC, prendido ? 0x04 : 0); }

// manda el cuadro a la memoria de video del G4; si FRAME no cambia en un
// cuadro, sigue igual, para que el LED y las entradas se prueben sin pantalla
static void enviar(void) {
  uint32_t f = LEER(PANTALLA_BASE + PANT_FRAME);
  uint32_t t0 = reloj();
  while (LEER(PANTALLA_BASE + PANT_FRAME) == f && reloj() - t0 < CICLOS_POR_CUADRO) {
  }
  volatile uint32_t *video = (volatile uint32_t *)(PANTALLA_BASE + PANT_PIXELES);
  for (int i = 0; i < 4096; i++) video[i] = pantalla[i];
}

// tonos de los efectos del juego: FREQ = f * 65536 / 46875 (27 MHz)
static void tono(int freq) {
  if (freq) {
    ESCRIBIR(AUDIO_BASE + AUDIO_VOL, 64);
    ESCRIBIR(AUDIO_BASE + AUDIO_FREQ, freq);
    ESCRIBIR(AUDIO_BASE + AUDIO_CONTROL, 1);
  } else {
    ESCRIBIR(AUDIO_BASE + AUDIO_CONTROL, 0);
  }
}

// ---------------------------------------------------------------- dibujo
static void rect(int x, int y, int w, int h, uint8_t c) {
  for (int j = y; j < y + h; j++)
    for (int i = x; i < x + w; i++)
      if (i >= 0 && i < 64 && j >= 0 && j < 64) pantalla[(j << 6) + i] = c;
}

static void marco(int x, int y, int w, int h, uint8_t c) {
  rect(x, y, w, 1, c);
  rect(x, y + h - 1, w, 1, c);
  rect(x, y, 1, h, c);
  rect(x + w - 1, y, 1, h, c);
}

// letras de 3 x 5: cada fila son 3 bits, la de arriba en los bits 14-12
static uint16_t letra(char c) {
  switch (c) {
    case 'A': return 0x2BED;
    case 'B': return 0x6BAE;
    case 'C': return 0x3923;
    case 'D': return 0x6B6E;
    case 'E': return 0x79A7;
    case 'F': return 0x79A4;
    case 'G': return 0x396B;
    case 'I': return 0x7497;
    case 'J': return 0x126A;
    case 'L': return 0x4927;
    case 'M': return 0x5FED;
    case 'N': return 0x6B6D;
    case 'O': return 0x2B6A;
    case 'P': return 0x6BA4;
    case 'R': return 0x6BAD;
    case 'S': return 0x388E;
    case 'T': return 0x7492;
    case 'U': return 0x5B6F;
    case 'X': return 0x5AAD;
    case 'Y': return 0x5A92;
    case '-': return 0x01C0;
    case '>': return 0x4454;
    case '/': return 0x12A4;
    case '0': return 0x7B6F;
    case '1': return 0x2C97;
    case '2': return 0x73E7;
    case '3': return 0x73CF;
    case '4': return 0x5BC9;
    case '5': return 0x79CF;
    case '6': return 0x79EF;
    case '7': return 0x7292;
    case '8': return 0x7BEF;
    case '9': return 0x7BCF;
    default:  return 0;  // espacio
  }
}

static void texto(int x, int y, const char *s, uint8_t c) {
  for (; *s; s++, x += 4) {
    uint16_t g = letra(*s);
    for (int f = 0; f < 5; f++)
      for (int k = 0; k < 3; k++)
        if (g & (1 << (14 - f - f - f - k))) {
          int px = x + k, py = y + f;
          if (px >= 0 && px < 64 && py >= 0 && py < 64) pantalla[(py << 6) + px] = c;
        }
  }
}

// numero de -127 a 127 sin dividir: se restan centenas y decenas
static void numero(int x, int y, int v, uint8_t c) {
  char s[5];
  int n = 0;
  if (v < 0) { s[n++] = '-'; v = -v; }
  int cen = 0, dec = 0;
  while (v >= 100) { v -= 100; cen++; }
  while (v >= 10) { v -= 10; dec++; }
  if (cen) s[n++] = '0' + cen;
  if (cen || dec) s[n++] = '0' + dec;
  s[n++] = '0' + v;
  s[n] = 0;
  texto(x, y, s, c);
}

static void limpiar(void) {
  for (int i = 0; i < 4096; i++) pantalla[i] = NEGRO;
}

// ---------------------------------------------------------------- pruebas
// 1: colores, bordes, orientacion y refresco
static void prueba_pantalla(int t) {
  marco(0, 0, 64, 64, BLANCO);                  // se deben ver los 4 bordes
  texto(3, 3, "1 PANTALLA", BLANCO);
  for (int c = 0; c < 8; c++) {
    int x = 4 + (c << 3) - c;                   // barras de 7 px: x = 4 + 7c
    rect(x, 11, 7, 32, c);                      // 0 negro ... 7 blanco
    char d[2] = {(char)('0' + c), 0};
    texto(x + 2, 45, d, BLANCO);                // numero de cada color
  }
  rect(59, 3, 3, 3, AZUL);                      // esquina de arriba a la derecha
  rect(2, 59, 3, 3, ROJO);                      // abajo a la izquierda
  rect(59, 59, 3, 3, VERDE);                    // abajo a la derecha
  int p = t & 63;                               // cuadro que va y vuelve
  int x = p < 32 ? p : 63 - p;
  rect(6 + x + (x >> 1), 53, 4, 4, BLANCO);     // de x = 6 a x = 52
}

static void cuadro_bit(int x, int y, const char *nombre, int prendido, uint8_t color) {
  texto(x, y, nombre, BLANCO);
  marco(x + 4, y - 1, 7, 7, BLANCO);
  if (prendido) rect(x + 5, y, 5, 5, color);
}

static void mando(int x0, int j, const char *nombre, control_t *c) {
  texto(x0 + 2, 10, nombre, BLANCO);
  rect(x0 + 12, 10, 5, 5, conectado(j) ? VERDE : ROJO);  // verde = llegan tramas
  // joystick: punto dentro de una caja de 17 x 17 (+ arriba)
  int dx = c->x >> 4, dy = c->y >> 4;           // -8 a 7
  if (dx < -6) dx = -6;
  if (dx > 6) dx = 6;
  if (dy < -6) dy = -6;
  if (dy > 6) dy = 6;
  marco(x0 + 2, 17, 17, 17, BLANCO);
  rect(x0 + 9 + dx, 24 - dy, 3, 3, AMARILLO);
  cuadro_bit(x0 + 21, 18, "B", c->boton & 1, AMARILLO);  // boton del joystick
  cuadro_bit(x0 + 21, 27, "M", c->ataque & 1, ROJO);    // movimiento (giroscopio)
  texto(x0 + 2, 36, "X", CIAN);
  numero(x0 + 7, 36, c->x, BLANCO);
  texto(x0 + 2, 42, "Y", CIAN);
  numero(x0 + 7, 42, c->y, BLANCO);
}

static void cuadrito(int x, int y, int prendido, uint8_t color) {
  marco(x, y, 7, 7, BLANCO);
  if (prendido) rect(x + 1, y + 1, 5, 5, color);
}

// 2: lo que llega de cada mando, los botones de la consola y los errores
static void prueba_entradas(int botones) {
  texto(3, 3, "2 ENTRADAS", BLANCO);
  mando(0, 0, "J1", &control[0]);
  mando(32, 1, "J2", &control[1]);
  rect(32, 10, 1, 37, AZUL);                    // separa J1 y J2
  texto(3, 50, "BOTONES", BLANCO);              // los 4 del GPIO
  for (int i = 0; i < 4; i++) cuadrito(33 + (i << 3), 49, (botones >> i) & 1, AMARILLO);
  texto(3, 58, "ERROR", BLANCO);                // del periferico de mandos
  cuadrito(33, 57, estado_mandos & 4, ROJO);    // error de UART
  cuadrito(41, 57, estado_mandos & 8, ROJO);    // error de checksum
}

static const int frecuencias[4] = {1230, 308, 154, 732};  // 880, 220, 110 y 523 Hz
static const char *const nombres[4] = {"1 MENU", "4 GOLPE", "8 CAIDA", "9 FIN"};

// 3: los cuatro efectos de sonido, el que suena va en amarillo
static void prueba_sonido(int actual, int t) {
  texto(3, 3, "3 SONIDO", BLANCO);
  for (int i = 0; i < 4; i++) {
    int y = 13 + (i << 3) + (i << 1);           // y = 13 + 10i
    uint8_t c = (i == actual) ? AMARILLO : BLANCO;
    if (i == actual) texto(4, y, ">", AMARILLO);
    texto(10, y, nombres[i], c);
  }
  rect(4, 55, t, 3, VERDE);                     // barra: tiempo hasta el siguiente
}

// ---------------------------------------------------------------- principal
int main(void) {
  ESCRIBIR(PANTALLA_BASE + PANT_CONTROL, 1);    // enciende la pantalla (G4)
  tono(0);
  iniciar_controles();

  int modo = 0, t = 0, boton_antes = 1, mandos_antes = 1;
  int efecto = 0, cuenta = 0, sostenido = 0;

  while (1) {
    uint32_t inicio = reloj();
    leer_entradas();
    contar_cuadro();
    t++;

    int botones = LEER(GPIO_BASE + GPIO_BOTONES) & 0xF;
    int boton = botones & 1;
    ESCRIBIR(GPIO_BASE + GPIO_LEDS, botones);    // los LEDs repiten los botones
    int mandos = (control[0].boton | control[1].boton) & 1;

    // boton de la consola, o el de J1 mantenido 2 s: siguiente prueba
    int largo = 0;
    if (control[0].boton & 1) {
      if (++sostenido == CUADROS_CAMBIO) largo = 1;
    } else {
      sostenido = 0;
    }
    if ((boton && !boton_antes) || largo) {
      modo = (modo == 2) ? 0 : modo + 1;
      efecto = 0;
      cuenta = 0;
      tono(0);
    }
    boton_antes = boton;

    // LED: prendido con cualquier boton; si no, parpadea (el procesador corre)
    led(botones || mandos || ((t >> 5) & 1));

    limpiar();
    if (modo == 0) {
      prueba_pantalla(t);
    } else if (modo == 1) {
      prueba_entradas(botones);
    } else {
      // un efecto por segundo: medio segundo de tono y medio de silencio;
      // el boton de un mando repite el actual
      if (cuenta == 0) tono(frecuencias[efecto]);
      if (cuenta == (CUADROS_POR_EFECTO >> 1)) tono(0);
      if (mandos && !mandos_antes) cuenta = 0;
      else if (++cuenta >= CUADROS_POR_EFECTO) {
        cuenta = 0;
        efecto = (efecto + 1) & 3;
      }
      prueba_sonido(efecto, cuenta);
    }
    mandos_antes = mandos;

    enviar();
    while (reloj() - inicio < CICLOS_POR_CUADRO) {
    }
  }
  return 0;
}
