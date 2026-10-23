📌 **Executive Summary**

SPARK (Anonymous Swarm Attestation for In-Vehicle Networks) là giải pháp
xác thực mật mã ẩn danh cho mạng ô tô thế hệ mới (Automotive Zonal 
Architecture), giúp kiểm tra tính toàn vẹn phần mềm của bầy ECU mà không 
làm rò rỉ cấu hình độc quyền của các nhà cung cấp linh kiện.

Để loại bỏ hoàn toàn nút thắt về độ trễ (latency bottleneck) khi xử lý 
mật mã bằng phần mềm thuần túy, dự án triển khai mô hình tăng tốc phần 
cứng (Hardware Offloading) qua Ethernet theo phân miền thực tế:

- 🖥️ **Internal Verifier (Miền Nội Bộ Xe)**: Raspberry Pi 5 đóng vai trò Zonal Gateway, thu thập dữ liệu từ các Swarm ECUs (ESP32), kết nối với Router nội bộ qua Wi-Fi và phát các yêu cầu xác thực SPARK qua giao thức UDP.

- 🌐 **External Verifier (Miền Xác Thực Bên Ngoài)**:
  - 🛜 **Router Nội Bộ**: Đóng vai trò trạm trung chuyển giữa Pi 5 và DE2-115, mô phỏng đúng kiến trúc mạng IoT/V2X thực tế.
  - ⚡ **FPGA DE2-115**: Nhận dữ liệu từ Router qua kết nối Ethernet vật lý, thực thi bóc tách khung mạng và tính toán băm/mã hóa ở tốc độ cao bằng phần cứng, sau đó dội kết quả về theo đường truyền cũ để Pi 5 kiểm tra và hiển thị.
