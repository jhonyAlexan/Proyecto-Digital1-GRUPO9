`timescale 1ns / 1ps

module tb_top_system_loopback;

    reg clk;
    reg rst_n;

    // Cable virtual de interconexión entre ambas FPGAs
    wire wire_uart; 
    wire [7:0] rx_leds;

    localparam CLK_PERIOD = 37.037; // 27 MHz

    // Instancia 1: FPGA Transmisora
    top_tx fpga_1_tx (
        .clk(clk),
        .rst_n(rst_n),
        .uart_tx(wire_uart)
    );

    // Instancia 2: FPGA Receptora
    top_rx fpga_2_rx (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_pin(wire_uart),
        .led_out(rx_leds)
    );

    // Generador de reloj
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // Variables auxiliares para reconstruir e imprimir la cadena completa
    integer i;
    reg [8*64-1:0] full_string; // Búfer de 64 caracteres de ancho para impresión en bloque

    // MONITOR DE MENSAJE COMPLETO
    // Se dispara cuando la FPGA 2 detecta el salto de línea '\n' (0x0A)
    always @(posedge clk) begin
        if (fpga_2_rx.msg_ready) begin
            
            // Empaquetar el contenido de la RAM en la variable vectorial
            for (i = 0; i < 64; i = i + 1) begin
                // Asigna cada byte del búfer a su posición correspondiente dentro del string
                full_string[(63-i)*8 +: 8] = fpga_2_rx.rx_buffer[i];
            end

            $display("--------------------------------------------------");
            $display("[%0t ns] MENSAJE COMPLETO RECIBIDO EN FPGA 2:", $time);
            $display("\"%s\"", full_string); // %s imprime todo el vector como texto en C/Verilog
            $display("--------------------------------------------------");
        end
    end

    // Secuencia principal de la simulación
    initial begin
        clk   = 0;
        rst_n = 0;

        $display("====================================================");
        $display("Simulacion del Sistema Completo (FPGA 1 <-> FPGA 2)");
        $display("====================================================");

        #100;
        rst_n = 1;
        $display("[%0t ns] Reset liberado. Esperando recepcion de datos...", $time);

        // Esperar tiempo suficiente para la transmisión completa
        #30_000_000; 

        $display("====================================================");
        $display("Prueba del sistema finalizada.");
        $display("====================================================");
        $finish;
    end

endmodule