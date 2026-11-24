module periferico_imu_mmio (
    input  wire        clk,
    input  wire        resetn,

    // Bus estándar según guía uart-riscv.pdf
    input  wire        cs,        // Chip select de la región (coordinar con mapa común, ej. 0x0046)
    input  wire [3:0]  addr,      // Offset local (mem_addr[5:2])
    input  wire        rd,        // Pulso de lectura del CPU
    output reg  [31:0] rdata,     // Salida registrada hacia el bus

    // Pines físicos hacia el sensor BMI160
    output wire        sclk,
    output wire        mosi,
    input  wire        miso,
    output wire        cs_n,

    // Salida física directa (Pin 29) y LEDs testigo
    output wire        golpe_pin,
    output wire [5:0]  leds
);

    wire golpe_detectado;

    top u_imu (
        .clk(clk),
        .btn_rst(resetn),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .cs_n(cs_n),
        .golpe_out(golpe_detectado),
        .uart_tx(),
        .leds(leds)
    );

    assign golpe_pin = golpe_detectado;

    // Lectura síncrona registrada (Offset 0x0: Bit 0 = golpe_detectado)
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rdata <= 32'd0;
        end else if (cs && rd) begin
            case (addr)
                4'h0:    rdata <= {31'd0, golpe_detectado};
                default: rdata <= 32'd0;
            endcase
        end
    end

endmodule
