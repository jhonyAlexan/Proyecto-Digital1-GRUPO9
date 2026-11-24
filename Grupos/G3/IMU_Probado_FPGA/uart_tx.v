module uart_tx (
    input  wire       clk,      // 27 MHz
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,
    output reg        busy
);
    // 27,000,000 / 115,200 = 234 ciclos por bit
    localparam CLKS_PER_BIT = 8'd234;

    reg [7:0] clk_cnt;
    reg [3:0] bit_idx;
    reg [9:0] frame;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx      <= 1'b1;
            busy    <= 1'b0;
            clk_cnt <= 8'd0;
            bit_idx <= 4'd0;
            frame   <= 10'h3FF;
        end else if (!busy) begin
            tx <= 1'b1;
            if (start) begin
                frame   <= {1'b1, data, 1'b0}; // Stop, 8 bits, Start
                busy    <= 1'b1;
                clk_cnt <= 8'd0;
                bit_idx <= 4'd0;
            end
        end else begin
            tx <= frame[bit_idx];
            if (clk_cnt == CLKS_PER_BIT - 1) begin
                clk_cnt <= 8'd0;
                if (bit_idx == 4'd9) begin
                    busy <= 1'b0;
                    tx   <= 1'b1;
                end else begin
                    bit_idx <= bit_idx + 1'b1;
                end
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
    end
endmodule
