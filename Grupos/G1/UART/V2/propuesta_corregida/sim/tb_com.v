`timescale 1ns/1ps
// Prueba del top com: se golpea uart_rx a mano con la trama del G5 (como la ESP32)
module tb_com;
    reg clk = 0, btn = 1, rx = 1;
    always #18.518 clk = ~clk;                       // 27 MHz

    wire [5:0] led;
    com #(.CICLOS_LED(200_000)) dut (.clk(clk), .btn_rst_n(btn), .uart_rx(rx), .led(led));

    integer fallos = 0;

    task byte_tx(input [7:0] b);
        integer i;
        begin
            rx = 0;                  repeat (234) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i];           repeat (234) @(posedge clk);
            end
            rx = 1;                  repeat (234) @(posedge clk);
        end
    endtask

    // AA, jugador, secuencia, X, Y, shield, punch, XOR(1..6); chk_ok = 0 lo daña
    task trama(input [7:0] jug, seq, tx_, ty, sh, pu, input chk_ok);
        reg [7:0] c;
        begin
            c = jug ^ seq ^ tx_ ^ ty ^ sh ^ pu;
            byte_tx(8'hAA); byte_tx(jug); byte_tx(seq); byte_tx(tx_);
            byte_tx(ty); byte_tx(sh); byte_tx(pu); byte_tx(chk_ok ? c : ~c);
            repeat (10) @(posedge clk);
        end
    endtask

    task check(input [255:0] nombre, input [15:0] obtenido, input [15:0] esperado);
        begin
            if (obtenido !== esperado) begin
                $display("FALLO %0s: obtenido %h, esperado %h", nombre, obtenido, esperado);
                fallos = fallos + 1;
            end else $display("ok    %0s = %h", nombre, obtenido);
        end
    endtask

    initial begin
        #4_000_000;                                  // reset automático al energizar
        $display("--- tras el reset: LEDs apagados ---");
        check("led", led, 6'b111111);

        $display("--- P1 X = +126 ---");
        trama(8'd1, 8'd0, 8'h7E, 8'h00, 8'd0, 8'd0, 1'b1);
        check("p1_x", dut.p1_x, 8'h7E);
        check("led[5] joy_activo", led[5], 1'b0);
        check("led[2] trama valida", led[2], 1'b0);

        $display("--- P2 Punch = 1, Shield = 1 ---");
        trama(8'd2, 8'd1, 8'h00, 8'h00, 8'd1, 8'd1, 1'b1);
        check("p2_punch", dut.p2_punch, 1'b1);
        check("p2_shield", dut.p2_shield, 1'b1);
        check("led[1]", led[1], 1'b0);

        $display("--- jugador invalido (5) ---");
        trama(8'd5, 8'd2, 8'h01, 8'h01, 8'd0, 8'd1, 1'b1);
        check("led[3] dir_err", led[3], 1'b0);

        $display("--- checksum malo ---");
        trama(8'd1, 8'd3, 8'h00, 8'h00, 8'd0, 8'd1, 1'b0);
        check("p1_punch (ignorado)", dut.p1_punch, 1'b0);
        check("led[4] val_err", led[4], 1'b0);

        $display("--- reset por boton ---");
        btn = 0; #1000; btn = 1; #1000;
        check("p1_x tras reset", dut.p1_x, 8'h00);
        check("p2_punch tras reset", dut.p2_punch, 1'b0);

        if (fallos == 0) $display("\nTODO OK");
        else             $display("\n%0d FALLOS", fallos);
        $finish;
    end
endmodule
