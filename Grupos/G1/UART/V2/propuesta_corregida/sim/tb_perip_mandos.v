`timescale 1ns/1ps
// Prueba del periférico de mandos con el bus del SoC (como lo lee el FemtoRV)
// La línea uart_rx se golpea como lo haría la ESP32 de la consola.
module tb_perip_mandos;
    reg clk = 0, reset = 1, rx = 1;
    always #18.518 clk = ~clk;                       // 27 MHz

    reg         cs = 0, rd = 0, wr = 0;
    reg  [31:0] addr = 0, d_in = 0;
    wire [31:0] d_out;

    peripheral_mandos dut (
        .clk(clk), .reset(reset), .d_in(d_in), .cs(cs), .addr(addr),
        .rd(rd), .wr(wr), .d_out(d_out), .uart_rx(rx),
        .joy1_data(), .joy2_data(), .status());

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

    // Lectura de 32 bits: cs y rd un ciclo, el dato queda en d_out al siguiente
    task leer(input [31:0] a, output [31:0] v);
        begin
            @(posedge clk); addr <= a; cs <= 1'b1; rd <= 1'b1;
            @(posedge clk); cs <= 1'b0; rd <= 1'b0;
            #1 v = d_out;
        end
    endtask

    task byte_tx(input [7:0] b, input stop_ok);
        integer i;
        begin
            rx = 0;                  repeat (234) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i];           repeat (234) @(posedge clk);
            end
            rx = stop_ok;            repeat (234) @(posedge clk);
            rx = 1;                  repeat (20)  @(posedge clk);
        end
    endtask

    task trama(input [7:0] jug, seq, tx_, ty, sh, pu, input chk_ok);
        reg [7:0] c;
        begin
            c = jug ^ seq ^ tx_ ^ ty ^ sh ^ pu;
            byte_tx(8'hAA,1); byte_tx(jug,1); byte_tx(seq,1); byte_tx(tx_,1);
            byte_tx(ty,1); byte_tx(sh,1); byte_tx(pu,1); byte_tx(chk_ok ? c : ~c, 1);
            repeat (10) @(posedge clk);
        end
    endtask

    reg [31:0] v;
    initial begin
        repeat (5) @(posedge clk); reset = 0;

        $display("--- tras el reset ---");
        leer(32'h0047_0000, v); check("JOY1_DATA", v, 32'h0);
        leer(32'h0047_0008, v); check("STATUS", v, 32'h0);

        $display("--- J1: X=-100 Y=+50 shield=1 punch=0 seq=7 ---");
        trama(8'd1, 8'd7, 8'h9C, 8'h32, 8'd1, 8'd0, 1'b1);
        leer(32'h0047_0000, v); check("JOY1_DATA", v, 32'h07_01_32_9C);
        check("  X con signo", $signed(v[7:0]), -100);
        leer(32'h0047_0008, v); check("STATUS (P1_VALID)", v, 32'h1);

        $display("--- J2: X=+127 Y=-127 shield=0 punch=1 seq=200 ---");
        trama(8'd2, 8'd200, 8'h7F, 8'h81, 8'd0, 8'd1, 1'b1);
        leer(32'h0047_0004, v); check("JOY2_DATA", v, 32'hC8_02_81_7F);
        leer(32'h0047_0000, v); check("JOY1_DATA (sin cambio)", v, 32'h07_01_32_9C);
        leer(32'h0047_0008, v); check("STATUS (P1|P2)", v, 32'h3);

        $display("--- checksum malo: J1 no cambia, CHECKSUM_ERROR ---");
        trama(8'd1, 8'd8, 8'h00, 8'h00, 8'd1, 8'd1, 1'b0);
        leer(32'h0047_0000, v); check("JOY1_DATA", v, 32'h07_01_32_9C);
        leer(32'h0047_0008, v); check("STATUS", v, 32'hB);

        $display("--- bit de parada malo: UART_ERROR, luego trama buena ---");
        byte_tx(8'hAA,1); byte_tx(8'd1,1); byte_tx(8'h33,0);
        trama(8'd1, 8'd9, 8'h05, 8'hFB, 8'd0, 8'd1, 1'b1);
        leer(32'h0047_0000, v); check("JOY1_DATA", v, 32'h09_02_FB_05);
        leer(32'h0047_0008, v); check("STATUS", v, 32'hF);

        $display("--- desplazamiento reservado y alias cada 16 bytes ---");
        leer(32'h0047_000C, v); check("+0xC reservado", v, 32'h0);
        leer(32'h0047_0014, v); check("+0x14 = JOY2", v, 32'hC8_02_81_7F);

        $display("--- escritura ignorada (solo lectura) ---");
        @(posedge clk); addr <= 32'h0047_0000; d_in <= 32'hFFFF_FFFF; cs <= 1; wr <= 1;
        @(posedge clk); cs <= 0; wr <= 0;
        leer(32'h0047_0000, v); check("JOY1_DATA", v, 32'h09_02_FB_05);

        $display("--- reset ---");
        @(posedge clk); reset = 1; @(posedge clk); @(posedge clk); reset = 0;
        leer(32'h0047_0000, v); check("JOY1_DATA", v, 32'h0);
        leer(32'h0047_0008, v); check("STATUS", v, 32'h0);

        if (fallos == 0) $display("\nTODO OK (%0d pruebas)", pruebas);
        else             $display("\n%0d FALLOS de %0d", fallos, pruebas);
        $finish;
    end
endmodule
