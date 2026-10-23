`timescale 1ns / 1ps



// ============================================================================

// Module: async_fifo.v

// Project: SPARK - Anonymous Swarm Attestation for In-Vehicle Networks

// Description: Behavioral Asynchronous Dual-Clock FIFO for Simulation & CDC.

// Safely transfers streaming packet byte data between Ethernet RX 

// Clock Domain (25MHz / 125MHz) and Crypto Core Domain (50MHz).

// ============================================================================



module async_fifo #(

    // DATA_WIDTH = 256 (payload) + 32 (packet_id) + 8 (packet_type) = 296 bits

    // Có thể nâng lên 352 nếu cần truyền thêm MAC/IP header

    parameter DATA_WIDTH = 296, 

    

    // ADDR_WIDTH = 4 -> Depth = 16. Đủ an toàn và tiết kiệm tài nguyên FPGA Cyclone IV

    parameter ADDR_WIDTH = 4 

)(

    // Write Clock Domain (Ethernet RX Clock - 125MHz)

    input  wire                  wr_clk,

    input  wire                  wr_rst_n,

    input  wire                  wr_en,

    input  wire [DATA_WIDTH-1:0] din,

    output wire                  full,

    

    // Read Clock Domain (System/Crypto Core Clock - 50MHz)

    input  wire                  rd_clk,

    input  wire                  rd_rst_n,

    input  wire                  rd_en,

    output wire [DATA_WIDTH-1:0] dout,

    output wire                  empty

);



    localparam DEPTH = 1 << ADDR_WIDTH;



    // Memory array (Sẽ được tổng hợp thành Block RAM trên FPGA)

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];



    // Pointers (Cần thêm 1 bit MSB để phân biệt Full/Empty)

    reg [ADDR_WIDTH:0] wr_ptr, wr_ptr_gray;

    reg [ADDR_WIDTH:0] rd_ptr, rd_ptr_gray;



    // Synchronizers (2-stage Flip-Flops để chống Metastability)

    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;

    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;



    // Binary to Gray conversion function

    function [ADDR_WIDTH:0] bin2gray(input [ADDR_WIDTH:0] bin);

        bin2gray = bin ^ (bin >> 1);

    endfunction



    // -------------------------------------------------------------------------

    // Write Clock Domain Logic

    // -------------------------------------------------------------------------

    always @(posedge wr_clk or negedge wr_rst_n) begin

        if (!wr_rst_n) begin

            wr_ptr      <= 0;

            wr_ptr_gray <= 0;

        end else if (wr_en && !full) begin

            mem[wr_ptr[ADDR_WIDTH-1:0]] <= din;

            wr_ptr                      <= wr_ptr + 1'b1;

            wr_ptr_gray                 <= bin2gray(wr_ptr + 1'b1);

        end

    end



    // Sync Read Pointer to Write Domain

    always @(posedge wr_clk or negedge wr_rst_n) begin

        if (!wr_rst_n) begin

            rd_ptr_gray_sync1 <= 0;

            rd_ptr_gray_sync2 <= 0;

        end else begin

            rd_ptr_gray_sync1 <= rd_ptr_gray;

            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;

        end

    end



    // Full Flag Generation

    assign full = (wr_ptr_gray == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});



    // -------------------------------------------------------------------------

    // Read Clock Domain Logic

    // -------------------------------------------------------------------------

    always @(posedge rd_clk or negedge rd_rst_n) begin

        if (!rd_rst_n) begin

            rd_ptr      <= 0;

            rd_ptr_gray <= 0;

        end else if (rd_en && !empty) begin

            rd_ptr      <= rd_ptr + 1'b1;

            rd_ptr_gray <= bin2gray(rd_ptr + 1'b1);

        end

    end



    // Sync Write Pointer to Read Domain

    always @(posedge rd_clk or negedge rd_rst_n) begin

        if (!rd_rst_n) begin

            wr_ptr_gray_sync1 <= 0;

            wr_ptr_gray_sync2 <= 0;

        end else begin

            wr_ptr_gray_sync1 <= wr_ptr_gray;

            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;

        end

    end



    // Empty Flag Generation

    assign empty = (rd_ptr_gray == wr_ptr_gray_sync2);

    

    // Data out

    assign dout = mem[rd_ptr[ADDR_WIDTH-1:0]];



endmodule