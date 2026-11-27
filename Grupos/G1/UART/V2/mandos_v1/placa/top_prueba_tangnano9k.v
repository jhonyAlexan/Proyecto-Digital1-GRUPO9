// -----------------------------------------------------------------------------
// top_prueba_tangnano9k.v - Prueba del enlace de mandos SIN procesador (G1 v1)
//
// ESP32 consola (GPIO17) --> pin 33 --> g1_mandos_mmio --> LEDs
//
// LEDs (activos en bajo en la placa; aqui se invierten una vez):
//   led[0] J1 recibido hace < 100 ms      led[3] J1 ataque
//   led[1] J2 recibido hace < 100 ms      led[4] J1 X o Y fuera del centro (|v| > 40)
//   led[2] J1 boton                       led[5] algun error (UART o checksum)
// Reset: boton S1 (pin 4, activo en bajo) + reset al encender.
// -----------------------------------------------------------------------------
module top_prueba_tangnano9k (
    input  wire       clk,            // 27 MHz, pin 52
    input  wire       btn_rst_n,      // pin 4
    input  wire       uart_rx_mando,  // pin 33
    output wire [5:0] led
);
    // Reset al encender + boton, liberado de forma sincrona
    reg [15:0] por = 16'd0;
    always @(posedge clk) if (!(&por)) por <= por + 1'b1;
    reg [1:0] rs = 2'b11;
    always @(posedge clk) rs <= {rs[0], ~(btn_rst_n & (&por))};
    wire rst = rs[1];

    wire [31:0] joy1, joy2;
    wire [3:0]  st;
    wire [31:0] d_out;
    wire        ack, trama_ok;

    g1_mandos_mmio u_mandos (
        .clk(clk), .rst(rst),
        .cs(1'b0), .rd(1'b0), .wr(1'b0), .addr(4'd0), .d_in(32'd0),
        .d_out(d_out), .ack(ack),
        .uart_rx(uart_rx_mando),
        .joy1_data(joy1), .joy2_data(joy2), .status(st), .trama_ok(trama_ok));

    // Detecta trama nueva por cambio de secuencia
    reg [7:0]  sec1, sec2;
    reg [21:0] t1, t2;                       // 100 ms = 2_700_000 ciclos
    always @(posedge clk) begin
        if (rst) begin
            sec1 <= 8'd0; sec2 <= 8'd0; t1 <= 0; t2 <= 0;
        end else begin
            sec1 <= joy1[31:24];
            sec2 <= joy2[31:24];
            if (sec1 != joy1[31:24]) t1 <= 22'd2_700_000; else if (t1 != 0) t1 <= t1 - 1'b1;
            if (sec2 != joy2[31:24]) t2 <= 22'd2_700_000; else if (t2 != 0) t2 <= t2 - 1'b1;
        end
    end

    wire signed [7:0] x1 = joy1[7:0];
    wire signed [7:0] y1 = joy1[15:8];
    wire mueve = (x1 > 40) || (x1 < -40) || (y1 > 40) || (y1 < -40);

    assign led = ~{ (st[2] | st[3]), mueve, joy1[17], joy1[16], (t2 != 0), (t1 != 0) };
endmodule
