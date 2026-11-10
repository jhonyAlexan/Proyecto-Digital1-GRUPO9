`timescale 1ns / 1ps

module tb_top_rx;

    reg        clk;
    reg        rst_n;
    reg        uart_rx_pin;
    wire [7:0] led_out;

    localparam CLK_PERIOD = 37.037; // Reloj a 27 MHz
    
    // Tiempo de duración de 1 bit a 9600 baudios (1/9600 s ≈ 104,166 ns)
    localparam BIT_PERIOD = 104_166; 

    // Instancia del módulo receptor bajo prueba
    top_rx uut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_pin(uart_rx_pin),
        .led_out(led_out)
    );

    // Generador de reloj
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // Tarea auxiliar en Verilog para simular el envío de 1 Byte en formato UART (8N1)
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            // 1. Bit de Inicio (Start Bit = 0)
            uart_rx_pin = 1'b0;
            #BIT_PERIOD;

            // 2. Transmisión de los 8 bits de datos (LSB primero)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_pin = data[i];
                #BIT_PERIOD;
            end

            // 3. Bit de Parada (Stop Bit = 1)
            uart_rx_pin = 1'b1;
            #BIT_PERIOD;
            
            $display("[%0t ns] Byte virtual enviado con exito: 0x%h ('%c')", $time, data, data);
        end
    endtask

    // Secuencia de prueba para el Receptor
    initial begin
        // Inicializar señales
        clk         = 0;
        rst_n       = 0;
        uart_rx_pin = 1'b1; // Línea UART en reposo (nivel ALTO)

        #100;
        rst_n = 1; // Liberar reset
        #BIT_PERIOD;

        $display("----------------------------------------");
        $display("Iniciando Simulacion del Receptor (RX)");
        $display("----------------------------------------");

        // Simular el envío de las letras "O", "K" y el salto de línea '\n'
        send_uart_byte("O");
        send_uart_byte("K");
        send_uart_byte(8'h0A); // Carácter ASCII de fin de línea '\n'

        #500_000;

        $display("----------------------------------------");
        $display("Simulacion de RX finalizada.");
        $display("----------------------------------------");
        $finish;
    end

endmodule