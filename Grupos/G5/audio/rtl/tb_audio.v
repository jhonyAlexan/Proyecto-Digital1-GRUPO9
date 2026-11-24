// tb_audio: testbench de peripheral_audio. Cada caso prueba transferencias del ASMD (T0 a T8,
// sección 3.6) y los criterios de la sección 2.5. Escribe tb_audio.vcd para GTKWave.
// Por defecto: clk = 27 MHz y CICLOS_BCLK = 18. Para 25 MHz: make sim25.
`timescale 1ps / 1ps

module tb_audio;
    parameter CICLOS_BCLK = 18;                      // 16 con 25 MHz
    parameter T_CLK       = 37036;                   // periodo de clk en ps (27 MHz); 40000 con 25 MHz
    localparam T_BCLK     = CICLOS_BCLK * T_CLK;
    localparam T_TRAMA    = 32 * T_BCLK;

    reg         clk = 1'b0, rst = 1'b1;
    reg         cs = 1'b0, rd = 1'b0, wr = 1'b0;
    reg  [3:0]  addr = 4'd0;
    reg  [31:0] d_in = 32'd0;
    wire [31:0] d_out;
    wire        ack, audio_bclk, audio_lrclk, audio_din;

    peripheral_audio #(.CICLOS_BCLK(CICLOS_BCLK)) dut (
        .clk(clk), .rst(rst), .cs(cs), .rd(rd), .wr(wr), .addr(addr), .d_in(d_in),
        .d_out(d_out), .ack(ack),
        .audio_bclk(audio_bclk), .audio_lrclk(audio_lrclk), .audio_din(audio_din)
    );

    always #(T_CLK / 2) clk = ~clk;

    // ---------------------------------------------------------------- resultados
    integer bien = 0, mal = 0;
    task comprobar(input cond, input [8*64-1:0] texto);
        begin
            if (cond) bien = bien + 1;
            else begin
                mal = mal + 1;
                $display("  FALLA  t=%0t ps  %0s", $time, texto);
            end
        end
    endtask

    // ---------------------------------------------------------------- acceso al bus
    task escribir(input [3:0] a, input [31:0] dato);
        begin
            @(negedge clk); cs = 1; wr = 1; addr = a; d_in = dato;
            @(negedge clk); cs = 0; wr = 0;
            comprobar(ack == 1'b1, "ack despues de una escritura");
        end
    endtask

    task leer(input [3:0] a, output [31:0] dato);
        begin
            @(negedge clk); cs = 1; rd = 1; addr = a;
            @(negedge clk); cs = 0; rd = 0;
            comprobar(ack == 1'b1, "ack despues de una lectura");
            dato = d_out;
        end
    endtask

    // ---------------------------------------------------------------- receptor I2S de referencia
    // Lee DIN en cada flanco de subida de BCLK. Cuando LRCLK cambia, el bit leído es el último
    // de la palabra anterior; la palabra nueva empieza en el siguiente flanco (un BCLK de retraso).
    reg  [15:0] acumulado = 16'd0;
    integer     nbits = 0;
    reg         lr_antes = 1'b0;
    reg  [15:0] palabra_izq = 16'd0, palabra_der = 16'd0;
    reg         hay_trama = 1'b0;               // se pone en 1 al completar el slot derecho
    integer     tramas = 0;

    always @(posedge audio_bclk) begin
        if (audio_lrclk != lr_antes) begin
            if (lr_antes == 1'b0) palabra_izq = {acumulado[14:0], audio_din};
            else begin
                palabra_der = {acumulado[14:0], audio_din};
                hay_trama = 1'b1;
                tramas = tramas + 1;
            end
            if (tramas > 1) comprobar(nbits == 15, "16 bits por slot");
            nbits = 0;
            acumulado = 16'd0;
        end else begin
            acumulado = {acumulado[14:0], audio_din};
            nbits = nbits + 1;
        end
        lr_antes = audio_lrclk;
    end

    // ---------------------------------------------------------------- tiempos de BCLK y LRCLK
    time t_sube = 0, t_baja = 0, t_lr = 0;
    // Las mediciones empiezan de cero con cada reset (el reset corta el período en curso)
    always @(posedge clk) if (rst) begin t_sube = 0; t_baja = 0; t_lr = 0; end
    always @(posedge audio_bclk) if (!rst) begin
        if (t_sube != 0) begin
            comprobar($time - t_sube == T_BCLK, "periodo de BCLK = 16 ciclos");
            comprobar($time - t_baja == T_BCLK / 2, "ciclo de trabajo de BCLK 50 %");
        end
        t_sube = $time;
    end
    always @(negedge audio_bclk) if (!rst) t_baja = $time;
    always @(negedge audio_lrclk) if (!rst) begin
        if (t_lr != 0) comprobar($time - t_lr == T_TRAMA, "trama = 512 ciclos de clk");
        t_lr = $time;
    end
    // LRCLK y DIN solo cambian junto con el flanco de bajada de BCLK
    always @(audio_lrclk) if (!rst) comprobar($time == t_baja, "LRCLK cambia en la bajada de BCLK");
    always @(audio_din)   if (!rst) comprobar($time == t_baja, "DIN cambia en la bajada de BCLK");

    // ---------------------------------------------------------------- cobertura del ASMD (sección 3.6)
    // Cuenta cuántas veces se ejecuta cada transferencia T0 a T8 de la tabla.
    integer cuenta_t [0:8];
    integer ti;
    initial for (ti = 0; ti <= 8; ti = ti + 1) cuenta_t[ti] = 0;
    always @(posedge clk) begin
        if (rst) cuenta_t[0] = cuenta_t[0] + 1;                                          // T0
        else begin
            if (!dut.tick_bajada) cuenta_t[1] = cuenta_t[1] + 1;                          // T1
            if (dut.tick_bajada)  cuenta_t[2] = cuenta_t[2] + 1;                          // T2
            if (dut.carga)        cuenta_t[3] = cuenta_t[3] + 1;                          // T3
            if (dut.tick_bajada && dut.cnt_bit != 5'd31) cuenta_t[4] = cuenta_t[4] + 1;   // T4
            if (dut.tick_bajada && dut.u_i2s.estado == 1'b0 && dut.cnt_bit == 5'd14)
                cuenta_t[5] = cuenta_t[5] + 1;                                            // T5
            if (dut.tick_bajada && dut.u_i2s.estado == 1'b1 && dut.cnt_bit == 5'd30)
                cuenta_t[6] = cuenta_t[6] + 1;                                            // T6
            if (cs && wr) cuenta_t[7] = cuenta_t[7] + 1;                                  // T7
            if (cs)       cuenta_t[8] = cuenta_t[8] + 1;                                  // T8
        end
    end

    // ---------------------------------------------------------------- utilidades
    task esperar_tramas(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                hay_trama = 1'b0;
                wait (hay_trama);
            end
        end
    endtask

    // Comprueba la trama recibida y devuelve la muestra (byte alto)
    task revisar_trama(output signed [7:0] muestra);
        begin
            comprobar(palabra_izq[7:0] == 8'h00, "bits 7:0 del slot izquierdo en cero");
            comprobar(palabra_der[7:0] == 8'h00, "bits 7:0 del slot derecho en cero");
            comprobar(palabra_izq == palabra_der, "misma muestra en los dos slots");
            muestra = palabra_izq[15:8];
        end
    endtask

    // ---------------------------------------------------------------- estímulos
    reg [31:0]        dato;
    reg signed [7:0]  m, m_antes;
    integer           k, subidas, freq_la;
    real              fs, f_esperada, t_primera, t_ultima, f_medida;

    initial begin
        $dumpfile("tb_audio.vcd");
        $dumpvars(0, tb_audio);
        fs      = 1.0e12 / (32.0 * CICLOS_BCLK * T_CLK);
        freq_la = $rtoi(440.0 * 65536.0 / fs + 0.5);          // FREQ más cercano a 440 Hz
        f_esperada = freq_la * fs / 65536.0;
        $display("== tb_audio: clk = %.2f MHz, CICLOS_BCLK = %0d, fs = %.1f Hz, FREQ(La4) = %0d",
                 1.0e6 / T_CLK, CICLOS_BCLK, fs, freq_la);

        // Caso 1 (T0): reset, las salidas I2S quedan en reposo
        repeat (4) @(posedge clk);
        comprobar({audio_bclk, audio_lrclk, audio_din} == 3'b000, "reposo durante el reset");
        @(negedge clk); rst = 0;

        // Caso 2 (T7, T8): registros, escritura, lectura y dirección sin uso
        escribir(4'h0, freq_la);          // La4
        escribir(4'h4, 32'd64);
        escribir(4'h8, 32'd1);
        escribir(4'hC, 32'hFFFF_FFFF);    // se ignora
        leer(4'h0, dato); comprobar(dato == freq_la, "lectura de FREQ");
        leer(4'h4, dato); comprobar(dato == 32'd64,  "lectura de VOL");
        leer(4'h8, dato); comprobar(dato == 32'd1,   "lectura de CONTROL");
        leer(4'hC, dato); comprobar(dato == 32'd0,   "direccion sin uso se lee 0");

        // Caso 4 (T3, T4): tono de 440 Hz, muestras de +64 o -64 y frecuencia medida
        // (el caso 3, tiempos con T1, T2, T5 y T6, se comprueba en cada flanco durante toda la simulación)
        esperar_tramas(2);
        $dumpoff;                         // el tramo largo no se guarda: el VCD queda pequeño
        subidas = 0; t_primera = 0; t_ultima = 0; m_antes = 0;
        for (k = 0; k < 1200; k = k + 1) begin
            esperar_tramas(1);
            revisar_trama(m);
            comprobar(m == 8'sd64 || m == -8'sd64, "muestra de +64 o -64");
            if (m_antes == -8'sd64 && m == 8'sd64) begin     // subida de la onda: se mide el instante
                if (subidas == 0) t_primera = $realtime;
                t_ultima = $realtime;
                subidas = subidas + 1;
            end
            m_antes = m;
        end
        // Frecuencia medida en segundos (tiempo de simulación), comparada con 440 Hz reales:
        // así un FREQ calculado para otro reloj se detecta.
        f_medida = (subidas - 1) * 1.0e12 / (t_ultima - t_primera);
        $display("   tono: %0d periodos en %.3f ms, f = %.2f Hz (440 Hz pedidos; con FREQ = %0d da %.2f Hz)",
                 subidas - 1, (t_ultima - t_primera) / 1.0e9, f_medida, freq_la, f_esperada);
        comprobar(f_medida > 439.0 && f_medida < 441.0, "frecuencia del La4 a menos de 1 Hz de 440 Hz");
        $dumpon;

        // Caso 5 (T3): borde, VOL máximo y FREQ = 32768 (la muestra alterna en cada trama)
        escribir(4'h4, 32'd127);
        escribir(4'h0, 32'd32768);
        esperar_tramas(2);
        revisar_trama(m_antes);
        for (k = 0; k < 6; k = k + 1) begin
            esperar_tramas(1);
            revisar_trama(m);
            comprobar(m == -m_antes, "con FREQ = 32768 la muestra alterna cada trama");
            comprobar(m == 8'sd127 || m == -8'sd127, "muestra de +127 o -127");
            m_antes = m;
        end

        // Caso 6 (T7, T3): silencio, ENABLE = 0 deja DIN en 0
        escribir(4'h8, 32'd0);
        esperar_tramas(2);
        for (k = 0; k < 4; k = k + 1) begin
            esperar_tramas(1);
            comprobar(palabra_izq == 16'd0 && palabra_der == 16'd0, "ENABLE = 0: DIN en 0");
        end

        // Caso 7 (T0): reset en plena trama, las salidas vuelven al reposo
        @(negedge clk); rst = 1;
        repeat (3) @(posedge clk);
        #1 comprobar({audio_bclk, audio_lrclk, audio_din} == 3'b000, "reposo tras reset en plena trama");
        @(negedge clk); rst = 0;
        repeat (40) @(posedge clk);

        $display("   cobertura del ASMD (veces que se ejecutó cada transferencia):");
        for (ti = 0; ti <= 8; ti = ti + 1) begin
            $display("     T%0d: %0d", ti, cuenta_t[ti]);
            comprobar(cuenta_t[ti] > 0, "toda transferencia del ASMD se ejecuta al menos una vez");
        end
        $display("== Resultado: %0d comprobaciones bien, %0d fallan", bien, mal);
        if (mal == 0) $display("== PASA");
        else          $display("== NO PASA");
        $finish;
    end
endmodule
