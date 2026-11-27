`timescale 1ns/1ps
// Prueba del top com: se golpea uart_rx a mano (como lo haría el ESP32)
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

        $display("--- P1 X = 7E ---");
        byte_tx(8'h11); byte_tx(8'h7E);
        check("p1_x", dut.p1_x, 8'h7E);
        check("led[5] joy_activo", led[5], 1'b0);
        check("led[2] byte recibido", led[2], 1'b0);

        $display("--- P2 Punch = 1 ---");
        byte_tx(8'h42); byte_tx(8'h01);
        check("p2_punch", dut.p2_punch, 1'b1);
        check("led[1]", led[1], 1'b0);

        $display("--- direccion invalida 0xFF ---");
        byte_tx(8'hFF);
        check("led[3] dir_err", led[3], 1'b0);

        $display("--- Punch con valor invalido 0x05 ---");
        byte_tx(8'h41); byte_tx(8'h05);
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
