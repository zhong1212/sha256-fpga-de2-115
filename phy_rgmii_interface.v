

`timescale 1ns / 1ps

module phy_rgmii_interface (
    input  wire        rx_clk,       // 125 MHz từ PIN_A15
    input  wire [3:0]  rgmii_rxd,    // 4-bit dữ liệu DDR từ PHY
    input  wire        rgmii_rx_dv,  // Tín hiệu Data Valid (RX_CTL)
    output reg  [7:0]  byte_out,     // 8-bit dữ liệu SDR ghép được
    output reg         dv_out        // Cờ báo Data Valid chuẩn SDR
);

    reg [3:0] rxd_pos;
    reg [3:0] rxd_neg;
    reg       dv_pos;
    reg       dv_neg;

    // 1. Chốt dữ liệu và Data Valid ở sườn dương
    always @(posedge rx_clk) begin
        rxd_pos <= rgmii_rxd;
        dv_pos  <= rgmii_rx_dv;
    end

    // 2. Chốt dữ liệu và Data Valid ở sườn âm
    always @(negedge rx_clk) begin
        rxd_neg <= rgmii_rxd;
        dv_neg  <= rgmii_rx_dv;
    end

    // 3. Ghép thành 8-bit và lọc cờ Data Valid sạch sẽ (chỉ lên mức 1 khi có gói tin thực tế)
    always @(posedge rx_clk) begin
        byte_out <= {rxd_neg, rxd_pos};
        dv_out   <= dv_pos & dv_neg; // Chỉ khi cả 2 sườn cùng có tín hiệu mới coi là valid
    end

endmodule