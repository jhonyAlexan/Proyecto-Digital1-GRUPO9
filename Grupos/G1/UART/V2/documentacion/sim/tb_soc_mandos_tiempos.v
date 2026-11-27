// =============================================================================
// tb_soc_mandos_tiempos.v (copia de tb_soc_mandos.v + VCD para B.6) — Prueba de integración: SoC completo + periférico de mandos
//
// El FemtoRV ejecuta sim/mandos_prueba.hex (8 instrucciones hechas a mano, no
// necesita el compilador RISC-V): lee JOY1_DATA, JOY2_DATA y STATUS en
// 0x0047_0000 y los copia en la RAM (0x400, 0x404, 0x408). El testbench manda
// tramas del G5 por RX_MANDOS a 115200 baudios y revisa lo que copió el CPU.
//
// Uso (desde projecto/consola): iverilog -g2012 -DBENCH -s tb_soc_mandos_tiempos ... ; ver V2/documentacion/sim/Makefile, objetivo soc
// =============================================================================
`timescale 1ns / 1ps

module tb_soc_mandos_tiempos;

  localparam integer CLK_FREQ = 27_000_000;           // Tang Nano 9K
  localparam integer BIT      = CLK_FREQ / 115_200;   // 234 ciclos por bit

  reg  clk = 0, resetn = 0, rx_mandos = 1;
  wire txd, led;
  wire [7:0] leds_ext;

  SOC #(.CLK_FREQ(CLK_FREQ), .BAUD(115200)) uut (
      .clk      (clk),
      .resetn   (resetn),
      .LEDS     (led),
      .RXD      (1'b1),
      .TXD      (txd),
      .RX_MANDOS(rx_mandos),
      .BOTONES  (4'b0),
      .LEDS_EXT (leds_ext)
  );

  always #18.518 clk = ~clk;

  integer fallos = 0, pruebas = 0;

  task check(input [255:0] nombre, input [31:0] obtenido, input [31:0] esperado);
    begin
      pruebas = pruebas + 1;
      if (obtenido !== esperado) begin
        $display("FALLO %0s: obtenido %h, esperado %h", nombre, obtenido, esperado);
        fallos = fallos + 1;
      end else $display("ok    %0s = %h", nombre, obtenido);
    end
  endtask

  task byte_tx(input [7:0] b);
    integer i;
    begin
      rx_mandos = 0;                repeat (BIT) @(posedge clk);
      for (i = 0; i < 8; i = i + 1) begin
        rx_mandos = b[i];           repeat (BIT) @(posedge clk);
      end
      rx_mandos = 1;                repeat (BIT) @(posedge clk);
    end
  endtask

  task trama(input [7:0] jug, seq, tx_, ty, sh, pu);
    begin
      byte_tx(8'hAA); byte_tx(jug); byte_tx(seq); byte_tx(tx_); byte_tx(ty);
      byte_tx(sh); byte_tx(pu); byte_tx(jug ^ seq ^ tx_ ^ ty ^ sh ^ pu);
      repeat (200) @(posedge clk);                    // el CPU vuelve a leer
    end
  endtask

  initial begin
    $dumpfile("tb_soc_mandos_tiempos.vcd");
    $dumpvars(1, uut);            // bus del CPU, chip_select y senales del SoC
    $dumpvars(1, uut.mandos);     // adaptador de bus del periferico
    $dumpvars(0, uut.CPU.PC);
    $dumpvars(0, uut.CPU.state);
    #1 $readmemh("sim/mandos_prueba.hex", uut.RAM.MEM);
    #200 resetn = 1;
    repeat (200) @(posedge clk);

    $display("--- sin tramas: todo en 0 ---");
    check("RAM[0x400] JOY1", uut.RAM.MEM[256], 32'h0);
    check("RAM[0x408] STATUS", uut.RAM.MEM[258], 32'h0);

    $display("--- J1: X=-100 Y=+50 shield=1 punch=0 seq=7 ---");
    trama(8'd1, 8'd7, 8'h9C, 8'h32, 8'd1, 8'd0);
    check("RAM[0x400] JOY1", uut.RAM.MEM[256], 32'h07_01_32_9C);
    check("RAM[0x408] STATUS", uut.RAM.MEM[258], 32'h1);

    $display("--- J2: X=+127 Y=-127 shield=0 punch=1 seq=200 ---");
    trama(8'd2, 8'd200, 8'h7F, 8'h81, 8'd0, 8'd1);
    check("RAM[0x404] JOY2", uut.RAM.MEM[257], 32'hC8_02_81_7F);
    check("RAM[0x408] STATUS", uut.RAM.MEM[258], 32'h3);

    if (fallos == 0) $display("\nTODO OK (%0d pruebas)", pruebas);
    else             $display("\n%0d FALLOS de %0d", fallos, pruebas);
    $finish;
  end

endmodule
