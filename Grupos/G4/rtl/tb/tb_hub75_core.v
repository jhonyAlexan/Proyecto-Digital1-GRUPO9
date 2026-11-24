// =============================================================================
// tb_hub75_core.v — Banco del core derivado de la tabla de transferencias
//
// Cada comprobación corresponde a una fila de la tabla (sección 7) y a los
// criterios de la sección 11.1:
//
//   R      Tras reset: OE = 1, LAT = 0, CLK = 1. Al bajar EN el core vuelve a
//          IDLE con OE = 1 y FRAME deja de contar.
//   T1-T4  Configuración: exactamente un registro 1 (11 pulsos con LAT) y un
//          registro 2 (12 pulsos), cada uno tras 64 pulsos, con el patrón
//          correcto en las 64 posiciones.
//   T2-T4  Barrido: 64 pulsos de CLK antes de cada latch; nunca sube CLK con
//          OE activo.
//   T5     ROW solo cambia con OE = 1; el latch de datos ocurre con 0 pulsos de
//          CLK durante LAT = 1.
//   T6     Con BRIGHT = 5, OE activo 5 ticks; con BRIGHT = 1000 y DT = 16,
//          15 ticks.
//   T7     Periodo de fila = (128 + 1 + DT) ticks = 290 ciclos (DT = 16).
//          FRAME cambia solo después de la fila 31.
//   Imagen Los 4096 píxeles reconstruidos por el panel virtual coinciden con
//          los escritos.
//
// DT = 16 para que la simulación sea corta. clk de 50 MHz (20 ns).
// Ejecutar desde Grupos/G4:  make sim-core   (formas de onda: make wave-core)
//
// Uso de IA: elaborado con ayuda de un asistente de IA a partir de los
// diagramas y la tabla de transferencias del README de G4; revisado y probado por el grupo.
// =============================================================================
`timescale 1ns / 1ns

module tb_hub75_core;

  localparam integer DT      = 16;
  localparam integer CLK_DIV = 2;
  localparam integer T_CLK   = 20;
  localparam integer T_FILA  = (128 + 1 + DT) * CLK_DIV;   // en ciclos: 290

  reg clk = 0;
  reg rst = 1;
  always #(T_CLK / 2) clk = ~clk;

  reg         enable = 0;
  reg  [ 9:0] brightness = 5;
  reg         fb_we = 0;
  reg  [11:0] fb_waddr = 0;
  reg  [ 2:0] fb_wdata = 0;
  wire        busy;
  wire [31:0] frame_count;
  wire [ 2:0] rgb0, rgb1;
  wire [ 4:0] row;
  wire        hclk, lat, oe;

  hub75_core #(.CLK_DIV(CLK_DIV), .DISPLAY_TICKS(DT)) dut (
      .clk(clk), .rst(rst), .enable(enable), .brightness(brightness),
      .fb_we(fb_we), .fb_waddr(fb_waddr), .fb_wdata(fb_wdata),
      .busy(busy), .frame_count(frame_count),
      .hub75_rgb0(rgb0), .hub75_rgb1(rgb1), .hub75_row(row),
      .hub75_clk(hclk), .hub75_lat(lat), .hub75_oe(oe));

  // Imagen de prueba: borde blanco, diagonal roja y cuadros de colores
  function [2:0] color(input integer x, input integer y);
    if (x == 0 || x == 63 || y == 0 || y == 63) color = 3'b111;
    else if (x == y)                             color = 3'b100;
    else if (((x >> 3) ^ (y >> 3)) & 1)          color = ((x >> 4) + 2 * (y >> 4)) % 7 + 1;
    else                                         color = 3'b000;
  endfunction

  // ------------------------------------------------------------- Errores
  integer errores = 0;
  task error(input [8*64-1:0] criterio);
    begin
      errores = errores + 1;
      if (errores <= 20) $display("  ERROR t=%0t ns: %0s", $time, criterio);
    end
  endtask

  // ------------------------------------------------- Panel virtual
  // Guarda los 6 bits en cada subida de CLK y copia la fila en cada LAT.
  reg [5:0] sr [0:63];               // registro de desplazamiento del panel
  reg [2:0] img [0:63][0:63];        // imagen reconstruida [y][x]
  integer   pulsos = 0;              // pulsos de CLK desde el último LAT
  integer   pulsos_lat = 0;          // pulsos de CLK con LAT = 1
  integer   cfg_reg1 = 0, cfg_reg2 = 0, latches_datos = 0;
  reg       en_lat = 0;
  reg       patron_ok = 1;
  integer   k, x, y;
  integer   filas_medidas = 0;

  // Palabras esperadas del driver
  localparam [15:0] P1 = 16'hFFFE, P2 = 16'h0200;

  always @(posedge hclk) if (!rst) begin
    // T2-T4: nunca sube CLK con el panel encendido
    if (oe === 1'b0) error("T2-T4: CLK sube con OE activo");
    for (k = 63; k > 0; k = k - 1) sr[k] = sr[k-1];
    sr[0] = {rgb0, rgb1};
    pulsos = pulsos + 1;
    if (lat) pulsos_lat = pulsos_lat + 1;
  end

  always @(posedge lat) if (!rst) begin
    en_lat     = 1;
    pulsos_lat = 0;
  end

  // Al bajar LAT se sabe cuántos pulsos vio el driver con LAT = 1
  always @(negedge lat) if (!rst && en_lat) begin
    en_lat = 0;
    if (pulsos_lat == 0) begin
      // ------------------------------------------------ latch de datos (T5)
      if (pulsos != 64) begin
        error("T2-T4: no hubo 64 pulsos antes del latch");
        $display("          pulsos = %0d", pulsos);
      end
      // sr[63] es la columna 0 (la primera que entró)
      for (k = 0; k < 64; k = k + 1) begin
        img[row][k]      = sr[63 - k][5:3];
        img[row + 32][k] = sr[63 - k][2:0];
      end
      latches_datos = latches_datos + 1;
      if (t_dato_ant != 0) begin
        if ((t_subida - t_dato_ant) == T_FILA * T_CLK) filas_medidas = filas_medidas + 1;
        else begin
          error("T7: periodo de fila distinto de (128 + 1 + DT) ticks");
          $display("          periodo = %0d ciclos", (t_subida - t_dato_ant) / T_CLK);
        end
      end
      t_dato_ant = t_subida;
    end else begin
      t_dato_ant = 0;
      // ---------------------------------------- palabra de configuración (T1-T4)
      if (pulsos != 64) error("T1-T4: la palabra de configuracion no tiene 64 pulsos");
      for (k = 0; k < 64; k = k + 1)
        if (sr[63 - k] !== {6{(pulsos_lat == 11) ? P1[k % 16] : P2[k % 16]}}) patron_ok = 0;
      if (pulsos_lat == 11)      cfg_reg1 = cfg_reg1 + 1;
      else if (pulsos_lat == 12) cfg_reg2 = cfg_reg2 + 1;
      else begin
        error("T1-T4: numero de pulsos con LAT distinto de 11 y de 12");
        $display("          pulsos con LAT = %0d", pulsos_lat);
      end
    end
    pulsos = 0;
  end

  // T5: ROW solo cambia con el panel apagado
  always @(row) if (!rst && $time > 0 && oe === 1'b0) error("T5: ROW cambia con OE activo");

  // T7: periodo de fila, medido entre subidas de LAT de dos latches de datos
  // seguidos (se reinicia tras la configuración o al deshabilitar)
  time t_subida = 0, t_dato_ant = 0;
  always @(posedge lat) if (!rst) t_subida = $time;

  // T6: duración de OE activo
  time    t_oe = 0;
  integer oe_ticks_esperados = 5;
  always @(negedge oe) if (!rst) t_oe = $time;
  always @(posedge oe) if (!rst && t_oe != 0) begin
    if (($time - t_oe) != oe_ticks_esperados * CLK_DIV * T_CLK) begin
      error("T6: OE activo un numero de ticks incorrecto");
      $display("          OE activo = %0d ticks (esperado %0d)",
               ($time - t_oe) / (CLK_DIV * T_CLK), oe_ticks_esperados);
    end
  end

  // FRAME solo cambia después de la fila 31
  always @(frame_count) if (!rst && $time > 0 && dut.u_dp.r !== 5'd0)
    error("T7: FRAME cambio sin terminar la fila 31");

  // ------------------------------------------------------------ Secuencia
  integer f0;
  initial begin
    if ($test$plusargs("vcd")) begin
      $dumpfile("build/tb_hub75_core.vcd");
      $dumpvars(0, tb_hub75_core);
    end

    $display("=== tb_hub75_core: criterios de la tabla de transferencias ===");
    repeat (4) @(posedge clk);
    @(negedge clk) rst = 0;

    // R: valores tras el reset
    @(negedge clk);
    if (oe !== 1'b1 || lat !== 1'b0 || hclk !== 1'b1 || busy !== 1'b0)
      error("R: valores despues del reset");
    else $display("R      OE=1, LAT=0, CLK=1 tras el reset            ok");

    // Cargar la imagen (puerto de escritura del framebuffer)
    for (y = 0; y < 64; y = y + 1)
      for (x = 0; x < 64; x = x + 1) begin
        @(negedge clk);
        fb_we = 1; fb_waddr = {y[5:0], x[5:0]}; fb_wdata = color(x, y);
      end
    @(negedge clk) fb_we = 0;
    if (pulsos != 0) error("H1: hubo pulsos de CLK sin EN");

    // T1-T7 con BRIGHT = 5: configuración + un cuadro completo
    brightness = 5; oe_ticks_esperados = 5;
    @(negedge clk) enable = 1;
    f0 = frame_count;
    wait (frame_count == f0 + 1);
    @(negedge clk);
    if (cfg_reg1 == 1 && cfg_reg2 == 1 && patron_ok)
      $display("T1-T4  un registro 1 (11 pulsos) y un registro 2 (12), patron correcto  ok");
    else begin
      error("T1-T4: configuracion incorrecta");
      $display("          reg1=%0d reg2=%0d patron_ok=%0d", cfg_reg1, cfg_reg2, patron_ok);
    end
    $display("T2-T5  %0d latches de datos con 64 pulsos y 0 pulsos durante LAT", latches_datos);
    $display("T6     BRIGHT = 5: OE activo 5 ticks");
    $display("T7     periodo de fila = %0d ciclos en %0d filas medidas", T_FILA, filas_medidas);

    // Imagen reconstruida
    begin : revisar_imagen
      integer malos;
      malos = 0;
      for (y = 0; y < 64; y = y + 1)
        for (x = 0; x < 64; x = x + 1)
          if (img[y][x] !== color(x, y)) malos = malos + 1;
      if (malos == 0) $display("Imagen 4096 pixeles reconstruidos iguales a los escritos  ok");
      else begin
        error("Imagen: pixeles distintos");
        $display("          %0d pixeles distintos", malos);
      end
    end

    // T6 con BRIGHT = 1000 y DT = 16: el último tick siempre apaga -> 15 ticks
    @(posedge lat);                          // cambiar entre filas
    brightness = 1000; oe_ticks_esperados = DT - 1;
    wait (frame_count == f0 + 2);
    $display("T6     BRIGHT = 1000, DT = 16: OE activo %0d ticks", DT - 1);

    // R: bajar EN -> termina la fila, vuelve a IDLE con OE = 1, FRAME se detiene
    @(negedge clk) enable = 0;
    t_dato_ant = 0;
    repeat (3 * T_FILA) @(posedge clk);
    f0 = frame_count;
    if (busy !== 1'b0 || oe !== 1'b1) error("R: con EN = 0 no volvio a IDLE con OE = 1");
    repeat (40 * T_FILA) @(posedge clk);
    if (frame_count !== f0) error("R: FRAME sigue contando con EN = 0");
    else $display("R      EN = 0: vuelve a IDLE, OE = 1 y FRAME se detiene  ok");

    $display("--------------------------------------------------------------");
    if (errores == 0) $display("PASS tb_hub75_core");
    else              $display("FAIL tb_hub75_core: %0d errores", errores);
    $finish;
  end

endmodule
