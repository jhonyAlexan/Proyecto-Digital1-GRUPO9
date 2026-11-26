// =============================================================================
// SOC.v — Sistema en chip (SoC) con el procesador FemtoRV32 Quark (RV32I)
//          e integración del Periférico de Pantalla HUB75 (64x64) con Doble Puerto
//
// MAPA DE MEMORIA (los 16 bits altos de la dirección eligen el bloque):
//   0x0040_xxxx  chip0  UART
//   0x0041_xxxx  chip1  LIBRE
//   0x0042_xxxx  chip2  Multiplicador
//   0x0043_xxxx  chip3  LIBRE
//   0x0044_xxxx  chip4  PANTALLA HUB75 (peripheral_hub75)
//   0x0045_xxxx  chip5  LIBRE
//   cualquier otra      RAM (en la práctica, 0x0000_0000 a 0x0000_7FFF)
// =============================================================================
module SOC #(
    parameter CLK_FREQ = 27_000_000,  // Frecuencia del reloj en Hz (Tang Primer 25K)
    parameter BAUD     = 115200       // Velocidad de la UART en baudios
) (
    input        clk,       // Reloj del sistema (27 MHz)
    input        resetn,    // Reset activo en bajo (0 = reiniciar)
    output [0:0] LEDS,      // LED de estado en placa
    input        RXD,       // UART: recepción
    output       TXD,       // UART: transmisión
    input  [3:0] BOTONES,   // Pulsadores externos
    output [7:0] LEDS_EXT,  // LEDs externos

    // --- SEÑALES PARA LA PANTALLA HUB75 (64x64) ---
    output       r1, g1, b1,
    output       r2, g2, b2,
    output       addr_a, addr_b, addr_c, addr_d, addr_e,
    output       hub75_clk,
    output       hub75_lat,
    output       hub75_oe
);

  // ===========================================================================
  // 1. PROCESADOR
  // ===========================================================================
  wire [31:0] mem_addr;
  wire [31:0] mem_rdata;
  wire        mem_rstrb;
  wire [31:0] mem_wdata;
  wire [ 3:0] mem_wmask;

  FemtoRV32 CPU (
      .clk      (clk),
      .reset    (resetn),     // el FemtoRV Quark usa reset activo en bajo
      .mem_addr (mem_addr),
      .mem_rdata(mem_rdata),
      .mem_rstrb(mem_rstrb),
      .mem_wdata(mem_wdata),
      .mem_wmask(mem_wmask),
      .mem_rbusy(1'b0),
      .mem_wbusy(1'b0)
  );

  // Señales de lectura y escritura comunes
  wire wr = |mem_wmask;  // 1 si el procesador está escribiendo
  wire rd = mem_rstrb;   // 1 si el procesador está leyendo

  // ===========================================================================
  // 2. DECODIFICADOR DE DIRECCIONES (chip select)
  // ===========================================================================
  wire [6:0] cs;
  wire cs_uart    = cs[0];  // 0x0040_xxxx
  wire cs_chip1   = cs[1];  // 0x0041_xxxx  (libre)
  wire cs_mult    = cs[2];  // 0x0042_xxxx
  wire cs_chip3   = cs[3];  // 0x0043_xxxx  (libre)
  wire cs_chip4   = cs[4];  // 0x0044_xxxx  <-- pantalla HUB75
  wire cs_chip5   = cs[5];  // 0x0045_xxxx  (libre)
  wire cs_ram     = cs[6];  // cualquier otra dirección

  wire [31:0] uart_dout;
  wire [31:0] hub75_dout;
  wire [31:0] mult_dout;
  wire [31:0] RAM_rdata;

  chip_select chip_select (
      .mem_addr  (mem_addr),
      .chip0_dout(uart_dout),  // 0x0040_xxxx
      .chip1_dout(32'b0),      // 0x0041_xxxx  libre
      .chip2_dout(mult_dout),  // 0x0042_xxxx
      .chip3_dout(32'b0),      // 0x0043_xxxx
      .chip4_dout(hub75_dout), // 0x0044_xxxx  pantalla HUB75
      .chip5_dout(32'b0),      // 0x0045_xxxx
      .chip6_dout(RAM_rdata),  // RAM
      .cs        (cs),
      .mem_rdata (mem_rdata)
  );

  // ===========================================================================
  // 3. MEMORIA RAM (programa + datos + pila)
  // ===========================================================================
  Memory RAM (
      .clk      (clk),
      .mem_addr (mem_addr),
      .mem_rdata(RAM_rdata),
      .mem_rstrb(cs_ram & rd),
      .mem_wdata(mem_wdata),
      .mem_wmask({4{cs_ram}} & mem_wmask)
  );

  // ===========================================================================
  // 4. PERIFÉRICO UART  (base 0x0040_0000)
  // ===========================================================================
  peripheral_uart #(
      .clk_freq(CLK_FREQ),
      .baud    (BAUD)
  ) per_uart (
      .clk    (clk),
      .rst    (!resetn),
      .d_in   (mem_wdata),
      .cs     (cs_uart),
      .addr   (mem_addr),
      .rd     (rd),
      .wr     (wr),
      .d_out  (uart_dout),
      .uart_tx(TXD),
      .uart_rx(RXD),
      .ledout (LEDS[0])
  );

  // ===========================================================================
  // 5. PERIFÉRICO MULTIPLICADOR  (base 0x0042_0000)
  // ===========================================================================
  peripheral_mult mult1 (
      .clk  (clk),
      .reset(!resetn),
      .d_in (mem_wdata),
      .cs   (cs_mult),
      .addr (mem_addr),
      .rd   (rd),
      .wr   (wr),
      .d_out(mult_dout)
  );

  // ===========================================================================
  // 6. PERIFÉRICO PANTALLA HUB75 64x64  (región 0x0044, chip 4)
  // ===========================================================================
  wire [2:0] hub75_rgb0, hub75_rgb1;
  wire [4:0] hub75_row;

  peripheral_hub75 #(
      .CLK_DIV      (2),          // tick cada 2 ciclos de clk
      .DISPLAY_TICKS(1024)
  ) u_hub75 (
      .clk       (clk),
      .rst       (!resetn),
      .cs        (cs_chip4),
      .rd        (rd),
      .addr      (mem_addr),
      .d_in      (mem_wdata),
      .wmask     (mem_wmask),
      .d_out     (hub75_dout),
      .hub75_rgb0(hub75_rgb0),
      .hub75_rgb1(hub75_rgb1),
      .hub75_row (hub75_row),
      .hub75_clk (hub75_clk),
      .hub75_lat (hub75_lat),
      .hub75_oe  (hub75_oe)
  );

  assign {r1, g1, b1} = hub75_rgb0;
  assign {r2, g2, b2} = hub75_rgb1;
  assign {addr_e, addr_d, addr_c, addr_b, addr_a} = hub75_row;

  assign LEDS_EXT = 8'b0;

endmodule