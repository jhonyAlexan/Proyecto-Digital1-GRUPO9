const int PIN_X  = 34;   // eje X, ADC1
const int PIN_Y  = 35;   // eje Y, ADC1
const int PIN_SW = 13;   // botón del joystick

void setup() {
  Serial.begin(115200);
  pinMode(PIN_SW, INPUT_PULLUP);   // pull-up interna: suelto = 1, presionado = 0
}

void loop() {
  int x    = analogRead(PIN_X);              // número crudo, 0 a 4095
  int y    = analogRead(PIN_Y);
  int x_mv = analogReadMilliVolts(PIN_X);    // milivoltios con calibración de fábrica
  int y_mv = analogReadMilliVolts(PIN_Y);
  bool presionado = (digitalRead(PIN_SW) == LOW);

  Serial.printf("X: %4d (%4d mV)   Y: %4d (%4d mV)   boton: %d\n",
                x, x_mv, y, y_mv, presionado);
  delay(100);
} 
