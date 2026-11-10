// ============================================================================
// MÓDULO PRINCIPAL (TOP)
// Equivale al programa principal en C que envía la cadena de texto repetidamente
// ============================================================================
module top_tx (
    input  wire clk,      // Reloj principal de la Tang Nano 9K (Pin 52 - 27 MHz)
    input  wire rst_n,    // Botón de reset (activo en bajo)
    output wire uart_tx   // Pin de salida física TX hacia la otra FPGA
);

    // Parámetros de configuración
    localparam CLK_FREQ = 27_000_000; // 27 MHz
    localparam BAUDRATE = 9600;

    // Señales de interconexión con el transmisor UART
    reg  [7:0] tx_data;
    reg        tx_start;
    wire       tx_busy;

    // Instancia del transmisor hardware UART
    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUDRATE(BAUDRATE)
    ) u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .tx(uart_tx),
        .busy(tx_busy)
    );

    // MEMORIA ROM: Almacena la cadena de caracteres "Dato enviado via GPIO...\n"
    // Equivale a `const char *mensaje` en C
    localparam MSG_LEN = 25;
    reg [7:0] message [0:MSG_LEN-1];

    initial begin
        message[0]  = "D"; message[1]  = "a"; message[2]  = "t"; message[3]  = "o";
        message[4]  = " "; message[5]  = "e"; message[6]  = "n"; message[7]  = "v";
        message[8]  = "i"; message[9]  = "a"; message[10] = "d"; message[11] = "o";
        message[12] = " "; message[13] = "v"; message[14] = "i"; message[15] = "a";
        message[16] = " "; message[17] = "G"; message[18] = "P"; message[19] = "I";
        message[20] = "O"; message[21] = "."; message[22] = "."; message[23] = ".";
        message[24] = 8'h0A; // Carácter de salto de línea '\n' en ASCII (0x0A)
    end

    // MÁQUINA DE ESTADOS (FSM)
    // Equivale al `while(1)` y `uart_puts()` de C
    localparam STATE_SEND_CHAR = 2'd0;
    localparam STATE_WAIT_TX   = 2'd1;
    localparam STATE_DELAY     = 2'd2;

    reg [1:0]  state;
    reg [5:0]  char_idx; // Índice del carácter actual
    reg [24:0] delay_counter; // Contador para el retardo (delay)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= STATE_SEND_CHAR;
            char_idx      <= 0;
            delay_counter <= 0;
            tx_start      <= 1'b0;
            tx_data       <= 8'h00;
        end else begin
            case (state)

                // PASO 1: Cargar el carácter y dar el pulso de inicio
                STATE_SEND_CHAR: begin
                    if (!tx_busy) begin
                        tx_data  <= message[char_idx]; // Cargar byte de la ROM
                        tx_start <= 1'b1;               // Iniciar transmisión
                        state    <= STATE_WAIT_TX;
                    end
                end

                // PASO 2: Esperar a que el transmisor empiece a enviar y se libere
                // Equivale a `while (UART_STATUS_REG & UART_TX_BUSY);`
                STATE_WAIT_TX: begin
                    tx_start <= 1'b0; // Limpiar el pulso de inicio
                    if (!tx_busy && !tx_start) begin
                        if (char_idx == MSG_LEN - 1) begin
                            char_idx <= 0;              // Reiniciar mensaje
                            state    <= STATE_DELAY;    // Ir al retardo
                        end else begin
                            char_idx <= char_idx + 1'b1; // Siguiente carácter
                            state    <= STATE_SEND_CHAR;
                        end
                    end
                end

                // PASO 3: Retardo por software/hardware entre envíos
                // Equivale a `for (volatile int i = 0; i < 1000000; i++);`
                STATE_DELAY: begin
                    // Espera aprox. 0.5 segundos (13,500,000 ciclos a 27 MHz)
                    if (delay_counter >= 27_000_000 / 2) begin
                        delay_counter <= 0;
                        state         <= STATE_SEND_CHAR;
                    end else begin
                        delay_counter <= delay_counter + 1'b1;
                    end
                end

                default: state <= STATE_SEND_CHAR;
            endcase
        end
    end

endmodule


// ============================================================================
// MÓDULO CONTROLADOR DE HARDWARE UART (TX)
// Convierte 1 byte en una trama serie de bits (Start bit + 8 datos + Stop bit)
// ============================================================================
module uart_tx #(
    parameter CLK_FREQ = 27_000_000,
    parameter BAUDRATE = 9600
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output reg        tx,
    output reg        busy
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUDRATE;

    localparam IDLE       = 2'd0;
    localparam START_BIT  = 2'd1;
    localparam DATA_BITS  = 2'd2;
    localparam STOP_BIT   = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  shifter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            tx        <= 1'b1; // Línea en ALTO en reposo
            busy      <= 1'b0;
            clk_count <= 0;
            bit_index <= 0;
            shifter   <= 8'h00;
        end else begin
            case (state)

                IDLE: begin
                    tx   <= 1'b1;
                    busy <= 1'b0;
                    clk_count <= 0;
                    bit_index <= 0;
                    if (tx_start) begin
                        shifter <= tx_data;
                        busy    <= 1'b1;
                        state   <= START_BIT;
                    end
                end

                // Bit de Inicio (Start Bit = 0)
                START_BIT: begin
                    tx <= 1'b0;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 0;
                        state     <= DATA_BITS;
                    end
                end

                // 8 Bits de Datos (LSB primero)
                DATA_BITS: begin
                    tx <= shifter[bit_index];
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 0;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1'b1;
                        end else begin
                            bit_index <= 0;
                            state     <= STOP_BIT;
                        end
                    end
                end

                // Bit de Parada (Stop Bit = 1)
                STOP_BIT: begin
                    tx <= 1'b1;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 0;
                        state     <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
