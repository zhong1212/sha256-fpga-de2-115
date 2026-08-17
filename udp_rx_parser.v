`timescale 1ns / 1ps

module udp_rx_parser (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [7:0]  rx_data,
    input  wire        rx_dv,
    output reg         mac_ip_match,
    output reg  [15:0] packet_length,
    output wire [3:0]  fsm_state_out,
    output reg         raw_packet_seen
);

    // Mẫu IP & Port chuẩn (Normal)
    localparam [31:0] IP_NORM     = 32'hC0A889C8; // 192.168.137.200
    localparam [15:0] PORT_NORM   = 16'h04D2;     // Port 1234
    localparam [39:0] SPARK_NORM  = 40'h535041524B; // Chữ "SPARK"

    // Mẫu IP & Port đảo Nibble (Swapped)
    localparam [31:0] IP_SWAP     = 32'h0C8A988C;
    localparam [15:0] PORT_SWAP   = 16'h402D;
    localparam [39:0] SPARK_SWAP  = 40'h35051425B4;

    reg [39:0] shift_data;
    reg [15:0] len_cnt;
    
    reg match_ip_norm, match_ip_swap;
    reg match_port_norm, match_port_swap;
    reg match_spark;

    // Đưa kết quả phát hiện ra để hiển thị lên dàn LED chẩn đoán
    assign fsm_state_out = {match_spark, (match_ip_norm | match_ip_swap), (match_port_norm | match_port_swap), 1'b0};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            shift_data        <= 40'd0;
            len_cnt           <= 16'd0;
            match_ip_norm     <= 1'b0;
            match_ip_swap     <= 1'b0;
            match_port_norm   <= 1'b0;
            match_port_swap   <= 1'b0;
            match_spark       <= 1'b0;
            mac_ip_match      <= 1'b0;
            packet_length     <= 16'd0;
            raw_packet_seen   <= 1'b0;
        end else begin
            raw_packet_seen <= 1'b0;
            mac_ip_match    <= 1'b0;

            if (!rx_dv) begin
                // Nếu bắt trúng IP HOẶC Port HOẶC chuỗi "SPARK" -> Kích hoạt PASS (LEDG[8])!
                if (match_ip_norm || match_ip_swap || match_port_norm || match_port_swap || match_spark) begin
                    mac_ip_match  <= 1'b1;
                    packet_length <= len_cnt;
                end

                // Reset trạng thái sau mỗi gói tin
                shift_data        <= 40'd0;
                len_cnt           <= 16'd0;
                match_ip_norm     <= 1'b0;
                match_ip_swap     <= 1'b0;
                match_port_norm   <= 1'b0;
                match_port_swap   <= 1'b0;
                match_spark       <= 1'b0;
            end else begin
                len_cnt         <= len_cnt + 1'b1;
                raw_packet_seen <= 1'b1; // Kích hoạt nháy LEDG[1]

                // Dịch dòng byte chạy qua liên tục
                shift_data <= {shift_data[31:0], rx_data};

                // Kiểm tra tất cả các mẫu cùng một lúc
                if ({shift_data[23:0], rx_data} == IP_NORM)    match_ip_norm   <= 1'b1;
                if ({shift_data[23:0], rx_data} == IP_SWAP)    match_ip_swap   <= 1'b1;
                if ({shift_data[7:0], rx_data}  == PORT_NORM)  match_port_norm <= 1'b1;
                if ({shift_data[7:0], rx_data}  == PORT_SWAP)  match_port_swap <= 1'b1;
                if ({shift_data[31:0], rx_data} == SPARK_NORM || {shift_data[31:0], rx_data} == SPARK_SWAP) match_spark <= 1'b1;
            end
        end
    end

endmodule