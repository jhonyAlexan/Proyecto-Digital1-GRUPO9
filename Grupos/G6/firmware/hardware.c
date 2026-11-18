// hardware.c - aqui esta todo lo que lee o escribe registros
#include "hardware.h"
#include "controles.h"

#define REG(dir) (*(volatile uint32_t *)(dir))

void iniciar_hardware(void) {
  REG(PANTALLA_BASE + PANT_CONTROL) = 1;  // EN: configura el panel y empieza a barrer
}

// Igual que getChar() del curso pero sin quedarse esperando.
// La UART guarda un solo byte, por eso hay que llamarla seguido.
void leer_uart(void) {
  if (REG(UART_BASE + UART_CONTROL) & (1 << 8)) {
    REG(UART_BASE + UART_CONTROL) = 0x02;
    uint8_t b = REG(UART_BASE + UART_DATO);
    REG(UART_BASE + UART_CONTROL) = 0x00;
    recibir_byte(b);
  }
}

// Manda los 4096 pixeles a la pantalla del G4.
// Se espera a que FRAME cambie para no escribir a mitad de un barrido.
void enviar_pantalla(uint8_t *pantalla) {
  uint32_t f = REG(PANTALLA_BASE + PANT_FRAME);
  while (REG(PANTALLA_BASE + PANT_FRAME) == f) leer_uart();

  REG(PANTALLA_BASE + PANT_PIXEL_DIR) = 0;  // x = 0, y = 0
  for (int i = 0; i < 4096; i++) {
    REG(PANTALLA_BASE + PANT_PIXEL_DAT) = pantalla[i];  // PIXEL_ADDR avanza solo
    if ((i & 63) == 0) leer_uart();
  }
}

void sonido(int efecto) {
  if (efecto != 0) REG(SONIDO_BASE) = efecto;
}

uint32_t ciclos(void) {
  uint32_t c;
  __asm__ volatile("rdcycle %0" : "=r"(c));
  return c;
}

int boton_inicio(void) { return REG(BOTON_BASE) & 1; }
