// -----------------------------------------------------------------------------
// tb_g1_mandos.v - Testbench de g1_mandos_mmio (G1 v1)
// Reloj 27 MHz, UART 115200 8N1, lecturas por el bus como las hace el femtoRV32.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_g1_mandos;
    localparam integer CLK_HZ = 27_000_000;
    localparam integer BAUD   = 115_200;
    localparam integer CPB    = CLK_HZ / BAUD;       // 234 ciclos por bit

    reg clk = 0;
    always #18.518 clk = ~clk;                       // ~27 MHz

    reg         rst = 1, cs = 0, rd = 0, wr = 0, uart_rx = 1;
    reg  [3:0]  addr = 0;
    wire [31:0] d_out, joy1, joy2;
    wire [3:0]  status;
    wire        ack, trama_ok;

    g1_mandos_mmio #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (
        .clk(clk), .rst(rst), .cs(cs), .rd(rd), .wr(wr), .addr(addr),
        .d_in(32'd0), .d_out(d_out), .ack(ack), .uart_rx(uart_rx),
        .joy1_data(joy1), .joy2_data(joy2), .status(status), .trama_ok(trama_ok));

    integer ok = 0, fallos = 0;

    task bit_uart(input b);
        begin uart_rx = b; repeat (CPB) @(posedge clk); end
    endtask

    task byte_uart(input [7:0] b);
        integer i;
        begin
            bit_uart(1'b0);
            for (i = 0; i < 8; i = i + 1) bit_uart(b[i]);
            bit_uart(1'b1);
        end
    endtask

    // Byte con bit de parada en 0 (error de trama)
    task byte_malo(input [7:0] b);
        integer i;
        begin
            bit_uart(1'b0);
            for (i = 0; i < 8; i = i + 1) bit_uart(b[i]);
            bit_uart(1'b0);
            bit_uart(1'b1); bit_uart(1'b1);
        end
    endtask

    task trama(input [7:0] j, input [7:0] s, input [7:0] x, input [7:0] y,
               input [7:0] b, input [7:0] a, input danar);
        reg [7:0] chk;
        begin
            chk = j ^ s ^ x ^ y ^ b ^ a;
            if (danar) chk = ~chk;
            byte_uart(8'hAA); byte_uart(j); byte_uart(s); byte_uart(x);
            byte_uart(y); byte_uart(b); byte_uart(a); byte_uart(chk);
            repeat (20) @(posedge clk);
        end
    endtask

    // Lectura de bus: cs y rd un ciclo; el dato vale cuando ack = 1
    task leer(input [3:0] a, output [31:0] v);
        begin
            @(negedge clk); cs = 1; rd = 1; addr = a;
            @(negedge clk); cs = 0; rd = 0;
            if (ack !== 1'b1) begin
                $display("FALLO: ack no subio en la lectura de 0x%0h", a);
                fallos = fallos + 1;
            end
            v = d_out;
        end
    endtask

    task revisar(input [8*40-1:0] nombre, input [31:0] obtenido, input [31:0] esperado);
        begin
            if (obtenido === esperado) begin
                ok = ok + 1;
                $display("OK    %0s = 0x%08h", nombre, obtenido);
            end else begin
                fallos = fallos + 1;
                $display("FALLO %0s = 0x%08h (esperado 0x%08h)", nombre, obtenido, esperado);
            end
        end
    endtask

    reg [31:0] v;

    initial begin
        $dumpfile("tb_g1_mandos.vcd");
        $dumpvars(0, tb_g1_mandos);
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (10) @(posedge clk);

        // 1. Estado inicial
        leer(4'h8, v); revisar("1 STATUS inicial", v, 32'h0);

        // 2. Trama valida J1: X = -100 (0x9C), Y = +90 (0x5A), boton 1, ataque 0, seq 7
        trama(8'd1, 8'd7, 8'h9C, 8'h5A, 8'd1, 8'd0, 1'b0);
        leer(4'h0, v); revisar("2 JOY1_DATA", v, 32'h07_01_5A_9C);
        leer(4'h8, v); revisar("2 STATUS (P1_VALID)", v, 32'h1);

        // 3. Trama valida J2 con 0xAA dentro de los datos (X = 0xAA), ataque 1
        trama(8'd2, 8'd200, 8'hAA, 8'h00, 8'd0, 8'd1, 1'b0);
        leer(4'h4, v); revisar("3 JOY2_DATA (0xAA como dato)", v, 32'hC8_02_00_AA);
        leer(4'h8, v); revisar("3 STATUS (P1 y P2)", v, 32'h3);

        // 4. Checksum malo: JOY1 no cambia y sube CHECKSUM_ERROR
        trama(8'd1, 8'd8, 8'h10, 8'h10, 8'd0, 8'd1, 1'b1);
        leer(4'h0, v); revisar("4 JOY1 sin cambio", v, 32'h07_01_5A_9C);
        leer(4'h8, v); revisar("4 STATUS (CHECKSUM_ERROR)", v, 32'hB);

        // 5. Jugador invalido (3) con XOR correcto: se ignora
        trama(8'd3, 8'd9, 8'h01, 8'h01, 8'd1, 8'd1, 1'b0);
        leer(4'h0, v); revisar("5 JOY1 sin cambio", v, 32'h07_01_5A_9C);
        leer(4'h4, v); revisar("5 JOY2 sin cambio", v, 32'hC8_02_00_AA);

        // 6. Basura antes de la trama y trama cortada (timeout de 1 ms)
        byte_uart(8'h13); byte_uart(8'h77);
        byte_uart(8'hAA); byte_uart(8'd1); byte_uart(8'd50);   // se corta aqui
        repeat (CLK_HZ / 1000 + 100) @(posedge clk);            // > 1 ms
        trama(8'd1, 8'd51, 8'h7F, 8'h81, 8'd0, 8'd0, 1'b0);
        leer(4'h0, v); revisar("6 resincroniza tras timeout", v, 32'h33_00_81_7F);

        // 7. Error de trama UART y recuperacion
        byte_malo(8'h55);
        trama(8'd2, 8'd201, 8'h05, 8'hFB, 8'd1, 8'd1, 1'b0);
        leer(4'h4, v); revisar("7 JOY2 tras error de trama", v, 32'hC9_03_FB_05);
        leer(4'h8, v); revisar("7 STATUS (UART_ERROR)", v, 32'hF);

        // 8. Direccion reservada devuelve 0
        leer(4'hC, v); revisar("8 reservado 0xC", v, 32'h0);

        // 9. Reset borra todo
        @(negedge clk); rst = 1; repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        leer(4'h0, v); revisar("9 JOY1 tras reset", v, 32'h0);
        leer(4'h8, v); revisar("9 STATUS tras reset", v, 32'h0);

        $display("--------------------------------------------");
        $display("Resultado: %0d OK, %0d FALLOS", ok, fallos);
        $finish;
    end
endmodule
