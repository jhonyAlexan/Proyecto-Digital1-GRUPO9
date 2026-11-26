// ============================================================================
// Módulo: peripheral_spi_flash.v
// Descripción: Adaptador MMIO de 32 bits para el controlador Flash SPI.
// Región asignada: 0x0045_0000 - 0x0045_000C (Base 0x0045)
// ============================================================================

module peripheral_spi_flash #(
    parameter integer TICK_DIV = 4
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        cs,
    input  wire        rd,
    input  wire [31:0] addr,
    input  wire [31:0] d_in,
    input  wire [3:0]  wmask,
    output wire [31:0] d_out,
    // Pines externos hacia Flash SPI W25Q64JV
    output wire        spi_cs_n,
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso
);

    wire [3:0]  sel;
    wire        start_pulse;
    wire        cs_hold;
    wire [7:0]  cmd;
    wire [23:0] flash_addr;
    wire [7:0]  tx_data;
    wire [7:0]  rx_data;
    wire        busy;
    wire        done;

    // 1. Decodificador local de registros (offsets 0x00, 0x04, 0x08, 0x0C)
    peripheral_spi_flash_addr_decoder u_decoder (
        .cs   (cs),
        .addr (addr[15:0]),
        .sel  (sel)
    );

    // 2. Banco de registros MMIO y sincronización de lectura registrada
    peripheral_spi_flash_register_control u_regs (
        .clk        (clk),
        .rst        (rst),
        .rd         (cs && rd),
        .wr         (cs && (|wmask)),
        .sel        (sel),
        .d_in       (d_in),
        .rx_data    (rx_data),
        .busy       (busy),
        .done       (done),
        .start      (start_pulse),
        .cs_hold    (cs_hold),
        .cmd        (cmd),
        .flash_addr (flash_addr),
        .tx_data    (tx_data),
        .d_out      (d_out)
    );

    // 3. Núcleo FSMD del Controlador SPI Modo 0
    spi_flash_controller #(
        .TICK_DIV(TICK_DIV)
    ) u_spi_core (
        .clk      (clk),
        .rst      (rst),
        .start    (start_pulse),
        .cs_hold  (cs_hold),
        .cmd      (cmd),
        .addr     (flash_addr),
        .tx_data  (tx_data),
        .rx_data  (rx_data),
        .busy     (busy),
        .done     (done),
        .spi_cs_n (spi_cs_n),
        .spi_sclk (spi_sclk),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso)
    );

endmodule

// ----------------------------------------------------------------------------
// Decodificador one-hot de registros internos (0x0045_0000 - 0x0045_000C)
// ----------------------------------------------------------------------------
module peripheral_spi_flash_addr_decoder (
    input  wire        cs,
    input  wire [15:0] addr,
    output reg  [3:0]  sel
);
    always @(*) begin
        sel = 4'b0000;
        if (cs) begin
            case (addr)
                16'h0000: sel = 4'b0001; // SPI_CTRL_STAT
                16'h0004: sel = 4'b0010; // SPI_CMD_ADDR
                16'h0008: sel = 4'b0100; // SPI_TX_DATA
                16'h000C: sel = 4'b1000; // SPI_RX_DATA
                default:  sel = 4'b0000;
            endcase
        end
    end
endmodule

// ----------------------------------------------------------------------------
// Control de registros MMIO y respuesta de lectura para FemtoRV32
// ----------------------------------------------------------------------------
module peripheral_spi_flash_register_control (
    input  wire        clk,
    input  wire        rst,
    input  wire        rd,
    input  wire        wr,
    input  wire [3:0]  sel,
    input  wire [31:0] d_in,
    input  wire [7:0]  rx_data,
    input  wire        busy,
    input  wire        done,
    output reg         start,
    output reg         cs_hold,
    output reg  [7:0]  cmd,
    output reg  [23:0] flash_addr,
    output reg  [7:0]  tx_data,
    output reg  [31:0] d_out
);
    // Escritura síncrona de registros y pulso start de 1 ciclo (W1P)
    always @(posedge clk) begin
        if (rst) begin
            start      <= 1'b0;
            cs_hold    <= 1'b0;
            cmd        <= 8'h00;
            flash_addr <= 24'h000000;
            tx_data    <= 8'h00;
        end else begin
            start <= 1'b0; // Pulso de un solo ciclo

            // 0x00: SPI_CTRL_STAT ([0]=start W1P, [1]=cs_hold)
            if (sel[0] && wr) begin
                cs_hold <= d_in[1];
                if (d_in[0] && !busy)
                    start <= 1'b1;
            end

            // 0x04: SPI_CMD_ADDR ([31:24]=cmd, [23:0]=addr)
            if (sel[1] && wr && !busy) begin
                cmd        <= d_in[31:24];
                flash_addr <= d_in[23:0];
            end

            // 0x08: SPI_TX_DATA ([7:0]=tx_data)
            if (sel[2] && wr && !busy) begin
                tx_data <= d_in[7:0];
            end
        end
    end

    // Lectura registrada (Quark consume d_out en el ciclo siguiente a rd)
    always @(posedge clk) begin
        if (rst) begin
            d_out <= 32'd0;
        end else if (rd) begin
            case (sel)
                4'b0001: d_out <= {22'd0, done, busy, 6'd0, cs_hold, 1'b0}; // CTRL_STAT
                4'b0010: d_out <= {cmd, flash_addr};                        // CMD_ADDR
                4'b0100: d_out <= {24'd0, tx_data};                         // TX_DATA
                4'b1000: d_out <= {24'd0, rx_data};                         // RX_DATA
                default: d_out <= 32'd0;
            endcase
        end
    end
endmodule
