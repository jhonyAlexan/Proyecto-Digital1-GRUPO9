`timescale 1ns/1ps
// Lazo cerrado: empaquetador -> uart_8n1 (TX) -> cable -> uart_8n1 (RX) -> desempaquetador
module tb_ctrl;
    reg clk = 0, rst_n = 0;
    always #18.518 clk = ~clk;                 // 27 MHz

    // Mando del jugador 2
    reg  [7:0] x = 8'hA5, y = 8'h3C;
    reg        punch = 1'b1;

    wire [7:0] tx_data;  wire tx_start, tx_busy, linea;
    wire [7:0] rx_data;  wire rx_valid, rx_ferr;

    empaquetador #(.SOLO_CAMBIOS(0)) emp (
        .clk(clk), .rst_n(rst_n), .jugador(4'h2),
        .x(x), .y(y), .punch(punch),
        .tx_data(tx_data), .tx_start(tx_start), .tx_busy(tx_busy));

    uart_8n1 u_tx (
        .clk(clk), .rst_n(rst_n),
        .tx_data(tx_data), .tx_start(tx_start), .tx(linea), .tx_busy(tx_busy),
        .rx(1'b1), .rx_data(), .rx_valid(), .rx_frame_err());

    uart_8n1 u_rx (
        .clk(clk), .rst_n(rst_n),
        .tx_data(8'd0), .tx_start(1'b0), .tx(), .tx_busy(),
        .rx(linea), .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_ferr));

    wire [7:0] p1_x, p1_y, p2_x, p2_y;
    wire       p1_punch, p2_punch, dir_err, val_err;

    desempaquetador des (
        .clk(clk), .rst_n(rst_n), .rx_data(rx_data), .rx_valid(rx_valid),
        .p1_x(p1_x), .p1_y(p1_y), .p1_punch(p1_punch),
        .p2_x(p2_x), .p2_y(p2_y), .p2_punch(p2_punch),
        .dir_err(dir_err), .val_err(val_err));

    // Segundo desempaquetador alimentado a mano (pruebas de error)
    reg [7:0] m_data = 0;  reg m_valid = 0;
    wire [7:0] q1_x, q1_y, q2_x, q2_y;  wire q1_p, q2_p, q_derr, q_verr;
    desempaquetador des2 (
        .clk(clk), .rst_n(rst_n), .rx_data(m_data), .rx_valid(m_valid),
        .p1_x(q1_x), .p1_y(q1_y), .p1_punch(q1_p),
        .p2_x(q2_x), .p2_y(q2_y), .p2_punch(q2_p),
        .dir_err(q_derr), .val_err(q_verr));

    integer fallos = 0, n_derr = 0, n_verr = 0;
    always @(posedge clk) if (q_derr) n_derr = n_derr + 1;
    always @(posedge clk) if (q_verr) n_verr = n_verr + 1;

    task check(input [255:0] nombre, input [15:0] obtenido, input [15:0] esperado);
        begin
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

    initial begin
        #200 rst_n = 1;

        // 1) Lazo cerrado, jugador 2
        #3_000_000;
        $display("--- lazo cerrado: P2 = (A5, 3C, 1) ---");
        check("p2_x", p2_x, 8'hA5);  check("p2_y", p2_y, 8'h3C);  check("p2_punch", p2_punch, 1'b1);
        check("p1_x (intacto)", p1_x, 8'h00);  check("p1_punch (intacto)", p1_punch, 1'b0);
        check("rx_frame_err", rx_ferr, 1'b0);

        // 2) Cambia el mando
        x = 8'h10;  y = 8'hFF;  punch = 1'b0;
        #3_000_000;
        $display("--- cambio de valores: P2 = (10, FF, 0) ---");
        check("p2_x", p2_x, 8'h10);  check("p2_y", p2_y, 8'hFF);  check("p2_punch", p2_punch, 1'b0);

        // 3) Errores, con entrada manual
        $display("--- errores ---");
        manda(8'hFF);                       // dirección inexistente
        manda(8'h11); manda(8'h7E);         // P1 X = 7E
        manda(8'h41); manda(8'h05);         // Punch con valor inválido
        manda(8'h13);                       // 0x13: un bit volteado de 0x11 / 0x12
        manda(8'h42); manda(8'h01);         // P2 Punch = 1
        check("q1_x", q1_x, 8'h7E);
        check("q1_punch (valor invalido ignorado)", q1_p, 1'b0);
        check("q2_punch", q2_p, 1'b1);
        check("dir_err (FF y 13)", n_derr, 2);
        check("val_err (punch=05)", n_verr, 1);

        if (fallos == 0) $display("\nTODO OK");
        else             $display("\n%0d FALLOS", fallos);
        $finish;
    end
endmodule
