module top (
    input  wire       clk,       // Pin 52
    input  wire       btn_rst,   // Pin 4
    output wire       sclk,      // Pin 25
    output wire       mosi,      // Pin 26
    input  wire       miso,      // Pin 27
    output wire       cs_n,      // Pin 28
    output wire       golpe_out, // Pin 29 (Salida física 0 o 1)
    output wire       uart_tx,   // Pin 17 (Monitor serial hacia PC)
    output wire [5:0] leds       // 6 LEDs
);

    reg        spi_start;
    reg [15:0] spi_tx;
    wire [7:0] spi_rx;
    wire       spi_done;

    spi_master u_spi (
        .clk(clk), .rst_n(btn_rst),
        .start(spi_start), .tx_data(spi_tx),
        .rx_data(spi_rx), .done(spi_done),
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

    reg        tx_start;
    reg [7:0]  tx_byte;
    wire       tx_busy;

    uart_tx u_uart (
        .clk(clk), .rst_n(btn_rst),
        .start(tx_start), .data(tx_byte),
        .tx(uart_tx), .busy(tx_busy)
    );

    function [7:0] to_hex(input [3:0] val);
        to_hex = (val < 4'd10) ? (8'd48 + val) : (8'd55 + val);
    endfunction

    reg [3:0]  state;
    reg [23:0] timer;
    reg [3:0]  reg_idx;
    reg [95:0] imu_shift;
    reg        sample_valid;
    reg [4:0]  char_idx;

    localparam S_BOOT      = 4'd0,
               S_DUMMY     = 4'd1,
               S_ACC_ON    = 4'd2,
               S_ACC_WAIT  = 4'd3,
               S_GYR_ON    = 4'd4,
               S_GYR_WAIT  = 4'd5,
               S_READ_REQ  = 4'd6,
               S_READ_WAIT = 4'd7,
               S_UART_SEND = 4'd8,
               S_UART_WAIT = 4'd9,
               S_LOOP_WAIT = 4'd10;

    wire signed [15:0] gx = {imu_shift[87:80], imu_shift[95:88]};
    wire signed [15:0] gy = {imu_shift[71:64], imu_shift[79:72]};
    wire signed [15:0] gz = {imu_shift[55:48], imu_shift[63:56]};
    wire signed [15:0] ax = {imu_shift[39:32], imu_shift[47:40]};
    wire signed [15:0] ay = {imu_shift[23:16], imu_shift[31:24]};
    wire signed [15:0] az = {imu_shift[7:0],   imu_shift[15:8]};

    wire [18:0] energia;
    reg  [19:0] max_energia; // Guarda el pico de energía entre envíos UART

    detector_golpe u_detector (
        .clk(clk),
        .rst_n(btn_rst),
        .sample_valid(sample_valid),
        .gx(gx), .gy(gy), .gz(gz),
        .ax(ax), .ay(ay), .az(az),
        .golpe_out(golpe_out),
        .energia_out(energia)
    );

    // Mensaje UART: "E:XXXXX GOLPE:1\r\n" (17 caracteres)
    reg [7:0] msg_char;
    always @(*) begin
        case (char_idx)
            5'd0:  msg_char = "E";
            5'd1:  msg_char = ":";
            5'd2:  msg_char = to_hex(max_energia[19:16]);
            5'd3:  msg_char = to_hex(max_energia[15:12]);
            5'd4:  msg_char = to_hex(max_energia[11:8]);
            5'd5:  msg_char = to_hex(max_energia[7:4]);
            5'd6:  msg_char = to_hex(max_energia[3:0]);
            5'd7:  msg_char = " ";
            5'd8:  msg_char = "G";
            5'd9:  msg_char = "O";
            5'd10: msg_char = "L";
            5'd11: msg_char = "P";
            5'd12: msg_char = "E";
            5'd13: msg_char = ":";
            5'd14: msg_char = golpe_out ? "1" : "0";
            5'd15: msg_char = 8'd13;
            5'd16: msg_char = 8'd10;
            default: msg_char = " ";
        endcase
    end

    always @(posedge clk or negedge btn_rst) begin
        if (!btn_rst) begin
            state        <= S_BOOT;
            timer        <= 24'd0;
            spi_start    <= 1'b0;
            tx_start     <= 1'b0;
            reg_idx      <= 4'd0;
            imu_shift    <= 96'd0;
            sample_valid <= 1'b0;
            char_idx     <= 5'd0;
            max_energia  <= 20'd0;
        end else begin
            spi_start    <= 1'b0;
            tx_start     <= 1'b0;
            sample_valid <= 1'b0;

            if (sample_valid && ({1'b0, energia} > max_energia))
                max_energia <= {1'b0, energia};

            case (state)
                S_BOOT: begin
                    if (timer == 24'd1_350_000) begin
                        timer     <= 0;
                        spi_tx    <= 16'hFF00;
                        spi_start <= 1'b1;
                        state     <= S_DUMMY;
                    end else timer <= timer + 1'b1;
                end

                S_DUMMY: if (spi_done) state <= S_ACC_ON;

                S_ACC_ON: begin
                    spi_tx    <= 16'h7E11;
                    spi_start <= 1'b1;
                    state     <= S_ACC_WAIT;
                end

                S_ACC_WAIT: begin
                    if (spi_done) timer <= 24'd1;
                    else if (timer > 0) begin
                        if (timer == 24'd270_000) begin
                            timer <= 0;
                            state <= S_GYR_ON;
                        end else timer <= timer + 1'b1;
                    end
                end

                S_GYR_ON: begin
                    spi_tx    <= 16'h7E15;
                    spi_start <= 1'b1;
                    state     <= S_GYR_WAIT;
                end

                S_GYR_WAIT: begin
                    if (spi_done) timer <= 24'd1;
                    else if (timer > 0) begin
                        if (timer == 24'd2_430_000) begin
                            timer   <= 0;
                            reg_idx <= 4'd0;
                            state   <= S_READ_REQ;
                        end else timer <= timer + 1'b1;
                    end
                end

                S_READ_REQ: begin
                    spi_tx    <= {1'b1, (7'h0C + {3'd0, reg_idx}), 8'h00};
                    spi_start <= 1'b1;
                    state     <= S_READ_WAIT;
                end

                S_READ_WAIT: begin
                    if (spi_done) begin
                        imu_shift <= {imu_shift[87:0], spi_rx};
                        if (reg_idx == 4'd11) begin
                            sample_valid <= 1'b1;
                            char_idx     <= 5'd0;
                            state        <= S_UART_SEND;
                        end else begin
                            reg_idx <= reg_idx + 1'b1;
                            state   <= S_READ_REQ;
                        end
                    end
                end

                S_UART_SEND: begin
                    if (!tx_busy) begin
                        tx_byte  <= msg_char;
                        tx_start <= 1'b1;
                        state    <= S_UART_WAIT;
                    end
                end

                S_UART_WAIT: begin
                    if (!tx_busy && !tx_start) begin
                        if (char_idx == 5'd16) begin
                            max_energia <= 20'd0;
                            timer       <= 0;
                            state       <= S_LOOP_WAIT;
                        end else begin
                            char_idx <= char_idx + 1'b1;
                            state    <= S_UART_SEND;
                        end
                    end
                end

                S_LOOP_WAIT: begin
                    if (timer == 24'd270_000) begin // 100 Hz
                        timer   <= 0;
                        reg_idx <= 4'd0;
                        state   <= S_READ_REQ;
                    end else timer <= timer + 1'b1;
                end
            endcase
        end
    end

    assign leds = golpe_out ? 6'b000000 : 6'b111111;

endmodule
