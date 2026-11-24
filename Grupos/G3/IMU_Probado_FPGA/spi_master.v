module spi_master (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [15:0] tx_data,
    output reg  [7:0]  rx_data,
    output reg         done,
    output reg         sclk,
    output reg         mosi,
    input  wire        miso,
    output reg         cs_n
);
    reg [4:0] clk_cnt;
    wire tick = (clk_cnt == 5'd13);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) clk_cnt <= 0;
        else if (cs_n) clk_cnt <= 0;
        else clk_cnt <= tick ? 5'd0 : clk_cnt + 1'b1;
    end

    reg [4:0] bit_cnt;
    reg [15:0] shift_tx;
    reg state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= 0;
            cs_n    <= 1'b1;
            sclk    <= 1'b0;
            mosi    <= 1'b0;
            done    <= 1'b0;
            bit_cnt <= 5'd0;
            rx_data <= 8'd0;
        end else begin
            done <= 1'b0;
            if (!state) begin
                cs_n <= 1'b1;
                sclk <= 1'b0;
                if (start) begin
                    cs_n     <= 1'b0;
                    shift_tx <= tx_data;
                    mosi     <= tx_data[15]; // <-- CORREGIDO: Bit 15 (MSB)
                    bit_cnt  <= 5'd15;
                    state    <= 1'b1;
                end
            end else if (tick) begin
                sclk <= ~sclk;
                if (!sclk) begin
                    if (bit_cnt <= 5'd7)
                        rx_data[bit_cnt[2:0]] <= miso;
                end else begin
                    if (bit_cnt == 5'd0) begin
                        cs_n  <= 1'b1;
                        state <= 1'b0;
                        done  <= 1'b1;
                    end else begin
                        bit_cnt <= bit_cnt - 1'b1;
                        mosi    <= shift_tx[bit_cnt - 1'b1];
                    end
                end
            end
        end
    end
endmodule
