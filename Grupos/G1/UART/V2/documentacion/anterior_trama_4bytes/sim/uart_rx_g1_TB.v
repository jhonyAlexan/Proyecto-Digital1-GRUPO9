// -----------------------------------------------------------------------------
// G1 - Comunicacion | Testbench autoverificable de uart_rx_g1
// Cada caso sale de un diagrama de la documentacion (README.md):
//   C1, C2  -> diagrama de tiempos (trama normal, valores extremos)
//   C3      -> diagrama de flujo / ASMD: falso start (glitch) se ignora
//   C4      -> ASMD trama: trama cortada + silencio -> timeout -> resincroniza
//   C5      -> ASMD byte: stop = 0 -> error_trama -> se descarta la trama
//   C6      -> ASMD trama: bits reservados != 0 -> no se publica
//   C7      -> tolerancia de reloj: ESP32 transmitiendo 2 % lenta y 2 % rapida
//   C8      -> rafaga de 5 tramas seguidas como envia la ESP32 cada 20 ms
// Ejecutar:  make sim     (iverilog + vvp)   |   make wave (GTKWave)
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module uart_rx_g1_TB;

    localparam real T_CLK  = 1e9/27e6;      // 37,037 ns  (27 MHz)
    localparam real T_BIT0 = 1e9/115200.0;  // 8680,6 ns  (115200 baudios)

    reg clk = 1'b0, rst_n = 1'b0, uart_rx = 1'b1;
    always #(T_CLK/2) clk = ~clk;

    wire [3:0]  id;
    wire [11:0] x, y;
    wire        atk, valido;

    uart_rx_g1 dut (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx),
        .id_fpga(id), .direccion_x(x), .direccion_y(y),
        .ataque(atk), .valido(valido)
    );

    real    t_bit = T_BIT0;
    integer errores = 0, n_validos = 0;

    always @(posedge clk) if (valido) n_validos = n_validos + 1;

    // ---------------- Tareas que imitan a la ESP32 ----------------
    task enviar_byte(input [7:0] b, input stop_ok);
        integer i;
        begin
            uart_rx = 1'b0;               #(t_bit);   // start
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = b[i];           #(t_bit);   // LSB primero
            end
            uart_rx = stop_ok;            #(t_bit);   // stop
            uart_rx = 1'b1;
        end
    endtask

    function [31:0] armar(input [3:0] i_d, input [11:0] dx, input [11:0] dy, input a);
        armar = {3'b000, a, dy, dx, i_d};   // igual que enviarTramaUART()
    endfunction

    task enviar_trama(input [31:0] t);
        begin
            enviar_byte(t[31:24], 1'b1);  // buffer[0] = MSB
            enviar_byte(t[23:16], 1'b1);
            enviar_byte(t[15:8],  1'b1);
            enviar_byte(t[7:0],   1'b1);
        end
    endtask

    task esperar_bits(input integer n);
        #(n*T_BIT0);
    endtask

    // Comprueba que la ultima publicacion trae estos campos
    task verificar(input [8*40-1:0] caso, input [3:0] e_id, input [11:0] e_x,
                   input [11:0] e_y, input e_a, input integer e_validos);
        begin
            if (n_validos !== e_validos || id !== e_id || x !== e_x ||
                y !== e_y || atk !== e_a) begin
                errores = errores + 1;
                $display("FALLA %0s: validos=%0d (esp %0d) id=%0d x=%0d y=%0d atk=%0d | esp id=%0d x=%0d y=%0d atk=%0d",
                         caso, n_validos, e_validos, id, x, y, atk, e_id, e_x, e_y, e_a);
            end else
                $display("OK    %0s: id=%0d x=%0d y=%0d atk=%0d", caso, id, x, y, atk);
        end
    endtask

    integer k;
    initial begin
        $dumpfile("uart_rx_g1_TB.vcd");
        $dumpvars(0, uart_rx_g1_TB);

        #(10*T_CLK) rst_n = 1'b1;
        esperar_bits(2);

        // C1: trama normal (ID=1, X=0xABC, Y=0x123, ataque=1)
        enviar_trama(armar(4'd1, 12'hABC, 12'h123, 1'b1));
        esperar_bits(2);
        verificar("C1 trama normal", 4'd1, 12'hABC, 12'h123, 1'b1, 1);

        // C2: valores extremos del ADC de 12 bits (X=4095, Y=0, sin ataque)
        enviar_trama(armar(4'd2, 12'd4095, 12'd0, 1'b0));
        esperar_bits(2);
        verificar("C2 extremos ADC", 4'd2, 12'd4095, 12'd0, 1'b0, 2);

        // C3: glitch de 1 us en reposo (menor que medio bit) + trama
        uart_rx = 1'b0; #1000; uart_rx = 1'b1;
        esperar_bits(3);
        enviar_trama(armar(4'd1, 12'd2048, 12'd1900, 1'b0));
        esperar_bits(2);
        verificar("C3 glitch ignorado", 4'd1, 12'd2048, 12'd1900, 1'b0, 3);

        // C4: solo 2 bytes, silencio de 5 bytes, trama completa
        enviar_byte(8'h1F, 1'b1);
        enviar_byte(8'hFF, 1'b1);
        esperar_bits(50);
        enviar_trama(armar(4'd3, 12'd100, 12'd200, 1'b1));
        esperar_bits(2);
        verificar("C4 resincronizacion", 4'd3, 12'd100, 12'd200, 1'b1, 4);

        // C5: byte 2 con stop = 0 -> se descarta; luego trama buena
        enviar_byte(8'h10, 1'b1);
        enviar_byte(8'h55, 1'b0);
        esperar_bits(50);
        enviar_trama(armar(4'd4, 12'd7, 12'd9, 1'b0));
        esperar_bits(2);
        verificar("C5 error de stop", 4'd4, 12'd7, 12'd9, 1'b0, 5);

        // C6: bits reservados [31:29] != 0 -> no se publica (siguen los de C5)
        enviar_trama(32'hE000_0005);
        esperar_bits(2);
        verificar("C6 reservados != 0", 4'd4, 12'd7, 12'd9, 1'b0, 5);

        // C7: ESP32 2 % lenta y 2 % rapida
        t_bit = T_BIT0*1.02;
        enviar_trama(armar(4'd5, 12'h5A5, 12'hA5A, 1'b1));
        esperar_bits(2);
        verificar("C7a baud +2%", 4'd5, 12'h5A5, 12'hA5A, 1'b1, 6);
        t_bit = T_BIT0*0.98;
        enviar_trama(armar(4'd6, 12'h0F0, 12'hF0F, 1'b0));
        esperar_bits(2);
        verificar("C7b baud -2%", 4'd6, 12'h0F0, 12'hF0F, 1'b0, 7);
        t_bit = T_BIT0;

        // C8: rafaga de 5 tramas con hueco de 1 bit
        for (k = 0; k < 5; k = k + 1) begin
            enviar_trama(armar(4'd1, 12'd1000 + k, 12'd3000 - k, k[0]));
            esperar_bits(1);
        end
        esperar_bits(2);
        verificar("C8 rafaga (ultima)", 4'd1, 12'd1004, 12'd2996, 1'b0, 12);

        if (errores == 0) $display("RESULTADO: TODAS LAS PRUEBAS PASARON");
        else              $display("RESULTADO: %0d PRUEBA(S) FALLARON", errores);
        $finish;
    end
endmodule
