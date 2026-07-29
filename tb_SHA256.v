`timescale 1ns/1ps

module tb_SHA256();

    // 1. Khai báo các tín hiệu điều khiển và dữ liệu
    reg         clk;
    reg         reset;
    reg         start;
    reg [511:0] block_in;
    wire [255:0] digest;
    wire        ready;
    wire        done;

    // 2. Kết nối với Module SHA256 (Unit Under Test - UUT)
    SHA256 uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .block_in(block_in),
        .digest(digest),
        .ready(ready),
        .done(done)
    );

    // 3. Tạo xung Clock 50MHz (Chu kỳ T = 20ns)
    always #10 clk = ~clk;

    // Đáp án Chuẩn NIST cho chuỗi "abc"
    parameter [255:0] NIST_EXPECTED = 256'hba7816bf_8f01cfea_414140de_5dae2223_b00361a3_96177a9c_b410ff61_f20015ad;

    // 4. Kịch bản mô phỏng
    initial begin
        // Khởi tạo trạng thái ban đầu
        clk = 0;
        reset = 1;
        start = 0;
        block_in = 0;

        // Xung Reset toàn hệ thống
        #40;
        reset = 0;
        #20;

        // Nạp khối dữ liệu 512-bit (Chuỗi "abc" đã Padding chuẩn 512-bit theo NIST)
        block_in = 512'h61626380_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000018;

        // Phát xung START 1 nhịp clock để kích hoạt lõi băm
        wait(ready == 1);
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Chờ tín hiệu DONE bật lên mức 1
        wait(done == 1);
        #10;

        // In kết quả kiểm tra tự động ra màn hình Console
        $display("\n==================================================================");
        $display("-> KET QUA BAM DUOC : 0x%h", digest);
        $display("-> DAP AN CHUAN NIST: 0x%h", NIST_EXPECTED);

        if (digest === NIST_EXPECTED) begin
            $display("\n[SUCCESS] CHUC MUNG! LOI SHA256 NHOI 'abc' RA KET QUA CHINH XAC 100%%!");
        end else begin
            $display("\n[FAILED] KET QUA KHONG KHOP! KIEM TRA LAI DATAPATH VOI FSM.");
        end
        $display("==================================================================\n");

        #100;
        $stop; // Dừng mô phỏng
    end

endmodule