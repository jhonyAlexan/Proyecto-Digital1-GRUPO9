// =============================================================================
// tb_peripheral_hub75.v — Banco de los registros MMIO (sección 11.2)
//
// Maneja el periférico solo por el bus, imitando a FemtoRV32 Quark:
//   escritura: cs y wmask activos durante un ciclo
//   lectura:   ciclo 1 con cs y rd (EXECUTE), ciclo 2 con cs y rd = 0 (WAIT):
//              el dato se toma en el ciclo 2, cuando rd ya bajó
//
// Comprobaciones:
//   1. Reset: CONTROL = 0, BRIGHT = 512, STATUS = 0, FRAME = 0
//   2. CONTROL y BRIGHT se escriben y se leen; BRIGHT guarda solo 10 bits
//   3. Una escritura con wmask = 0000 no cambia nada
//   4. El offset reservado 0x000C, la ventana del framebuffer y un offset
//      inválido se leen como 0
//   5. d_out se conserva después de la lectura (rd = 0, cs = 0)
//   6. El píxel (10, 40) va en 0x0044_6828 y cae en la mitad inferior
//   7. Imagen completa por la ventana; el panel virtual la reconstruye
//   8. STATUS.BUSY = 1 con EN = 1; FRAME avanza; con EN = 0 vuelve a 0
//
// Ejecutar desde Grupos/G4:  make sim-regs   (handshake en GTKWave: make wave-regs)
//
// Uso de IA: elaborado con ayuda de un asistente de IA (Claude) a partir de los
// diagramas y la tabla de transferencias del README de G4; revisado y probado por el grupo.
// =============================================================================
`timescale 1ns / 1ns

module tb_peripheral_hub75;

  localparam integer DT      = 16;
  localparam integer CLK_DIV = 2;
  localparam integer T_FILA  = (128 + 1 + DT) * CLK_DIV;   // ciclos

  // Direcciones absolutas (región 0x0044)
  localparam [31:0] BASE      = 32'h0044_0000;
  localparam [31:0] A_CONTROL = BASE + 32'h0000;
  localparam [31:0] A_BRIGHT  = BASE + 32'h0004;
  localparam [31:0] A_STATUS  = BASE + 32'h0008;
  localparam [31:0] A_RESERV  = BASE + 32'h000C;
  localparam [31:0] A_FRAME   = BASE + 32'h0010;
  localparam [31:0] A_FB      = BASE + 32'h4000;

  reg clk = 0;
  reg rst = 1;
  always #10 clk = ~clk;                      // 50 MHz

  // ------------------------------------------------------------- Bus
  reg         cs = 0, rd = 0;
  reg  [31:0] addr = 0, d_in = 0;
  reg  [ 3:0] wmask = 0;
  wire [31:0] d_out;
  wire [ 2:0] rgb0, rgb1;
  wire [ 4:0] row;
  wire        hclk, lat, oe;

  peripheral_hub75 #(.CLK_DIV(CLK_DIV), .DISPLAY_TICKS(DT)) dut (
      .clk(clk), .rst(rst),
      .cs(cs), .rd(rd), .addr(addr), .d_in(d_in), .wmask(wmask), .d_out(d_out),
      .hub75_rgb0(rgb0), .hub75_rgb1(rgb1), .hub75_row(row),
      .hub75_clk(hclk), .hub75_lat(lat), .hub75_oe(oe));

  // chip_select del curso: cs = (mem_addr[31:16] == 0x0044)
  task escribir(input [31:0] a, input [31:0] d, input [3:0] m);
    begin
      @(negedge clk); addr = a; d_in = d; wmask = m; cs = (a[31:16] == 16'h0044);
      @(negedge clk); cs = 0; wmask = 0;
    end
  endtask

  task leer(input [31:0] a, output [31:0] d);
    begin
      @(negedge clk); addr = a; cs = (a[31:16] == 16'h0044); rd = 1;   // EXECUTE
      @(negedge clk); rd = 0;                                          // WAIT
      d = d_out;                                                       // aquí lo toma Quark
      @(negedge clk); cs = 0;
    end
  endtask

  integer errores = 0;
  task revisar(input [8*40-1:0] nombre, input [31:0] obtenido, input [31:0] esperado);
    begin
      if (obtenido !== esperado) begin
        errores = errores + 1;
        $display("  ERROR %0s = 0x%08h (esperado 0x%08h)", nombre, obtenido, esperado);
      end else
        $display("  %0s = %0d  ok", nombre, obtenido);
    end
  endtask

  // Imagen de prueba
  function [2:0] color(input integer x, input integer y);
    if (x == 0 || x == 63 || y == 0 || y == 63) color = 3'b111;
    else if (x == y)                             color = 3'b100;
    else if (((x >> 3) ^ (y >> 3)) & 1)          color = ((x >> 4) + 2 * (y >> 4)) % 7 + 1;
    else                                         color = 3'b000;
  endfunction

  // ------------------------------------------------- Panel virtual
  reg [5:0] sr [0:63];
  reg [2:0] img [0:63][0:63];
  integer   pulsos = 0, pulsos_lat = 0, k, x, y;
  always @(posedge hclk) if (!rst) begin
    for (k = 63; k > 0; k = k - 1) sr[k] = sr[k-1];
    sr[0] = {rgb0, rgb1};
    pulsos = pulsos + 1;
    if (lat) pulsos_lat = pulsos_lat + 1;
  end
  always @(posedge lat) if (!rst) pulsos_lat = 0;
  always @(negedge lat) if (!rst) begin
    if (pulsos_lat == 0 && pulsos == 64)
      for (k = 0; k < 64; k = k + 1) begin
        img[row][k]      = sr[63 - k][5:3];
        img[row + 32][k] = sr[63 - k][2:0];
      end
    pulsos = 0;
  end

  // ------------------------------------------------------------ Secuencia
  reg [31:0] v, f0, f1;
  integer    malos;

  initial begin
    if ($test$plusargs("vcd")) begin
      $dumpfile("build/tb_peripheral_hub75.vcd");
      $dumpvars(0, tb_peripheral_hub75);
    end
    $display("=== tb_peripheral_hub75: registros MMIO por el bus ===");
    repeat (4) @(posedge clk);
    @(negedge clk) rst = 0;

    $display("1. Valores despues del reset");
    leer(A_CONTROL, v); revisar("CONTROL", v, 0);
    leer(A_BRIGHT,  v); revisar("BRIGHT", v, 512);
    leer(A_STATUS,  v); revisar("STATUS", v, 0);
    leer(A_FRAME,   v); revisar("FRAME", v, 0);

    $display("2. Escritura y lectura");
    escribir(A_BRIGHT, 300, 4'b1111);               leer(A_BRIGHT, v); revisar("BRIGHT", v, 300);
    escribir(A_BRIGHT, 32'hFFFF_FC00 | 77, 4'b1111); leer(A_BRIGHT, v); revisar("BRIGHT (10 bits)", v, 77);

    $display("3. Escritura con wmask = 0000");
    escribir(A_BRIGHT, 999, 4'b0000);               leer(A_BRIGHT, v); revisar("BRIGHT sin cambio", v, 77);
    escribir(A_CONTROL, 1, 4'b0000);                leer(A_CONTROL, v); revisar("CONTROL sin cambio", v, 0);

    $display("4. Offsets que se leen como 0");
    leer(A_RESERV, v);            revisar("0x000C reservado", v, 0);
    leer(A_FB + 32'h0100, v);     revisar("ventana del framebuffer", v, 0);
    leer(BASE + 32'h0020, v);     revisar("offset 0x0020 invalido", v, 0);

    $display("5. d_out se conserva despues de la lectura");
    leer(A_BRIGHT, v);
    repeat (5) @(negedge clk);
    revisar("d_out 5 ciclos despues", d_out, 77);

    $display("6. Pixel (10, 40) en 0x0044_6828");
    escribir(32'h0044_6828, 3'b110, 4'b1111);
    @(negedge clk);
    revisar("mem_bot[8*64+10]", dut.u_core.u_fb.mem_bot[8 * 64 + 10], 3'b110);

    $display("7. Imagen completa por la ventana del framebuffer");
    for (y = 0; y < 64; y = y + 1)
      for (x = 0; x < 64; x = x + 1)
        escribir(A_FB + 4 * (64 * y + x), {29'd0, color(x, y)}, 4'b1111);
    escribir(A_BRIGHT, 8, 4'b1111);
    escribir(A_CONTROL, 1, 4'b1111);
    leer(A_STATUS, v); revisar("STATUS.BUSY con EN = 1", v, 1);
    leer(A_FRAME, f0);
    repeat (3 * 32 * T_FILA + 2000) @(posedge clk);
    leer(A_FRAME, f1);
    $display("  FRAME paso de %0d a %0d", f0, f1);
    if (f1 - f0 < 2) begin errores = errores + 1; $display("  ERROR FRAME no avanza"); end
    malos = 0;
    for (y = 0; y < 64; y = y + 1)
      for (x = 0; x < 64; x = x + 1)
        if (img[y][x] !== color(x, y)) malos = malos + 1;
    revisar("pixeles distintos en el panel", malos, 0);

    $display("8. Apagar");
    escribir(A_CONTROL, 0, 4'b1111);
    repeat (3 * T_FILA) @(posedge clk);
    leer(A_STATUS, v);  revisar("STATUS.BUSY con EN = 0", v, 0);
    revisar("OE (panel apagado)", oe, 1);

    $display("--------------------------------------------------------------");
    if (errores == 0) $display("PASS tb_peripheral_hub75");
    else              $display("FAIL tb_peripheral_hub75: %0d errores", errores);
    $finish;
  end

endmodule
