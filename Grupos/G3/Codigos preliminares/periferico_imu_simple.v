module periferico_imu_simple (
    input  wire        clk,       // Reloj 27 MHz del sistema
    input  wire        resetn,    // Reset activo en bajo

    // Interfaz hacia el bus de memoria del FemtoRV
    input  wire        sel,       // 1 cuando el procesador lee la dirección de este módulo
    output wire [31:0] rdata,     // Dato de 32 bits hacia el procesador (Bit 0 = golpe)

    // Pines físicos hacia el sensor BMI160
    output wire        sclk,
    output wire        mosi,
    input  wire        miso,
    output wire        cs_n,

    // Salida física directa de 1 bit (Pin 29) y LEDs testigo
    output wire        golpe_bit,
    output wire [5:0]  leds
);

    wire golpe_detectado;

    // Instancia tu diseño principal ya probado (SPI + Detector de golpe)
    top u_imu (
        .clk(clk),
        .btn_rst(resetn),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .cs_n(cs_n),
        .golpe_out(golpe_detectado),
        .uart_tx(),               // Desconectado en el SoC porque el FemtoRV usa su propio UART
        .leds(leds)
    );

    // Entrega 1 solo bit útil (Bit 0) en el bus de lectura del procesador
    assign rdata     = sel ? {31'd0, golpe_detectado} : 32'd0;
    assign golpe_bit = golpe_detectado;

endmodule
