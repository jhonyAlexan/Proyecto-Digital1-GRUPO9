// =============================================================================
// G1 - Comunicacion | tb_perip_mandos_filas.v
// Testbench del periferico de mandos (peripheral_mandos) POR EL BUS DEL SoC.
//
// Cada comprobacion cita la fila de la tabla de transferencias (README §6):
//   R0..R11  receptor UART 8N1        (uart_8n1, parte RX)
//   D0..D11  desempaquetador de trama (desempaquetador)
//   B0..B9   adaptador de bus / STATUS (perip_mandos)
// Ademas, el banco CUENTA cuantas veces se ejecuta cada fila. Si alguna fila
// queda en 0, la prueba falla: asi se demuestra que el banco recorre todo el
// ASMD y no solo "el caso feliz".
//
// Reloj: CLK_HZ (27 MHz por defecto). Para la placa del G4 (25 MHz):
//   make filas25   (compila con -DCLK25)
// =============================================================================
`timescale 1ns/1ps
module tb_perip_mandos_filas;

`ifdef CLK25
    localparam integer CLK_HZ = 25_000_000;
`else
    localparam integer CLK_HZ = 27_000_000;
`endif
    localparam integer BAUD = 115_200;
    localparam integer CPB  = CLK_HZ / BAUD;          // 234 (27 MHz) / 217 (25 MHz)
    localparam integer HALF = CPB / 2;
    localparam integer TMAX = CLK_HZ / 1000;          // 1 ms
    localparam real    TCLK = 1.0e9 / CLK_HZ;
    localparam real    TBIT0 = 1.0e9 / BAUD;

    // ------------------------------------------------------------------ DUT --
    reg         clk = 1'b0, reset = 1'b1, cs = 1'b0, rd = 1'b0, wr = 1'b0;
    reg  [31:0] addr = 32'h0047_0000, d_in = 32'h0;
    reg         uart_rx = 1'b1;
    wire [31:0] d_out, joy1, joy2;
    wire [3:0]  status;

    always #(TCLK/2) clk = ~clk;

    peripheral_mandos #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (
        .clk(clk), .reset(reset), .d_in(d_in), .cs(cs), .addr(addr),
        .rd(rd), .wr(wr), .d_out(d_out), .uart_rx(uart_rx),
        .joy1_data(joy1), .joy2_data(joy2), .status(status));

    // ------------------------------------------------- contadores por fila --
    integer nR[0:11], nD[0:11], nB[0:9];
    integer i;
    initial for (i = 0; i < 12; i = i + 1) begin nR[i] = 0; nD[i] = 0; if (i < 10) nB[i] = 0; end

    // Alias de senales internas (valores ANTES del flanco: los NBA aun no se aplican)
    wire [2:0] rs   = dut.u_uart.r_state;
    wire [8:0] rc   = dut.u_uart.r_cnt;
    wire [2:0] ri   = dut.u_uart.r_idx;
    wire       rin  = dut.u_uart.rx_in;
    wire [1:0] ds   = dut.des.state;
    wire [2:0] di   = dut.des.idx;
    wire       rv   = dut.des.rx_valid;
    wire       rfe  = dut.des.rx_frame_err;
    wire [7:0] rdat = dut.des.rx_data;
    wire [7:0] xl   = dut.des.xor_l;
    wire [7:0] jl   = dut.des.jug_l;
    wire [31:0] esp = dut.des.espera;

    always @(posedge clk) begin
        if (reset) begin nR[0] = nR[0] + 1; nD[0] = nD[0] + 1; nB[0] = nB[0] + 1; end
        else begin
            // ---- R: receptor UART ----
            nR[1] = nR[1] + 1;                                              // R1 sincronizador
            case (rs)
                3'd0: nR[2] = nR[2] + 1;                                    // R2 IDLE
                3'd1: if (rc != HALF-1) nR[3] = nR[3] + 1;                  // R3
                      else if (!rin)    nR[4] = nR[4] + 1;                  // R4 start OK
                      else              nR[5] = nR[5] + 1;                  // R5 glitch
                3'd2: if (rc != CPB-1)  nR[6] = nR[6] + 1;                  // R6
                      else if (ri != 7) nR[7] = nR[7] + 1;                  // R7 bit 0..6
                      else              nR[8] = nR[8] + 1;                  // R8 bit 7
                3'd3: if (rc != CPB-1)  nR[6] = nR[6] + 1;                  // R6 (en STOP)
                      else if (rin)     nR[9] = nR[9] + 1;                  // R9 byte OK
                      else              nR[10] = nR[10] + 1;                // R10 stop = 0
                3'd4: if (rin)          nR[11] = nR[11] + 1;                // R11 ESPERA -> IDLE
            endcase
            // ---- D: desempaquetador ----
            if (rfe) nD[1] = nD[1] + 1;                                     // D1
            else if (rv) begin
                case (ds)
                    2'd0: if (rdat == 8'hAA) nD[2] = nD[2] + 1;             // D2 cabecera
                          else               nD[3] = nD[3] + 1;             // D3 basura
                    2'd1: if (di != 3'd6)    nD[4] = nD[4] + 1;             // D4 bytes 1..5
                          else               nD[5] = nD[5] + 1;             // D5 byte 6
                    2'd2: if (rdat != xl)    nD[6] = nD[6] + 1;             // D6 checksum malo
                          else if (jl == 1)  nD[7] = nD[7] + 1;             // D7 publica J1
                          else if (jl == 2)  nD[8] = nD[8] + 1;             // D8 publica J2
                          else               nD[9] = nD[9] + 1;             // D9 jugador malo
                endcase
            end else if (ds != 2'd0) begin
                if (esp != TMAX-1) nD[10] = nD[10] + 1;                     // D10 espera++
                else               nD[11] = nD[11] + 1;                     // D11 plazo vencido
            end
            // ---- B: adaptador de bus y STATUS ----
            if (dut.p1_nuevo)     nB[1] = nB[1] + 1;                        // B1
            if (dut.p2_nuevo)     nB[2] = nB[2] + 1;                        // B2
            if (dut.rx_frame_err) nB[3] = nB[3] + 1;                        // B3
            if (dut.val_err)      nB[4] = nB[4] + 1;                        // B4
            if (cs && rd) case (addr[3:0])
                4'h0: nB[5] = nB[5] + 1;                                    // B5
                4'h4: nB[6] = nB[6] + 1;                                    // B6
                4'h8: nB[7] = nB[7] + 1;                                    // B7
                default: nB[8] = nB[8] + 1;                                 // B8
            endcase
            else nB[9] = nB[9] + 1;                                         // B9 d_out se mantiene
        end
    end

    // -------------------------------------------------- tareas (la ESP32) --
    real tbit = TBIT0;
    task enviar_byte(input [7:0] b, input stop);
        integer k;
        begin
            uart_rx = 1'b0;          #(tbit);
            for (k = 0; k < 8; k = k + 1) begin uart_rx = b[k]; #(tbit); end
            uart_rx = stop;          #(tbit);
            uart_rx = 1'b1;
        end
    endtask

    task enviar_trama(input [7:0] jug, seq, x, y, sh, pu);
        begin
            enviar_byte(8'hAA, 1); enviar_byte(jug, 1); enviar_byte(seq, 1);
            enviar_byte(x, 1);     enviar_byte(y, 1);   enviar_byte(sh, 1);
            enviar_byte(pu, 1);    enviar_byte(jug ^ seq ^ x ^ y ^ sh ^ pu, 1);
            #(2*TBIT0);
        end
    endtask

    // Lectura como la hace el FemtoRV: cs y rd un ciclo, d_out en el flanco siguiente
    task leer(input [3:0] off, output [31:0] dato);
        begin
            @(negedge clk); addr = 32'h0047_0000 | off; cs = 1; rd = 1;
            @(negedge clk); cs = 0; rd = 0;           // d_out se capturo en el flanco intermedio
            dato = d_out;
        end
    endtask

    task escribir(input [3:0] off, input [31:0] v);
        begin
            @(negedge clk); addr = 32'h0047_0000 | off; cs = 1; wr = 1; d_in = v;
            @(negedge clk); cs = 0; wr = 0;
        end
    endtask

    integer fallos = 0, pruebas = 0;
    task check(input [8*48-1:0] fila, input [31:0] obtenido, input [31:0] esperado);
        begin
            pruebas = pruebas + 1;
            if (obtenido !== esperado) begin
                fallos = fallos + 1;
                $display("FALLA [%0s] obtenido %h esperado %h", fila, obtenido, esperado);
            end else
                $display("ok    [%0s] = %h", fila, obtenido);
        end
    endtask

    reg [31:0] v, antes;
    initial begin
        $dumpfile("tb_perip_mandos_filas.vcd");
        $dumpvars(0, tb_perip_mandos_filas);
        $display("Reloj %0d Hz, %0d ciclos por bit", CLK_HZ, CPB);

        #(20*TCLK) reset = 1'b0;
        #(3*TBIT0);

        $display("--- C0 reset: registros y STATUS en 0 ---");
        leer(4'h0, v); check("R0 D0 B0 B5 JOY1 tras reset", v, 32'h0);
        leer(4'h8, v); check("B0 B7 STATUS tras reset", v, 32'h0);

        $display("--- C1 trama J1: seq 0x11, X -100, Y +50, shield 1, punch 0 ---");
        enviar_trama(8'd1, 8'h11, 8'h9C, 8'h32, 8'd1, 8'd0);
        leer(4'h0, v); check("R2-R9 D2 D4 D5 D7 B5 JOY1", v, 32'h11_01_32_9C);
        leer(4'h8, v); check("B1 B7 STATUS = P1_VALID", v, 32'h1);

        $display("--- C2 trama J2: seq 200, X +127, Y -127, shield 0, punch 1 ---");
        enviar_trama(8'd2, 8'd200, 8'h7F, 8'h81, 8'd0, 8'd1);
        leer(4'h4, v); check("D8 B6 JOY2", v, 32'hC8_02_81_7F);
        leer(4'h8, v); check("B2 B7 STATUS = P1|P2_VALID", v, 32'h3);

        $display("--- C3 basura antes de la cabecera ---");
        enviar_byte(8'h55, 1); enviar_byte(8'h00, 1);
        enviar_trama(8'd1, 8'h12, 8'h05, 8'hFB, 8'd0, 8'd1);
        leer(4'h0, v); check("D3 basura ignorada, JOY1", v, 32'h12_02_FB_05);

        $display("--- C4 0xAA dentro de los datos (X = 0xAA) ---");
        enviar_trama(8'd1, 8'h13, 8'hAA, 8'h00, 8'd1, 8'd1);
        leer(4'h0, v); check("D4 por posicion, JOY1", v, 32'h13_03_00_AA);

        $display("--- C5 checksum malo ---");
        antes = joy1;
        enviar_byte(8'hAA,1); enviar_byte(8'd1,1); enviar_byte(8'h14,1); enviar_byte(8'h10,1);
        enviar_byte(8'h20,1); enviar_byte(8'd0,1); enviar_byte(8'd0,1); enviar_byte(8'h00,1);
        #(2*TBIT0);
        leer(4'h0, v); check("D6 JOY1 no cambia", v, antes);
        leer(4'h8, v); check("B4 STATUS CHECKSUM_ERROR", v, 32'hB);

        $display("--- C6 jugador 3 (checksum correcto) ---");
        enviar_trama(8'd3, 8'h15, 8'h01, 8'h02, 8'd0, 8'd0);
        leer(4'h0, v); check("D9 JOY1 no cambia", v, antes);
        leer(4'h4, v); check("D9 JOY2 no cambia", v, 32'hC8_02_81_7F);

        $display("--- C7 trama cortada (3 bytes) + 1,5 ms de silencio ---");
        enviar_byte(8'hAA,1); enviar_byte(8'd2,1); enviar_byte(8'h16,1);
        #(1_500_000);
        enviar_trama(8'd2, 8'h17, 8'h11, 8'h22, 8'd1, 8'd0);
        leer(4'h4, v); check("D10 D11 resincroniza, JOY2", v, 32'h17_01_22_11);

        $display("--- C8 byte con stop = 0 a mitad de trama ---");
        enviar_byte(8'hAA,1); enviar_byte(8'd1,1); enviar_byte(8'h18,0);
        uart_rx = 1'b0; #(3*TBIT0); uart_rx = 1'b1; #(2*TBIT0);   // linea pegada en 0
        enviar_trama(8'd1, 8'h19, 8'hF0, 8'h0F, 8'd0, 8'd0);
        leer(4'h0, v); check("R10 R11 D1 JOY1 tras error", v, 32'h19_00_0F_F0);
        leer(4'h8, v); check("B3 STATUS UART_ERROR", v, 32'hF);

        $display("--- C9 glitch de 1 us en reposo ---");
        uart_rx = 1'b0; #1000; uart_rx = 1'b1; #(3*TBIT0);
        enviar_trama(8'd1, 8'h1A, 8'h01, 8'h01, 8'd0, 8'd0);
        leer(4'h0, v); check("R5 glitch ignorado, JOY1", v, 32'h1A_00_01_01);

        $display("--- C10 offset reservado y escritura ---");
        leer(4'hC, v); check("B8 offset 0xC lee 0", v, 32'h0);
        escribir(4'h0, 32'hDEAD_BEEF);
        leer(4'h0, v); check("B9 escritura ignorada", v, 32'h1A_00_01_01);

        $display("--- C11 reloj de la ESP32 +2 %% y -2 %% ---");
        tbit = TBIT0 * 1.02;
        enviar_trama(8'd2, 8'h1B, 8'h40, 8'hC0, 8'd1, 8'd1);
        leer(4'h4, v); check("R7 R8 baud +2%, JOY2", v, 32'h1B_03_C0_40);
        tbit = TBIT0 * 0.98;
        enviar_trama(8'd2, 8'h1C, 8'hC0, 8'h40, 8'd0, 8'd0);
        leer(4'h4, v); check("R7 R8 baud -2%, JOY2", v, 32'h1C_00_40_C0);
        tbit = TBIT0;

        $display("--- C12 reset en mitad de una trama ---");
        enviar_byte(8'hAA,1); enviar_byte(8'd1,1);
        @(negedge clk) reset = 1'b1; #(5*TCLK); @(negedge clk) reset = 1'b0;
        leer(4'h0, v); check("R0 D0 JOY1 en 0", v, 32'h0);
        leer(4'h8, v); check("B0 STATUS en 0", v, 32'h0);
        #(10*TBIT0);
        enviar_trama(8'd1, 8'h1D, 8'h7F, 8'h7F, 8'd1, 8'd1);
        leer(4'h0, v); check("D2..D7 tras reset, JOY1", v, 32'h1D_03_7F_7F);

        // ------------------------------------------- cobertura por fila --
        $display("\nCobertura de la tabla de transferencias (veces que se ejecuto cada fila):");
        for (i = 0; i < 12; i = i + 1) begin
            $display("  R%0d = %0d", i, nR[i]);
            if (nR[i] == 0) begin fallos = fallos + 1; $display("  FALLA: fila R%0d nunca se ejecuto", i); end
        end
        for (i = 0; i < 12; i = i + 1) begin
            $display("  D%0d = %0d", i, nD[i]);
            if (nD[i] == 0) begin fallos = fallos + 1; $display("  FALLA: fila D%0d nunca se ejecuto", i); end
        end
        for (i = 0; i < 10; i = i + 1) begin
            $display("  B%0d = %0d", i, nB[i]);
            if (nB[i] == 0) begin fallos = fallos + 1; $display("  FALLA: fila B%0d nunca se ejecuto", i); end
        end

        if (fallos == 0) $display("\nRESULTADO: TODO OK (%0d comprobaciones, 34 filas cubiertas)", pruebas);
        else             $display("\nRESULTADO: %0d FALLA(S)", fallos);
        $finish;
    end
endmodule
