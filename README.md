\# ⚡ FPGA-Accelerated SHA-256 Zonal Gateway Node

> **In-Line Hardware Cryptographic Offloading over UDP/IP Stack on Altera Cyclone IV DE2-115 & Raspberry Pi 5**
![FPGA](https://img.shields.io/badge/FPGA-Altera%20Cyclone%20IV%20EP4CE115-blue)
![Language](https://img.shields.io/badge/HDL-Verilog%20HDL-orange)
![Host](https://img.shields.io/badge/Host-Raspberry%20Pi%205%20(Linux)-red)
![Protocol](https://img.shields.io/badge/Protocol-MII%20%7C%20Ethernet%20%7C%20IPv4%20%7C%20UDP-green)
![Standard](https://img.shields.io/badge/Compliance-FIPS%20180--4%20(NIST)-purple)

---

## 📌 Executive Summary / Tổng Quan Dự Án

Trong kiến trúc mạng ô tô hiện đại (Automotive Zonal Architecture), kiến
trúc mạng nội bộ (IVNs) đang dịch chuyển mạnh mẽ từ mô hình Domain Architecture
sang mô hình Zonal Architecture. Ở đó, thay vì gom nhóm theo chức năng của
xe, các ECU con được gom nhóm vật lý theo các vùng cục bộ và kết nối trực
tiếp với một Zonal Gateway ở biên thông qua các giao thức bus tốc độ thấp
như CAN, CAN FD, CAN XL, và được đảm bảo an toàn vận hành bằng giao thức
Anonymous Swarm Attestation, giúp chứng minh toàn bộ nhóm ECU hoạt động bình
thường mà không để lộ bất kỳ thông tin nào của từng ECU, đồng thời bảo vệ
tuyệt đối cấu hình firmware của các nhà cung cấp linh kiện.

Tuy nhiên, khi thực hiện giao thức trên bằng phần mềm thuần túy (chỉ dùng
Pi 4, Pi 5,…), việc tính toán các hàm băm mật mã như SHA-256, bóc tách gói
tin Ethernet hay tính toán phép nhân điểm đường cong elliptic (ECC) chiếm
dụng 1 lượng tài nguyên tính toán rất lớn của CPU, làm giảm đi đáng kể tốc
độ tính toán, ảnh hưởng chung tới toàn bộ quá trình xác thực.

Vì vậy, dự án này tập trung vào việc tăng tốc quá trình tính toán mật mã
thông qua việc triển khai một nút Zonal Gateway Offloading phần cứng trên
FPGA DE2-115, giao tiếp trực tiếp với Host Gateway (Raspberry Pi 5) qua kết
nối Ethernet MII/UDP. Toàn bộ quá trình bóc tách gói tin L2-L4 và tính toán
mã băm SHA-256 với 512-bit block, được thực hiện hoàn toàn ở tầng hardware,
giải phóng 100% tài nguyên CPU của Host.

---

## 🏗️ System Architecture / Kiến Trúc Hệ Thống
Zonal Gateway được nâng cấp để trở thành hạt nhân xử lý của hệ thống,
chuyển toàn bộ công việc tính toán sang FPGA, Pi 5 chỉ còn đóng vai trò
điều phối. Kiến trúc nâng cấp cụ thể gồm 2 phần:

Control Plane - Raspberry Pi 5:

- Nhiệm vụ: Điều phối toàn bộ hoạt động của hệ thống
- Chức năng: Thu thập bằng chứng xác thực từ các ECU con, quản lý phiên xác thực,
  và giao tiếp trực tiếp với TPM 2.0 qua bus SPI. Sau đó, Pi 5 đóng gói
  các tác vụ này thành các Crypto Jobs để chuyển tiếp xuống FPGA qua
  kết nối Gigabit Ethernet.

Data Plane - FPGA DE2-115:
- Nhiệm vụ: Tăng tốc quá trình tính toán mật mã và bộ lọc mạng
- Chức năng: Nhận Crypto Jobs từ Pi 5, sau đó tự động nhận diện và lọc bỏ gói tin
  rác ở tốc độ đường truyền. Dữ liệu hợp lệ được đẩy vào động cơ băm
  SHA-256 thiết kế dạng Pipelined 512-bit, từ đó tính toán phản hồi
  với độ trễ tối thiểu, giải phóng hoàn toàn tài nguyên CPU cho Host.

---

## 💻 System Configuration / Cấu hình hệ thống

| Hạng mục | Thông số cấu hình |
| :--- | :--- |
| Hardware Platform | Terasic DE2-115 (Cyclone IV EP4CE115) + Raspberry Pi 5 (Linux 64-bit) |
| Physical Interface | Board Port ENET0 (Marvell 88E1111 PHY) |
| Network Protocol | RGMII Gigabit Ethernet (1000 Mbps @ 125 MHz DDR) |
| Packet Processing Logic | Hardware-only FSM Parser (Stack-less L2/L3/L4, zero soft processor) |
| Crypto Standard | SHA-256 Hasher (Pipelined 512-bit block processing) & ECC hardware accelerator |
---

## Quy trình test băng thông mạng giữa 2 thiết bị
## 🟢 VÒNG 0: Kiểm tra Kết nối Vật lý & Loopback

### Mục đích

* Xác minh đường truyền cáp mạng và chip PHY Marvell trên bo mạch DE2-115 hoạt động ổn định ở tốc độ cao (Gigabit - 125MHz).
* Kiểm tra khả năng đồng bộ hóa phần cứng thông qua việc ghép nối dữ liệu RGMII (chuyển đổi 4-bit DDR sang 8-bit SDR sử dụng lõi IP cứng ALTDDIO_IN của Intel).

### Cơ chế hoạt động

* Mạch hoạt động theo cơ chế phản hồi thô (Loopback trực tiếp): Nhận toàn bộ gói tin ở cổng RX và đẩy nguyên xi ra cổng TX, đảm bảo cáp thông mạch, không suy hao tín hiệu và không xảy ra hiện tượng mất dữ liệu thô (bit error) giữa Pi 5 và FPGA.


## 🔵 VÒNG 1: Bộ Bóc Tách Gói Tin & Tường Lửa Một Chiều

### Mục đích

* Tích hợp máy trạng thái hữu hạn (FSM Parser) vào FPGA để biến thiết bị thành bộ phân tách gói tin ở tầng mạng.
* Khóa chặt hoàn toàn kênh phát (ENET0_TX_EN = 0) để xây dựng mô hình tường lửa một chiều (Simplex Firewall), chuyên tập trung kiểm duyệt luồng dữ liệu đầu vào.

### Kết quả & Trực quan hóa qua LED

* Dàn đèn LED xanh (LEDG): Hiển thị trực quan tiến trình xác thực (trạng thái nhận sóng, nhận diện port, IP và nội dung payload).
* Dàn đèn LED đỏ (LEDR): Hiển thị chính xác chiều dài khung Ethernet (Packet Length) của gói tin đi qua.
* Cờ PASS (LEDG[8]): Hệ thống chỉ kích hoạt khi và chỉ khi nhận diện chính xác gói tin UDP hợp lệ chứa đúng địa chỉ IP đích, số cổng Port và chuỗi định danh "SPARK".


## 📊 Bảng Chẩn Đoán Trạng Thái LED (Diagnostic Panel)

| **Tên Đèn**      | **Tín hiệu / Logic trong Code**         | **Ý nghĩa trạng thái chẩn đoán**                                                            |
| ---------------- | --------------------------------------- | ------------------------------------------------------------------------------------------- |
| **`LEDG[0]`**    | `clk_cnt[26]` (Nháy 1Hz)                | Báo hiệu xung nhịp hệ thống 125MHz từ chân RX_CLK đang sống và hoạt động bình thường.       |
| **`LEDG[1]`**    | `(stretch_raw > 0)`                     | Nháy chớp báo hiệu **có gói tin thô** đang đập vào cổng nhận (RX).                          |
| **`LEDG[2]`**    | `phy_rst_n`                             | Sáng cố định khi chip PHY Marvell đã được cấp xung reset thành công (Sẵn sàng hoạt động).   |
| **`LEDG[3]`**    | `(stretch_pass > 0) & latched_state[1]` | Sáng lên khi FSM bóc tách và **bắt trúng Port mạng** hợp lệ.                                |
| **`LEDG[4]`**    | `(stretch_pass > 0) & latched_state[2]` | Sáng lên khi FSM bóc tách và **bắt trúng Địa chỉ IP** hợp lệ.                               |
| **`LEDG[5]`**    | `(stretch_pass > 0) & latched_state[3]` | Sáng lên khi FSM bóc tách và **bắt trúng chuỗi "SPARK"**.                                   |
| **`LEDG[7:6]`**  | `2'b00`                                 | Dự phòng (Đang tắt).                                                                        |
| **`LEDG[8]`**    | `(stretch_pass > 0)`                    | **CỜ PASS TOÀN DIỆN:** Sáng rực rỡ 1.2 giây khi gói tin vượt qua toàn bộ tường lửa bảo mật. |
| **`LEDR[15:0]`** | `Packet Length Register`                | Hiển thị kích thước (tính bằng byte) của gói tin nhận được.                                 |



## 🧱 Verilog Modules Breakdown / Structure Mã Nguồn

Dự án được mô-đun hóa hoàn toàn theo kiến trúc HDL chuẩn công nghiệp:

- 📂 **`de2_115_zonal_top.v`**: Top-level module quản lý phân phối Clock (50MHz System / 25MHz MII TX), Power-On Auto Reset cho IC PHY Marvell (10ms Pulse), và bộ hiển thị trạng thái LED Telemetry (100ms Pulse Stretcher).
- 📂 **`SHA256.v`**: Lõi băm SHA-256 thuần Verilog tuân thủ FIPS 180-4. Tích hợp bộ tính toán lịch thông điệp $W_t$ ($0 \rightarrow 63$), đường dữ liệu 8 thanh ghi trạng thái $A \rightarrow H$ và FSM điều khiển 64 vòng băm.
- 📂 **`udp_sha256_bridge.v`**: Bộ điều phối luồng dữ liệu trung tâm tích hợp các mạch **Clock Domain Crossing (CDC) Pulse Synchronizer** giúp chuyển đổi tín hiệu an toàn giữa các miền xung Clock ($25\text{ MHz}$ RX/TX Clock và $50\text{ MHz}$ System Clock).
- 📂 **`udp_rx_parser.v`**: Máy trạng thái (FSM) bóc tách gói tin L2/L3/L4. Tự động lọc địa chỉ MAC, IP đích, UDP Port và trích xuất đúng 64 Bytes (512 bits) Payload để bắn sang lõi SHA-256.
- 📂 **`udp_tx_framer.v`**: Bộ đóng gói khung truyền ngược về Host. Tự động sinh gói tin ARP Reply (khi Host hỏi ARP) và đóng gói UDP Packet chứa 1 Byte Status (`0xAA`) kèm 32 Bytes Digest SHA-256.
- 📂 **`phy_rgmii_interface.v`**: Khối giao tiếpPHY tầng thấp, xử lý biến đổi MII Nibble (4-bit @ 25MHz) thành GMII Byte (8-bit) với khả năng tự động đồng bộ pha Preamble (`0xD5`).
- 📂 **`gateway_host.py`**: Script Python trên Pi 5 chịu trách nhiệm thực hiện Padding chuẩn FIPS 180-4 cho chuỗi đầu vào ASCII, đóng gói UDP Payload (`0x01` + 64-byte block), bắn qua Socket `SO_BINDTODEVICE` và đo đạc Round-trip Latency.

---

## 🧪 Verification & Standard Test Vectors / Kiểm Thử

Hệ thống được xác minh tính đúng đắn dựa trên chuỗi thử nghiệm tiêu chuẩn của **NIST FIPS 180-4**:

### NIST Test Case 1: Input `"abc"`
- **ASCII Input:** `"abc"`
- **Hex Payload (512-bit Block sau Padding):**
  `61626380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018`
- **Expected SHA-256 Digest:**
  `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`

```bash
# Kết quả thực thi trên Terminal Raspberry Pi 5
$ sudo ./env/bin/python3 gateway_host.py

=================================================================
[*] Chuỗi đầu vào (ASCII) : 'abc'
[*] Độ dài Padding       : 64 bytes (512 bits)
[*] Payload Hex (512-bit) : 6162638000000000...00000018
=================================================================
[*] Đang gửi UDP Payload (65 bytes) tới FPGA (192.168.137.200:5000)...

[+] THÀNH CÔNG! NHẬN PHẢN HỒI TỪ FPGA [192.168.137.200:5000]
[+] Thời gian xử lý vòng (Round-trip Latency): 142.850 µs
[+] Status Return : 0xAA (0xAA = Success)
[+] SHA-256 Digest: ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
[✓] CHECKPOINT PASSED: Mã băm khớp 100% với đáp án tiêu chuẩn NIST!
