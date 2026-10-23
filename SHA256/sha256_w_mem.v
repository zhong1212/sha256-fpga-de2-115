// =====================================================================
// Author: Nhat Trung Le/ Hardware Accelerator for SPARK - Anonymous 
// Swarm Attestation for In-Vehicle Networks
// Module: sha256_w_mem
// Description: Message schedule module with sliding window for SHA-256
//
// Based on the original design by Joachim Strömbergson (Secworks)
// Licensed under the BSD 2-Clause License.
// =====================================================================
//======================================================================
//
// sha256_w_mem.v
// -------------------
// The W memory. This version uses 16 32-bit registers as a sliding
// window to generate the 64 words.
//
//
// Author: Joachim Strombergson
// Copyright (c) 2013, Secworks Sweden AB
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or
// without modification, are permitted provided that the following
// conditions are met:
//
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in
//    the documentation and/or other materials provided with the
//    distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
// FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
// COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
// BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
// STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//======================================================================

`default_nettype none

module sha256_w_mem (
    input  wire        clk, 
    input  wire        reset_n, 

    input  wire [511:0] block, 
    input  wire [5:0]  round, 

    input  wire        init,
    input  wire        next,
    output wire [31:0] w
);
// =========================================================================
    // 1. KHAI BÁO CÁC THANH GHI VÀ DÂY TRUNG GIAN
    // =========================================================================
    reg [31:0] w_mem [0:15]; // Mảng 16 thanh ghi vật lý (Cửa sổ trượt 512-bit)

    // 16 đường dây tạm chứa dữ liệu thế hệ tiếp theo (Next State)
    reg [31:0] w_mem00_new, w_mem01_new, w_mem02_new, w_mem03_new;
    reg [31:0] w_mem04_new, w_mem05_new, w_mem06_new, w_mem07_new;
    reg [31:0] w_mem08_new, w_mem09_new, w_mem10_new, w_mem11_new;
    reg [31:0] w_mem12_new, w_mem13_new, w_mem14_new, w_mem15_new;

    reg        w_mem_we; // Cờ cho phép ghi vào w_mem

    // Biến tạm cho phép toán SHA-256
    reg [31:0] w0, w1, w9, w14;
    reg [31:0] d0, d1;
    reg [31:0] w_new;
    reg [31:0] w_tmp;

    // =========================================================================
    // 2. MẠCH TUẦN TỰ (Sequential Logic): Chốt dữ liệu theo nhịp Clock
    // =========================================================================
    always @(posedge clk or negedge reset_n) begin : reg_update
        integer i;
        if (!reset_n) begin
            for (i = 0; i < 16; i = i + 1) begin
                w_mem[i] <= 32'h0;
            end
        end
        else begin
            if (w_mem_we) begin
                w_mem[0]  <= w_mem00_new;
                w_mem[1]  <= w_mem01_new;
                w_mem[2]  <= w_mem02_new;
                w_mem[3]  <= w_mem03_new;
                w_mem[4]  <= w_mem04_new;
                w_mem[5]  <= w_mem05_new;
                w_mem[6]  <= w_mem06_new;
                w_mem[7]  <= w_mem07_new;
                w_mem[8]  <= w_mem08_new;
                w_mem[9]  <= w_mem09_new;
                w_mem[10] <= w_mem10_new;
                w_mem[11] <= w_mem11_new;
                w_mem[12] <= w_mem12_new;
                w_mem[13] <= w_mem13_new;
                w_mem[14] <= w_mem14_new;
                w_mem[15] <= w_mem15_new;
            end
        end
    end

    // =========================================================================
    // 3. MẠCH TỔ HỢP (Combinational Logic): Tính toán toán học & Nối dây
    // =========================================================================
    always @(*) begin : w_mem_select
        // A. Set giá trị mặc định để chống Unintended Latch
        w_mem00_new = 32'h0;
        w_mem01_new = 32'h0;
        w_mem02_new = 32'h0;
        w_mem03_new = 32'h0;
        w_mem04_new = 32'h0;
        w_mem05_new = 32'h0;
        w_mem06_new = 32'h0;
        w_mem07_new = 32'h0;
        w_mem08_new = 32'h0;
        w_mem09_new = 32'h0;
        w_mem10_new = 32'h0;
        w_mem11_new = 32'h0;
        w_mem12_new = 32'h0;
        w_mem13_new = 32'h0;
        w_mem14_new = 32'h0;
        w_mem15_new = 32'h0;
        w_mem_we    = 1'b0;

        // B. Rút trích 4 điểm chốt từ mảng thanh ghi
        w0  = w_mem[0];
        w1  = w_mem[1];
        w9  = w_mem[9];
        w14 = w_mem[14];

        // C. Tính d0 (sigma0), d1 (sigma1) và w_new theo FIPS 180-4
        d0    = {w1[6:0], w1[31:7]} ^ {w1[17:0], w1[31:18]} ^ {3'b000, w1[31:3]};
        d1    = {w14[16:0], w14[31:17]} ^ {w14[18:0], w14[31:19]} ^ {10'b0000000000, w14[31:10]};
        w_new = d1 + w9 + d0 + w0;

        // D. Xử lý kịch bản Nạp ban đầu vs Dịch trượt cửa sổ
        if (init) begin
            w_mem00_new = block[511 : 480];
            w_mem01_new = block[479 : 448];
            w_mem02_new = block[447 : 416];
            w_mem03_new = block[415 : 384];
            w_mem04_new = block[383 : 352];
            w_mem05_new = block[351 : 320];
            w_mem06_new = block[319 : 288];
            w_mem07_new = block[287 : 256];
            w_mem08_new = block[255 : 224];
            w_mem09_new = block[223 : 192];
            w_mem10_new = block[191 : 160];
            w_mem11_new = block[159 : 128];
            w_mem12_new = block[127 :  96];
            w_mem13_new = block[ 95 :  64];
            w_mem14_new = block[ 63 :  32];
            w_mem15_new = block[ 31 :   0];
            w_mem_we    = 1'b1;
        end
        else if (next && (round > 15)) begin
            w_mem00_new = w_mem[1];
            w_mem01_new = w_mem[2];
            w_mem02_new = w_mem[3];
            w_mem03_new = w_mem[4];
            w_mem04_new = w_mem[5];
            w_mem05_new = w_mem[6];
            w_mem06_new = w_mem[7];
            w_mem07_new = w_mem[8];
            w_mem08_new = w_mem[9];
            w_mem09_new = w_mem[10];
            w_mem10_new = w_mem[11];
            w_mem11_new = w_mem[12];
            w_mem12_new = w_mem[13];
            w_mem13_new = w_mem[14];
            w_mem14_new = w_mem[15];
            w_mem15_new = w_new;
            w_mem_we    = 1'b1;
        end

        // E. Bộ dồn kênh (MUX) chọn ngõ ra w_tmp
        if (round <= 15) begin
            w_tmp = w_mem[round[3:0]];
        end
        else begin
            w_tmp = w_new;
        end
    end
	 // Gán ngõ ra liên tục
    assign w = w_tmp;

endmodule


 





