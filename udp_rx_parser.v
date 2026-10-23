`timescale 1ns / 1ps



module udp_rx_parser (

    input wire         clk,

    input wire         reset_n,



    input wire [7:0]   rx_data,

    input wire         rx_dv,



    output reg         packet_valid,

    output reg [15:0]  packet_length,



    output reg [31:0]  packet_id,

    output reg [7:0]   packet_type,

    output reg [15:0]  payload_len,

    output reg [255:0] payload,



    output reg         raw_packet_seen, 

    output reg         ip_matched_out,

    output reg         port_matched_out,

    output reg         magic_matched_out,



    output wire [3:0]  fsm_state_out

);



    // Protocol configuration

    localparam [31:0]  DEST_IP = 32'hC0A801C8; // 192.168.1.200

    localparam [15:0]  DEST_PORT = 16'h1388;   // 5000

    localparam [15:0]  MAGIC = 16'hAA55;

    localparam [7:0]   VERSION = 8'd1;



    // FSM states (Đã xóa S_DONE dư thừa, đẩy S_WAIT_END lên thành 7)

    localparam [3:0]

        S_IDLE     = 4'd0, S_PREAMBLE = 4'd1, S_ETHERNET = 4'd2, S_IPV4     = 4'd3,

        S_UDP      = 4'd4, S_CUSTOM   = 4'd5, S_PAYLOAD  = 4'd6, S_WAIT_END = 4'd7;



    reg [3:0] state;

    assign fsm_state_out = state;



    // Counters

    reg [15:0] byte_cnt;

    reg [5:0]  payload_cnt;



    // Temporary registers

    reg [31:0] dst_ip_reg;

    reg [15:0] dst_port_reg;



    reg [15:0] custom_magic_reg;

    reg [7:0]  custom_version_reg;

    reg [7:0]  custom_type_reg;

    reg [31:0] custom_packet_id_reg;

    reg [15:0] custom_payload_len_reg;



    reg ip_ok;

    reg port_ok;

    reg magic_ok;

    reg version_ok;



    // Main parser    

    always @(posedge clk or negedge reset_n)

    begin

        if (!reset_n)

        begin

            state <= S_IDLE;

            byte_cnt <= 16'd0;

            payload_cnt <= 6'd0;



            packet_valid <= 1'b0;

            packet_length <= 16'd0;



            packet_id <= 32'd0;

            packet_type <= 8'd0;

            payload_len <= 16'd0;

            payload <= 256'd0;



            raw_packet_seen <= 1'b0;



            ip_matched_out <= 1'b0;

            port_matched_out <= 1'b0;

            magic_matched_out <= 1'b0;



            dst_ip_reg <= 32'd0;

            dst_port_reg <= 16'd0;



            custom_magic_reg <= 16'd0;

            custom_version_reg <= 8'd0;

            custom_type_reg <= 8'd0;

            custom_packet_id_reg <= 32'd0;

            custom_payload_len_reg <= 16'd0;



            ip_ok <= 1'b0;

            port_ok <= 1'b0;

            magic_ok <= 1'b0;

            version_ok <= 1'b0;

        end

        else 

        begin 

            packet_valid <= 1'b0;

            raw_packet_seen <= 1'b0;

            

            // LOGIC RESET TOÀN CỤC CHUẨN: Bất cứ khi nào rx_dv rớt = 0, lập tức dọn dẹp FSM

            if (!rx_dv) 

            begin

                state <= S_IDLE;

                byte_cnt <= 16'd0;

                payload_cnt <= 6'd0;

                    

                ip_ok <= 1'b0; port_ok <= 1'b0; magic_ok <= 1'b0; version_ok <= 1'b0;

                ip_matched_out <= 1'b0; port_matched_out <= 1'b0; magic_matched_out <= 1'b0;

            end

            else 

            begin

                case (state)



                    // IDLE

                    S_IDLE:

                    begin

                        byte_cnt <= 16'd0;

                        payload_cnt <= 6'd0;



                        ip_ok <= 1'b0;

                        port_ok <= 1'b0;

                        magic_ok <= 1'b0;

                        version_ok <= 1'b0;



                        ip_matched_out <= 1'b0;

                        port_matched_out <= 1'b0;

                        magic_matched_out <= 1'b0;



                        if (rx_data == 8'h55)

                        begin

                            state <= S_PREAMBLE;

                            byte_cnt <= 16'd1;

                            raw_packet_seen <= 1'b1;

                        end

                    end



                    // PREAMBLE + SFD

                    S_PREAMBLE:

                    begin

                        if (rx_data == 8'h55) begin

                            if (byte_cnt > 16'd10) begin

                                state <= S_WAIT_END;

                                byte_cnt <= 16'd0;

                            end

                            else begin

                                byte_cnt <= byte_cnt + 1'b1;

                            end

                        end

                        else if (rx_data == 8'hD5) begin

                            state <= S_ETHERNET;

                            byte_cnt <= 16'd0;

                        end

                        else begin

                            state <= S_WAIT_END;

                            byte_cnt <= 16'd0;

                        end

                    end

                          

                    // ETHERNET HEADER

                    S_ETHERNET:

                    begin

                        if (byte_cnt == 16'd12) 

                        begin

                            if (rx_data != 8'h08) begin 

                                state <= S_WAIT_END;

                                byte_cnt <= 16'd0;

                            end

                            else begin 

                                byte_cnt <= byte_cnt + 1'b1;

                            end

                        end

                        else if (byte_cnt == 16'd13) 

                        begin

                            if (rx_data == 8'h00) begin

                                state <= S_IPV4;

                                byte_cnt <= 16'd0;

                            end

                            else begin

                                state <= S_WAIT_END;

                                byte_cnt <= 16'd0;

                            end

                        end

                        else begin

                            byte_cnt <= byte_cnt + 1'b1;

                        end

                    end



                    // IPv4 HEADER

                    S_IPV4:

                    begin

                        case (byte_cnt)

                            16'd0: begin

                                if (rx_data != 8'h45) begin

                                    state <= S_WAIT_END;

                                    byte_cnt <= 16'd0;

                                end

                                else byte_cnt <= byte_cnt + 1'b1;

                            end

                            16'd9: begin

                                if (rx_data != 8'h11) begin

                                    state <= S_WAIT_END;

                                    byte_cnt <= 16'd0;

                                end

                                else byte_cnt <= byte_cnt + 1'b1;

                            end

                            16'd16: begin dst_ip_reg[31:24] <= rx_data; byte_cnt <= byte_cnt + 1'b1; end

                            16'd17: begin dst_ip_reg[23:16] <= rx_data; byte_cnt <= byte_cnt + 1'b1; end

                            16'd18: begin dst_ip_reg[15:8]  <= rx_data; byte_cnt <= byte_cnt + 1'b1; end

                            16'd19: begin

                                dst_ip_reg[7:0] <= rx_data;

                                if ({dst_ip_reg[31:8], rx_data} == DEST_IP || {dst_ip_reg[31:8], rx_data} == 32'hFFFFFFFF ) begin

                                    ip_ok <= 1'b1;

                                    ip_matched_out <= 1'b1;

                                    state <= S_UDP;

                                    byte_cnt <= 16'd0;

                                end

                                else begin

                                    state <= S_WAIT_END;

                                    byte_cnt <= 16'd0;

                                end

                            end

                            default: begin

                                byte_cnt <= byte_cnt + 1'b1;

                            end

                        endcase

                    end



                    // UDP HEADER

                    S_UDP:

                    begin

                        case (byte_cnt)

                            16'd2: begin

                                dst_port_reg[15:8] <= rx_data;

                                byte_cnt <= byte_cnt + 1'b1;

                            end

                            16'd3: begin

                                dst_port_reg[7:0] <= rx_data;

                                if ({dst_port_reg[15:8], rx_data} == DEST_PORT) begin

                                    port_ok <= 1'b1;

                                    port_matched_out <= 1'b1;

                                    byte_cnt <= byte_cnt + 1'b1;

                                end

                                else begin

                                    state <= S_WAIT_END;

                                    byte_cnt <= 16'd0;

                                end

                            end

                            16'd7: begin

                                state <= S_CUSTOM;

                                byte_cnt <= 16'd0;

                            end

                            default: begin

                                byte_cnt <= byte_cnt + 1'b1;

                            end

                        endcase

                    end



                    // CUSTOM HEADER

                    S_CUSTOM:

                    begin

                        case (byte_cnt)

                            16'd0: begin custom_magic_reg[15:8] <= rx_data; byte_cnt <= byte_cnt + 1'b1; end

                            16'd1: begin

                                custom_magic_reg[7:0] <= rx_data;

                                if ({custom_magic_reg[15:8], rx_data} == MAGIC) begin

                                    magic_ok <= 1'b1;

                                    magic_matched_out <= 1'b1;

                                    byte_cnt <= byte_cnt + 1'b1;

                                end

                                else begin state <= S_WAIT_END; byte_cnt <= 16'd0; end

                            end

                            16'd2: begin

                                custom_version_reg <= rx_data;

                                if (rx_data == VERSION) begin

                                    version_ok <= 1'b1;

                                    byte_cnt <= byte_cnt + 1'b1;

                                end

                                else begin state <= S_WAIT_END; byte_cnt <= 16'd0; end

                            end

                            16'd3: begin custom_type_reg <= rx_data; byte_cnt <= byte_cnt + 1'b1; end

                            16'd4: begin custom_packet_id_reg[31:24] <= rx_data; byte_cnt <= byte_cnt + 1'b1; end

                            16'd5: begin custom_packet_id_reg[23:16] <= rx_data; byte_cnt <= byte_cnt + 1'b1; end

                            16'd6: begin custom_packet_id_reg[15:8]  <= rx_data; byte_cnt <= byte_cnt + 1'b1; end

                            16'd7: begin custom_packet_id_reg[7:0]   <= rx_data; byte_cnt <= byte_cnt + 1'b1; end

                            16'd8: begin custom_payload_len_reg[15:8]<= rx_data; byte_cnt <= byte_cnt + 1'b1; end

                            16'd9: begin

                                custom_payload_len_reg[7:0] <= rx_data;

                                if ({custom_payload_len_reg[15:8], rx_data} == 16'd32) begin

                                    payload <= 256'd0;

                                    payload_cnt <= 6'd0;

                                    state <= S_PAYLOAD;

                                    byte_cnt <= 16'd0;

                                end

                                else begin state <= S_WAIT_END; byte_cnt <= 16'd0; end

                            end

                            default: begin byte_cnt <= byte_cnt + 1'b1; end

                        endcase

                    end



                    // PAYLOAD (Shift Register & 0-Latency Validate)

                    S_PAYLOAD:

                    begin

                        payload <= {payload[247:0], rx_data};

                        

                        if (payload_cnt == 6'd31) begin

                            packet_id <= custom_packet_id_reg;

                            packet_type <= custom_type_reg;

                            payload_len <= custom_payload_len_reg;

                            packet_length <= 16'd42;



                            // Bắn xung valid NGAY TẠI NHỊP CHỐT BYTE CUỐI CÙNG

                            if (ip_ok && port_ok && magic_ok && version_ok)

                                packet_valid <= 1'b1;



                            state <= S_WAIT_END;

                            payload_cnt <= 6'd0;

                        end

                        else begin

                            payload_cnt <= payload_cnt + 1'b1;

                        end

                    end

                          

                    S_WAIT_END:

                    begin

                        // Chờ rx_dv rớt về 0 để clear trạng thái (do khối if (!rx_dv) bên trên đảm nhận)

                    end



                    default:

                    begin

                        state <= S_IDLE;

                        byte_cnt <= 16'd0;

                        payload_cnt <= 6'd0;

                    end



                endcase

            end

        end

    end



endmodule