	`timescale 1ns / 1ps

	module de2_115_zonal_top (
		 input  wire        CLOCK_50,
		 output wire [17:0] LEDR,
		 output wire [8:0]  LEDG,

		 // Ethernet PHY 0 Pins
		 input  wire        ENET0_RX_CLK,
		 input  wire [3:0]  ENET0_RX_DATA,
		 input  wire        ENET0_RX_DV,
		 
		 output wire        ENET0_GTX_CLK,
		 output wire [3:0]  ENET0_TX_DATA,
		 output wire        ENET0_TX_EN,
		 output wire        ENET0_RST_N

		//I. Khóa TX và tạo xung Reset 
	);//Vòng 1: Khóa kênh TX, chỉ nhận dữ liệu RX
		 assign ENET0_GTX_CLK = 1'b0;
		 assign ENET0_TX_DATA = 4'b0000;
		 assign ENET0_TX_EN   = 1'b0;

		 // Tạo xung reset 10ms cho chip PHY Marvell 
		 reg [19:0] phy_rst_cnt = 20'd0;
		 reg        phy_rst_n   = 1'b0;

		 always @(posedge CLOCK_50) begin
			  if (phy_rst_cnt < 20'd500_000) begin
					phy_rst_cnt <= phy_rst_cnt + 1'b1;
					phy_rst_n   <= 1'b0;
			  end else begin
					phy_rst_n   <= 1'b1;
			  end
		 end
		 assign ENET0_RST_N = phy_rst_n;
		 
	 /*
	 //___Vòng 0: Test kết nối vật lý giữa DE2-115 và Pi 5___
	  // Chuyển đổi RGMII RX (DDR 4-bit -> SDR 8-bit)
    wire [7:0] rx_byte;
    wire [1:0] rx_ctl;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : rx_data_ddio
            ALTDDIO_IN #(
                .width(1)
            ) ddio_rx_inst (
                .datain(ENET0_RX_DATA[i]),
                .inclock(ENET0_RX_CLK),
                .dataout_h(rx_byte[i]),     // Bit ở sườn lên
                .dataout_l(rx_byte[i+4])    // Bit ở sườn xuống
            );
        end
    endgenerate

    ALTDDIO_IN #(.width(1)) ddio_rx_ctl (
        .datain(ENET0_RX_DV),
        .inclock(ENET0_RX_CLK),
        .dataout_h(rx_ctl[0]),
        .dataout_l(rx_ctl[1])
    );

    // Passthrough Trực Tiếp Ở Tầng SDR (Loopback Vòng 0)
    wire [7:0] tx_byte = (rx_ctl[0] == 1'b1) ? rx_byte : 8'h00;
    wire [1:0] tx_ctl  = rx_ctl;

    // Chuyển đổi RGMII TX (SDR 8-bit -> DDR 4-bit)
    generate
        for (i = 0; i < 4; i = i + 1) begin : tx_data_ddio
            ALTDDIO_OUT #(
                .width(1)
            ) ddio_tx_inst (
                .datain_h(tx_byte[i]),
                .datain_l(tx_byte[i+4]),
                .outclock(ENET0_RX_CLK),
                .dataout(ENET0_TX_DATA[i])
            );
        end
    endgenerate

    ALTDDIO_OUT #(.width(1)) ddio_tx_ctl (
        .datain_h(tx_ctl[0]),
        .datain_l(tx_ctl[1]),
        .outclock(ENET0_RX_CLK),
        .dataout(ENET0_TX_EN)
    );

    ALTDDIO_OUT #(.width(1)) ddio_gtx_clk (
        .datain_h(1'b1),
        .datain_l(1'b0),
        .outclock(ENET0_RX_CLK), 
        .dataout(ENET0_GTX_CLK)
    );

    // Đèn báo debug + Bộ kéo dài xung LED
	 
    // Đèn chớp báo nhịp Clock 125MHz
    reg [24:0] clk_cnt;
    always @(posedge ENET0_RX_CLK) clk_cnt <= clk_cnt + 1'b1;
    assign LEDG[0] = clk_cnt[24]; 
    assign LEDG[8] = 1'b1;        // Báo có điện

    // Kéo dài thời gian sáng cho LED
    reg [23:0] rx_led_hold_cnt = 24'd0;
    always @(posedge ENET0_RX_CLK) begin
        if (ENET0_RX_DV == 1'b1) begin
            // Có gói tin -> Nạp bộ đếm (sáng 0.1s)
            rx_led_hold_cnt <= 24'd12_500_000; //12.5 triệu clock
        end else if (rx_led_hold_cnt > 24'd0) begin
            // Giảm dần bộ đếm
            rx_led_hold_cnt <= rx_led_hold_cnt - 1'b1;
        end
    end
    
    // Bộ đếm chưa về 0 -> LEDR[0] sáng
    assign LEDR[0] = (rx_led_hold_cnt > 24'd0);
	 */

	 //Vòng 1: FSM bóc tách gói tin
	 wire [3:0] rx_data_high; // Dữ liệu sườn dương (4 bit thấp)
    wire [3:0] rx_data_low;  // Dữ liệu sườn âm (4 bit cao)
    wire       rx_dv_high;   // Cờ DV sườn dương
    wire       rx_dv_low;    // Cờ ER sườn âm

    // IP lõi đọc 4-bit Data DDR
    altddio_in #(
        .width(4),
        .intended_device_family("Cyclone IV E")
    ) ddrio_data_inst (
        .datain    (ENET0_RX_DATA),
        .inclock   (ENET0_RX_CLK),
        .dataout_h (rx_data_high), // Bắt tại sườn dương
        .dataout_l (rx_data_low),  // Bắt tại sườn âm
        .aclr      (~phy_rst_n)    // Xóa khi có Reset
    );
	 // IP lõi đọc 1-bit Control DDR 
    altddio_in #(
        .width(1),
        .intended_device_family("Cyclone IV E")
    ) ddrio_ctrl_inst (
        .datain    (ENET0_RX_DV),
        .inclock   (ENET0_RX_CLK),
        .dataout_h (rx_dv_high), 
        .dataout_l (rx_dv_low),  
        .aclr      (~phy_rst_n)
    );
    // Ghép RGMII DDR -> SDR
    wire [7:0] rx_byte;
    wire       rx_dv_sync;
	 assign rx_byte    = {rx_data_low, rx_data_high};
	 assign rx_dv_sync = rx_dv_high;
    /*
    phy_rgmii_interface phy_rx_inst (
        .rx_clk      (ENET0_RX_CLK),
        .rgmii_rxd   (ENET0_RX_DATA),
        .rgmii_rx_dv (ENET0_RX_DV),
        .byte_out    (rx_byte),
        .dv_out      (rx_dv_sync)
    );*/
	 

    // III. Module Parser
    wire        packet_valid;
    wire [15:0] pkt_len;
    wire [3:0]  fsm_state;
    wire        raw_packet_seen;
	 wire        ip_matched;   
    wire        port_matched;

    udp_rx_parser parser_inst (
        .clk             (ENET0_RX_CLK),
        .reset_n         (phy_rst_n),
        .rx_data         (rx_byte),
        .rx_dv           (rx_dv_sync),
        .mac_ip_match    (packet_valid),
        .packet_length   (pkt_len),
        .fsm_state_out   (fsm_state),
        .raw_packet_seen (raw_packet_seen),
		  .ip_matched_out  (ip_matched),  
        .port_matched_out(port_matched)
    );
    // IV. Mạch Stretch kéo dài xung và gán đèn LED
    // Mạch Stretch giữ LED sáng 1.2 giây
    reg [27:0] stretch_pass = 28'd0;
    reg [27:0] stretch_raw  = 28'd0;
	 reg [27:0] stretch_ip   = 28'd0;
    reg [27:0] stretch_port = 28'd0;
    reg [15:0] latched_len  = 16'd0;
    /*reg [3:0]  latched_state= 4'd0;*/

    always @(posedge ENET0_RX_CLK or negedge phy_rst_n) begin
        if (!phy_rst_n) begin
            stretch_pass <= 28'd0;
            stretch_raw  <= 28'd0;
            stretch_ip   <= 28'd0;
            stretch_port <= 28'd0;
            latched_len  <= 16'd0;
        end else begin
		      if (raw_packet_seen) begin
                stretch_raw <= 28'd30_000_000;   // Nháy theo gói
            end else if (stretch_raw > 0) begin
                stretch_raw <= stretch_raw - 1'b1;
					 end
            if (packet_valid) begin
                stretch_pass <= 28'd150_000_000; // Sáng 1.2s ở 125MHz
                latched_len  <= pkt_len;
                /*latched_state<= fsm_state;*/
            end else if (stretch_pass > 0) begin
                stretch_pass <= stretch_pass - 1'b1;
            end
				if (ip_matched) begin
                stretch_ip <= 28'd150_000_000;
            end else if (stretch_ip > 0) begin
                stretch_ip <= stretch_ip - 1'b1;
            end
				if (port_matched) begin
                stretch_port <= 28'd150_000_000;
            end else if (stretch_port > 0) begin
                stretch_port <= stretch_port - 1'b1;
            end	
		  end
	end


    // Xung Heartbeat 1Hz
    reg [26:0] clk_cnt = 27'd0;
    always @(posedge ENET0_RX_CLK) begin
        clk_cnt <= clk_cnt + 1'b1;
    end

    // ==========================================
    // BẢNG GÁN ĐÈN CHẨN ĐOÁN TRỰC TIẾP
    // ==========================================
    assign LEDG[0] = clk_cnt[26];      
    assign LEDG[1] = (stretch_raw > 0);
    assign LEDG[2] = phy_rst_n;        
    assign LEDG[3] = (stretch_port > 0); // Độc lập: Sáng nếu qua được mốc Port
    assign LEDG[4] = (stretch_ip > 0);   // Độc lập: Sáng nếu qua được mốc IP
    assign LEDG[8] = (stretch_pass > 0); // Sáng 1.2s nếu Pass 100%

    // Tắt các đèn xanh chưa dùng đến để tránh nhiễu
    assign LEDG[7:5] = 3'b000; 
    /*
    assign LEDR[15:0]  = (stretch_pass > 0) ? latched_len : 16'd0;
    assign LEDR[17:16] = 2'b00;
	 */
	 // ==========================================
    // X-RAY MODE: Chụp lại byte đầu tiên của gói tin vật lý
    // ==========================================
    reg [7:0] first_byte = 8'd0;
    reg       rx_dv_prev = 1'b0;

    always @(posedge ENET0_RX_CLK) begin
        rx_dv_prev <= rx_dv_sync;
        
        // Ngay khi cờ rx_dv vừa bật lên (Bắt đầu 1 gói tin mới)
        if (rx_dv_sync == 1'b1 && rx_dv_prev == 1'b0) begin
            first_byte <= rx_byte; // Chụp ngay byte đó lại
        end
    end

    // Gán 8 bit này ra 8 đèn LED đỏ đầu tiên
    assign LEDR[7:0]   = first_byte;
    assign LEDR[17:8]  = 10'd0; // Tắt các đèn không dùng

endmodule
