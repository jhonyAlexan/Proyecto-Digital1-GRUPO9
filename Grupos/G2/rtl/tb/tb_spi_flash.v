// ============================================================================
// Archivo: Grupos/G2/rtl/tb/tb_spi_flash.v
// Descripción: Banco de pruebas autoverificado para peripheral_spi_flash y
//              spi_flash_controller (SPI Modo 0, len dinámico, done retenido,
//              lectura de datos y ráfaga continua con cs_hold).
// ============================================================================

`timescale 1ns / 1ps

module tb_spi_flash;

    // Reloj maestro del SoC: 27 MHz -> T_clk = 37.037 ns
    localparam real CLK_HALF_PERIOD = 18.5185;
    localparam integer TICK_DIV     = 4;

    // Direcciones MMIO del periférico Flash SPI (Base 0x0045_0000)
    localparam [31:0] REG_CTRL_STAT = 32'h0045_0000;
    localparam [31:0] REG_CMD_ADDR  = 32'h0045_0004;
    localparam [31:0] REG_TX_DATA   = 32'h0045_0008;
    localparam [31:0] REG_RX_DATA   = 32'h0045_000C;

    // Señales del bus MMIO hacia el DUT
    reg         clk;
    reg         rst;
    reg         cs;
    reg         rd;
    reg  [31:0] addr;
    reg  [31:0] d_in;
    reg  [3:0]  wmask;
    wire [31:0] d_out;

    // Líneas físicas SPI Modo 0
    wire        spi_cs_n;
    wire        spi_sclk;
    wire        spi_mosi;
    reg         spi_miso;

    // Contadores de verificación automática
    integer tests_passed;
    integer tests_failed;
    reg [31:0] rdata;

    // Instancia del periférico completo (Adaptador MMIO + Núcleo FSMD)
    peripheral_spi_flash #(
        .TICK_DIV(TICK_DIV)
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .cs       (cs),
        .rd       (rd),
        .addr     (addr),
        .d_in     (d_in),
        .wmask    (wmask),
        .d_out    (d_out),
        .spi_cs_n (spi_cs_n),
        .spi_sclk (spi_sclk),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso)
    );

    // Generación de reloj maestro de 27 MHz
    initial clk = 1'b0;
    always #(CLK_HALF_PERIOD) clk = ~clk;

    // ========================================================================
    // Modelo comportamental de esclavo Flash SPI W25Q64JV (Modo 0)
    // ========================================================================
    reg [7:0]  flash_mem [0:255];
    reg [7:0]  mosi_log  [0:31];
    integer    total_mosi_bytes;

    reg [2:0]  slave_bit_cnt;
    integer    slave_byte_cnt;
    reg [7:0]  slave_shift_in;
    reg [7:0]  slave_cmd;
    reg [23:0] slave_addr;
    reg [7:0]  slave_tx_shift;

    // Reinicio de contadores internos del esclavo al bajar CS#
    always @(negedge spi_cs_n) begin
        slave_bit_cnt  <= 3'd0;
        slave_byte_cnt <= 0;
        slave_shift_in <= 8'h00;
        slave_cmd      <= 8'h00;
        slave_addr     <= 24'h000000;
        slave_tx_shift <= 8'h00;
        spi_miso       <= 1'b0;
    end

    always @(posedge spi_cs_n) begin
        spi_miso <= 1'b0;
    end

    // Muestreo de MOSI en flanco de subida de SCLK (CPHA = 0)
    always @(posedge spi_sclk) begin
        if (!spi_cs_n) begin
            slave_shift_in = {slave_shift_in[6:0], spi_mosi};
            if (slave_bit_cnt == 3'd7) begin
                mosi_log[total_mosi_bytes] = {slave_shift_in[6:0], spi_mosi};
                total_mosi_bytes           = total_mosi_bytes + 1;

                if (slave_byte_cnt == 0)
                    slave_cmd = {slave_shift_in[6:0], spi_mosi};
                else if (slave_byte_cnt == 1)
                    slave_addr[23:16] = {slave_shift_in[6:0], spi_mosi};
                else if (slave_byte_cnt == 2)
                    slave_addr[15:8] = {slave_shift_in[6:0], spi_mosi};
                else if (slave_byte_cnt == 3)
                    slave_addr[7:0] = {slave_shift_in[6:0], spi_mosi};

                slave_byte_cnt = slave_byte_cnt + 1;
                slave_bit_cnt  = 3'd0;
            end else begin
                slave_bit_cnt = slave_bit_cnt + 3'd1;
            end
        end
    end

    // Actualización de MISO en flanco de bajada de SCLK (CPHA = 0)
    always @(negedge spi_sclk) begin
        if (!spi_cs_n) begin
            if (slave_bit_cnt == 3'd0) begin
                if (slave_cmd == 8'h03 && slave_byte_cnt == 4) begin
                    // Primer byte de datos tras recibir opcode 0x03 + 24-bit addr
                    slave_tx_shift = flash_mem[slave_addr[7:0]];
                    spi_miso       = slave_tx_shift[7];
                end else if (slave_cmd == 8'h03 && slave_byte_cnt > 4) begin
                    // Autoincremento de dirección en lectura continua (cs_hold = 1)
                    slave_addr     = slave_addr + 24'd1;
                    slave_tx_shift = flash_mem[slave_addr[7:0]];
                    spi_miso       = slave_tx_shift[7];
                end else if (slave_cmd == 8'h05 && slave_byte_cnt >= 1) begin
                    // Read Status Register-1: BUSY = 0
                    slave_tx_shift = 8'h00;
                    spi_miso       = 1'b0;
                end else begin
                    spi_miso       = 1'b0;
                end
            end else begin
                slave_tx_shift = {slave_tx_shift[6:0], 1'b0};
                spi_miso       = slave_tx_shift[7];
            end
        end
    end

    // ========================================================================
    // Tareas auxiliares de acceso al bus MMIO y aserciones
    // ========================================================================
    task mmio_write;
        input [31:0] waddr;
        input [31:0] wdata;
        begin
            @(negedge clk);
            cs    = 1'b1;
            rd    = 1'b0;
            wmask = 4'b1111;
            addr  = waddr;
            d_in  = wdata;
            @(posedge clk);
            #1;
            cs    = 1'b0;
            wmask = 4'b0000;
            d_in  = 32'd0;
        end
    endtask

    task mmio_read;
        input  [31:0] raddr;
        output [31:0] rdata_out;
        begin
            @(negedge clk);
            cs    = 1'b1;
            rd    = 1'b1;
            wmask = 4'b0000;
            addr  = raddr;
            @(posedge clk);
            #1;
            rdata_out = d_out;
            cs        = 1'b0;
            rd        = 1'b0;
        end
    endtask

    task wait_spi_done;
        output [31:0] status_out;
        integer guard;
        begin
            guard = 0;
            status_out = 32'd0;
            while (status_out[9] == 1'b0 && guard < 2000) begin
                mmio_read(REG_CTRL_STAT, status_out);
                guard = guard + 1;
            end
            if (guard >= 2000) begin
                $display("[FALLA] Timeout esperando bandera done=1 en SPI_CTRL_STAT");
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    task check_equal;
        input [31:0] actual;
        input [31:0] expected;
        input [8*64-1:0] msg;
        begin
            if (actual === expected) begin
                $display("[PASA]  %0s (valor = 0x%08h)", msg, actual);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FALLA] %0s -> esperado: 0x%08h, obtenido: 0x%08h",
                         msg, expected, actual);
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    // ========================================================================
    // Secuencia principal de pruebas (traza transiciones T0-T12)
    // ========================================================================
    integer i;
    initial begin
        $dumpfile("tb_spi_flash.vcd");
        $dumpvars(0, tb_spi_flash);

        tests_passed     = 0;
        tests_failed     = 0;
        total_mosi_bytes = 0;

        // Inicialización de contenido conocido en la Flash simulada
        for (i = 0; i < 256; i = i + 1)
            flash_mem[i] = 8'hFF;
        flash_mem[8'h10] = 8'hA5; // Sprite byte 0
        flash_mem[8'h11] = 8'h3C; // Sprite byte 1 (ráfaga)
        flash_mem[8'h12] = 8'h7E; // Sprite byte 2

        // --------------------------------------------------------------------
        // CASO 1: Reset síncrono (T0) y reposo IDLE (T1)
        // --------------------------------------------------------------------
        $display("\n--- CASO 1: Reset sincrono (T0) y estado de reposo IDLE (T1) ---");
        rst   = 1'b1;
        cs    = 1'b0;
        rd    = 1'b0;
        wmask = 4'b0000;
        addr  = 32'd0;
        d_in  = 32'd0;
        repeat (4) @(posedge clk);
        #1;
        rst = 1'b0;
        repeat (2) @(posedge clk);
        #1;

        check_equal({31'd0, spi_cs_n}, 32'd1, "T0/T1: spi_cs_n en alto en IDLE");
        check_equal({29'd0, dut.u_spi_core.u_fsm_control.state}, 32'd0,
                    "T0/T1: FSM en estado IDLE (000)");
        mmio_read(REG_CTRL_STAT, rdata);
        check_equal(rdata[9:8], 2'b00, "T0/T1: busy=0 y done=0 tras reset");

        // --------------------------------------------------------------------
        // CASO 2: Comando WREN 0x06 (len = 1) y retención de bandera done (T12)
        // --------------------------------------------------------------------
        $display("\n--- CASO 2: Comando 0x06 WREN (len=1) y retencion de done ---");
        total_mosi_bytes = 0;
        mmio_write(REG_CMD_ADDR, {8'h06, 24'h000000});
        mmio_write(REG_CTRL_STAT, 32'h0000_0001); // start=1, cs_hold=0

        @(posedge clk);
        #1;
        check_equal({29'd0, dut.u_spi_core.u_datapath.len}, 32'd1,
                    "T2: Decodificacion dinamica len=1 para opcode 0x06");

        wait_spi_done(rdata);
        check_equal(rdata[9:8], 2'b10, "T12: done=1 y busy=0 al finalizar WREN");
        check_equal({31'd0, spi_cs_n}, 32'd1, "T12: spi_cs_n liberado tras WREN");
        check_equal({31'd0, total_mosi_bytes}, 32'd1, "Trama WREN envio exactamente 1 byte");
        check_equal({24'd0, mosi_log[0]}, 32'h0000_0006, "Byte MOSI recibido = 0x06");

        // Verificar que done permanece retenido varios ciclos después en IDLE (T1)
        repeat (10) @(posedge clk);
        mmio_read(REG_CTRL_STAT, rdata);
        check_equal({31'd0, rdata[9]}, 32'd1, "T1: Bandera done retenida en registro");

        // --------------------------------------------------------------------
        // CASO 3: Sector Erase 0x20 (len = 4) y limpieza de done al reiniciar (T2)
        // --------------------------------------------------------------------
        $display("\n--- CASO 3: Sector Erase 0x20 (len=4) y limpieza de done ---");
        total_mosi_bytes = 0;
        mmio_write(REG_CMD_ADDR, {8'h20, 24'h7F0000});
        mmio_write(REG_CTRL_STAT, 32'h0000_0001); // start=1

        @(posedge clk);
        #1;
        check_equal({29'd0, dut.u_spi_core.u_datapath.len}, 32'd4,
                    "T2: Decodificacion dinamica len=4 para opcode 0x20");
        mmio_read(REG_CTRL_STAT, rdata);
        check_equal(rdata[9:8], 2'b01, "T2: Limpieza inmediata done=0 y busy=1");

        wait_spi_done(rdata);
        check_equal({31'd0, total_mosi_bytes}, 32'd4, "Trama Sector Erase envio 4 bytes");
        check_equal({24'd0, mosi_log[0]}, 32'h0000_0020, "Byte 0 MOSI = 0x20");
        check_equal({24'd0, mosi_log[1]}, 32'h0000_007F, "Byte 1 MOSI = 0x7F");
        check_equal({24'd0, mosi_log[2]}, 32'h0000_0000, "Byte 2 MOSI = 0x00");
        check_equal({24'd0, mosi_log[3]}, 32'h0000_0000, "Byte 3 MOSI = 0x00");

        // --------------------------------------------------------------------
        // CASO 4: Lectura simple Read Data 0x03 (len = 5) desde 0x000010
        // --------------------------------------------------------------------
        $display("\n--- CASO 4: Lectura simple 0x03 (len=5) desde direccion 0x000010 ---");
        total_mosi_bytes = 0;
        mmio_write(REG_TX_DATA, 32'h0000_0000);
        mmio_write(REG_CMD_ADDR, {8'h03, 24'h000010});
        mmio_write(REG_CTRL_STAT, 32'h0000_0001); // start=1, cs_hold=0

        wait_spi_done(rdata);
        check_equal({31'd0, total_mosi_bytes}, 32'd5, "Trama Read envio 5 bytes (40 bits)");
        mmio_read(REG_RX_DATA, rdata);
        check_equal(rdata, 32'h0000_00A5, "SPI_RX_DATA capturo 0xA5 desde MISO");

        // --------------------------------------------------------------------
        // CASO 5: Lectura continua en ráfaga manteniendo cs_hold = 1
        // --------------------------------------------------------------------
        $display("\n--- CASO 5: Lectura continua en rafaga con cs_hold = 1 ---");
        // Primer byte con cs_hold = 1 (bit [1] = 1, bit [0] start = 1 -> 0x03)
        mmio_write(REG_CMD_ADDR, {8'h03, 24'h000010});
        mmio_write(REG_CTRL_STAT, 32'h0000_0003);
        wait_spi_done(rdata);

        check_equal({31'd0, spi_cs_n}, 32'd0,
                    "T12 (cs_hold=1): spi_cs_n permanece en bajo tras primer byte");
        mmio_read(REG_RX_DATA, rdata);
        check_equal(rdata, 32'h0000_00A5, "Primer byte de rafaga = 0xA5");

        // Segundo byte consecutivo (0x000011) liberando cs_hold = 0 al terminar
        mmio_write(REG_CMD_ADDR, {8'h00, 24'h000000}); // Opcode dummy -> len=1
        mmio_write(REG_CTRL_STAT, 32'h0000_0001);      // start=1, cs_hold=0
        wait_spi_done(rdata);

        check_equal({31'd0, spi_cs_n}, 32'd1,
                    "T12 (cs_hold=0): spi_cs_n vuelve a 1 al cerrar rafaga");
        mmio_read(REG_RX_DATA, rdata);
        check_equal(rdata, 32'h0000_003C, "Segundo byte consecutivo de rafaga = 0x3C");

        // --------------------------------------------------------------------
        // Resumen final
        // --------------------------------------------------------------------
        $display("\n====================================================");
        $display(" RESUMEN SIMULACION G2 SPI FLASH: %0d PASA | %0d FALLA",
                 tests_passed, tests_failed);
        $display("====================================================\n");

        if (tests_failed == 0)
            $display("RESULTADO GLOBAL: PASA");
        else
            $display("RESULTADO GLOBAL: FALLA");

        $finish;
    end

    // Watchdog de seguridad contra bloqueos
    initial begin
        #5000000;
        $display("[FALLA] Watchdog timeout excedido");
        $finish;
    end

endmodule
