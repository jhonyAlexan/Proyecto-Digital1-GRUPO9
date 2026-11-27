// respuesta_solicitud: la ESP32 espera la solicitud de la FPGA ('?' = 0x3F) por UART2 y
// responde con el paquete de 8 bytes de la sección 3.2.3 del README del joystick:
//   AA, jugador, secuencia, X, Y, botón, ataque, XOR de los bytes 1 a 6.
// X e Y van en 8 bits con signo (-127 a 127, 0 con la palanca en reposo).
// Conexiones: GPIO17 (TX2) -> pin 28 de la FPGA, GPIO16 (RX2) <- pin 29 de la FPGA, GND común.
// Por el USB (monitor serie a 115200) imprime lo que envía, para depurar.

const int PIN_X   = 34;      // eje X, ADC1
const int PIN_Y   = 35;      // eje Y, ADC1
const int PIN_SW  = 13;      // botón del joystick
const int PIN_RX2 = 16;      // llega uart_tx de la FPGA
const int PIN_TX2 = 17;      // va a uart_rx de la FPGA

const uint8_t CABECERA  = 0xAA;
const uint8_t SOLICITUD = 0x3F;   // '?'
const uint8_t JUGADOR   = 1;      // 1 en el mando 1, 2 en el mando 2

int reposo_x, reposo_y;           // lectura con la palanca quieta, medida al encender
uint8_t secuencia = 0;
unsigned long ultima_solicitud = 0;
unsigned long ultimo_aviso = 0;

// Promedio de 32 lecturas: baja el ruido del ADC
int promedio(int pin) {
  long suma = 0;
  for (int i = 0; i < 32; i++) suma += analogRead(pin);
  return suma / 32;
}

// De 12 bits sin signo (0 a 4095) a 8 bits con signo: se resta el reposo y se divide entre 16
int8_t escalar(int lectura, int reposo) {
  int v = (lectura - reposo) / 16;
  if (v > 127)  v = 127;
  if (v < -127) v = -127;
  return (int8_t) v;
}

void setup() {
  Serial.begin(115200);                                  // USB: monitor serie
  Serial2.begin(115200, SERIAL_8N1, PIN_RX2, PIN_TX2);   // enlace con la FPGA
  pinMode(PIN_SW, INPUT_PULLUP);                         // suelto = 1, presionado = 0
  delay(200);
  reposo_x = promedio(PIN_X);                            // no muevas la palanca al encender
  reposo_y = promedio(PIN_Y);
  Serial.printf("Reposo medido: X = %d, Y = %d. Esperando solicitudes de la FPGA...\n",
                reposo_x, reposo_y);
}

void loop() {
  if (Serial2.available() > 0) {
    uint8_t c = Serial2.read();
    if (c == SOLICITUD) {
      uint8_t p[8];
      p[0] = CABECERA;
      p[1] = JUGADOR;
      p[2] = secuencia;
      p[3] = (uint8_t) escalar(analogRead(PIN_X), reposo_x);
      p[4] = (uint8_t) escalar(analogRead(PIN_Y), reposo_y);
      p[5] = (digitalRead(PIN_SW) == LOW) ? 1 : 0;
      p[6] = 0;                                          // ataque: sin usar por ahora
      p[7] = p[1] ^ p[2] ^ p[3] ^ p[4] ^ p[5] ^ p[6];
      Serial2.write(p, 8);

      if (secuencia % 50 == 0)                           // una línea cada medio segundo
        Serial.printf("Solicitud %3d   X = %4d   Y = %4d   boton = %d\n",
                      secuencia, (int8_t) p[3], (int8_t) p[4], p[5]);
      secuencia++;
      ultima_solicitud = millis();
    }
  }

  // Si la FPGA no pide nada en 1 s, avisa una vez por segundo
  if (millis() - ultima_solicitud > 1000 && millis() - ultimo_aviso > 1000) {
    Serial.println("Sin solicitudes de la FPGA: revisa el cable pin 29 -> GPIO16, la GND y que la FPGA esté cargada");
    ultimo_aviso = millis();
  }
}
