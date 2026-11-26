// =============================================================================
// tb_soc.v — Testbench del SoC completo con soporte para Pantalla HUB75
//            + resumen de los accesos a la pantalla HUB75
// =============================================================================
`timescale 1ns / 1ns

module tb_soc;

  localparam integer CLK_FREQ   = 25_000_000;
  localparam integer BAUD       = CLK_FREQ / 32;            // UART rápida solo en simulación
  localparam integer BIT_CICLOS = 16 * (CLK_FREQ / BAUD / 16);  // ciclos de reloj por bit
  localparam integer DUMP_CICLOS = 20_000;                  // ciclos guardados en el VCD

  reg        clk = 0;
  reg        resetn = 0;
  reg  [3:0] botones = 0;
  wire       txd;
  wire [7:0] leds_ext;
  wire       led;

  // --- SEÑALES DE LA PANTALLA HUB75 PARA SIMULACIÓN ---
  wire r1, g1, b1;
  wire r2, g2, b2;
  wire addr_a, addr_b, addr_c, addr_d, addr_e;
  wire hub75_clk;
  wire hub75_lat;
  wire hub75_oe;

  SOC #(
      .CLK_FREQ(CLK_FREQ),
      .BAUD    (BAUD)
  ) uut (
      .clk     (clk),
      .resetn  (resetn),
      .LEDS    (led),
      .RXD     (1'b1),       // nadie le envía datos al SoC
      .TXD     (txd),
      .BOTONES (botones),
      .LEDS_EXT(leds_ext),
      // Conexión del puerto HUB75
      .r1      (r1),
      .g1      (g1),
      .b1      (b1),
      .r2      (r2),
      .g2      (g2),
      .b2      (b2),
      .addr_a  (addr_a),
      .addr_b  (addr_b),
      .addr_c  (addr_c),
      .addr_d  (addr_d),
      .addr_e  (addr_e),
      .hub75_clk(hub75_clk),
      .hub75_lat(hub75_lat),
      .hub75_oe(hub75_oe)
  );

  // Reloj de 25 MHz: periodo de 40 ns
  always #20 clk = ~clk;

  // ---------------------------------------------------- Control del tiempo ---
  integer ciclos_max;
  integer ciclo = 0;
  integer valor;
  always @(posedge clk) ciclo <= ciclo + 1;

  // ------------------------------------------------- Receptor UART del PC ---
  integer i;
  reg [7:0] caracter;
  integer caracteres = 0;
  integer ultimo = 0;     // ciclo en que llegó el último carácter
  always begin
    @(negedge txd);                         // bit de inicio
    repeat (BIT_CICLOS / 2) @(posedge clk); // ir a la mitad del bit
    for (i = 0; i < 8; i = i + 1) begin
      repeat (BIT_CICLOS) @(posedge clk);
      caracter[i] = txd;                    // primero llega el bit menos significativo
    end
    repeat (BIT_CICLOS) @(posedge clk);     // bit de parada
    $write("%c", caracter);
    $fflush;
    caracteres = caracteres + 1;
    ultimo = ciclo;
  end

  // ------------------------------------------- Accesos a la pantalla HUB75 ---
  // Cuenta las escrituras del CPU a la región 0x0044 (peripheral_hub75)
  integer esc_control = 0, esc_bright = 0, esc_fb = 0, lect_frame = 0;
  always @(posedge clk) begin
    if (uut.cs_chip4 && uut.wr) begin
      if (uut.mem_addr[15:14] == 2'b01) esc_fb = esc_fb + 1;
      else case (uut.mem_addr[15:0])
        16'h0000: begin
          esc_control = esc_control + 1;
          $display("HUB75: CONTROL <- %0d (ciclo %0d)", uut.mem_wdata, ciclo);
        end
        16'h0004: begin
          esc_bright = esc_bright + 1;
          $display("HUB75: BRIGHT <- %0d", uut.mem_wdata[9:0]);
        end
      endcase
    end
    if (uut.cs_chip4 && uut.rd && uut.mem_addr[15:0] == 16'h0010) lect_frame = lect_frame + 1;
  end

  // Resumen y copia de la imagen en build/pantalla.txt (un valor {R,G,B} por píxel)
  integer x, y, archivo;
  task revisar_pantalla;
    begin
      $display("\n--- Pantalla HUB75 ---");
      $display("Escrituras: CONTROL=%0d BRIGHT=%0d framebuffer=%0d; lecturas de FRAME=%0d",
               esc_control, esc_bright, esc_fb, lect_frame);
      $display("CONTROL.EN=%0d  BRIGHT=%0d  FRAME=%0d",
               uut.u_hub75.u_regs.enable, uut.u_hub75.u_regs.brightness,
               uut.u_hub75.frame_count);
      archivo = $fopen("build/pantalla.txt", "w");
      for (y = 0; y < 64; y = y + 1)
        for (x = 0; x < 64; x = x + 1)
          $fwrite(archivo, "%0d\n", (y < 32) ? uut.u_hub75.u_core.u_fb.mem_top[y * 64 + x]
                                              : uut.u_hub75.u_core.u_fb.mem_bot[(y - 32) * 64 + x]);
      $fclose(archivo);
      $display("Imagen guardada en build/pantalla.txt");
    end
  endtask

  initial begin
    if (!$value$plusargs("ciclos=%d", ciclos_max)) begin
      if (!$value$plusargs("+ciclos=%d", ciclos_max)) ciclos_max = 2_000_000;
    end

    // Intenta leer con o sin el signo más (+)
    if ($value$plusargs("botones=%d", valor) || $value$plusargs("+botones=%d", valor)) begin
      botones = valor;
      $display("INFO_TESTBENCH: Botones configurados exitosamente a = %0d", valor);
    end else begin
      $display("INFO_TESTBENCH: Advertencia, no se detectó argumento de botones, usando valor por defecto 0");
    end

    if ($test$plusargs("vcd")) begin
      $dumpfile("build/tb_soc.vcd");
      $dumpvars(0, tb_soc);
    end

    $display("=== Simulacion del SoC con Pantalla HUB75 ===");
    repeat (10) @(posedge clk);
    resetn = 1;                             // soltar el reset: el CPU arranca en 0x0

    if ($test$plusargs("vcd")) begin
      repeat (DUMP_CICLOS) @(posedge clk);
      $dumpoff;
    end

    wait (ciclo >= ciclos_max || (caracteres > 0 && ciclo - ultimo > 100_000));
    $display("\n=== Fin: %0d ciclos simulados, %0d caracteres recibidos, LEDS_EXT = %b ===",
             ciclo, caracteres, leds_ext);
    revisar_pantalla;
    $finish;
  end

endmodule
