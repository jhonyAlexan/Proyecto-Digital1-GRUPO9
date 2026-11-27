`timescale 1ns/1ps
// Lazo cerrado: empaquetador -> uart_8n1 (TX) -> cable -> uart_8n1 (RX) -> desempaquetador
// Trama del G5: AA, jugador, secuencia, X, Y, shield, punch, XOR(1..6)
module tb_ctrl;
    reg clk = 0, rst_n = 0;
    always #18.518 clk = ~clk;                 // 27 MHz

    // Mando del jugador 2 (X e Y con signo)
    reg  [7:0] x = 8'h64, y = 8'hC4;           // +100, -60
    reg        punch = 1'b1, shield = 1'b0;

    wire [7:0] tx_data;  wire tx_start, tx_busy, linea;
    wire [7:0] rx_data;  wire rx_valid, rx_ferr;

    // Periodo corto para no simular 1/30 s (una trama son 8*10*234 = 18720 ciclos)
    empaquetador #(.PERIODO(25_000)) emp (
        .clk(clk), .rst_n(rst_n), .jugador(4'h2),
        .x(x), .y(y), .punch(punch), .shield(shield),
        .tx_data(tx_data), .tx_start(tx_start), .tx_busy(tx_busy));

    uart_8n1 u_tx (
        .clk(clk), .rst_n(rst_n),
        .tx_data(tx_data), .tx_start(tx_start), .tx(linea), .tx_busy(tx_busy),
        .rx(1'b1), .rx_data(), .rx_valid(), .rx_frame_err());

    uart_8n1 u_rx (
        .clk(clk), .rst_n(rst_n),
        .tx_data(8'd0), .tx_start(1'b0), .tx(), .tx_busy(),
        .rx(linea), .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_ferr));

    wire [7:0] p1_x, p1_y, p1_seq, p2_x, p2_y, p2_seq;
    wire       p1_punch, p1_shield, p2_punch, p2_shield, p1_nuevo, p2_nuevo, dir_err, val_err;

    desempaquetador des (
        .clk(clk), .rst_n(rst_n),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_ferr),
        .p1_x(p1_x), .p1_y(p1_y), .p1_punch(p1_punch), .p1_shield(p1_shield), .p1_seq(p1_seq),
        .p2_x(p2_x), .p2_y(p2_y), .p2_punch(p2_punch), .p2_shield(p2_shield), .p2_seq(p2_seq),
        .p1_nuevo(p1_nuevo), .p2_nuevo(p2_nuevo), .dir_err(dir_err), .val_err(val_err));

    // Segundo desempaquetador alimentado a mano (pruebas de error), plazo de 200 ciclos
    reg [7:0] m_data = 0;  reg m_valid = 0, m_ferr = 0;
    wire [7:0] q1_x, q1_y, q1_seq, q2_x, q2_y, q2_seq;
    wire q1_p, q1_s, q2_p, q2_s, q1_n, q2_n, q_derr, q_verr;
    desempaquetador #(.T_MAX_CICLOS(200)) des2 (
        .clk(clk), .rst_n(rst_n),
        .rx_data(m_data), .rx_valid(m_valid), .rx_frame_err(m_ferr),
        .p1_x(q1_x), .p1_y(q1_y), .p1_punch(q1_p), .p1_shield(q1_s), .p1_seq(q1_seq),
        .p2_x(q2_x), .p2_y(q2_y), .p2_punch(q2_p), .p2_shield(q2_s), .p2_seq(q2_seq),
        .p1_nuevo(q1_n), .p2_nuevo(q2_n), .dir_err(q_derr), .val_err(q_verr));

    integer fallos = 0, pruebas = 0, n_derr = 0, n_verr = 0, n_q1 = 0, n_p2 = 0;
    always @(posedge clk) begin
        if (q_derr) n_derr = n_derr + 1;
        if (q_verr) n_verr = n_verr + 1;
        if (q1_n)   n_q1   = n_q1 + 1;
        if (p2_nuevo) n_p2 = n_p2 + 1;
    end

    task check(input [255:0] nombre, input [15:0] obtenido, input [15:0] esperado);
        begin
            pruebas = pruebas + 1;
            if (obtenido !== esperado) begin
                $display("FALLO %0s: obtenido %h, esperado %h", nombre, obtenido, esperado);
                fallos = fallos + 1;
            end else $display("ok    %0s = %h", nombre, obtenido);
        end
    endtask

    task manda(input [7:0] b);
        begin
            @(posedge clk); m_data <= b; m_valid <= 1'b1;
            @(posedge clk); m_valid <= 1'b0;
            repeat (3) @(posedge clk);
        end
    endtask

    // Trama completa a mano; chk_ok = 0 manda un checksum equivocado
    task trama(input [7:0] jug, seq, tx_, ty, sh, pu, input chk_ok);
        reg [7:0] c;
        begin
            c = jug ^ seq ^ tx_ ^ ty ^ sh ^ pu;
            manda(8'hAA); manda(jug); manda(seq); manda(tx_); manda(ty);
            manda(sh); manda(pu); manda(chk_ok ? c : ~c);
        end
    endtask

    reg [7:0] seq_a;
    initial begin
        #200 rst_n = 1;

        // 1) Lazo cerrado, jugador 2
        #1_200_000;
        $display("--- lazo cerrado: P2 = (+100, -60, punch 1, shield 0) ---");
        check("p2_x", p2_x, 8'h64);  check("p2_y", p2_y, 8'hC4);
        check("p2_punch", p2_punch, 1'b1);  check("p2_shield", p2_shield, 1'b0);
        check("p1_x (intacto)", p1_x, 8'h00);  check("p1_punch (intacto)", p1_punch, 1'b0);
        check("rx_frame_err", rx_ferr, 1'b0);
        check("val_err", val_err, 1'b0);

        // 2) Cambia el mando; la secuencia debe subir
        seq_a = p2_seq;
        x = 8'h81;  y = 8'h7F;  punch = 1'b0;  shield = 1'b1;      // -127, +127
        #2_000_000;
        $display("--- cambio de valores: P2 = (-127, +127, punch 0, shield 1) ---");
        check("p2_x", p2_x, 8'h81);  check("p2_y", p2_y, 8'h7F);
        check("p2_punch", p2_punch, 1'b0);  check("p2_shield", p2_shield, 1'b1);
        check("secuencia sube", (p2_seq != seq_a), 1'b1);
        check("tramas recibidas >= 3", (n_p2 >= 3), 1'b1);

        // 3) Errores, con entrada manual
        $display("--- errores (entrada manual) ---");
        manda(8'h11); manda(8'h7E);                            // basura antes de la cabecera
        trama(8'd1, 8'd5, 8'h10, 8'hF0, 8'd1, 8'd0, 1'b1);    // P1 válida
        check("q1_x", q1_x, 8'h10);  check("q1_y", q1_y, 8'hF0);
        check("q1_shield", q1_s, 1'b1);  check("q1_seq", q1_seq, 8'd5);

        trama(8'd1, 8'd6, 8'h55, 8'h55, 8'd0, 8'd1, 1'b0);    // checksum malo
        check("q1_x (checksum malo)", q1_x, 8'h10);
        check("val_err", n_verr, 1);

        trama(8'd3, 8'd7, 8'h01, 8'h02, 8'd0, 8'd0, 1'b1);    // jugador 3
        check("dir_err (jugador 3)", n_derr, 1);

        trama(8'd2, 8'd8, 8'hAA, 8'hAA, 8'd0, 8'd1, 1'b1);    // 0xAA dentro de los datos
        check("q2_x (0xAA como dato)", q2_x, 8'hAA);  check("q2_punch", q2_p, 1'b1);

        manda(8'hAA); manda(8'd1); manda(8'd9);                // trama cortada
        repeat (300) @(posedge clk);                           // vence el plazo
        trama(8'd1, 8'd10, 8'h20, 8'h30, 8'd0, 8'd1, 1'b1);
        check("q1_x tras plazo", q1_x, 8'h20);

        manda(8'hAA); manda(8'd1);                             // trama cortada por error UART
        @(posedge clk); m_ferr <= 1'b1; @(posedge clk); m_ferr <= 1'b0;
        trama(8'd1, 8'd11, 8'h40, 8'h50, 8'd0, 8'd0, 1'b1);
        check("q1_x tras error de UART", q1_x, 8'h40);
        check("tramas validas P1", n_q1, 3);

        if (fallos == 0) $display("\nTODO OK (%0d pruebas)", pruebas);
        else             $display("\n%0d FALLOS de %0d", fallos, pruebas);
        $finish;
    end
endmodule
