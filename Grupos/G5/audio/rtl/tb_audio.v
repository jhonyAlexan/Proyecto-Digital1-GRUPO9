// tb_audio: testbench de peripheral_audio. Comprueba los criterios de la sección 2.5.
// Simula con clk = 25 MHz y CICLOS_BCLK = 16. Escribe tb_audio.vcd para GTKWave.
`timescale 1ns / 1ps

module tb_audio;
    localparam CICLOS_BCLK = 16;
    localparam T_CLK       = 40;                     // 25 MHz
    localparam T_BCLK      = CICLOS_BCLK * T_CLK;    // 640 ns
    localparam T_TRAMA     = 32 * T_BCLK;            // 20 480 ns

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
                $display("  FALLA  t=%0t ns  %0s", $time, texto);
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
    integer           k, subidas, primera, ultima;
    real              tramas_por_periodo, f_medida;

    initial begin
        $dumpfile("tb_audio.vcd");
        $dumpvars(0, tb_audio);
        $display("== tb_audio: clk = 25 MHz, CICLOS_BCLK = %0d", CICLOS_BCLK);

        // 1. Reset: las salidas I2S quedan en reposo
        repeat (4) @(posedge clk);
        comprobar({audio_bclk, audio_lrclk, audio_din} == 3'b000, "reposo durante el reset");
        @(negedge clk); rst = 0;

        // 2. Registros: escritura, lectura y dirección sin uso
        escribir(4'h0, 32'd591);          // La4 = 440,33 Hz
        escribir(4'h4, 32'd64);
        escribir(4'h8, 32'd1);
        escribir(4'hC, 32'hFFFF_FFFF);    // se ignora
        leer(4'h0, dato); comprobar(dato == 32'd591, "lectura de FREQ");
        leer(4'h4, dato); comprobar(dato == 32'd64,  "lectura de VOL");
        leer(4'h8, dato); comprobar(dato == 32'd1,   "lectura de CONTROL");
        leer(4'hC, dato); comprobar(dato == 32'd0,   "direccion sin uso se lee 0");

        // 3. Tono de 440 Hz: muestras de +64 o -64 y frecuencia medida
        esperar_tramas(2);
        $dumpoff;                         // el tramo largo no se guarda: el VCD queda pequeño
        subidas = 0; primera = 0; ultima = 0; m_antes = 0;
        for (k = 0; k < 1200; k = k + 1) begin
            esperar_tramas(1);
            revisar_trama(m);
            comprobar(m == 8'sd64 || m == -8'sd64, "muestra de +64 o -64");
            if (m_antes == -8'sd64 && m == 8'sd64) begin
                if (subidas == 0) primera = k;
                ultima = k;
                subidas = subidas + 1;
            end
            m_antes = m;
        end
        tramas_por_periodo = (ultima - primera) * 1.0 / (subidas - 1);
        f_medida = 48828.125 / tramas_por_periodo;
        $display("   tono: %0d periodos, %.2f tramas por periodo, f = %.2f Hz (esperado 440,33 Hz)",
                 subidas - 1, tramas_por_periodo, f_medida);
        comprobar(f_medida > 439.0 && f_medida < 441.7, "frecuencia de 440,33 Hz");
        $dumpon;

        // 4. Caso de borde: VOL máximo y FREQ = 32768 (la muestra alterna en cada trama)
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

        // 5. Silencio: ENABLE = 0 deja DIN en 0
        escribir(4'h8, 32'd0);
        esperar_tramas(2);
        for (k = 0; k < 4; k = k + 1) begin
            esperar_tramas(1);
            comprobar(palabra_izq == 16'd0 && palabra_der == 16'd0, "ENABLE = 0: DIN en 0");
        end

        // 6. Reset en plena trama: las salidas vuelven al reposo
        @(negedge clk); rst = 1;
        repeat (3) @(posedge clk);
        #1 comprobar({audio_bclk, audio_lrclk, audio_din} == 3'b000, "reposo tras reset en plena trama");
        @(negedge clk); rst = 0;
        repeat (40) @(posedge clk);

        $display("== Resultado: %0d comprobaciones bien, %0d fallan", bien, mal);
        if (mal == 0) $display("== PASA");
        else          $display("== NO PASA");
        $finish;
    end
endmodule
