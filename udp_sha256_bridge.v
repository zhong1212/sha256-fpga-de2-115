`timescale 1ns / 1ps

// ============================================================================
// Module: udp_sha256_bridge.v (Bypass Mode)
// Project: SPARK - Anonymous Swarm Attestation for In-Vehicle Networks
// Description: Đóng vai trò cầu nối ở miền 50MHz. Trực tiếp rút dữ liệu từ 
//              ngõ ra của RX FIFO và đẩy thẳng vào ngõ vào của TX FIFO,
//              quản lý trễ 1 nhịp đọc của M9K Block RAM.
// ============================================================================

module udp_sha256_bridge #(
    parameter DATA_WIDTH = 296 // packet_id (32) + packet_type (8) + payload (256)
)(
    input  wire                  clk,       // 50 MHz
    input  wire                  reset_n,

    // --- Giao tiếp với RX FIFO (Đọc dữ liệu ra) ---
    input  wire                  rx_empty,
    output reg                   rx_rd_en,
    input  wire [DATA_WIDTH-1:0] rx_dout,

    // --- Giao tiếp với TX FIFO (Ghi dữ liệu vào) ---
    input  wire                  tx_full,
    output reg                   tx_wr_en,
    output reg  [DATA_WIDTH-1:0] tx_din,

    // --- Diagnostic Status ---
    output wire [1:0]            bridge_state_out
);

    // =========================================================================
    // FSM State Definitions (Đúng 3 trạng thái theo yêu cầu)
    // =========================================================================
    localparam [1:0] 
        S_IDLE  = 2'd0,
        S_WAIT  = 2'd1,
        S_WRITE = 2'd2;

    reg [1:0] state;
    assign bridge_state_out = state;

    // =========================================================================
    // FSM Control Logic
    // =========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state    <= S_IDLE;
            rx_rd_en <= 1'b0;
            tx_wr_en <= 1'b0;
            tx_din   <= {DATA_WIDTH{1'b0}};
        end else begin
            
            // Xóa cờ kích hoạt đọc/ghi mặc định sau mỗi nhịp xung để tạo pulse 1 chu kỳ
            rx_rd_en <= 1'b0;
            tx_wr_en <= 1'b0;

            case (state)
                // -------------------------------------------------------------
                // Nhịp 1: Chờ RX FIFO có dữ liệu và TX FIFO chưa đầy
                // -------------------------------------------------------------
                S_IDLE: begin
                    if (!rx_empty && !tx_full) begin
                        rx_rd_en <= 1'b1; // Bơm xung đọc vào RX FIFO
                        state    <= S_WAIT;
                    end
                end

                // -------------------------------------------------------------
                // Nhịp 2: Đứng chờ Block RAM (RX FIFO) đẩy dữ liệu ra ngõ rx_dout
                // Trễ 1 nhịp là đặc trưng bắt buộc của Synchronous RAM (M9K)
                // -------------------------------------------------------------
                S_WAIT: begin
                    state <= S_WRITE;
                end

                // -------------------------------------------------------------
                // Nhịp 3: Chốt dữ liệu đã ổn định vào tx_din và kích hoạt ghi
                // -------------------------------------------------------------
                S_WRITE: begin
                    tx_din   <= rx_dout;
                    tx_wr_en <= 1'b1; // Kích hoạt FIFO TX nhận dữ liệu
                    state    <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule