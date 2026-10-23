`timescale 1ns / 1ps

// ============================================================================
// Module: de2_115_zonal_top
// Project: SPARK - Anonymous Swarm Attestation for In-Vehicle Networks
// Architecture: RX (125MHz) -> FIFO 1 -> Bridge (50MHz) -> FIFO 2 -> TX (125MHz)
// ============================================================================

module de2_115_zonal_top (
    input  wire        CLOCK_50,

    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,

    input  wire        ENET0_RX_CLK,
    input  wire [3:0]  ENET0_RX_DATA,
    input  wire        ENET0_RX_DV,

    output wire        ENET0_GTX_CLK,
    output wire [3:0]  ENET0_TX_DATA,
    output wire        ENET0_TX_EN,
    output wire        ENET0_RST_N
);

    // ============================================================
    // 1. HARDWARE PHY RESET (10ms Delay)
    // ============================================================
    reg [19:0] phy_rst_cnt = 20'd0;
    reg        phy_rst_n   = 1'b0;

    always @(posedge CLOCK_50) begin
        if (phy_rst_cnt < 20'd500_000) begin
            phy_rst_cnt <= phy_rst_cnt + 1'b1;
            phy_rst_n   <= 1'b0;
        end else begin
            phy_rst_n   <= 1'b1;
        end
    end
    assign ENET0_RST_N = phy_rst_n;

    // ============================================================
    // 2. CLOCK MANAGEMENT (TX PLL: 50 MHz -> 125 MHz)
    // ============================================================
    wire [4:0] tx_pll_clk;
    wire       tx_clk;
    wire       tx_pll_locked;
    wire       tx_reset_n;

    assign tx_clk     = tx_pll_clk[0];
    assign tx_reset_n = phy_rst_n & tx_pll_locked;

    altpll #(
        .bandwidth_type("AUTO"),
        .clk0_divide_by(2),
        .clk0_duty_cycle(50),
        .clk0_multiply_by(5),
        .compensate_clock("CLK0"),
        .inclk0_input_frequency(20000),
        .operation_mode("NORMAL"),
        .pll_type("AUTO"),
        .width_clock(5)
    ) tx_pll (
        .inclk({1'b0, CLOCK_50}),
        .areset(~phy_rst_n),
        .clk(tx_pll_clk),
        .locked(tx_pll_locked)
    );

    assign ENET0_GTX_CLK = tx_clk;

    // ============================================================
    // 3. RGMII RX (DDR to SDR Conversion)
    // ============================================================
    wire [3:0] rx_data_high, rx_data_low;
    wire       rx_dv_high, rx_dv_low;

    altddio_in #(
        .width(4), .intended_device_family("Cyclone IV E")
    ) ddrio_data_inst (
        .datain(ENET0_RX_DATA),
        .inclock(ENET0_RX_CLK),
        .dataout_h(rx_data_high),
        .dataout_l(rx_data_low),
        .aclr(~phy_rst_n)
    );

    altddio_in #(
        .width(1), .intended_device_family("Cyclone IV E")
    ) ddrio_ctrl_inst (
        .datain(ENET0_RX_DV),
        .inclock(ENET0_RX_CLK),
        .dataout_h(rx_dv_high),
        .dataout_l(rx_dv_low),
        .aclr(~phy_rst_n)
    );

    wire [7:0] rx_byte = {rx_data_low, rx_data_high};
    wire       rx_dv   = rx_dv_high ^ rx_dv_low;

    // ============================================================
    // 4. UDP RX PARSER (Miền 125 MHz)
    // ============================================================
    wire        packet_valid;
    wire [31:0] packet_id;
    wire [7:0]  packet_type;
    wire [255:0] payload;
    wire [15:0] packet_length, payload_len;
    
    wire raw_packet_seen, ip_matched, port_matched, magic_matched;
    wire [3:0] fsm_state;

    udp_rx_parser parser_inst (
        .clk(ENET0_RX_CLK),
        .reset_n(phy_rst_n),
        .rx_data(rx_byte),
        .rx_dv(rx_dv),
        .packet_valid(packet_valid),
        .packet_length(packet_length),
        .packet_id(packet_id),
        .packet_type(packet_type),
        .payload_len(payload_len),
        .payload(payload),
        .raw_packet_seen(raw_packet_seen),
        .ip_matched_out(ip_matched),
        .port_matched_out(port_matched),
        .magic_matched_out(magic_matched),
        .fsm_state_out(fsm_state)
    );

    // ============================================================
    // 5. CDC INTERCONNECT: RX -> FIFO -> BRIDGE -> FIFO -> TX
    // DATA_WIDTH = 296 (32-bit ID + 8-bit Type + 256-bit Payload)
    // ============================================================
    wire [295:0] rx_fifo_din = {packet_id, packet_type, payload};
    wire [295:0] rx_fifo_dout;
    wire         rx_fifo_full, rx_fifo_empty;
    wire         bridge_rx_rd_en;

    // --- RX ASYNC FIFO ---
    async_fifo #(.DATA_WIDTH(296), .ADDR_WIDTH(4)) rx_fifo_inst (
        .wr_clk(ENET0_RX_CLK),  .wr_rst_n(phy_rst_n),
        .wr_en(packet_valid),   .din(rx_fifo_din),   .full(rx_fifo_full),
        
        .rd_clk(CLOCK_50),      .rd_rst_n(phy_rst_n),
        .rd_en(bridge_rx_rd_en),.dout(rx_fifo_dout), .empty(rx_fifo_empty)
    );

    wire [295:0] tx_fifo_din;
    wire [295:0] tx_fifo_dout;
    wire         tx_fifo_full, tx_fifo_empty;
    wire         bridge_tx_wr_en;

    // --- BRIDGE BYPASS (Miền 50 MHz) ---
    wire [1:0] bridge_state;
    udp_sha256_bridge bridge_inst (
        .clk(CLOCK_50),            .reset_n(phy_rst_n),
        .rx_empty(rx_fifo_empty),  .rx_rd_en(bridge_rx_rd_en), .rx_dout(rx_fifo_dout),
        .tx_full(tx_fifo_full),    .tx_wr_en(bridge_tx_wr_en), .tx_din(tx_fifo_din),
        .bridge_state_out(bridge_state)
    );

    // --- TX ASYNC FIFO ---
    wire framer_tx_rd_en;
    async_fifo #(.DATA_WIDTH(296), .ADDR_WIDTH(4)) tx_fifo_inst (
        .wr_clk(CLOCK_50),       .wr_rst_n(phy_rst_n),
        .wr_en(bridge_tx_wr_en), .din(tx_fifo_din),    .full(tx_fifo_full),
        
        .rd_clk(tx_clk),         .rd_rst_n(tx_reset_n),
        .rd_en(framer_tx_rd_en), .dout(tx_fifo_dout),  .empty(tx_fifo_empty)
    );

    // ============================================================
    // 6. PHASE ALIGNMENT (Miền 125 MHz - TX)
    // D-FlipFlop trễ 1 nhịp để khớp với M9K RAM của TX FIFO
    // ============================================================
    wire tx_busy;
    reg  framer_rd_en_reg;
    reg  tx_start_reg;

    always @(posedge tx_clk or negedge tx_reset_n) begin
        if (!tx_reset_n) begin
            framer_rd_en_reg <= 1'b0;
            tx_start_reg     <= 1'b0;
        end else begin
            // Kích xung đọc khi có dữ liệu, Framer rảnh và hệ thống không kẹt xung cũ
            if (!tx_fifo_empty && !tx_busy && !framer_rd_en_reg && !tx_start_reg)
                framer_rd_en_reg <= 1'b1;
            else
                framer_rd_en_reg <= 1'b0;

            // D-FlipFlop tạo Phase Alignment (Trễ 1 nhịp clock)
            tx_start_reg <= framer_rd_en_reg; 
        end
    end

    assign framer_tx_rd_en = framer_rd_en_reg;
    wire   tx_start        = tx_start_reg;

    // Bóc tách Bus 296-bit trở lại để đẩy vào TX Framer
    wire [31:0]  tx_framer_id   = tx_fifo_dout[295:264];
    wire [7:0]   tx_framer_type = tx_fifo_dout[263:256];
    wire [255:0] tx_framer_plld = tx_fifo_dout[255:0];

    // ============================================================
    // 7. UDP TX FRAMER (Miền 125 MHz)
    // ============================================================
    wire [7:0] tx_byte;
    wire       tx_en_sdr;
    wire       tx_done;

    udp_tx_framer tx_framer_inst (
        .clk(tx_clk),
        .reset_n(tx_reset_n),
        .tx_start(tx_start),
        .tx_packet_id(tx_framer_id),
        .tx_packet_type(tx_framer_type),
        .tx_payload(tx_framer_plld),
        .tx_busy(tx_busy),
        .tx_done(tx_done),
        .tx_data(tx_byte),
        .tx_en(tx_en_sdr)
    );

    // ============================================================
    // 8. RGMII TX (SDR to DDR Conversion)
    // ============================================================
    altddio_out #(
        .width(4), .intended_device_family("Cyclone IV E")
    ) ddrio_tx_data_inst (
        .datain_h(tx_byte[3:0]),
        .datain_l(tx_byte[7:4]),
        .outclock(tx_clk),
        .outclocken(1'b1),
        .aclr(~tx_reset_n),
        .dataout(ENET0_TX_DATA)
    );

    altddio_out #(
        .width(1), .intended_device_family("Cyclone IV E")
    ) ddrio_tx_en_inst (
        .datain_h(tx_en_sdr),
        .datain_l(tx_en_sdr),
        .outclock(tx_clk),
        .outclocken(1'b1),
        .aclr(~tx_reset_n),
        .dataout(ENET0_TX_EN)
    );

    // ============================================================
    // 9. DEBUG & LED STATUS
    // ============================================================
    reg [26:0] clk_cnt = 27'd0;
    always @(posedge ENET0_RX_CLK or negedge phy_rst_n) begin
        if (!phy_rst_n) clk_cnt <= 27'd0;
        else clk_cnt <= clk_cnt + 1'b1;
    end

    // RX Leds
    assign LEDG[0] = clk_cnt[26];        // Heartbeat (Chớp nháy)
    assign LEDG[1] = raw_packet_seen;
    assign LEDG[2] = phy_rst_n;
    assign LEDG[3] = port_matched;
    assign LEDG[4] = ip_matched;
    assign LEDG[5] = magic_matched;
    assign LEDG[6] = packet_valid;
    assign LEDG[7] = tx_busy;
    assign LEDG[8] = tx_en_sdr;

    // Status / System state Leds
    assign LEDR[1:0]   = bridge_state;
    assign LEDR[2]     = tx_start;       // Nháy lên 1 nhịp khi Framer bắt đầu
    assign LEDR[15]    = tx_busy;
    assign LEDR[17]    = tx_pll_locked;  // Phải luôn sáng báo hiệu PLL ổn định

    assign LEDR[14:3]  = 12'd0;
    assign LEDR[16]    = 1'b0;
endmodule