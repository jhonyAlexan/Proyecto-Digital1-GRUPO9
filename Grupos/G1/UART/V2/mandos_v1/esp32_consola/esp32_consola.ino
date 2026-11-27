// -----------------------------------------------------------------------------
// G1 v1 - ESP32 DE LA CONSOLA (puente inalambrico -> UART)
//
// Recibe por ESP-NOW las tramas de 8 bytes de los dos mandos (J1 y J2), las
// valida y las reenvia sin cambios por UART2 (GPIO17, 115200 8N1) a la FPGA de
// la consola, donde el periferico de mandos (region 0x0047) las guarda.
//
// Dos modos de envio, los dos activos a la vez:
//   - Continuo: cada trama valida que llega se reenvia de inmediato (~30/s por mando).
//   - Por solicitud (montaje del G5): si la FPGA envia '?' por GPIO16, se
//     reenvia la ultima trama de cada jugador.
//
// Si un mando deja de llegar por mas de 500 ms, se deja de reenviar su trama;
// la secuencia ya no cambia y el juego (G6) lo marca como desconectado.
// -----------------------------------------------------------------------------
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>

#define CANAL_WIFI 1          // mismo canal que en los mandos

const int PIN_TX2 = 17;       // hacia el pin uart_rx_mando de la FPGA
const int PIN_RX2 = 16;       // desde la FPGA (solicitud '?'), opcional
const uint32_t VENCE_MS = 500;

HardwareSerial SerialFPGA(2);

// Ultima trama valida de cada jugador (la escribe la tarea de Wi-Fi)
volatile uint8_t  ultima[2][8];
volatile bool     nueva[2]  = {false, false};
volatile uint32_t llegada[2] = {0, 0};
volatile uint32_t descartadas = 0;
portMUX_TYPE candado = portMUX_INITIALIZER_UNLOCKED;

bool tramaValida(const uint8_t *t, int len) {
  if (len != 8 || t[0] != 0xAA) return false;
  if (t[1] != 1 && t[1] != 2) return false;
  uint8_t x = t[1] ^ t[2] ^ t[3] ^ t[4] ^ t[5] ^ t[6];
  return x == t[7];
}

void guardar(const uint8_t *datos, int len) {
  if (!tramaValida(datos, len)) { descartadas++; return; }
  int j = datos[1] - 1;
  portENTER_CRITICAL(&candado);
  for (int i = 0; i < 8; i++) ultima[j][i] = datos[i];
  nueva[j] = true;
  llegada[j] = millis();
  portEXIT_CRITICAL(&candado);
}

#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
void alRecibir(const esp_now_recv_info_t *info, const uint8_t *datos, int len) {
  guardar(datos, len);
}
#else
void alRecibir(const uint8_t *mac, const uint8_t *datos, int len) {
  guardar(datos, len);
}
#endif

// Copia la trama del jugador j y la envia; solo_nueva = modo continuo
void enviarJugador(int j, bool solo_nueva) {
  uint8_t t[8];
  bool enviar;
  portENTER_CRITICAL(&candado);
  bool vigente = (millis() - llegada[j]) < VENCE_MS && llegada[j] != 0;
  enviar = vigente && (!solo_nueva || nueva[j]);
  if (enviar) {
    for (int i = 0; i < 8; i++) t[i] = ultima[j][i];
    nueva[j] = false;
  }
  portEXIT_CRITICAL(&candado);
  if (enviar) SerialFPGA.write(t, 8);   // 8 bytes = ~0,7 ms a 115200
}

void setup() {
  Serial.begin(115200);
  SerialFPGA.begin(115200, SERIAL_8N1, PIN_RX2, PIN_TX2);

  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  esp_wifi_set_channel(CANAL_WIFI, WIFI_SECOND_CHAN_NONE);
  if (esp_now_init() != ESP_OK) {
    Serial.println("Error iniciando ESP-NOW");
  }
  esp_now_register_recv_cb(alRecibir);

  Serial.printf("G1 consola lista. MAC=%s canal=%d\n",
                WiFi.macAddress().c_str(), CANAL_WIFI);
}

void loop() {
  // Modo continuo
  enviarJugador(0, true);
  enviarJugador(1, true);

  // Modo por solicitud: '?' desde la FPGA
  while (SerialFPGA.available()) {
    if (SerialFPGA.read() == '?') {
      enviarJugador(0, false);
      enviarJugador(1, false);
    }
  }

  // Estado por el monitor serie cada segundo
  static uint32_t ultimo = 0;
  if (millis() - ultimo > 1000) {
    ultimo = millis();
    uint32_t a = millis();
    Serial.printf("J1 %s  J2 %s  descartadas=%lu\n",
                  (llegada[0] && a - llegada[0] < VENCE_MS) ? "OK" : "--",
                  (llegada[1] && a - llegada[1] < VENCE_MS) ? "OK" : "--",
                  (unsigned long)descartadas);
  }
}
