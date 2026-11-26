// Banco de prueba: femtorv32_quark del curso + RAM con el .hex + modelos de los
// perifericos con el mapa de cada grupo:
//   0x0040 UART del SoC (bit 2 del control = LED)   0x0041 GPIO (botones y LEDs)
//   0x0043 sonido G5 (FREQ, VOL, CONTROL)           0x0044 pantalla G4 (FRAME, pixeles)
//   0x0047 mandos G5 (JOY1, JOY2, STATUS)
// Se corre con correr.sh. Lo que hace la prueba esta en un escenario (.vh).
`timescale 1ns/1ps
`ifndef HEX
`define HEX "pruebas.hex"
`endif
`ifndef FRAME_CYC
`define FRAME_CYC 20000   // cada cuantos ciclos cambia FRAME en la pantalla
`endif
`ifndef TRAMA_NS
`define TRAMA_NS 680000   // cada cuanto llega una trama nueva de J1 y J2
`endif
`ifndef ESCENARIO
`define ESCENARIO "escenario.vh"
`endif
module tb;
  reg clk = 0;
  always #1 clk = ~clk;
  reg resetn = 0;

  wire [31:0] addr, wdata;
  wire [3:0] wmask;
  wire rstrb;
  reg [31:0] rdata;

  FemtoRV32 #(.ADDR_WIDTH(24)) cpu (
      .clk(clk), .reset(resetn), .mem_addr(addr), .mem_rdata(rdata), .mem_rstrb(rstrb),
      .mem_wdata(wdata), .mem_wmask(wmask), .mem_rbusy(1'b0), .mem_wbusy(1'b0));

  reg [31:0] MEM[0:8191];
  integer k;
  initial begin
    $readmemh(`HEX, MEM);
    // en la FPGA los registros arrancan en 0; en el simulador arrancan en X
    for (k = 0; k < 32; k = k + 1) cpu.registerFile[k] = 0;
    cpu.aluShamt = 0; cpu.aluReg = 0; cpu.cycles = 0; cpu.rs1 = 0; cpu.rs2 = 0; cpu.instr = 0;
    rdata = 0;
  end

  wire [15:0] region = addr[31:16];
  wire wr = |wmask;

  reg led = 0;
  integer cambios_led = 0;
  reg [3:0] botones = 0;
  reg [7:0] leds_gpio = 0;
  reg [15:0] audio_freq = 0;
  reg [6:0] audio_vol = 0;
  reg audio_on = 0;
  reg [2:0] fb[0:4095];
  integer cuadros_enviados = 0, escrituras = 0;
  reg [31:0] frame = 0;
  reg [31:0] joy1 = 0, joy2 = 0, joy_estado = 0;
  integer ciclo = 0;

  always @(posedge clk) begin
    ciclo <= ciclo + 1;
    if (ciclo % `FRAME_CYC == 0) frame <= frame + 1;

    if (rstrb) begin
      if (addr < 32'h00400000) rdata <= MEM[addr[14:2]];
      else if (region == 16'h0041) rdata <= (addr[4:0] == 5'h08) ? {28'b0, botones} :
                                             (addr[4:0] == 5'h04) ? {24'b0, leds_gpio} : 0;
      else if (region == 16'h0044) rdata <= (addr[15:0] == 16'h0010) ? frame : 0;
      else if (region == 16'h0047) rdata <= (addr[3:0] == 4'h0) ? joy1 :
                                             (addr[3:0] == 4'h4) ? joy2 :
                                             (addr[3:0] == 4'h8) ? joy_estado : 0;
      else rdata <= 0;
    end

    if (wr) begin
      if (addr < 32'h00400000) begin
        if (wmask[0]) MEM[addr[14:2]][7:0] <= wdata[7:0];
        if (wmask[1]) MEM[addr[14:2]][15:8] <= wdata[15:8];
        if (wmask[2]) MEM[addr[14:2]][23:16] <= wdata[23:16];
        if (wmask[3]) MEM[addr[14:2]][31:24] <= wdata[31:24];
      end else if (region == 16'h0040 && addr[4:0] == 5'h10) begin
        if (led != wdata[2]) cambios_led = cambios_led + 1;
        led <= wdata[2];
      end else if (region == 16'h0041 && addr[4:0] == 5'h04) begin
        leds_gpio <= wdata[7:0];
      end else if (region == 16'h0043) begin
        case (addr[3:0])
          4'h0: audio_freq <= wdata[15:0];
          4'h4: audio_vol <= wdata[6:0];
          4'h8: begin
            if (audio_on != wdata[0])
              $display("SONIDO %0s FREQ=%0d VOL=%0d (cuadro %0d)", wdata[0] ? "prende" : "apaga",
                       audio_freq, audio_vol, cuadros_enviados);
            audio_on <= wdata[0];
          end
        endcase
      end else if (region == 16'h0044) begin
        if (addr[15:14] == 2'b01) begin  // pixeles: 0x0044_4000 a 0x0044_7FFC
          fb[addr[13:2]] <= wdata[2:0];
          escrituras = escrituras + 1;
          if (addr[13:2] == 12'd4095) cuadros_enviados = cuadros_enviados + 1;
        end
      end else if (addr >= 32'h00400000) begin
        $display("ESCRITURA FUERA DEL MAPA %h = %h", addr, wdata);
      end
    end
  end

  // ---- mandos: el periferico del G5 deja la ultima trama valida en un registro
  reg [7:0] j1x = 0, j1y = 0, j2x = 0, j2y = 0, sec1 = 0, sec2 = 0;
  reg j1b = 0, j1a = 0, j2b = 0, j2a = 0, mandos_on = 0;
  always begin
    #(`TRAMA_NS);
    if (mandos_on) begin
      sec1 = sec1 + 1;
      sec2 = sec2 + 1;
      joy1 = {sec1, 6'b0, j1a, j1b, j1y, j1x};
      joy2 = {sec2, 6'b0, j2a, j2b, j2y, j2x};
      joy_estado = joy_estado | 32'h3;
    end
  end

  task volcar(input [8*40-1:0] nombre);
    integer i, f;
    begin
      f = $fopen(nombre, "w");
      for (i = 0; i < 4096; i = i + 1) $fwrite(f, "%0d", fb[i]);
      $fclose(f);
      $display("cuadro guardado: %0s (cuadros enviados %0d, LED %0d, LEDs GPIO %b)", nombre,
               cuadros_enviados, led, leds_gpio);
    end
  endtask

  task esperar_cuadros(input integer n);
    integer meta;
    begin
      meta = cuadros_enviados + n;
      while (cuadros_enviados < meta) @(posedge clk);
    end
  endtask

  integer ciclo_antes;
  initial begin
    repeat (10) @(posedge clk);
    resetn = 1;
`include `ESCENARIO
    $display("cambios de LED %0d, escrituras de pixel %0d", cambios_led, escrituras);
    $finish;
  end
endmodule
