`timescale 1ns / 1ps

module tb_top_tx;

    // 1. Declaración de señales de prueba
    reg  clk;
    reg  rst_n;
    wire uart_tx;

    // Periodo para un reloj de 27 MHz: (1 / 27,000,000) s ≈ 37.037 ns
    localparam CLK_PERIOD = 37.037;

    // 2. Instancia del módulo a probar (UUT - Unit Under Test)
    top_tx uut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_tx(uart_tx)
    );

    // 3. Generación de la señal de reloj (27 MHz continuo)
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // 4. Secuencia de prueba
    initial begin
        // Configuración inicial de señales
        clk   = 0;
        rst_n = 0; // Mantener en reset inicial

        $display("----------------------------------------");
        $display("Iniciando Simulacion del Transmisor (TX)");
        $display("----------------------------------------");

        // Liberar el reset después de 100 ns
        #100;
        rst_n = 1;
        $display("[%0t ns] Reset liberado. El transmisor debe comenzar...", $time);

        // Dejar correr la simulación suficiente tiempo para transmitir varios caracteres
        // A 9600 baudios, cada bit tarda aprox. 104,166 ns (~104 us). 
        // 1 byte (10 bits en total) toma ~1.04 ms = 1,040,000 ns.
        #5_000_000;

        $display("----------------------------------------");
        $display("Simulacion de TX finalizada con exito.");
        $display("----------------------------------------");
        $finish; // Finalizar la simulación
    end

    // Monitor visual para ver en consola cuando la línea cambia de estado
    initial begin
        $monitor("[%0t ns] Estado de linea UART TX = %b", $time, uart_tx);
    end

endmodule