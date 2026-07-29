================================================================================
⚡ FPGA-Accelerated SHA-256 Zonal Gateway Node

In-Line Hardware Cryptographic Offloading over UDP/IP Stack on 
Altera Cyclone IV DE2-115 & Raspberry Pi 5
================================================================================

📌 1. EXECUTIVE SUMMARY / TỔNG QUAN DỰ ÁN
--------------------------------------------------------------------------------
Trong kiến trúc mạng ô tô hiện đại (Automotive Zonal Architecture) và mạng 
IoT Edge, các nút Zonal Gateway phải xử lý khối lượng lớn dữ liệu cần xác thực 
tính toàn vẹn (Integrity Verification) với độ trễ cực thấp (Deterministic 
Low-Latency). Việc tính toán các hàm băm mật mã như SHA-256 hoàn toàn bằng 
phần mềm (Software Engine) trên CPU Gateway tạo ra nghẽn cổ chai (CPU Overhead) 
và biến động độ trễ (Jitter). 

Dự án này triển khai một nút Zonal Gateway Offloading phần cứng trên FPGA 
DE2-115, giao tiếp trực tiếp với Host Gateway (Raspberry Pi 5) qua kết nối 
Ethernet MII/UDP. Toàn bộ quá trình bóc tách gói tin L2-L4 và tính toán mã băm 
SHA-256 (512-bit block) được thực hiện hoàn toàn ở tầng hardware (In-Line 
Pipeline), giải phóng 100% tài nguyên CPU của Host.


🏗️ 2. SYSTEM ARCHITECTURE / KIẾN TRÚC HỆ THỐNG
--------------------------------------------------------------------------------
Dự án này là phân hệ cốt lõi (Phase 1) nằm trong kiến trúc SPARK Protocol Host 
dành cho mạng In-Vehicle Network (IVN). Kiến trúc tổng thể chia thành 3 vùng:

1. In-Vehicle Network (IVN): Bao gồm các ECU giao tiếp qua bus CAN / CAN FD. 
   Các ECU này gửi dữ liệu xác thực (L_k, R_k) tới Zonal Gateway.
2. Raspberry Pi 5 (Edge Device / Zonal Gateway): Đóng vai trò là Host thu thập 
   dữ liệu từ mạng CAN và đóng gói thành các Crypto Jobs. Dữ liệu được truyền 
   tải qua giao diện Gigabit Ethernet tới FPGA.
3. FPGA DE2-115 (Crypto Accelerator): Đảm nhiệm xử lý phần cứng toàn bộ các 
   phép toán mật mã nặng. Khối SHA-256 Hasher được thiết kế dạng Pipelined, 
   giúp tăng tốc độ xử lý từ 0.32 ms xuống chỉ còn ~0.05 ms (tăng tốc 6x).


💻 3. TECHNICAL SPECIFICATIONS / THÔNG SỐ KỸ THUẬT
--------------------------------------------------------------------------------
+--------------------+---------------------------------------------------------+
| Hạng mục           | Thông số chi tiết                                       |
+--------------------+---------------------------------------------------------+
| FPGA Board         | Terasic DE2-115 (Altera Cyclone IV EP4CE115F29C7)       |
| Host System        | Raspberry Pi 5 (Rasp OS 64-bit / Linux Kernel 6.x)      |
| Physical Interface | Board Port ENET0 (Top Port) - Marvell 88E1111 PHY       |
| Network Protocol   | Custom MII Layer-2/3/4 Processing Stack (No IP Stack)   |
| Ethernet Speed     | Fast Ethernet 100 Mbps (MII Single Data Rate @ 25 MHz)  |
| Crypto Standard    | FIPS 180-4 SHA-256 (256-bit Digest Output)              |
| Addressing         | FPGA: 192.168.137.200 | Host Pi 5: 192.168.137.100      |
| UDP Service Port   | Cổng 5000 (Bidirectional Datagram Execution)            |
+--------------------+---------------------------------------------------------+


🧱 4. VERILOG MODULES BREAKDOWN / CẤU TRÚC MÃ NGUỒN
--------------------------------------------------------------------------------
* de2_115_zonal_top.v: Top-level module quản lý phân phối Clock (50MHz/25MHz), 
  Power-On Auto Reset cho IC PHY Marvell, và bộ hiển thị LED Telemetry.
* SHA256.v: Lõi băm SHA-256 thuần Verilog tuân thủ FIPS 180-4. Tích hợp bộ tính 
  toán lịch thông điệp W_t, đường dữ liệu 8 thanh ghi trạng thái A->H và FSM.
* udp_sha256_bridge.v: Bộ điều phối luồng dữ liệu trung tâm tích hợp các mạch 
  Clock Domain Crossing (CDC) Pulse Synchronizer.
* udp_rx_parser.v: Máy trạng thái (FSM) bóc tách gói tin L2/L3/L4. Lọc MAC, 
  IP đích, UDP Port và trích xuất đúng 64 Bytes (512 bits) Payload.
* udp_tx_framer.v: Bộ đóng gói khung truyền ngược về Host. Tự động sinh gói 
  tin ARP Reply và đóng gói UDP Packet chứa 1 Byte Status (0xAA) + 32 Bytes.
* phy_rgmii_interface.v: Khối giao tiếp PHY tầng thấp, biến đổi MII Nibble.
* gateway_host.py: Script Python trên Pi 5 thực hiện Padding chuẩn FIPS 180-4 
  và giao tiếp Socket UDP.


🧪 5. VERIFICATION / KIỂM THỬ VỚI ĐÁP ÁN CHUẨN NIST
--------------------------------------------------------------------------------
NIST Test Case 1: Input "abc"

* ASCII Input: "abc"
* Hex Payload (512-bit Block sau Padding):
  61626380 00000000 00000000 00000000 
  00000000 00000000 00000000 00000000 
  00000000 00000000 00000000 00000000 
  00000000 00000000 00000000 00000018

* Expected SHA-256 Digest: 
  ba7816bf 8f01cfea 414140de 5dae2223 
  b00361a3 96177a9c b410ff61 f20015ad

[ Kết quả thực thi trên Terminal Raspberry Pi 5 ]
$ sudo ./env/bin/python3 gateway_host.py

=================================================================
[*] Chuỗi đầu vào (ASCII) : 'abc'
[*] Độ dài Padding        : 64 bytes (512 bits)
[*] Payload Hex (512-bit) : 6162638000000000...00000018
=================================================================
[*] Đang gửi UDP Payload (65 bytes) tới FPGA (192.168.137.200:5000)...

[+] THÀNH CÔNG! NHẬN PHẢN HỒI TỪ FPGA [192.168.137.200:5000]
[+] Thời gian xử lý vòng (Round-trip Latency): 142.850 µs
[+] Status Return : 0xAA (0xAA = Success)
[+] SHA-256 Digest: ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad

[✓] CHECKPOINT PASSED: Mã băm khớp 100% với đáp án tiêu chuẩn NIST!
