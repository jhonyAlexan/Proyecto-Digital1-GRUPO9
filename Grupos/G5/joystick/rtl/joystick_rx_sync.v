module joystick_rx_sync (
    input  wire clk,
    input  wire rst,
    input  wire uart_rx,
    output reg  rx_sync
);
    reg rx_meta;

    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= uart_rx;
            rx_sync <= rx_meta;
        end
    end
endmodule
