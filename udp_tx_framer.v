`timescale 1ns / 1ps



// ============================================================================

// Module: udp_tx_framer.v

// Project: SPARK - Anonymous Swarm Attestation for In-Vehicle Networks

// Description: Hardware UDP Transmit Framer.

//              Sends 256-bit SHA-256 digest from FPGA to Pi 5.

//

// Network:

//              FPGA : 192.168.0.200

//              Pi 5 : 192.168.1.12

//              UDP  : 5000

// ============================================================================



module udp_tx_framer #(

    // --- L2: Ethernet MAC Addressing ---

    parameter [47:0] FPGA_MAC       = 48'h02_00_00_00_00_01,

    parameter [47:0] TARGET_MAC     = 48'hFF_FF_FF_FF_FF_FF, // Broadcast hoặc MAC của Pi 5



    // --- L3: IPv4 Addressing ---

    parameter [31:0] FPGA_IP        = 32'hC0_A8_01_C8,       // 192.168.1.200 (khớp DEST_IP bên RX)

    parameter [31:0] TARGET_IP      = 32'hC0_A8_01_0C,       // 192.168.1.12 (Pi 5)



    // --- L4: UDP Port Addressing ---

    parameter [15:0] SRC_PORT       = 16'h13_88,             // 5000

    parameter [15:0] DST_PORT       = 16'h13_88              // 5000 (khớp DEST_PORT bên RX)

)(

    input  wire         clk,

    input  wire         reset_n,



    // --- Control Interface from Bridge / SHA Core ---

    input  wire         tx_start,

    input  wire [31:0]  tx_packet_id,    // Khớp packet_id bên RX

    input  wire [7:0]   tx_packet_type,  // Khớp packet_type bên RX

    input  wire [255:0] tx_payload,      // 256-bit SHA digest

    output reg          tx_busy,

    output reg          tx_done,



    // --- Output PHY Interface (RGMII SDR Mode) ---

    output reg  [7:0]   tx_data,

    output reg          tx_en

);



    // =========================================================================

    // Protocol Constants (Hardcoded to match udp_rx_parser)

    // =========================================================================

    localparam [15:0] MAGIC             = 16'hAA55;

    localparam [7:0]  VERSION           = 8'd1;

    localparam [15:0] CUSTOM_PAYLOAD_LEN= 16'd32;



    // Length constants

    localparam [15:0] IP_TOTAL_LEN      = 16'd70; // 20(IP) + 8(UDP) + 10(Custom) + 32(Payload) = 0x0046

    localparam [15:0] UDP_TOTAL_LEN     = 16'd50; // 8(UDP) + 10(Custom) + 32(Payload) = 0x0032



    // =========================================================================

    // FSM State Definitions (Consistent with RX convention)

    // =========================================================================

    localparam [2:0] 

        S_IDLE     = 3'd0,

        S_PREAMBLE = 3'd1,

        S_ETHERNET = 3'd2,

        S_IPV4     = 3'd3,

        S_UDP      = 3'd4,

        S_CUSTOM   = 3'd5, // Chèn thêm để đồng bộ tầng ứng dụng

        S_PAYLOAD  = 3'd6,

        S_GAP      = 3'd7;



    reg [2:0]   state;

    reg [5:0]   cnt;

    reg [255:0] payload_reg;



    // Lưu chốt ID và Type khi bắt đầu phát

    reg [31:0]  packet_id_reg;

    reg [7:0]   packet_type_reg;



    // =========================================================================

    // IPv4 Header Checksum Calculation

    // =========================================================================

    wire [15:0] ip_chksum;



    wire [31:0] sum_raw =

          16'h4500               // Version, IHL, Type of Service

        + IP_TOTAL_LEN           // Total Length: 70 bytes = 16'h0046

        + 16'h0001               // Identification

        + 16'h4000               // Flags (Don't Fragment), Fragment Offset

        + 16'h4011               // TTL = 64 (0x40), Protocol = UDP (0x11)

        + FPGA_IP[31:16]

        + FPGA_IP[15:0]

        + TARGET_IP[31:16]

        + TARGET_IP[15:0];



    wire [19:0] sum_folded = sum_raw[15:0] + sum_raw[31:16];

    wire [16:0] sum_folded_2 = sum_folded[15:0] + sum_folded[19:16];

    assign ip_chksum = ~(sum_folded_2[15:0] + sum_folded_2[16]);



    // =========================================================================

    // FSM

    // =========================================================================

    always @(posedge clk or negedge reset_n) begin

        if (!reset_n) begin

            state       <= S_IDLE;

            cnt         <= 6'd0;

            tx_data     <= 8'h00;

            tx_en       <= 1'b0;

            tx_busy     <= 1'b0;

            tx_done     <= 1'b0;

            payload_reg <= 256'd0;

        end else begin



            // Default: tx_done is a one-clock pulse

            tx_done <= 1'b0;



            case (state)



                // -------------------------------------------------------------

                // IDLE

                // -------------------------------------------------------------

                S_IDLE: begin

                    tx_en   <= 1'b0;

                    tx_data <= 8'h00;

                    cnt     <= 6'd0;

                    tx_busy <= 1'b0;



                    if (tx_start) begin

                        tx_busy     <= 1'b1;

                        payload_reg <= tx_payload;

                        state       <= S_PREAMBLE;

                    end

                end



                // -------------------------------------------------------------

                // Ethernet preamble + SFD

                // 7 x 0x55 + 0xD5

                // -------------------------------------------------------------

                S_PREAMBLE: begin

                    tx_en <= 1'b1;

                    cnt   <= cnt + 1'b1;



                    if (cnt < 6'd7) begin

                        tx_data <= 8'h55;

                    end else begin

                        tx_data <= 8'hD5;

                        cnt     <= 6'd0;

                        state   <= S_ETHERNET;

                    end

                end



                // -------------------------------------------------------------

                // Ethernet II Header - 14 bytes

                // -------------------------------------------------------------

                S_ETHERNET: begin

                    tx_en <= 1'b1;

                    cnt   <= cnt + 1'b1;



                    case (cnt)

                        // Destination MAC

                        6'd0:  tx_data <= TARGET_MAC[47:40];

                        6'd1:  tx_data <= TARGET_MAC[39:32];

                        6'd2:  tx_data <= TARGET_MAC[31:24];

                        6'd3:  tx_data <= TARGET_MAC[23:16];

                        6'd4:  tx_data <= TARGET_MAC[15:8];

                        6'd5:  tx_data <= TARGET_MAC[7:0];



                        // Source MAC (Đã chuẩn hóa tên thành FPGA_MAC)

                        6'd6:  tx_data <= FPGA_MAC[47:40];

                        6'd7:  tx_data <= FPGA_MAC[39:32];

                        6'd8:  tx_data <= FPGA_MAC[31:24];

                        6'd9:  tx_data <= FPGA_MAC[23:16];

                        6'd10: tx_data <= FPGA_MAC[15:8];

                        6'd11: tx_data <= FPGA_MAC[7:0];



                        // EtherType = IPv4

                        6'd12: tx_data <= 8'h08;

                        6'd13: begin

                            tx_data <= 8'h00;

                            cnt     <= 6'd0;

                            state   <= S_IPV4;

                        end



                        default: tx_data <= 8'h00;

                    endcase

                end



                // -------------------------------------------------------------

                // IPv4 Header - 20 bytes

                // -------------------------------------------------------------

                S_IPV4: begin

                    tx_en <= 1'b1;

                    cnt   <= cnt + 1'b1;



                    case (cnt)



                        6'd0:  tx_data <= 8'h45;       // IPv4 / IHL=5

                        6'd1:  tx_data <= 8'h00;       // TOS



                        // Total Length = 70 bytes (0x0046) - Sử dụng localparam

                        6'd2:  tx_data <= IP_TOTAL_LEN[15:8];

                        6'd3:  tx_data <= IP_TOTAL_LEN[7:0];



                        // Identification

                        6'd4:  tx_data <= 8'h00;

                        6'd5:  tx_data <= 8'h01;



                        // Flags & Fragment Offset (Don't Fragment)

                        6'd6:  tx_data <= 8'h40;

                        6'd7:  tx_data <= 8'h00;



                        // TTL = 64

                        6'd8:  tx_data <= 8'h40;



                        // Protocol = UDP (0x11)

                        6'd9:  tx_data <= 8'h11;



                        // Header checksum (Sử dụng ip_chksum đã được vá lỗi carry)

                        6'd10: tx_data <= ip_chksum[15:8];

                        6'd11: tx_data <= ip_chksum[7:0];



                        // Source IP (Đã chuẩn hóa thành FPGA_IP)

                        6'd12: tx_data <= FPGA_IP[31:24];

                        6'd13: tx_data <= FPGA_IP[23:16];

                        6'd14: tx_data <= FPGA_IP[15:8];

                        6'd15: tx_data <= FPGA_IP[7:0];



                        // Destination IP

                        6'd16: tx_data <= TARGET_IP[31:24];

                        6'd17: tx_data <= TARGET_IP[23:16];

                        6'd18: tx_data <= TARGET_IP[15:8];



                        6'd19: begin

                            tx_data <= TARGET_IP[7:0];

                            cnt     <= 6'd0;

                            state   <= S_UDP; // Chuyển sang S_UDP

                        end



                        default: tx_data <= 8'h00;



                    endcase

                end

              

                // -------------------------------------------------------------

                // UDP Header - 8 bytes

                // -------------------------------------------------------------

                S_UDP: begin

                    tx_en <= 1'b1;

                    cnt   <= cnt + 1'b1;



                    case (cnt)

                        // Source Port

                        6'd0: tx_data <= SRC_PORT[15:8];

                        6'd1: tx_data <= SRC_PORT[7:0];



                        // Destination Port

                        6'd2: tx_data <= DST_PORT[15:8];

                        6'd3: tx_data <= DST_PORT[7:0];



                        // UDP Length = 50 bytes (Sử dụng localparam UDP_TOTAL_LEN)

                        6'd4: tx_data <= UDP_TOTAL_LEN[15:8];

                        6'd5: tx_data <= UDP_TOTAL_LEN[7:0];



                        // UDP checksum = 0x0000 (Cho phép bỏ qua trong IPv4)

                        6'd6: tx_data <= 8'h00;

                        6'd7: begin

                            tx_data <= 8'h00;

                            cnt     <= 6'd0;

                            state   <= S_CUSTOM; // Chuyển sang S_CUSTOM thay vì nhảy thẳng vào PAYLOAD

                        end



                        default: tx_data <= 8'h00;

                    endcase

                end



                // -------------------------------------------------------------

                // Custom Application Header - 10 bytes

                // Sử dụng packet_id_reg và packet_type_reg đã latch ở S_IDLE

                // -------------------------------------------------------------

                S_CUSTOM: begin

                    tx_en <= 1'b1;

                    cnt   <= cnt + 1'b1;



                    case (cnt)

                        6'd0: tx_data <= MAGIC[15:8];

                        6'd1: tx_data <= MAGIC[7:0];

                        

                        6'd2: tx_data <= VERSION;

                        6'd3: tx_data <= packet_type_reg;

                        

                        6'd4: tx_data <= packet_id_reg[31:24];

                        6'd5: tx_data <= packet_id_reg[23:16];

                        6'd6: tx_data <= packet_id_reg[15:8];

                        6'd7: tx_data <= packet_id_reg[7:0];

                        

                        6'd8: tx_data <= CUSTOM_PAYLOAD_LEN[15:8];

                        6'd9: begin

                            tx_data <= CUSTOM_PAYLOAD_LEN[7:0];

                            cnt     <= 6'd0;

                            state   <= S_PAYLOAD;

                        end



                        default: tx_data <= 8'h00;

                    endcase

                end



                // -------------------------------------------------------------

                // Payload - 32 bytes (Phát dữ liệu 256-bit nguyên vẹn)

                // -------------------------------------------------------------

                S_PAYLOAD: begin

                    tx_en       <= 1'b1;

                    tx_data     <= payload_reg[255:248]; // Đẩy byte cao nhất (MSB) ra trước

                    payload_reg <= {payload_reg[247:0], 8'h00}; // Dịch trái 8 bit

                    cnt         <= cnt + 1'b1;



                    if (cnt == 6'd31) begin

                        cnt   <= 6'd0;

                        state <= S_GAP; // Đủ 32 bytes thì hạ tx_en, chuyển sang tạo khoảng nghỉ

                    end

                end



                // -------------------------------------------------------------

                // Inter-Packet Gap (IPG) - 12 cycles

                // -------------------------------------------------------------

                S_GAP: begin

                    tx_en   <= 1'b0;

                    tx_data <= 8'h00;

                    cnt     <= cnt + 1'b1;



                    if (cnt == 6'd11) begin

                        tx_done <= 1'b1; // Báo hiệu đã phát xong trọn vẹn gói tin

                        tx_busy <= 1'b0; // Module sẵn sàng nhận lệnh tx_start mới

                        cnt     <= 6'd0;

                        state   <= S_IDLE;

                    end

                end



                // -------------------------------------------------------------

                // Bảo vệ FSM

                // -------------------------------------------------------------

                default: begin

                    state   <= S_IDLE;

                    tx_busy <= 1'b0;

                    tx_en   <= 1'b0;

                    cnt     <= 6'd0;

                end

            endcase

        end

    end

endmodule