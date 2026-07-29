module SHA256(
input  wire         clk,
input  wire         reset,
input  wire         start,
input  wire [511:0] block_in,

output reg [255:0]  digest,
output wire         ready,
output reg          done
);

//Core Function

function [31:0] ch (input[31:0] x,y,z);
    ch = (x&y) ^ (~x&z);
endfunction
function [31:0] maj (input[31:0] x,y,z);
    maj = (x&y) ^ (y&z) ^ (x&z);
endfunction
function [31:0] sum0 (input[31:0] x);
    sum0 = {x[1:0], x[31:2]} ^ {x[12:0], x[31:13]} ^ {x[21:0], x[31:22]};
endfunction
function [31:0] sum1 (input[31:0] x);
    sum1 = {x[5:0], x[31:6]} ^ {x[10:0], x[31:11]} ^ {x[24:0], x[31:25]};
endfunction
function [31:0] sig0 (input[31:0] x);
    sig0 = {x[6:0], x[31:7]} ^ {x[17:0], x[31:18]} ^ (x>>3);
endfunction
function [31:0] sig1 (input[31:0] x);
    sig1 = {x[16:0], x[31:17]} ^ {x[18:0], x[31:19]} ^ (x>>10); //(x>>3) = {3'b000, x[31:3]}
endfunction

// Message Scheduler 

reg [31:0] w[0:63];
integer i;
reg [31:0] w_temp[0:63];

// k[t], t=0,1,...,63
reg [31:0] k[0:63];
initial begin
        k[0]=32'h428a2f98; k[1]=32'h71374491; k[2]=32'hb5c0fbcf; k[3]=32'he9b5dba5;
        k[4]=32'h3956c25b; k[5]=32'h59f111f1; k[6]=32'h923f82a4; k[7]=32'hab1c5ed5;
        k[8]=32'hd807aa98; k[9]=32'h12835b01; k[10]=32'h243185be; k[11]=32'h550c7dc3;
        k[12]=32'h72be5d74; k[13]=32'h80deb1fe; k[14]=32'h9bdc06a7; k[15]=32'hc19bf174;
        k[16]=32'he49b69c1; k[17]=32'hefbe4786; k[18]=32'h0fc19dc6; k[19]=32'h240ca1cc;
        k[20]=32'h2de92c6f; k[21]=32'h4a7484aa; k[22]=32'h5cb0a9dc; k[23]=32'h76f988da;
        k[24]=32'h983e5152; k[25]=32'ha831c66d; k[26]=32'hb00327c8; k[27]=32'hbf597fc7;
        k[28]=32'hc6e00bf3; k[29]=32'hd5a79147; k[30]=32'h06ca6351; k[31]=32'h14292967;
        k[32]=32'h27b70a85; k[33]=32'h2e1b2138; k[34]=32'h4d2c6dfc; k[35]=32'h53380d13;
        k[36]=32'h650a7354; k[37]=32'h766a0abb; k[38]=32'h81c2c92e; k[39]=32'h92722c85;
        k[40]=32'ha2bfe8a1; k[41]=32'ha81a664b; k[42]=32'hc24b8b70; k[43]=32'hc76c51a3;
        k[44]=32'hd192e819; k[45]=32'hd6990624; k[46]=32'hf40e3585; k[47]=32'h106aa070;
        k[48]=32'h19a4c116; k[49]=32'h1e376c08; k[50]=32'h2748774c; k[51]=32'h34b0bcb5;
        k[52]=32'h391c0cb3; k[53]=32'h4ed8aa4a; k[54]=32'h5b9cca4f; k[55]=32'h682e6ff3;
        k[56]=32'h748f82ee; k[57]=32'h78a5636f; k[58]=32'h84c87814; k[59]=32'h8cc70208;
        k[60]=32'h90befffa; k[61]=32'ha4506ceb; k[62]=32'hbef9a3f7; k[63]=32'hc67178f2;
		  end
// FSM and Hash Flow 
localparam [1:0] STATE_IDLE = 2'b00, 
                 STATE_HASH = 2'b01, 
                 STATE_DONE = 2'b10;
reg [1:0] state;
reg [5:0] round_counter;
//8 registers
reg [31:0] a, b, c, d, e, f, g, h;
// H[0] -> H[7]
parameter H0 = 32'h6a09e667, H1 = 32'hbb67ae85, H2 = 32'h3c6ef372, H3 = 32'ha54ff53a;
parameter H4 = 32'h510e527f, H5 = 32'h9b05688c, H6 = 32'h1f83d9ab, H7 = 32'h5be0cd19;
wire [31:0] t1 = h + sum1(e) + ch(e, f, g) + k[round_counter] + w[round_counter];
wire [31:0] t2 = sum0(a) + maj(a, b, c);

assign ready = (state == STATE_IDLE);

always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= STATE_IDLE;
            round_counter <= 0;
            done <= 0;
            digest <= 0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    done <= 0;
                    if (start) begin
                        // Calculate w_temp[t], t=0,1,...,63
                        w_temp[0] = block_in[511:480]; w_temp[1] = block_in[479:448];
                        w_temp[2] = block_in[447:416]; w_temp[3] = block_in[415:384];
                        w_temp[4] = block_in[383:352]; w_temp[5] = block_in[351:320];
                        w_temp[6] = block_in[319:288]; w_temp[7] = block_in[287:256];
                        w_temp[8] = block_in[255:224]; w_temp[9] = block_in[223:192];
                        w_temp[10]= block_in[191:160]; w_temp[11]= block_in[159:128];
                        w_temp[12]= block_in[127:96];  w_temp[13]= block_in[95:64];
                        w_temp[14]= block_in[63:32];   w_temp[15]= block_in[31:0];

                        for (i = 16; i < 64; i = i + 1) begin
                            w_temp[i] = sig1(w_temp[i-2]) + w_temp[i-7] + sig0(w_temp[i-15]) + w_temp[i-16];
                        end
                        for (i = 0; i < 64; i = i + 1) begin
                            w[i] <= w_temp[i];
                        end

                        // 8 new values a-h
                        a <= H0; b <= H1; c <= H2; d <= H3;
                        e <= H4; f <= H5; g <= H6; h <= H7;

                        round_counter <= 0;
                        state <= STATE_HASH;
                    end
                end

                STATE_HASH: begin
                    // Update 8 registers
                    h <= g;
                    g <= f;
                    f <= e;
                    e <= d + t1;
                    d <= c;
                    c <= b;
                    b <= a;
                    a <= t1 + t2;

                    if (round_counter == 63) begin
                        state <= STATE_DONE;
                    end else begin
                        round_counter <= round_counter + 1;
                    end
                end

                STATE_DONE: begin
                    // Calculate Hash
                    digest <= {(a + H0), (b + H1), (c + H2), (d + H3), 
                               (e + H4), (f + H5), (g + H6), (h + H7)};
                    done <= 1;
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule


