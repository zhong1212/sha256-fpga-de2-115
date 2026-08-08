`timescale 1ns / 1ps

module de2_115_zonal_top (
    input  wire        CLOCK_50,
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,

    // Ethernet PHY 0 Pins
    output wire        ENET0_RST_N,
    input  wire        ENET0_RX_CLK,
    input  wire [3:0]  ENET0_RX_DATA,
    input  wire        ENET0_RX_DV,
    
    output wire        ENET0_GTX_CLK,
    output wire [3:0]  ENET0_TX_DATA,
    output wire        ENET0_TX_EN
);

    // Tạo xung reset cho chip PHY Marvell 
    reg [19:0] phy_rst_cnt = 20'h0;
    reg        phy_rst_n   = 1'b0;

    always @(posedge CLOCK_50) begin
        if (phy_rst_cnt < 20'hF_FFFF) begin // Giữ Reset mức LOW khoảng 20ms
            phy_rst_cnt <= phy_rst_cnt + 1'b1;
            phy_rst_n   <= 1'b0;
        end else begin
            phy_rst_n   <= 1'b1;            // Nhả mức HIGH
        end
    end

    assign ENET0_RST_N = phy_rst_n;

    // Chuyển đổi RGMII RX (DDR 4-bit -> SDR 8-bit)
    wire [7:0] rx_byte;
    wire [1:0] rx_ctl;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : rx_data_ddio
            ALTDDIO_IN #(
                .width(1)
            ) ddio_rx_inst (
                .datain(ENET0_RX_DATA[i]),
                .inclock(ENET0_RX_CLK),
                .dataout_h(rx_byte[i]),     // Bit ở sườn lên
                .dataout_l(rx_byte[i+4])    // Bit ở sườn xuống
            );
        end
    endgenerate

    ALTDDIO_IN #(.width(1)) ddio_rx_ctl (
        .datain(ENET0_RX_DV),
        .inclock(ENET0_RX_CLK),
        .dataout_h(rx_ctl[0]),
        .dataout_l(rx_ctl[1])
    );

    // Passthrough Trực Tiếp Ở Tầng SDR (Loopback Vòng 0)
    wire [7:0] tx_byte = (rx_ctl[0] == 1'b1) ? rx_byte : 8'h00;
    wire [1:0] tx_ctl  = rx_ctl;

    // Chuyển đổi RGMII TX (SDR 8-bit -> DDR 4-bit)
    generate
        for (i = 0; i < 4; i = i + 1) begin : tx_data_ddio
            ALTDDIO_OUT #(
                .width(1)
            ) ddio_tx_inst (
                .datain_h(tx_byte[i]),
                .datain_l(tx_byte[i+4]),
                .outclock(ENET0_RX_CLK),
                .dataout(ENET0_TX_DATA[i])
            );
        end
    endgenerate

    ALTDDIO_OUT #(.width(1)) ddio_tx_ctl (
        .datain_h(tx_ctl[0]),
        .datain_l(tx_ctl[1]),
        .outclock(ENET0_RX_CLK),
        .dataout(ENET0_TX_EN)
    );

    ALTDDIO_OUT #(.width(1)) ddio_gtx_clk (
        .datain_h(1'b1),
        .datain_l(1'b0),
        .outclock(ENET0_RX_CLK), 
        .dataout(ENET0_GTX_CLK)
    );

    // Đèn báo debug + Bộ kéo dài xung LED
	 
    // Đèn chớp báo nhịp Clock 125MHz
    reg [24:0] clk_cnt;
    always @(posedge ENET0_RX_CLK) clk_cnt <= clk_cnt + 1'b1;
    assign LEDG[0] = clk_cnt[24]; 
    assign LEDG[8] = 1'b1;        // Báo có điện

    // Kéo dài thời gian sáng cho LED
    reg [23:0] rx_led_hold_cnt = 24'd0;
    always @(posedge ENET0_RX_CLK) begin
        if (ENET0_RX_DV == 1'b1) begin
            // Có gói tin -> Nạp bộ đếm (sáng 0.1s)
            rx_led_hold_cnt <= 24'd12_500_000; //12.5 triệu clock
        end else if (rx_led_hold_cnt > 24'd0) begin
            // Giảm dần bộ đếm
            rx_led_hold_cnt <= rx_led_hold_cnt - 1'b1;
        end
    end
    
    // Bộ đếm chưa về 0 -> LEDR[0] sáng
    assign LEDR[0] = (rx_led_hold_cnt > 24'd0);

endmodule