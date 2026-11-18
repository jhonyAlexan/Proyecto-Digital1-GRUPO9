// hardware.h - direcciones y registros de los perifericos que usa el juego
// Las direcciones base son una propuesta: faltan en memory_map.yml (G2).
#ifndef HARDWARE_H
#define HARDWARE_H

#include <stdint.h>

#define FRECUENCIA_CPU 50000000  // reloj del SoC segun G4; confirmar con G2

// UART que recibe las tramas de J1 y J2 (ESP32 receptor -> FPGA)
#define UART_BASE      0x00400000
#define UART_DATO      0x08
#define UART_CONTROL   0x10

// Pantalla RGB 64x64 (registros del README del G4)
#define PANTALLA_BASE  0x00430000
#define PANT_CONTROL   0x00  // bit 0 = EN
#define PANT_BRILLO    0x04
#define PANT_PIXEL_DIR 0x08  // [5:0] = x, [11:6] = y
#define PANT_PIXEL_DAT 0x0C  // [2:0] = {R,G,B}, avanza solo al siguiente pixel
#define PANT_FRAME     0x10  // cuadros mostrados

#define SONIDO_BASE    0x00440000  // codigo del efecto (G5)
#define BOTON_BASE     0x00450000  // boton de inicio (bit 0)

void iniciar_hardware(void);
void leer_uart(void);
void enviar_pantalla(uint8_t *pantalla);
void sonido(int efecto);
uint32_t ciclos(void);
int boton_inicio(void);

#endif
