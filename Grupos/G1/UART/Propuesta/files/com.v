// -----------------------------------------------------------------------------
// com.v — TOP del mando UART para la Tang Nano 9K (reloj de 27 MHz)
//
//   ESP32 --UART 115200 8N1--> uart_rx --> uart_8n1 --> desempaquetador
//                                                       --> registros P1 / P2
//
// Esta FPGA solo RECIBE: el ESP32 arma los bytes {PER_addr, jugador} + valor.
// (El empaquetador no se instancia aquí; la rama TX de uart_8n1 queda sin usar.)
//
// LEDs (activos en BAJO en la placa; aquí se invierten una sola vez):
//   led[0] = p1_punch                 led[3] = dir_err  (100 ms)
//   led[1] = p2_punch                 led[4] = val_err o error de trama (100 ms)
//   led[2] = byte recibido (100 ms)   led[5] = algún eje X/Y de P1 o P2 distinto de 0
//
// Reset: botón (activo en bajo) y además un reset automático al energizar.
// -----------------------------------------------------------------------------
module com #(
    parameter CLK_HZ     = 27_000_000,
    parameter BAUD       = 115_200,
    parameter CICLOS_LED = 2_700_000        // 100 ms a 27 MHz
)(
    input  wire       clk,
    input  wire       btn_rst_n,            // botón, activo en bajo
    input  wire       uart_rx,              // desde el TX del ESP32
    output wire [5:0] led                   // activos en bajo
);
    // ------------------------- Reset ------------------------------------------
    reg [15:0] por = 16'd0;                 // ~2,4 ms tras energizar
    wire       por_listo = &por;
    always @(posedge clk) if (!por_listo) por <= por + 1'b1;

    wire rst_in_n = btn_rst_n & por_listo;
    reg  [1:0] rst_sh = 2'b00;              // suelta el reset de forma síncrona
    always @(posedge clk or negedge rst_in_n) begin
        if (!rst_in_n) rst_sh <= 2'b00;
        else           rst_sh <= {rst_sh[0], 1'b1};
    end
    wire rst_n = rst_sh[1];

    // ------------------------- UART + desempaquetador -------------------------
    wire [7:0] rx_data;
    wire       rx_valid, rx_frame_err;

    uart_8n1 #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
        .clk(clk), .rst_n(rst_n),
        .tx_data(8'd0), .tx_start(1'b0), .tx(), .tx_busy(),
        .rx(uart_rx), .rx_data(rx_data), .rx_valid(rx_valid),
        .rx_frame_err(rx_frame_err));

    wire [7:0] p1_x, p1_y, p2_x, p2_y;
    wire       p1_punch, p2_punch, dir_err, val_err;

    desempaquetador des (
        .clk(clk), .rst_n(rst_n),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .p1_x(p1_x), .p1_y(p1_y), .p1_punch(p1_punch),
        .p2_x(p2_x), .p2_y(p2_y), .p2_punch(p2_punch),
        .dir_err(dir_err), .val_err(val_err));

    // ------------------------- LEDs -------------------------------------------
    wire rx_led, dir_led, err_led;
    com_pulso #(.CICLOS(CICLOS_LED)) s_rx  (.clk(clk), .rst_n(rst_n), .pulso(rx_valid),                .activo(rx_led));
    com_pulso #(.CICLOS(CICLOS_LED)) s_dir (.clk(clk), .rst_n(rst_n), .pulso(dir_err),                 .activo(dir_led));
    com_pulso #(.CICLOS(CICLOS_LED)) s_err (.clk(clk), .rst_n(rst_n), .pulso(val_err | rx_frame_err),  .activo(err_led));

    wire joy_activo = |{p1_x, p1_y, p2_x, p2_y};

    assign led = ~{joy_activo, err_led, dir_led, rx_led, p2_punch, p1_punch};
endmodule

// Alarga un pulso de 1 ciclo para que el LED se alcance a ver
module com_pulso #(
    parameter CICLOS = 2_700_000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire pulso,
    output wire activo
);
    reg [$clog2(CICLOS+1)-1:0] cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          cnt <= 0;
        else if (pulso)      cnt <= CICLOS;
        else if (cnt != 0)   cnt <= cnt - 1'b1;
    end
    assign activo = (cnt != 0);
endmodule
