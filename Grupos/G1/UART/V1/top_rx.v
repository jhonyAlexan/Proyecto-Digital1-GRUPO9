// ============================================================================
// MÓDULO PRINCIPAL RECEPTOR (TOP)
// Reconstruye cadenas de texto recibidas por RX y las almacena en memoria RAM
// ============================================================================
module top_rx (
    input  wire       clk,        // Reloj principal de la Tang Nano 9K (Pin 52 - 27 MHz)
    input  wire       rst_n,      // Botón de reset (activo en bajo)
    input  wire       uart_rx_pin,// Pin de entrada física RX proveniente de la otra FPGA
    output reg  [7:0] led_out     // Opcional: Visualizar el último byte o estado en LEDs
);

    // Configuración de la frecuencia del reloj y baudrate
    localparam CLK_FREQ = 27_000_000; // 27 MHz
    localparam BAUDRATE = 9600;

    // Señales de conexión con el módulo RX hardware
    wire [7:0] rx_data;
    wire       rx_valid;

    // Instancia del Receptor UART Hardware
    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUDRATE(BAUDRATE)
    ) u_uart_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx_pin),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    // ========================================================================
    // BÚFER DE MEMORIA Y LÓGICA DE ENSAMBLADO
    // ========================================================================
    reg [7:0] rx_buffer [0:63]; // Memoria RAM interna de 64 bytes
    reg [5:0] idx;              // Índice de posición dentro del búfer (0 a 63)
    reg       msg_ready;        // Bandera que indica que la frase llegó completa

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx       <= 0;
            msg_ready <= 1'b0;
            led_out   <= 8'h00;
        end else begin
            msg_ready <= 1'b0;

            if (rx_valid) begin
                led_out <= rx_data;

                if (rx_data != 8'h0A && idx < 63) begin
                    rx_buffer[idx] <= rx_data;
                    idx            <= idx + 1'b1;
                end else begin
                    rx_buffer[idx] <= 8'h00;
                    msg_ready      <= 1'b1;
                    idx            <= 0;
                end
            end
        end
    end

endmodule


// ============================================================================
// MÓDULO CONTROLADOR DE HARDWARE UART (RX)
// ============================================================================
module uart_rx #(
    parameter CLK_FREQ = 27_000_000,
    parameter BAUDRATE = 9600
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUDRATE;

    localparam IDLE       = 3'd0;
    localparam START_BIT  = 3'd1;
    localparam DATA_BITS  = 3'd2;
    localparam STOP_BIT   = 3'd3;
    localparam CLEANUP    = 3'd4;

    reg [2:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  shifter;

    // Sincronizador de 2 etapas para evitar metaestabilidad
    reg rx_sync_1, rx_sync_2;
    always @(posedge clk) begin
        rx_sync_1 <= rx;
        rx_sync_2 <= rx_sync_1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            rx_data   <= 8'h00;
            rx_valid  <= 1'b0;
            clk_count <= 0;
            bit_index <= 0;
            shifter   <= 8'h00;
        end else begin
            case (state)

                IDLE: begin
                    rx_valid  <= 1'b0;
                    clk_count <= 0;
                    bit_index <= 0;
                    if (rx_sync_2 == 1'b0) begin
                        state <= START_BIT;
                    end
                end

                START_BIT: begin
                    if (clk_count == (CLKS_PER_BIT / 2) - 1) begin
                        if (rx_sync_2 == 1'b0) begin
                            clk_count <= 0;
                            state     <= DATA_BITS;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                DATA_BITS: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 0;
                        shifter[bit_index] <= rx_sync_2;
                        
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1'b1;
                        end else begin
                            bit_index <= 0;
                            state     <= STOP_BIT;
                        end
                    end
                end

                STOP_BIT: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        rx_data  <= shifter;
                        rx_valid <= 1'b1;
                        clk_count <= 0;
                        state    <= CLEANUP;
                    end
                end

                CLEANUP: begin
                    rx_valid <= 1'b0;
                    state    <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule