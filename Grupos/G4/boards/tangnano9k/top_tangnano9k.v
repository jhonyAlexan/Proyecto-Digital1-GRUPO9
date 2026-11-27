// =============================================================================
// top_tangnano9k.v

// =============================================================================
module top_tangnano9k (
    input        clk,       // 27 MHz
    input        btn_s1,    // reset (presionado = 0)
    input        btn_s2,    // pulsador de usuario (presionado = 0)
    output [5:0] led,       // LEDs de la tarjeta (0 = encendido)
    input        uart_rx,
    output       uart_tx,

    // Panel HUB75
    output       r1, g1, b1,
    output       r2, g2, b2,
    output       addr_a, addr_b, addr_c, addr_d, addr_e,
    output       hub75_clk,
    output       hub75_lat,
    output       hub75_oe
);

  wire [7:0] leds_soc;
  wire       led_uart;  // LED controlado por la UART: no se usa en esta tarjeta

  SOC #(
      .CLK_FREQ(27_000_000),  // ¡Si se deja en 50 MHz, la UART envía basura!
      .BAUD    (115200)
  ) soc (
      .clk      (clk),
      .resetn   (btn_s1),
      .LEDS     (led_uart),
      .RXD      (uart_rx),
      .TXD      (uart_tx),
      .BOTONES  ({3'b000, ~btn_s2}),
      .LEDS_EXT (leds_soc),
      .r1       (r1),
      .g1       (g1),
      .b1       (b1),
      .r2       (r2),
      .g2       (g2),
      .b2       (b2),
      .addr_a   (addr_a),
      .addr_b   (addr_b),
      .addr_c   (addr_c),
      .addr_d   (addr_d),
      .addr_e   (addr_e),
      .hub75_clk(hub75_clk),
      .hub75_lat(hub75_lat),
      .hub75_oe (hub75_oe)
  );

  assign led = ~leds_soc[5:0];

endmodule
