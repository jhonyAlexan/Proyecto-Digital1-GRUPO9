// top_joystick_tangnano9k: prueba del lado FPGA del mando en la Tang Nano 9K.
// La FPGA le pide la lectura a la ESP32 cada 10 ms y guarda X en 0x0042 e Y en 0x0043.
// Los LEDs muestran lo recibido, para probar sin el módulo de comunicaciones:
//   LED 0: X > +32 (derecha)   LED 1: X < -32 (izquierda)
//   LED 2: Y > +32             LED 3: Y < -32
//   LED 4: botón presionado    LED 5: comunicación con la ESP32 funcionando
module top_joystick_tangnano9k (
    input  wire       clk,       // 27 MHz (pin 52)
    input  wire       btn_s1,    // S1, reset: vale 0 al presionar (pin 4)
    input  wire       uart_rx,   // desde GPIO17 (TX2) de la ESP32 (pin 28)
    output wire       uart_tx,   // hacia GPIO16 (RX2) de la ESP32 (pin 29)
    output wire [5:0] led        // LEDs de la tarjeta: 0 = encendido
);
    // ------------------------------------------------------------------ reset
    // rst vale 1 durante 16 ciclos al encender y mientras S1 esté presionado.
    reg [1:0] s1_sync  = 2'b11;
    reg [3:0] arranque = 4'd0;
    reg       rst      = 1'b1;

    always @(posedge clk) begin
        s1_sync <= {s1_sync[0], btn_s1};
        if (!s1_sync[1]) begin
            arranque <= 4'd0;
            rst      <= 1'b1;
        end else if (arranque != 4'd15) begin
            arranque <= arranque + 1'b1;
            rst      <= 1'b1;
        end else begin
            rst      <= 1'b0;
        end
    end

    // ------------------------------------------------------------------ mando
    wire [7:0] eje_x, eje_y;
    wire       boton, comunicacion_ok;

    joystick_mando #(.CLK_HZ(27_000_000)) u_mando (
        .clk(clk), .rst(rst), .uart_rx(uart_rx), .uart_tx(uart_tx),
        .dir(16'h0000), .leer(1'b0), .dato(), .listo(),   // el módulo de comunicaciones va aquí
        .eje_x(eje_x), .eje_y(eje_y), .boton(boton), .nuevo_dato(),
        .comunicacion_ok(comunicacion_ok), .checksum_error()
    );

    // ------------------------------------------------------------------ LEDs
    // Los ejes son de 8 bits con signo: se comparan como números con signo.
    wire derecha   = ($signed(eje_x) >  8'sd32);
    wire izquierda = ($signed(eje_x) < -8'sd32);
    wire arriba    = ($signed(eje_y) >  8'sd32);
    wire abajo     = ($signed(eje_y) < -8'sd32);

    assign led = ~{comunicacion_ok, boton, abajo, arriba, izquierda, derecha};
endmodule
