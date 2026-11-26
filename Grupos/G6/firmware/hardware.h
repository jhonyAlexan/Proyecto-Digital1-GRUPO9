// hardware.h - direcciones y registros de los perifericos que usa el juego
// Mapa tomado de los README de cada grupo (26 de noviembre de 2026).
// Solo este archivo y hardware.c conocen direcciones.
#ifndef HARDWARE_H
#define HARDWARE_H

#include <stdint.h>

#define FRECUENCIA_CPU 27000000  // reloj unico del SoC (Tang Nano 9K, G2)

// GPIO del SoC (0x0041): 4 botones y 8 LEDs
#define GPIO_BASE      0x00410000
#define GPIO_LEDS      0x04
#define GPIO_BOTONES   0x08  // bits 3:0, 1 = oprimido

// Sonido (G5, 0x0043): generador de tonos
#define AUDIO_BASE     0x00430000
#define AUDIO_FREQ     0x00  // f = FREQ * fs / 65536 (fs = 46 875 Hz con 27 MHz)
#define AUDIO_VOL      0x04  // 0 a 127
#define AUDIO_CONTROL  0x08  // bit 0: 1 = suena

// Pantalla RGB 64x64 (G4, 0x0044)
#define PANTALLA_BASE  0x00440000
#define PANT_CONTROL   0x00  // bit 0 = EN
#define PANT_BRILLO    0x04
#define PANT_ESTADO    0x08  // bit 0 = barriendo
#define PANT_FRAME     0x10  // cuadros mostrados
#define PANT_PIXELES   0x4000  // pixel (x, y) en +0x4000 + 4 * (64 * y + x), color {R,G,B}

// Mandos (G5, 0x0047): el periferico recibe las tramas y deja lo ultimo valido
#define MANDOS_BASE    0x00470000
#define MANDO_J1       0x00  // [7:0] X, [15:8] Y, [16] boton, [17] ataque, [31:24] secuencia
#define MANDO_J2       0x04
#define MANDOS_ESTADO  0x08  // bit 0 J1 valido, bit 1 J2 valido, bit 2 error UART, bit 3 error checksum

void iniciar_hardware(void);
void leer_mandos(void);
void enviar_pantalla(uint8_t *pantalla);
void sonido(int efecto);
uint32_t ciclos(void);
int boton_inicio(void);

#endif
