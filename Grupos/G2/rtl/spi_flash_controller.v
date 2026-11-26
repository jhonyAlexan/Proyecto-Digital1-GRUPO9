// ============================================================================
// Módulo: spi_flash_controller.v
// Descripción: Controlador Maestro SPI Modo 0 (CPOL=0, CPHA=0) bajo metodología
//              FSMD (Unidad de Control + Camino de Datos) para Flash W25Q64JV.
// Reloj maestro: 27 MHz | f_SCLK = 3.375 MHz (TICK_DIV = 4)
// ============================================================================

module spi_flash_controller #(
    parameter integer TICK_DIV = 4  // Semiperíodo T_half = 4 ciclos @ 27 MHz
) (
    input  wire        clk,
    input  wire        rst,
    // Interfaz con registros MMIO
    input  wire        start,
    input  wire        cs_hold,
    input  wire [7:0]  cmd,
    input  wire [23:0] addr,
    input  wire [7:0]  tx_data,
    output wire [7:0]  rx_data,
    output wire        busy,
    output wire        done,
    // Interfaz física SPI Modo 0 hacia W25Q64JV
    output wire        spi_cs_n,
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso
);

    // Señales internas de interconexión Control <-> Datapath
    wire       sclk_tick;
    wire       bit_done;
    wire       byte_done;
    wire       ld_params;
    wire       init_xfer;
    wire       sample_miso;
    wire       shift_bit;
    wire       next_byte_en;
    wire       cap_last_byte;

    // 1. Generador de pulsos de habilitación (1 ciclo de clk cada TICK_DIV)
    spi_tick_gen #(
        .TICK_DIV(TICK_DIV)
    ) u_tick_gen (
        .clk       (clk),
        .rst       (rst),
        .sclk_tick (sclk_tick)
    );

    // 2. Unidad de Control (FSM de 5 estados, transiciones T0-T12)
    spi_fsm_control u_fsm_control (
        .clk           (clk),
        .rst           (rst),
        .start         (start),
        .cs_hold       (cs_hold),
        .sclk_tick     (sclk_tick),
        .bit_done      (bit_done),
        .byte_done     (byte_done),
        .ld_params     (ld_params),
        .init_xfer     (init_xfer),
        .sample_miso   (sample_miso),
        .shift_bit     (shift_bit),
        .next_byte_en  (next_byte_en),
        .cap_last_byte (cap_last_byte),
        .busy          (busy),
        .done          (done),
        .spi_cs_n      (spi_cs_n),
        .spi_sclk      (spi_sclk)
    );

    // 3. Camino de Datos (Datapath)
    spi_datapath u_datapath (
        .clk           (clk),
        .rst           (rst),
        .cmd           (cmd),
        .addr          (addr),
        .tx_data       (tx_data),
        .ld_params     (ld_params),
        .init_xfer     (init_xfer),
        .sample_miso   (sample_miso),
        .shift_bit     (shift_bit),
        .next_byte_en  (next_byte_en),
        .cap_last_byte (cap_last_byte),
        .spi_miso      (spi_miso),
        .bit_done      (bit_done),
        .byte_done     (byte_done),
        .rx_data       (rx_data),
        .spi_mosi      (spi_mosi)
    );

endmodule

// ----------------------------------------------------------------------------
// Submódulo 1: Generador de pulsos de habilitación sclk_tick
// ----------------------------------------------------------------------------
module spi_tick_gen #(
    parameter integer TICK_DIV = 4
) (
    input  wire clk,
    input  wire rst,
    output reg  sclk_tick
);
    localparam integer CNT_W = (TICK_DIV <= 2) ? 1 : $clog2(TICK_DIV);
    reg [CNT_W-1:0] div_cnt;

    always @(posedge clk) begin
        if (rst) begin
            div_cnt   <= {CNT_W{1'b0}};
            sclk_tick <= 1'b0;
        end else if (div_cnt == TICK_DIV - 1) begin
            div_cnt   <= {CNT_W{1'b0}};
            sclk_tick <= 1'b1;
        end else begin
            div_cnt   <= div_cnt + 1'b1;
            sclk_tick <= 1'b0;
        end
    end
endmodule

// ----------------------------------------------------------------------------
// Submódulo 2: Unidad de Control (FSM de 5 estados, Tabla RT T0-T12)
// ----------------------------------------------------------------------------
module spi_fsm_control (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire cs_hold,
    input  wire sclk_tick,
    input  wire bit_done,
    input  wire byte_done,
    output reg  ld_params,
    output reg  init_xfer,
    output reg  sample_miso,
    output reg  shift_bit,
    output reg  next_byte_en,
    output reg  cap_last_byte,
    output reg  busy,
    output reg  done,
    output reg  spi_cs_n,
    output reg  spi_sclk
);
    localparam [2:0] IDLE      = 3'b000,
                     LOAD_CMD  = 3'b001,
                     SCLK_LOW  = 3'b010,
                     SCLK_HIGH = 3'b011,
                     STOP      = 3'b100;

    reg [2:0] state, next_state;

    // Lógica combinacional de próximo estado y órdenes al datapath
    always @(*) begin
        next_state    = state;
        ld_params     = 1'b0;
        init_xfer     = 1'b0;
        sample_miso   = 1'b0;
        shift_bit     = 1'b0;
        next_byte_en  = 1'b0;
        cap_last_byte = 1'b0;

        case (state)
            IDLE: begin
                if (start) begin
                    ld_params  = 1'b1; // T2
                    next_state = LOAD_CMD;
                end
            end

            LOAD_CMD: begin
                if (sclk_tick) begin
                    init_xfer  = 1'b1; // T4
                    next_state = SCLK_LOW;
                end
            end

            SCLK_LOW: begin
                if (sclk_tick) begin
                    sample_miso = 1'b1; // T6 (flanco de subida SCLK)
                    next_state  = SCLK_HIGH;
                end
            end

            SCLK_HIGH: begin
                if (sclk_tick) begin
                    if (!bit_done) begin
                        shift_bit  = 1'b1; // T8 (siguiente bit)
                        next_state = SCLK_LOW;
                    end else if (!byte_done) begin
                        next_byte_en = 1'b1; // T9 (siguiente byte de la trama)
                        next_state   = SCLK_LOW;
                    end else begin
                        cap_last_byte = 1'b1; // T10 (fin de trama)
                        next_state    = STOP;
                    end
                end
            end

            STOP: begin
                if (sclk_tick) begin
                    next_state = IDLE; // T12
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // Registros de estado y salidas físicas registradas
    always @(posedge clk) begin
        if (rst) begin
            // T0: Reset síncrono
            state    <= IDLE;
            spi_cs_n <= 1'b1;
            spi_sclk <= 1'b0;
            busy     <= 1'b0;
            done     <= 1'b0;
        end else begin
            state <= next_state;

            case (state)
                IDLE: begin
                    spi_sclk <= 1'b0;
                    if (start) begin
                        // T2: Arranque de transacción, limpia done
                        busy <= 1'b1;
                        done <= 1'b0;
                    end else begin
                        // T1: Reposo, retiene done y respeta cs_hold
                        spi_cs_n <= ~cs_hold;
                        busy     <= 1'b0;
                    end
                end

                LOAD_CMD: begin
                    spi_sclk <= 1'b0;
                    busy     <= 1'b1;
                    if (sclk_tick)
                        spi_cs_n <= 1'b0; // T4 (t0)
                end

                SCLK_LOW: begin
                    spi_cs_n <= 1'b0;
                    busy     <= 1'b1;
                    if (sclk_tick)
                        spi_sclk <= 1'b1; // T6 (flanco de subida)
                end

                SCLK_HIGH: begin
                    spi_cs_n <= 1'b0;
                    busy     <= 1'b1;
                    if (sclk_tick)
                        spi_sclk <= 1'b0; // T8, T9, T10 (flanco de bajada)
                end

                STOP: begin
                    spi_sclk <= 1'b0;
                    if (sclk_tick) begin
                        // T12 (tf): Libera CS# según cs_hold y retiene done=1
                        spi_cs_n <= ~cs_hold;
                        busy     <= 1'b0;
                        done     <= 1'b1;
                    end else begin
                        spi_cs_n <= 1'b0;
                        busy     <= 1'b1;
                    end
                end

                default: begin
                    spi_cs_n <= 1'b1;
                    spi_sclk <= 1'b0;
                    busy     <= 1'b0;
                end
            endcase
        end
    end
endmodule

// ----------------------------------------------------------------------------
// Submódulo 3: Camino de Datos (Datapath)
// ----------------------------------------------------------------------------
module spi_datapath (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  cmd,
    input  wire [23:0] addr,
    input  wire [7:0]  tx_data,
    input  wire        ld_params,
    input  wire        init_xfer,
    input  wire        sample_miso,
    input  wire        shift_bit,
    input  wire        next_byte_en,
    input  wire        cap_last_byte,
    input  wire        spi_miso,
    output wire        bit_done,
    output wire        byte_done,
    output reg  [7:0]  rx_data,
    output reg         spi_mosi
);
    // Sincronizador 2-FF para entrada asíncrona spi_miso
    reg miso_ff1, miso_sync;
    always @(posedge clk) begin
        if (rst) begin
            miso_ff1  <= 1'b0;
            miso_sync <= 1'b0;
        end else begin
            miso_ff1  <= spi_miso;
            miso_sync <= miso_ff1;
        end
    end

    // Registros internos del datapath
    reg [7:0]  cmd_reg;
    reg [23:0] addr_reg;
    reg [7:0]  tx_reg;
    reg [7:0]  shift_reg;
    reg [2:0]  bit_cnt;
    reg [2:0]  byte_cnt;
    reg [2:0]  len;

    // Decodificación dinámica de longitud de trama (len) según opcode JEDEC
    function [2:0] decodificar_len;
        input [7:0] opcode;
        begin
            case (opcode)
                8'h06:   decodificar_len = 3'd1; // WREN: 1 byte comando
                8'h05:   decodificar_len = 3'd2; // RDSR: 1 byte cmd + 1 byte status
                8'h20:   decodificar_len = 3'd4; // Sector Erase: 1 cmd + 3 addr
                8'h03,
                8'h02:   decodificar_len = 3'd5; // Read / Page Program: 1 cmd + 3 addr + 1 data
                default: decodificar_len = 3'd1; // Ráfaga continua (cs_hold=1) o 1 byte
            endcase
        end
    endfunction

    // Multiplexor del siguiente byte a transmitir
    reg [7:0] next_byte;
    always @(*) begin
        case (byte_cnt)
            3'd0:    next_byte = addr_reg[23:16];
            3'd1:    next_byte = addr_reg[15:8];
            3'd2:    next_byte = addr_reg[7:0];
            default: next_byte = tx_reg;
        endcase
    end

    // Banderas de estado hacia la FSM
    assign bit_done  = (bit_cnt == 3'd7);
    assign byte_done = (byte_cnt == (len - 3'd1));

    // Transferencias RT síncronas
    always @(posedge clk) begin
        if (rst) begin
            cmd_reg   <= 8'h00;
            addr_reg  <= 24'h000000;
            tx_reg    <= 8'h00;
            shift_reg <= 8'h00;
            rx_data   <= 8'h00;
            bit_cnt   <= 3'd0;
            byte_cnt  <= 3'd0;
            len       <= 3'd1;
            spi_mosi  <= 1'b0;
        end else begin
            if (ld_params) begin
                // T2: Captura parámetros y decodifica longitud
                cmd_reg  <= cmd;
                addr_reg <= addr;
                tx_reg   <= tx_data;
                len      <= decodificar_len(cmd);
            end else if (init_xfer) begin
                // T4: Carga primer byte (comando) y coloca MSB en MOSI
                bit_cnt   <= 3'd0;
                byte_cnt  <= 3'd0;
                shift_reg <= cmd_reg;
                spi_mosi  <= cmd_reg[7];
            end else if (sample_miso) begin
                // T6: Muestrea MISO en flanco de subida de SCLK
                shift_reg <= {shift_reg[6:0], miso_sync};
            end else if (shift_bit) begin
                // T8: Desplaza siguiente bit en flanco de bajada de SCLK
                bit_cnt  <= bit_cnt + 3'd1;
                spi_mosi <= shift_reg[7];
            end else if (next_byte_en) begin
                // T9: Guarda byte recibido y carga siguiente byte de trama
                rx_data   <= shift_reg;
                byte_cnt  <= byte_cnt + 3'd1;
                bit_cnt   <= 3'd0;
                shift_reg <= next_byte;
                spi_mosi  <= next_byte[7];
            end else if (cap_last_byte) begin
                // T10: Captura el último byte recibido
                rx_data <= shift_reg;
            end
        end
    end
endmodule
