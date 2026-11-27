// -----------------------------------------------------------------------------
// G1 V2 - ESP32-C3 SUPER MINI DEL MANDO (variante del esp32_mando.ino original)
//
// Misma trama y mismo enlace (ESP-NOW) que la version para ESP32 DevKit; solo
// cambian los pines, segun el issue #21 del G5 (una sola ESP32-C3 por mando):
//   Joystick X  -> GPIO0 (ADC1_CH0)
//   Joystick Y  -> GPIO1 (ADC1_CH1)
//   Boton (SW)  -> GPIO10, activo en bajo
//   Ataque G3   -> GPIO3 (golpe_out, activo en alto)  [pin libre, a confirmar]
//   UART1 con la FPGA del mando: RX GPIO20, TX GPIO21, 115200 8N1
//
// La ESP32-C3 tiene Wi-Fi y Bluetooth LE, pero NO Bluetooth clasico, por eso
// el enlace es ESP-NOW (sobre Wi-Fi). No hay que emparejar ni escribir MAC.
//
// Dos modos (MODO_PUENTE):
//   false: la C3 lee el joystick, arma la trama y la envia ~30 veces/s por
//          ESP-NOW y por UART1. Si la FPGA del mando envia '?' (0x3F), responde
//          con la ultima trama (montaje del G5, seccion 3.2.3 de su README).
//   true : la FPGA del mando (empaquetador) arma la trama y la manda por UART1;
//          la C3 solo busca tramas validas (0xAA ... XOR) y las reenvia por
//          ESP-NOW a la consola. Asi "un byte que entra por la UART del mando
//          sale por la UART de la consola" (criterio del issue #21).
//
// Trama: [0] 0xAA [1] jugador [2] secuencia [3] X int8 [4] Y int8
//        [5] boton bit0 [6] ataque bit0 [7] XOR de los bytes 1 a 6
//
// Placa en el IDE: "ESP32C3 Dev Module" (o "Nologo ESP32C3 Super Mini"),
// con "USB CDC On Boot: Enabled" para que Serial vaya por el USB.
// NO PROBADO en hardware: falta compilarlo y cargarlo en una C3 real.
// -----------------------------------------------------------------------------
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>

// ======================= CONFIGURACION POR MANDO ============================
#define JUGADOR      1       // 1 para el mando del J1, 2 para el del J2
#define MODO_PUENTE  false   // ver arriba
#define INVERTIR_X   false
#define INVERTIR_Y   false
#define CANAL_WIFI   1       // el mismo en la consola
// ============================================================================

const int PIN_X      = 0;    // ADC1_CH0
const int PIN_Y      = 1;    // ADC1_CH1
const int PIN_SW     = 10;
const int PIN_ATAQUE = 3;
const int PIN_RX1    = 20;   // desde la FPGA del mando
const int PIN_TX1    = 21;   // hacia la FPGA del mando

const uint32_t PERIODO_MS  = 33;    // ~30 tramas/s
const int      ZONA_MUERTA = 80;
const int      ADC_MIN = 0, ADC_MAX = 4095;

uint8_t DESTINO[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

HardwareSerial SerialFPGA(1);
int centro_x = 2048, centro_y = 2048;
uint8_t secuencia = 0;
uint8_t ultima[8] = {0xAA, JUGADOR, 0, 0, 0, 0, 0, JUGADOR};
uint32_t envios_fallidos = 0, reenviadas = 0;

int leerADC(int pin) {
  int s = 0;
  for (int i = 0; i < 4; i++) s += analogRead(pin);
  return s >> 2;
}

int8_t aEje(int crudo, int centro, bool invertir) {
  int d = crudo - centro, v;
  if (d > ZONA_MUERTA)       v = (long)(d - ZONA_MUERTA) * 127 / (ADC_MAX - centro - ZONA_MUERTA);
  else if (d < -ZONA_MUERTA) v = (long)(d + ZONA_MUERTA) * 127 / (centro - ADC_MIN - ZONA_MUERTA);
  else                       v = 0;
  if (v > 127) v = 127;
  if (v < -127) v = -127;
  return (int8_t)(invertir ? -v : v);
}

void calibrarCentro() {
  long sx = 0, sy = 0;
  for (int i = 0; i < 32; i++) { sx += analogRead(PIN_X); sy += analogRead(PIN_Y); delay(2); }
  centro_x = sx / 32; centro_y = sy / 32;
  if (centro_x < 1000 || centro_x > 3000) centro_x = 2048;
  if (centro_y < 1000 || centro_y > 3000) centro_y = 2048;
}

void armarTrama(uint8_t *t) {
  bool boton  = (digitalRead(PIN_SW) == LOW);
  bool ataque = (digitalRead(PIN_ATAQUE) == HIGH);
  int8_t x = aEje(leerADC(PIN_X), centro_x, INVERTIR_X);
  int8_t y = -aEje(leerADC(PIN_Y), centro_y, INVERTIR_Y);   // Y > 0 = arriba
  t[0] = 0xAA; t[1] = JUGADOR; t[2] = secuencia++;
  t[3] = (uint8_t)x; t[4] = (uint8_t)y;
  t[5] = boton ? 1 : 0; t[6] = ataque ? 1 : 0;
  t[7] = t[1] ^ t[2] ^ t[3] ^ t[4] ^ t[5] ^ t[6];
}

bool tramaValida(const uint8_t *t) {
  if (t[0] != 0xAA || (t[1] != 1 && t[1] != 2)) return false;
  return (t[1] ^ t[2] ^ t[3] ^ t[4] ^ t[5] ^ t[6]) == t[7];
}

void enviar(const uint8_t *t) {
  if (esp_now_send(DESTINO, t, 8) != ESP_OK) envios_fallidos++;
}

// MODO_PUENTE: ventana deslizante de 8 bytes sobre lo que llega de la FPGA
void puenteDesdeFPGA() {
  static uint8_t v[8];
  static int n = 0;
  while (SerialFPGA.available()) {
    uint8_t b = SerialFPGA.read();
    if (n < 8) v[n++] = b;
    else { memmove(v, v + 1, 7); v[7] = b; }
    if (n == 8 && tramaValida(v)) {
      enviar(v);
      memcpy(ultima, v, 8);
      reenviadas++;
      n = 0;
    }
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_SW, INPUT_PULLUP);
  pinMode(PIN_ATAQUE, INPUT_PULLDOWN);
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);
  SerialFPGA.begin(115200, SERIAL_8N1, PIN_RX1, PIN_TX1);

  if (!MODO_PUENTE) calibrarCentro();   // no tocar el joystick al encender

  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  esp_wifi_set_channel(CANAL_WIFI, WIFI_SECOND_CHAN_NONE);
  if (esp_now_init() != ESP_OK) Serial.println("Error iniciando ESP-NOW");
  esp_now_peer_info_t par = {};
  memcpy(par.peer_addr, DESTINO, 6);
  par.channel = CANAL_WIFI;
  par.encrypt = false;
  esp_now_add_peer(&par);

  Serial.printf("G1 mando C3 J%d listo (%s). MAC=%s\n", JUGADOR,
                MODO_PUENTE ? "puente" : "joystick", WiFi.macAddress().c_str());
}

void loop() {
  if (MODO_PUENTE) {
    puenteDesdeFPGA();
  } else {
    static uint32_t ultimo = 0;
    if (millis() - ultimo >= PERIODO_MS) {
      ultimo = millis();
      armarTrama(ultima);
      enviar(ultima);
      SerialFPGA.write(ultima, 8);
    }
    // Solicitud '?' de la FPGA del mando (montaje del G5)
    while (SerialFPGA.available()) {
      if (SerialFPGA.read() == '?') SerialFPGA.write(ultima, 8);
    }
  }

  static uint32_t dep = 0;
  if (millis() - dep > 500) {
    dep = millis();
    Serial.printf("J%d seq=%3u X=%4d Y=%4d B=%u A=%u fallos=%lu reenviadas=%lu\n",
                  ultima[1], ultima[2], (int8_t)ultima[3], (int8_t)ultima[4],
                  ultima[5], ultima[6], (unsigned long)envios_fallidos,
                  (unsigned long)reenviadas);
  }
}
