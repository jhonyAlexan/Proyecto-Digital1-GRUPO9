// tb_joystick_mando: prueba el lado FPGA del mando con un modelo de la ESP32.
// El modelo espera el byte '?' de la FPGA y responde con el paquete de 8 bytes:
// AA, jugador, secuencia, X, Y, botón, ataque, XOR de los bytes 1 a 6.
// Además cuenta cuántas veces se ejecuta cada transferencia T0 a T27 de la tabla de 3.6
// y falla si alguna queda en cero.
`timescale 1ns/1ps
module tb_joystick_mando;
    localparam real    T_CLK   = 37.037;       // 27 MHz
    localparam real    T_BIT   = 8680.6;       // 115 200 baudios
    localparam integer PERIODO = 54_000;       // 2 ms entre solicitudes (10 ms en la placa)

    reg         clk = 0, rst = 1;
    reg         esp_tx = 1;                    // línea ESP32 -> FPGA
    wire        fpga_tx;                       // línea FPGA -> ESP32
    reg  [15:0] dir = 0;
    reg         leer = 0;
    wire [7:0]  dato, eje_x, eje_y;
    wire        listo, boton, nuevo_dato, comunicacion_ok, checksum_error;

    always #(T_CLK / 2) clk = ~clk;

    joystick_mando #(.PERIODO_CICLOS(PERIODO)) dut (
        .clk(clk), .rst(rst), .uart_rx(esp_tx), .uart_tx(fpga_tx),
        .dir(dir), .leer(leer), .dato(dato), .listo(listo),
        .eje_x(eje_x), .eje_y(eje_y), .boton(boton), .nuevo_dato(nuevo_dato),
        .comunicacion_ok(comunicacion_ok), .checksum_error(checksum_error)
    );

    integer bien = 0, fallan = 0;
    task comprobar(input ok, input [8*56-1:0] texto);
        begin
            if (ok) bien = bien + 1;
            else begin fallan = fallan + 1; $display("   FALLA: %0s", texto); end
        end
    endtask

    // ------------------------------------------------------------ modelo de la ESP32
    reg  [7:0] esp_x = 8'h46, esp_y = 8'hF6;   // X = +70, Y = -10
    reg        esp_boton = 0;
    reg        esp_responde = 1;               // 0: la ESP32 se queda callada
    reg        esp_xor_malo = 0;               // 1: envía el XOR equivocado
    reg  [7:0] esp_secuencia = 0;
    integer    solicitudes = 0, errores_xor = 0;
    real       t_solicitud_1 = 0, t_solicitud_2 = 0;

    // Un byte 8N1; si parada_mala = 1, el bit de parada sale en 0 (error de trama)
    task esp_enviar_byte(input [7:0] b, input parada_mala);
        integer k;
        begin
            esp_tx = 0; #(T_BIT);
            for (k = 0; k < 8; k = k + 1) begin esp_tx = b[k]; #(T_BIT); end
            esp_tx = parada_mala ? 1'b0 : 1'b1; #(T_BIT);
            esp_tx = 1; #(T_BIT);
        end
    endtask

    task esp_paquete(input [7:0] jugador, input [7:0] x, input [7:0] y, input [7:0] bot, input xor_malo);
        reg [7:0] suma;
        begin
            suma = jugador ^ esp_secuencia ^ x ^ y ^ bot ^ 8'd0;
            if (xor_malo) suma = ~suma;
            esp_enviar_byte(8'hAA, 0); esp_enviar_byte(jugador, 0); esp_enviar_byte(esp_secuencia, 0);
            esp_enviar_byte(x, 0);     esp_enviar_byte(y, 0);       esp_enviar_byte(bot, 0);
            esp_enviar_byte(8'd0, 0);  esp_enviar_byte(suma, 0);
            esp_secuencia = esp_secuencia + 1;
        end
    endtask

    task esp_recibir_byte(output [7:0] b);
        integer k;
        begin
            @(negedge fpga_tx);
            #(T_BIT * 1.5);                        // centro del bit 0
            for (k = 0; k < 8; k = k + 1) begin b[k] = fpga_tx; #(T_BIT); end
        end
    endtask

    reg [7:0] pedido;
    always begin
        esp_recibir_byte(pedido);
        if (pedido == 8'h3F) begin
            solicitudes = solicitudes + 1;
            if (solicitudes == 1) t_solicitud_1 = $realtime;
            if (solicitudes == 2) t_solicitud_2 = $realtime;
            if (esp_responde) begin
                #20000;                            // la ESP32 tarda unos 20 us en leer el ADC
                esp_paquete(8'd1, esp_x, esp_y, {7'd0, esp_boton}, esp_xor_malo);
            end
        end
    end

    always @(posedge clk) if (checksum_error) errores_xor = errores_xor + 1;

    // ------------------------------------------------------------ cobertura de la tabla de 3.6
    // Cada condición usa los valores de antes del flanco, igual que el Verilog.
    integer cuenta_t [0:27];
    integer t;
    initial for (t = 0; t <= 27; t = t + 1) cuenta_t[t] = 0;

    always @(posedge clk) begin
        if (rst) cuenta_t[0] = cuenta_t[0] + 1;
        else begin
            // Solicitud
            if (dut.u_solicitud.cuenta != PERIODO - 1) cuenta_t[1] = cuenta_t[1] + 1;
            if (dut.u_solicitud.cuenta == PERIODO - 1) cuenta_t[2] = cuenta_t[2] + 1;
            if (nuevo_dato)                            cuenta_t[3] = cuenta_t[3] + 1;
            // Transmisor: REPOSO 0, INICIO 1, DATOS 2, PARADA 3
            if (dut.u_tx.estado == 0 && dut.u_tx.tx_start)                   cuenta_t[4] = cuenta_t[4] + 1;
            if (dut.u_tx.estado != 0 && dut.u_tx.cuenta != 0)                cuenta_t[5] = cuenta_t[5] + 1;
            if (dut.u_tx.estado == 1 && dut.u_tx.cuenta == 0)                cuenta_t[6] = cuenta_t[6] + 1;
            if (dut.u_tx.estado == 2 && dut.u_tx.cuenta == 0 && dut.u_tx.indice != 7) cuenta_t[7] = cuenta_t[7] + 1;
            if (dut.u_tx.estado == 2 && dut.u_tx.cuenta == 0 && dut.u_tx.indice == 7) cuenta_t[8] = cuenta_t[8] + 1;
            if (dut.u_tx.estado == 3 && dut.u_tx.cuenta == 0)                cuenta_t[9] = cuenta_t[9] + 1;
            // Receptor: REPOSO 0, INICIO 1, DATOS 2, PARADA 3, RECUPERAR 4
            if (dut.u_rx.cuenta != 0)                                        cuenta_t[10] = cuenta_t[10] + 1;
            if (dut.u_rx.cuenta == 0) begin
                if (dut.u_rx.estado == 0 && !dut.u_rx.rx_sync)               cuenta_t[11] = cuenta_t[11] + 1;
                if (dut.u_rx.estado == 1 && !dut.u_rx.rx_sync)               cuenta_t[12] = cuenta_t[12] + 1;
                if (dut.u_rx.estado == 1 &&  dut.u_rx.rx_sync)               cuenta_t[13] = cuenta_t[13] + 1;
                if (dut.u_rx.estado == 2 && dut.u_rx.indice != 7)            cuenta_t[14] = cuenta_t[14] + 1;
                if (dut.u_rx.estado == 2 && dut.u_rx.indice == 7)            cuenta_t[15] = cuenta_t[15] + 1;
                if (dut.u_rx.estado == 3 &&  dut.u_rx.rx_sync)               cuenta_t[16] = cuenta_t[16] + 1;
                if (dut.u_rx.estado == 3 && !dut.u_rx.rx_sync)               cuenta_t[17] = cuenta_t[17] + 1;
                if (dut.u_rx.estado == 4 &&  dut.u_rx.rx_sync)               cuenta_t[18] = cuenta_t[18] + 1;
            end
            // Ensamblador: BUSCAR 0, CAMPOS 1, CHECKSUM 2
            if (dut.rx_frame_err)                                            cuenta_t[19] = cuenta_t[19] + 1;
            else if (dut.rx_valid) begin
                if (dut.u_ensamblador.estado == 0 && dut.rx_data == 8'hAA)   cuenta_t[20] = cuenta_t[20] + 1;
                if (dut.u_ensamblador.estado == 1)                           cuenta_t[21] = cuenta_t[21] + 1;
                if (dut.cargar_p1 || dut.cargar_p2)                          cuenta_t[22] = cuenta_t[22] + 1;
                if (checksum_error)                                          cuenta_t[23] = cuenta_t[23] + 1;
                if (dut.u_ensamblador.evaluar && !checksum_error && !dut.cargar_p1 && !dut.cargar_p2)
                                                                             cuenta_t[25] = cuenta_t[25] + 1;
            end else if (dut.u_ensamblador.estado != 0 &&
                         dut.u_ensamblador.espera == dut.u_ensamblador.T_MAX_CICLOS - 1)
                                                                             cuenta_t[24] = cuenta_t[24] + 1;
            // Registros X e Y
            if (nuevo_dato) cuenta_t[26] = cuenta_t[26] + 1;
            if (leer)       cuenta_t[27] = cuenta_t[27] + 1;
        end
    end

    // ------------------------------------------------------------ lectura por dirección
    reg [7:0] leido;
    task leer_dir(input [15:0] d);
        begin
            @(negedge clk); dir = d; leer = 1;
            @(negedge clk); leer = 0;
            comprobar(listo == 1'b1, "listo vale 1 el ciclo siguiente a leer");
            leido = dato;
        end
    endtask

    task esperar_solicitudes(input integer n);
        integer objetivo;
        begin
            objetivo = solicitudes + n;
            wait (solicitudes == objetivo);
            #1_000_000;                            // 1 ms: tiempo de sobra para la respuesta
        end
    endtask

    initial begin
        $dumpfile("tb_joystick_mando.vcd");
        $dumpvars(0, tb_joystick_mando);
        repeat (5) @(posedge clk); rst = 0;

        // 1. La FPGA pide, la ESP32 responde y X, Y quedan en 0x0042 y 0x0043 (T1 a T18, T20 a T22, T26, T27)
        esperar_solicitudes(1);
        leer_dir(16'h0042); comprobar(leido == 8'h46, "0x0042 = X = 0x46 (+70)");
        leer_dir(16'h0043); comprobar(leido == 8'hF6, "0x0043 = Y = 0xF6 (-10)");
        leer_dir(16'h0044); comprobar(leido == 8'h00, "otra direccion se lee 0");
        comprobar(comunicacion_ok == 1'b1, "comunicacion_ok = 1 con respuestas");

        // 2. Período entre solicitudes (T2)
        esperar_solicitudes(1);
        comprobar((t_solicitud_2 - t_solicitud_1) > 1_990_000 && (t_solicitud_2 - t_solicitud_1) < 2_010_000,
                  "una solicitud cada 2 ms en simulacion");

        // 3. Valores nuevos: el registro sigue a la palanca (T26)
        esp_x = 8'h81; esp_y = 8'h7F; esp_boton = 1;
        esperar_solicitudes(1);
        leer_dir(16'h0042); comprobar(leido == 8'h81, "X nuevo = 0x81 (-127)");
        leer_dir(16'h0043); comprobar(leido == 8'h7F, "Y nuevo = 0x7F (+127)");
        comprobar(boton == 1'b1, "boton = 1");

        // 4. XOR equivocado: el paquete se descarta y los registros no cambian (T23)
        esp_xor_malo = 1; esp_x = 8'h10;
        esperar_solicitudes(1);
        leer_dir(16'h0042); comprobar(leido == 8'h81, "XOR malo: X no cambia");
        comprobar(errores_xor > 0, "XOR malo: checksum_error se activa");
        esp_xor_malo = 0;

        // 5. La ESP32 deja de responder: comunicacion_ok baja después de 10 solicitudes
        esp_responde = 0;
        esperar_solicitudes(12);
        comprobar(comunicacion_ok == 1'b0, "sin respuesta: comunicacion_ok = 0");
        leer_dir(16'h0042); comprobar(leido == 8'h81, "sin respuesta: X conserva el ultimo valor");

        // 6. Ruido, error de trama, paquete incompleto y jugador inválido, con la ESP32 callada.
        //    Se inyectan justo después de una solicitud, cuando la línea está libre.
        #1000;
        esp_tx = 0; #2000; esp_tx = 1; #20000;                        // pulso de 2 us (T13)
        esp_enviar_byte(8'h55, 1); #20000;                            // parada en 0 (T17, T18, T19)
        esp_enviar_byte(8'hAA, 0); esp_enviar_byte(8'h01, 0); esp_enviar_byte(8'h05, 0);
        #1_500_000;                                                   // se corta: incompleto (T24)
        esp_paquete(8'd3, 8'h33, 8'h33, 8'd0, 0);                     // jugador 3 (T25)
        #100_000;
        leer_dir(16'h0042); comprobar(leido == 8'h81, "ruido, trama mala, incompleto y jugador 3: X no cambia");
        leer_dir(16'h0043); comprobar(leido == 8'h7F, "ruido, trama mala, incompleto y jugador 3: Y no cambia");

        // 7. Vuelve a responder: se recupera sola (T3)
        esp_responde = 1;
        esperar_solicitudes(1);
        comprobar(comunicacion_ok == 1'b1, "vuelve la respuesta: comunicacion_ok = 1");
        leer_dir(16'h0042); comprobar(leido == 8'h10, "vuelve la respuesta: X = 0x10");

        // Cobertura
        $display("   cobertura de la tabla de 3.6 (veces que se ejecuta cada transferencia):");
        for (t = 0; t <= 27; t = t + 1) begin
            $display("     T%0d = %0d", t, cuenta_t[t]);
            comprobar(cuenta_t[t] > 0, "cada transferencia se ejecuta al menos una vez");
        end

        $display("== tb_joystick_mando: %0d solicitudes, %0d comprobaciones bien, %0d fallan == %0s",
                 solicitudes, bien, fallan, (fallan == 0) ? "PASA" : "NO PASA");
        $finish;
    end
endmodule
