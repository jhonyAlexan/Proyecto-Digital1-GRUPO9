// -----------------------------------------------------------------------------
// G1 v1 - ESP32 DEL MANDO (una por jugador)
//
// Lee el joystick (ejes X/Y y boton) y la senal de ataque del G3 (golpe_out),
// arma la trama de 8 bytes acordada con G5/G6 y la envia de forma inalambrica
// (ESP-NOW) a la ESP32 de la consola. Opcionalmente la saca tambien por cable
// (UART2, GPIO17) para probar sin enlace inalambrico, igual que el montaje del G5.
//
// Trama (G5, README joystick 3.2.3; G6 controles.h):
//   [0] 0xAA  [1] jugador (1 o 2)  [2] secuencia  [3] X (int8)  [4] Y (int8)
//   [5] boton (bit 0)  [6] ataque (bit 0)  [7] XOR de los bytes 1 a 6
//
// Convencion de ejes (G6 juego.c): X > 0 derecha, Y > 0 arriba (saltar).
// Umbral del juego: |valor| > 40.
//
// Placa: ESP32 DevKit (ESP32 original). Core Arduino-ESP32 2.x o 3.x.
// -----------------------------------------------------------------------------
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>

// ======================= CONFIGURACION POR MANDO ============================
#define JUGADOR            1      // 1 para el mando del J1, 2 para el del J2
#define INVERTIR_X         false  // cambiar si el punto de prueba del G6 va al reves
#define INVERTIR_Y         false
#define SALIDA_UART_DIRECTA true  // true: tambien envia la trama por GPIO17 (cable)
#define CANAL_WIFI         1      // debe ser el mismo en la ESP32 de la consola
// ============================================================================

// Pines (los mismos del G5 para el joystick; ADC1, compatible con Wi-Fi)
const int PIN_X      = 34;   // VRx, ADC1
const int PIN_Y      = 35;   // VRy, ADC1
const int PIN_SW     = 13;   // boton del joystick, activo en bajo
const int PIN_ATAQUE = 27;   // golpe_out del G3 (pin 29 de su Tang Nano), activo en alto
const int PIN_TX2    = 17;   // UART2 TX hacia la FPGA (modo cable)
const int PIN_RX2    = 16;   // UART2 RX (no se usa)

const uint32_t PERIODO_MS = 33;   // ~30 tramas por segundo (G5 3.2.2)
const int      ZONA_MUERTA = 80;  // cuentas de ADC alrededor del centro
const int      ADC_MIN = 0, ADC_MAX = 4095;

// Direccion de difusion: la consola acepta tramas validas de cualquier mando,
// asi no hay que escribir direcciones MAC en el codigo.
uint8_t DESTINO[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

HardwareSerial SerialFPGA(2);
int centro_x = 2048, centro_y = 2048;
uint8_t secuencia = 0;
uint32_t envios_fallidos = 0;

// Lectura con promedio de 4 muestras para bajar el ruido del ADC
int leerADC(int pin) {
  int s = 0;
  for (int i = 0; i < 4; i++) s += analogRead(pin);
  return s >> 2;
}

// Convierte una lectura de 12 bits en -127..127 respecto al centro medido
int8_t aEje(int crudo, int centro, bool invertir) {
  int d = crudo - centro;
  int v;
  if (d > ZONA_MUERTA) {
    v = (long)(d - ZONA_MUERTA) * 127 / (ADC_MAX - centro - ZONA_MUERTA);
  } else if (d < -ZONA_MUERTA) {
    v = (long)(d + ZONA_MUERTA) * 127 / (centro - ADC_MIN - ZONA_MUERTA);
  } else {
    v = 0;
  }
  if (v > 127) v = 127;
  if (v < -127) v = -127;
  return (int8_t)(invertir ? -v : v);
}

void calibrarCentro() {
  long sx = 0, sy = 0;
  for (int i = 0; i < 32; i++) {
    sx += analogRead(PIN_X);
    sy += analogRead(PIN_Y);
    delay(2);
  }
  centro_x = sx / 32;
  centro_y = sy / 32;
  // Proteccion contra un centro absurdo (joystick desconectado)
  if (centro_x < 1000 || centro_x > 3000) centro_x = 2048;
  if (centro_y < 1000 || centro_y > 3000) centro_y = 2048;
}

void armarTrama(uint8_t *t) {
  bool boton  = (digitalRead(PIN_SW) == LOW);
  bool ataque = (digitalRead(PIN_ATAQUE) == HIGH);
  int8_t x = aEje(leerADC(PIN_X), centro_x, INVERTIR_X);
  // En la mayoria de modulos el ADC de Y crece hacia abajo: por eso se niega
  // aqui para que Y > 0 sea "arriba". Si queda al reves, usar INVERTIR_Y.
  int8_t y = -aEje(leerADC(PIN_Y), centro_y, INVERTIR_Y);

  t[0] = 0xAA;
  t[1] = JUGADOR;
  t[2] = secuencia++;
  t[3] = (uint8_t)x;
  t[4] = (uint8_t)y;
  t[5] = boton ? 1 : 0;
  t[6] = ataque ? 1 : 0;
  t[7] = t[1] ^ t[2] ^ t[3] ^ t[4] ^ t[5] ^ t[6];
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_SW, INPUT_PULLUP);
  pinMode(PIN_ATAQUE, INPUT_PULLDOWN);   // sin G3 conectado, ataque = 0
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);        // rango 0 a ~3,1 V (G5 1.2)

  if (SALIDA_UART_DIRECTA) {
    SerialFPGA.begin(115200, SERIAL_8N1, PIN_RX2, PIN_TX2);
  }

  calibrarCentro();   // no tocar el joystick al encender

  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  esp_wifi_set_channel(CANAL_WIFI, WIFI_SECOND_CHAN_NONE);
  if (esp_now_init() != ESP_OK) {
    Serial.println("Error iniciando ESP-NOW");
  }

  esp_now_peer_info_t par = {};
  memcpy(par.peer_addr, DESTINO, 6);
  par.channel = CANAL_WIFI;
  par.encrypt = false;
  esp_now_add_peer(&par);

  Serial.printf("G1 mando J%d listo. Centro X=%d Y=%d. MAC=%s\n",
                JUGADOR, centro_x, centro_y, WiFi.macAddress().c_str());
}

void loop() {
  static uint32_t ultimo = 0;
  uint32_t ahora = millis();
  if (ahora - ultimo < PERIODO_MS) return;
  ultimo = ahora;

  uint8_t trama[8];
  armarTrama(trama);

  if (esp_now_send(DESTINO, trama, sizeof(trama)) != ESP_OK) envios_fallidos++;
  if (SALIDA_UART_DIRECTA) SerialFPGA.write(trama, sizeof(trama));

  // Depuracion por el monitor serie (cada ~0,5 s)
  if ((trama[2] & 0x0F) == 0) {
    Serial.printf("J%d seq=%3u X=%4d Y=%4d B=%u A=%u chk=%02X fallos=%lu\n",
                  trama[1], trama[2], (int8_t)trama[3], (int8_t)trama[4],
                  trama[5], trama[6], trama[7], (unsigned long)envios_fallidos);
  }
}
