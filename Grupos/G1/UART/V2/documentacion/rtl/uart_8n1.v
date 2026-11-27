// -----------------------------------------------------------------------------
// UART 8N1 (TX + RX).  Tang Nano 9K: CLK_HZ = 27_000_000, BAUD = 115_200
// Se llama uart_8n1 para no chocar con el módulo "uart" de rtl/uart/uart.v
//
// TX: poner tx_data y pulsar tx_start (1 ciclo) cuando tx_busy = 0.
//     tx_busy sube en el mismo ciclo en que tx_start vale 1.
// RX: rx_valid es un pulso de 1 ciclo con rx_data listo.
//     Si el stop bit no es 1 no hay rx_valid: se levanta rx_frame_err y se
//     espera a que la línea vuelva a 1 antes de buscar otro start (R_ESPERA).
// -----------------------------------------------------------------------------
module uart_8n1 #(
    parameter CLK_HZ = 27_000_000,
    parameter BAUD   = 115_200
)(
    input  wire       clk,
    input  wire       rst_n,
    // TX
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output reg        tx,
    output wire       tx_busy,
    // RX
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        rx_frame_err
);
    localparam integer CPB  = CLK_HZ / BAUD;      // 234 ciclos por bit
    localparam integer HALF = CPB / 2;
    localparam integer CW   = $clog2(CPB) + 1;

    // ------------------------------- TX --------------------------------------
    localparam T_IDLE = 2'd0, T_START = 2'd1, T_DATA = 2'd2, T_STOP = 2'd3;

    reg [1:0]    t_state;
    reg [CW-1:0] t_cnt;
    reg [2:0]    t_idx;
    reg [7:0]    t_sh;

    assign tx_busy = (t_state != T_IDLE) | tx_start;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t_state <= T_IDLE;
            t_cnt   <= 0;
            t_idx   <= 3'd0;
            t_sh    <= 8'd0;
            tx      <= 1'b1;
        end else begin
            case (t_state)
                T_IDLE: begin
                    tx    <= 1'b1;
                    t_cnt <= 0;
                    t_idx <= 3'd0;
                    if (tx_start) begin
                        t_sh    <= tx_data;
                        tx      <= 1'b0;                 // start bit
                        t_state <= T_START;
                    end
                end
                T_START: begin
                    if (t_cnt == CPB-1) begin
                        t_cnt   <= 0;
                        tx      <= t_sh[0];              // bit 0 (LSB primero)
                        t_state <= T_DATA;
                    end else t_cnt <= t_cnt + 1'b1;
                end
                T_DATA: begin
                    if (t_cnt == CPB-1) begin
                        t_cnt <= 0;
                        if (t_idx == 3'd7) begin
                            tx      <= 1'b1;             // stop bit
                            t_state <= T_STOP;
                        end else begin
                            t_idx <= t_idx + 1'b1;
                            t_sh  <= {1'b0, t_sh[7:1]};
                            tx    <= t_sh[1];
                        end
                    end else t_cnt <= t_cnt + 1'b1;
                end
                T_STOP: begin
                    if (t_cnt == CPB-1) begin
                        t_cnt   <= 0;
                        t_state <= T_IDLE;
                    end else t_cnt <= t_cnt + 1'b1;
                end
            endcase
        end
    end

    // ------------------------------- RX --------------------------------------
    localparam R_IDLE = 3'd0, R_START = 3'd1, R_DATA = 3'd2, R_STOP = 3'd3,
               R_ESPERA = 3'd4;

    reg [1:0]    rx_sync;
    reg [2:0]    r_state;
    reg [CW-1:0] r_cnt;
    reg [2:0]    r_idx;
    reg [7:0]    r_sh;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rx_sync <= 2'b11;
        else        rx_sync <= {rx_sync[0], rx};
    end
    wire rx_in = rx_sync[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state      <= R_IDLE;
            r_cnt        <= 0;
            r_idx        <= 3'd0;
            r_sh         <= 8'd0;
            rx_data      <= 8'd0;
            rx_valid     <= 1'b0;
            rx_frame_err <= 1'b0;
        end else begin
            rx_valid     <= 1'b0;
            rx_frame_err <= 1'b0;

            case (r_state)
                R_IDLE: begin
                    r_cnt <= 0;
                    r_idx <= 3'd0;
                    if (!rx_in) r_state <= R_START;
                end
                R_START: begin                           // verificar start a mitad de bit
                    if (r_cnt == HALF-1) begin
                        r_cnt <= 0;
                        r_state <= rx_in ? R_IDLE : R_DATA;
                    end else r_cnt <= r_cnt + 1'b1;
                end
                R_DATA: begin
                    if (r_cnt == CPB-1) begin
                        r_cnt <= 0;
                        r_sh  <= {rx_in, r_sh[7:1]};     // LSB primero
                        if (r_idx == 3'd7) r_state <= R_STOP;
                        else               r_idx   <= r_idx + 1'b1;
                    end else r_cnt <= r_cnt + 1'b1;
                end
                R_STOP: begin
                    if (r_cnt == CPB-1) begin
                        r_cnt   <= 0;
                        if (rx_in) begin
                            rx_data  <= r_sh;
                            rx_valid <= 1'b1;
                            r_state  <= R_IDLE;
                        end else begin
                            rx_frame_err <= 1'b1;
                            r_state      <= R_ESPERA;   // línea en 0: no leer basura
                        end
                    end else r_cnt <= r_cnt + 1'b1;
                end
                R_ESPERA: if (rx_in) r_state <= R_IDLE;
                default:  r_state <= R_IDLE;
            endcase
        end
    end
endmodule
