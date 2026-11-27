# Diseño del `spi_master` y del periférico MMIO (G3 — IMU BMI160)
 
Reloj `clk` = 27 MHz. SPI modo 0 (CPOL=0, CPHA=0), trama de 16 bits, reset asíncrono activo en bajo.
 
> Los diagramas de este documento se derivaron de `spi_master.v` ya implementado y probado en la Tang Nano 9K. El testbench `tb_spi_master_tabla.v` se escribió a partir de la tabla de transferencias de la sección 4.
 
## 1. Clasificación control / datapath
 
| Elemento | Clase | Función |
|---|---|---|
| `state` (1 bit) + fase de `sclk` | Control | Selecciona la transferencia |
| `cs_n`, `done`, `sclk` | Control | Salidas generadas por el controlador |
| `clk_cnt` (5 b) + comparador `== 13` | Datapath | Divisor: genera `tick` cada 14 ciclos |
| `shift_tx` (16 b) | Datapath | Trama a enviar |
| `bit_cnt` (5 b) + comparadores `== 0` y `<= 7` | Datapath | Índice de bit; condiciones `last_bit` y `rx_window` |
| Mux 16:1 `shift_tx[bit_cnt-1]` | Datapath | Siguiente bit hacia `mosi` |
| `rx_data` (8 b) | Datapath | Registro de recepción |
 
Órdenes control → datapath: `load_tx`, `dec_bit`, `sample_rx`, `div_clear`.
Condiciones datapath → control: `tick`, `last_bit`, `rx_window`.
 
## 2. Arquitectura control / datapath
 
```mermaid
flowchart LR
  start[/"start"/] --> FSM
  tx[/"tx_data[15:0]"/] --> SH
  miso[/"miso"/] --> RX
 
  subgraph SPI["spi_master"]
    direction LR
    subgraph CTRL["CONTROL"]
      FSM["FSM<br/>IDLE / LOW / HIGH"]
      OUT["cs_n, sclk, done"]
    end
    subgraph DP["DATAPATH"]
      DIV["clk_cnt 5b<br/>== 13 : tick"]
      SH["shift_tx 16b"]
      BC["bit_cnt 5b<br/>last_bit, rx_window"]
      MUX["mux 16:1"]
      RX["rx_data 8b"]
    end
    FSM -- "load_tx, dec_bit,<br/>sample_rx, div_clear" --> DP
    DP -- "tick, last_bit,<br/>rx_window" --> FSM
    FSM --> OUT
    SH --> MUX
    BC --> MUX
  end
 
  MUX --> mosi[/"mosi"/]
  OUT --> pins[/"sclk, cs_n, done"/]
  RX --> rxd[/"rx_data[7:0]"/]
```
 
## 3. FSM
 
| Estado | `state` | `sclk` | Salidas |
|---|---|---|---|
| IDLE | 0 | 0 | `cs_n = 1` |
| LOW (espera subida) | 1 | 0 | `cs_n = 0` |
| HIGH (espera bajada) | 1 | 1 | `cs_n = 0` |
 
```mermaid
stateDiagram-v2
  [*] --> IDLE : rst_n = 0 (T0)
  IDLE --> IDLE : start = 0 (T1)
  IDLE --> LOW : start = 1 / load_tx (T2)
  LOW --> LOW : tick = 0 (T3)
  LOW --> HIGH : tick = 1 / sclk=1, sample_rx (T4)
  HIGH --> HIGH : tick = 0 (T3)
  HIGH --> LOW : tick = 1 y bit_cnt != 0 / sclk=0, dec_bit (T5)
  HIGH --> IDLE : tick = 1 y bit_cnt = 0 / sclk=0, cs_n=1, done=1 (T6)
```
 
## 4. ASMD y tabla de transferencias
 
```mermaid
flowchart TD
  I["IDLE<br/>cs_n=1, sclk=0"] --> Ds{"start = 1 ?"}
  Ds -- "No (T1)" --> I
  Ds -- "Sí" --> T2["T2: cs_n=0, shift_tx=tx_data,<br/>mosi=tx_data[15], bit_cnt=15"]
  T2 --> L["LOW<br/>sclk=0"]
  L --> Dt1{"tick = 1 ?"}
  Dt1 -- "No (T3)" --> L
  Dt1 -- "Sí" --> T4["T4: sclk=1<br/>si bit_cnt <= 7: rx_data[bit_cnt]=miso"]
  T4 --> H["HIGH<br/>sclk=1"]
  H --> Dt2{"tick = 1 ?"}
  Dt2 -- "No (T3)" --> H
  Dt2 -- "Sí" --> Dl{"bit_cnt = 0 ?"}
  Dl -- "No" --> T5["T5: sclk=0, bit_cnt=bit_cnt-1,<br/>mosi=shift_tx[bit_cnt-1]"]
  T5 --> L
  Dl -- "Sí" --> T6["T6: sclk=0, cs_n=1, done=1"]
  T6 --> I
```
 
Valor por defecto en cada flanco: `done <= 0`. Lo que no aparece mantiene su valor.
 
| ID | Estado y condición | Transferencias en el flanco | Próximo estado |
|---|---|---|---|
| T0 | `rst_n = 0` | `state=0, cs_n=1, sclk=0, mosi=0, done=0, bit_cnt=0, rx_data=0, clk_cnt=0` | IDLE |
| T1 | IDLE, `start = 0` | `cs_n=1, sclk=0` | IDLE |
| T2 | IDLE, `start = 1` | `cs_n=0, shift_tx=tx_data, mosi=tx_data[15], bit_cnt=15, state=1` | LOW |
| T3 | LOW/HIGH, `tick = 0` | `clk_cnt=clk_cnt+1` | mismo |
| T4 | LOW, `tick = 1` | `sclk=1`; si `bit_cnt<=7`: `rx_data[bit_cnt]=miso`; `clk_cnt=0` | HIGH |
| T5 | HIGH, `tick = 1`, `bit_cnt != 0` | `sclk=0, bit_cnt=bit_cnt-1, mosi=shift_tx[bit_cnt-1]`; `clk_cnt=0` | LOW |
| T6 | HIGH, `tick = 1`, `bit_cnt = 0` | `sclk=0, cs_n=1, state=0, done=1`; `clk_cnt=0` | IDLE |
| D1 | `cs_n = 1` | `clk_cnt=0` | — |
 
Notas de temporización:
- `bit_cnt` es el índice del bit que está en la línea. En la subida se muestrea con ese índice; en la bajada se decrementa. Por eso `rx_data[bit_cnt] <= miso` captura el bit correcto.
- En T2 `cs_n` baja en el mismo flanco que acepta `start`; el divisor empieza a contar al flanco siguiente, así que la primera subida de SCLK llega 14 ciclos después.
- En T5 `mosi` usa el valor anterior de `bit_cnt`.
## 5. Tiempos (de `ondas_spi.vcd`)
 
| Evento | Ciclos desde la aceptación de `start` | Tiempo |
|---|---|---|
| `cs_n` baja, `mosi` = bit 15 | 0 | 0 |
| 1.ª subida de SCLK | 14 | 518 ns |
| 1.ª bajada de SCLK | 28 | 1,04 µs |
| Subida del bit 7 (empieza a guardarse `rx_data`) | 238 | 8,8 µs |
| `cs_n` sube, `done` = 1 durante 1 ciclo | 448 | 16,6 µs |
 
SCLK = 27 MHz / 28 ≈ 964 kHz.
 
```mermaid
gantt
    title Transacción SPI de 16 bits (ciclos de clk desde start)
    dateFormat  X
    axisFormat  %s
    section cs_n en bajo
    cs_n = 0 (448 ciclos)        :0, 448
    section SCLK
    Medio período inicial (14)   :0, 14
    Bit 15 y bit 14 (ignorados)  :14, 56
    Bits 13 a 8 (ignorados)      :56, 224
    Bits 7 a 0 (se guardan)      :224, 448
    section done
    done = 1 (1 ciclo)           :crit, 448, 449
```
 
## 6. Periférico MMIO (`periferico_imu_mmio.v`)
 
El IMU corre solo; el procesador solo consulta el estado. Por eso **no hay START/BUSY/DONE** visibles.
 
| Señal | Dir. | Ancho | Descripción |
|---|---|---|---|
| `clk`, `resetn` | E | 1 | 27 MHz, activo en bajo |
| `cs` | E | 1 | Región del periférico |
| `addr` | E | 4 | `mem_addr[5:2]` |
| `rd` | E | 1 | Lectura |
| `rdata` | S | 32 | Dato leído |
| `miso` | E | 1 | Desde el BMI160 |
| `sclk`, `mosi`, `cs_n` | S | 1 | Hacia el BMI160 |
| `golpe_pin` | S | 1 | Salida directa de golpe |
| `leds[5:0]` | S | 6 | LEDs testigo |
 
Mapa de registros (región tentativa `0x0046`, sujeta al acuerdo con G5 y G6):
 
| Dirección | `addr` | Acceso | Contenido |
|---|---|---|---|
| `0x0046_0000` | `4'h0` | R | bit 0 = `golpe_detectado`; bits 31..1 = 0 |
| resto | otros | R | `32'd0` |
 
Decodificador: `cs = (mem_addr[31:16] == 16'h0046)`.
 
```mermaid
flowchart LR
  A["mem_addr[31:16]"] --> D{"== 0x0046 ?"}
  D -- "sí" --> CS["cs = 1"]
  B["mem_addr[5:2]"] --> AD["addr[3:0]"]
  R["mem_rstrb"] --> RD["rd"]
  CS --> P["periferico_imu_mmio"]
  AD --> P
  RD --> P
  P --> RDATA["rdata[31:0]<br/>bit 0 = golpe"]
  RDATA --> MUX["mux de lectura del SoC"]
```
 
Tiempos del handshake de lectura:
 
```mermaid
sequenceDiagram
  participant CPU as femtoRV32
  participant P as periferico_imu_mmio
  Note over CPU,P: Ciclo N
  CPU->>P: cs=1, rd=1, addr=0
  Note over CPU,P: Ciclo N+1
  P-->>CPU: rdata = {31'd0, golpe_detectado}
```
 
`golpe_out` dura 150 ms (4 050 000 ciclos), por lo que el sondeo no pierde el evento.
 
Alternativa pendiente de acuerdo con G1, G5 y G6: enviar el bit de golpe dentro de la trama del mando hacia `JOY*_DATA[17]`, sin región propia.
 
