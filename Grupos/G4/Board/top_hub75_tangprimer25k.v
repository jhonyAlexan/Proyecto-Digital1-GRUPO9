// =============================================================================
// top_hub75_tangprimer25k.v — Prueba del core en la Tang Primer 25K, SIN CPU
//
// Al soltar el reset escribe una imagen de prueba en el framebuffer (borde
// blanco, diagonal roja y cuadros de los colores) por el mismo puerto que usa
// el adaptador MMIO, y después pone EN = 1 con BRIGHT = 512.
//
// Reloj de la placa: 50 MHz (pin E2). Con CLK_DIV = 2: tick de 40 ns, CLK del
// panel de 12,5 MHz y refresco de ~678 Hz.
// Pines: board/tangprimer25k_hub75.cst
//
// Uso de IA: elaborado con ayuda de un asistente de IA (Claude) a partir de los
// diagramas y la tabla de transferencias del README de G4; revisado y probado por el grupo.
// =============================================================================
module top_hub75_tangprimer25k (
    input  wire clk,          // 50 MHz
    input  wire resetn,       // botón, activo en bajo

    output wire r1, g1, b1,
    output wire r2, g2, b2,
    output wire addr_a, addr_b, addr_c, addr_d, addr_e,
    output wire hub75_clk,
    output wire hub75_lat,
    output wire hub75_oe
);

    // Reset síncrono activo en alto (contrato del curso)
    reg [1:0] rst_sinc = 2'b11;
    always @(posedge clk) rst_sinc <= {rst_sinc[0], ~resetn};
    wire rst = rst_sinc[1];

    // ------------------------------------------------ Escritor de la imagen
    reg  [12:0] p = 0;                      // 0..4095; el bit 12 = terminado
    wire [5:0]  x = p[5:0];
    wire [5:0]  y = p[11:6];
    wire        listo = p[12];

    wire borde = (x == 0) || (x == 63) || (y == 0) || (y == 63);
    wire [2:0] color = borde         ? 3'b111 :                          // borde
                       (x == y)      ? 3'b100 :                          // diagonal
                       (x[3] ^ y[3]) ? ({1'b0, x[5:4]} + {y[5:4], 1'b0} + 3'd1)
                                     : 3'b000;

    always @(posedge clk) begin
        if (rst)         p <= 0;
        else if (!listo) p <= p + 1'b1;
    end

    // ------------------------------------------------------------- Core
    wire [2:0] rgb0, rgb1;
    wire [4:0] row;

    hub75_core #(.CLK_DIV(2), .DISPLAY_TICKS(1024)) u_core (
        .clk(clk), .rst(rst),
        .enable(listo), .brightness(10'd512),
        .fb_we(!listo && !rst), .fb_waddr(p[11:0]), .fb_wdata(color),
        .busy(), .frame_count(),
        .hub75_rgb0(rgb0), .hub75_rgb1(rgb1), .hub75_row(row),
        .hub75_clk(hub75_clk), .hub75_lat(hub75_lat), .hub75_oe(hub75_oe)
    );

    assign {r1, g1, b1} = rgb0;
    assign {r2, g2, b2} = rgb1;
    assign {addr_e, addr_d, addr_c, addr_b, addr_a} = row;

endmodule
