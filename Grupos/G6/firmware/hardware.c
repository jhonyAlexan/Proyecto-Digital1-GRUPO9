// hardware.c - aqui esta todo lo que lee o escribe registros
#include "hardware.h"
#include "controles.h"

#define REG(dir) (*(volatile uint32_t *)(dir))

void iniciar_hardware(void) {
  REG(PANTALLA_BASE + PANT_CONTROL) = 1;  // EN: configura el panel y empieza a barrer
  REG(AUDIO_BASE + AUDIO_CONTROL) = 0;    // en silencio
  REG(AUDIO_BASE + AUDIO_VOL) = 64;
}

// El periferico del G5 recibe las tramas en hardware y guarda la ultima valida
// de cada jugador; aqui solo se leen sus registros, una vez por cuadro.
void leer_mandos(void) {
  uint32_t estado = REG(MANDOS_BASE + MANDOS_ESTADO);
  if (estado & 1) actualizar_control(0, REG(MANDOS_BASE + MANDO_J1));
  if (estado & 2) actualizar_control(1, REG(MANDOS_BASE + MANDO_J2));
}

// Manda los 4096 pixeles a la memoria de video del G4.
// Espera a que FRAME cambie para no escribir a mitad de un barrido, pero
// como maximo un cuadro: si la pantalla no responde, el juego sigue.
void enviar_pantalla(uint8_t *pantalla) {
  uint32_t f = REG(PANTALLA_BASE + PANT_FRAME);
  uint32_t t0 = ciclos();
  while (REG(PANTALLA_BASE + PANT_FRAME) == f && ciclos() - t0 < FRECUENCIA_CPU / 60) {
  }

  volatile uint32_t *video = (volatile uint32_t *)(PANTALLA_BASE + PANT_PIXELES);
  for (int i = 0; i < 4096; i++) video[i] = pantalla[i];  // direccion = 4 * i
}

// Cada efecto es un tono con su duracion. FREQ = f * 65536 / 46875 (fs con 27 MHz).
static int cuadros_sonido = 0;

void sonido(int efecto) {
  int freq = 0, cuadros = 0;
  if (efecto == 1)      { freq = 1230; cuadros = 6;  }  // empezar: 880 Hz, 0,1 s
  else if (efecto == 4) { freq = 308;  cuadros = 4;  }  // golpe: 220 Hz
  else if (efecto == 8) { freq = 154;  cuadros = 18; }  // caida: 110 Hz, 0,3 s
  else if (efecto == 9) { freq = 732;  cuadros = 30; }  // fin: 523 Hz, 0,5 s

  if (freq) {
    REG(AUDIO_BASE + AUDIO_FREQ) = freq;
    REG(AUDIO_BASE + AUDIO_CONTROL) = 1;
    cuadros_sonido = cuadros;
  } else if (cuadros_sonido > 0) {
    cuadros_sonido--;
    if (cuadros_sonido == 0) REG(AUDIO_BASE + AUDIO_CONTROL) = 0;
  }
}

uint32_t ciclos(void) {
  uint32_t c;
  __asm__ volatile("rdcycle %0" : "=r"(c));
  return c;
}

// Boton 1 del GPIO de la consola (opcional: tambien sirve el boton del joystick)
int boton_inicio(void) { return REG(GPIO_BASE + GPIO_BOTONES) & 1; }
