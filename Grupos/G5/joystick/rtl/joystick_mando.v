// joystick_mando: lado FPGA del mando. La FPGA le pide la lectura a la ESP32 por UART,
// recibe el paquete de 8 bytes (sección 3.2.3), lo valida y guarda X en 0x0042 e Y en 0x0043.
//
//   joystick_solicitud -> joystick_uart_tx --uart_tx--> ESP32
//   ESP32 --uart_rx--> joystick_uart_rx -> joystick_ensamblador -> joystick_registros_xy
module joystick_mando #(
    parameter integer CLK_HZ            = 27_000_000,
    parameter integer BAUD              = 115_200,
    parameter integer PERIODO_CICLOS    = CLK_HZ / 100,   // una solicitud cada 10 ms
    parameter integer MAX_SIN_RESPUESTA = 10,
    parameter [15:0]  DIR_X             = 16'h0042,
    parameter [15:0]  DIR_Y             = 16'h0043
) (
    input  wire        clk,
    input  wire        rst,
    // Cables hacia la ESP32
    input  wire        uart_rx,          // desde el TX de la ESP32
    output wire        uart_tx,          // hacia el RX de la ESP32
    // Puerto de lectura por dirección
    input  wire [15:0] dir,
    input  wire        leer,
    output wire [7:0]  dato,
    output wire        listo,
    // Valores y estado
    output wire [7:0]  eje_x,
    output wire [7:0]  eje_y,
    output wire        boton,
    output wire        nuevo_dato,       // pulso de un ciclo cuando se guarda una muestra
    output wire        comunicacion_ok,
    output wire        checksum_error
);
    wire [7:0]  rx_data;
    wire        rx_valid, rx_frame_err;
    wire [31:0] datos_muestra;
    wire        cargar_p1, cargar_p2;
    wire        tx_start, tx_ocupado;
    wire [7:0]  tx_data;

    // El mando tiene un solo joystick: se acepta el paquete del jugador 1 o del 2
    assign nuevo_dato = cargar_p1 || cargar_p2;

    joystick_solicitud #(
        .PERIODO_CICLOS(PERIODO_CICLOS), .MAX_SIN_RESPUESTA(MAX_SIN_RESPUESTA)
    ) u_solicitud (
        .clk(clk), .rst(rst), .tx_ocupado(tx_ocupado), .respuesta_valida(nuevo_dato),
        .tx_start(tx_start), .tx_data(tx_data), .comunicacion_ok(comunicacion_ok)
    );

    joystick_uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst(rst), .tx_data(tx_data), .tx_start(tx_start),
        .uart_tx(uart_tx), .tx_ocupado(tx_ocupado)
    );

    joystick_uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk), .rst(rst), .uart_rx(uart_rx),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_frame_err)
    );

    joystick_ensamblador #(.CLK_HZ(CLK_HZ)) u_ensamblador (
        .clk(clk), .rst(rst), .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_frame_err),
        .datos_muestra(datos_muestra), .cargar_p1(cargar_p1), .cargar_p2(cargar_p2),
        .checksum_error(checksum_error)
    );

    joystick_registros_xy #(.DIR_X(DIR_X), .DIR_Y(DIR_Y)) u_registros (
        .clk(clk), .rst(rst), .cargar(nuevo_dato), .datos_muestra(datos_muestra),
        .dir(dir), .leer(leer), .dato(dato), .listo(listo),
        .eje_x(eje_x), .eje_y(eje_y), .boton(boton)
    );
endmodule
