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
