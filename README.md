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

## 🧪 5-Stage Verification Roadmap / Lộ trình 5 vòng kiểm thử

🔹 Vòng 0: Hardware-level Loopback

* Mục tiêu:
  Kiểm chứng chất lượng đường truyền cáp vật lý và tính đúng đắn
  của khối IP cứng RGMII DDR (ALTDDIO_IN / ALTDDIO_OUT) trên FPGA.

* Cách kiểm thử:
  Nối tắt trực tiếp đường ra của bộ nhận mạng RX Parser sang
  đầu vào của bộ phát mạng TX Framer ngay tại module
  Top-level của FPGA, bỏ qua hoàn toàn các khối lọc an ninh và mật mã.

* Kết quả kỳ vọng:
  Pi 5 gửi các chuỗi byte thô thử nghiệm (ví dụ: 0xDEADBEEF) qua
  Ethernet và nhận lại chính xác 100% nội dung phản hồi không bị
  suy hao hay trượt bit.

🔹 Vòng 1: Tường lửa một chiều (Simplex Firewall)

* Mục tiêu:
Kiểm chứng FSM Parser lọc bỏ 100% gói rác nền (ARP, mDNS, IPv6...)
ở tốc độ 1 Gbps, chỉ tiếp nhận gói tin SPARK hợp lệ.

* Kiểm thử:
Gán IP/ARP tĩnh trên Pi 5. Bắn gói tin UDP chứa mã "SPRK"
hướng tới Port 1234 trên FPGA.

* Kết quả kỳ vọng:
Gói rác hoặc trạng thái tĩnh: Toàn bộ LED tắt hoàn toàn.
Gói SPARK hợp lệ: LEDG[8] sáng 1.2s; hàng LEDR[15:0] hiển thị
chính xác chiều dài gói tin dưới dạng nhị phân.

🔹 Vòng 2: Tích hợp lõi mật mã SHA-256

* Mục tiêu:
  Hiện thực hóa khả năng gia tốc băm tính toàn vẹn gói tin bằng
  cách ghép nối an toàn bộ lọc mạng với lõi tính toán SHA-256
  phần cứng.

* Kết quả kỳ vọng:
  Kết quả băm 256-bit trả về từ FPGA trùng khớp hoàn toàn
  từng bit với giá trị tính toán phần mềm tương ứng chạy trên
  Pi 5 đối với cùng một gói tin Payload.
---

## 📊 Bảng Chẩn Đoán Trạng Thái LED (Diagnostic Panel)

| Tên Đèn | Tín hiệu / Logic trong Code | Ý nghĩa trạng thái chẩn đoán |
| :--- | :--- | :--- |
| **`LEDG[0]`** | `clk_cnt[26]` (Nháy 1Hz) | Báo hiệu xung nhịp hệ thống 125MHz từ chân RX_CLK đang
 sống và hoạt động bình thường. |
| **`LEDG[1]`** | `(stretch_raw > 0)` | Nháy chớp báo hiệu có gói tin thô đang đập vào cổng RX. |
| **`LEDG[2]`** | `phy_rst_n` | Sáng cố định khi chip PHY Marvell đã được cấp xung reset thành công. |
| **`LEDG[3]`** | `(stretch_pass > 0) & latched_state[1]` | Sáng lên khi FSM bóc tách và bắt trúng 
Port mạng hợp lệ. |
| **`LEDG[4]`** | `(stretch_pass > 0) & latched_state[2]` | Sáng lên khi FSM bóc tách và bắt trúng 
Địa chỉ IP hợp lệ. |
| **`LEDG[5]`** | `(stretch_pass > 0) & latched_state[3]` | Sáng lên khi FSM bóc tách và bắt trúng
 chuỗi "SPARK". |
| **`LEDG[7:6]`** | `2'b00` | Dự phòng (Đang tắt). |
| **`LEDG[8]`** | `(stretch_pass > 0)` | CỜ PASS TOÀN DIỆN: Sáng 1.2 giây khi gói tin vượt qua toàn bộ
 tường lửa bảo mật. |
| **`LEDR[15:0]`** | `Packet Length Register` | Hiển thị kích thước (tính bằng byte) của gói tin 
nhận được. |
