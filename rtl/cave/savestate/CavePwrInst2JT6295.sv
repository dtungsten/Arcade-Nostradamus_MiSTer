///////////////////////////////////////////
// MODULE cave_pwrinst2_ss_jt6295_timing
module cave_pwrinst2_ss_jt6295_timing(

    input       clk,

    input       cen,

    input       ss,

    output reg  cen_sr,   // Sample rate

    output reg  cen_sr4,  // 4x sample rate

    output reg  cen_sr4b, // 4x sample rate, 180 shift

    output reg  cen_sr32
,
input auto_ss_rd, input auto_ss_wr, input [31:0] auto_ss_data_in, input [7:0] auto_ss_device_idx, input [15:0] auto_ss_state_idx, input [7:0] auto_ss_base_device_idx, output logic [31:0] auto_ss_data_out, output logic auto_ss_ack


);
genvar auto_ss_idx;

wire device_match = (auto_ss_device_idx == auto_ss_base_device_idx);




reg  [2:0] base=0;

reg  [5:0] cnt =6'd0;

wire [2:0] lim = ss ? 3'h3 : 3'h4;





always @(posedge clk)
begin
 begin

    cen_sr4 <= 1'd0;

    cen_sr4b<= 1'd0;

    cen_sr  <= 1'd0;

    cen_sr32<= 1'b0;

    if( cen ) begin

        base    <= (base==lim) ? 3'd0 : base+3'd1;

        if(base==3'd0) cnt <= (cnt==6'd32) ? 6'd0 : cnt+6'd1;



        cen_sr32<= !cnt[5] && base==3'd0;

        cen_sr4 <= !cnt[5] && cnt[2:0] == 3'b000 && base == 3'd0;

        cen_sr4b<= !cnt[5] && cnt[2:0] == 3'b100 && base == 3'd0;

        cen_sr  <= {cnt,base} == 9'd0;

    end

end
if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
0: begin
    cnt <= auto_ss_data_in[5:0];
    base <= auto_ss_data_in[8:6];
    cen_sr <= auto_ss_data_in[9];
    cen_sr32 <= auto_ss_data_in[10];
    cen_sr4 <= auto_ss_data_in[11];
    cen_sr4b <= auto_ss_data_in[12];
end
default: begin
end
endcase
end
end


always_comb begin
    auto_ss_data_out = 32'h0;
    auto_ss_ack = 1'b0;
    if (auto_ss_rd && device_match) begin
        case (auto_ss_state_idx)
        0: begin
            auto_ss_data_out[12:0] = {cen_sr4b, cen_sr4, cen_sr32, cen_sr, base, cnt};
            auto_ss_ack = 1'b1;
        end
        default: begin
        end
        endcase
    end
end





endmodule


///////////////////////////////////////////
// MODULE cave_pwrinst2_ss_CaveOKIM6295Rom
module cave_pwrinst2_ss_CaveOKIM6295Rom(

  input         rst,

  input         clk,

  input         cen4,

  input         cen32,

  input         wait_for_rom,

  input         align_ctrl_ok,

  input         save_hold,

  input  [17:0] adpcm_addr,

  input  [17:0] ctrl_addr,

  output reg [7:0]  adpcm_dout,

  output reg [7:0]  ctrl_dout,

  output reg        ctrl_ok,

  input             debug_capture_start,

  input      [17:0] debug_capture_addr,

  output reg [47:0] debug_table_bytes,

  output reg [47:0] debug_body_bytes,

  output reg        debug_body_done,

  output reg [17:0] rom_addr,

  input      [7:0]  rom_data,

  input             rom_ok
,
input auto_ss_rd, input auto_ss_wr, input [31:0] auto_ss_data_in, input [7:0] auto_ss_device_idx, input [15:0] auto_ss_state_idx, input [7:0] auto_ss_base_device_idx, output logic [31:0] auto_ss_data_out, output logic auto_ss_ack


);
genvar auto_ss_idx;

wire device_match = (auto_ss_device_idx == auto_ss_base_device_idx);


  reg [7:0] st;

  reg [1:0] wait2;

  reg       ctrl_ok_pending;

  reg       debug_body_capture;

  reg [2:0] debug_body_count;

  reg [17:0] debug_body_next_addr;

  reg [47:0] debug_table_live_bytes;



  wire new_addr = rom_addr != ctrl_addr;

  wire adpcm_new_addr = rom_addr != adpcm_addr;

  wire adpcm_data_ok = ~wait_for_rom | rom_ok;



  always @(posedge clk)
begin
 begin

    if (rst)

      st <= 8'h00;

    else if (cen4)

      st <= 8'h80;

    else if (cen32)

      st <= {st[6:0], st[7]};

  end
if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
1: begin
    st <= auto_ss_data_in[25:18];
end
default: begin
end
endcase
end
end





  always @(posedge clk)
begin
 begin

    if (rst) begin

      rom_addr <= 18'h0;

      adpcm_dout <= 8'h00;

      ctrl_dout <= 8'h00;

      ctrl_ok <= 1'b0;

      debug_table_bytes <= 48'h000000000000;

      debug_table_live_bytes <= 48'h000000000000;

      debug_body_bytes <= 48'h000000000000;

      debug_body_done <= 1'b0;

      debug_body_capture <= 1'b0;

      debug_body_count <= 3'd0;

      debug_body_next_addr <= 18'h0;

      wait2 <= 2'b0;

      ctrl_ok_pending <= 1'b0;

    end

    else if (!save_hold) begin

      if (debug_capture_start & ~debug_body_capture & ~debug_body_done) begin

        debug_body_bytes <= 48'h000000000000;

        debug_body_done <= 1'b0;

        debug_body_capture <= 1'b1;

        debug_body_count <= 3'd0;

        debug_body_next_addr <= debug_capture_addr;

        debug_table_bytes <= debug_table_live_bytes;

      end



      case (st)

        8'b00000001,

        8'b00000010: begin

          rom_addr <= adpcm_addr;

          if (adpcm_data_ok & ~adpcm_new_addr) begin

            adpcm_dout <= rom_data;

            if (debug_body_capture & (adpcm_addr == debug_body_next_addr)) begin

              case (debug_body_count)

                3'd0: debug_body_bytes[7:0] <= rom_data;

                3'd1: debug_body_bytes[15:8] <= rom_data;

                3'd2: debug_body_bytes[23:16] <= rom_data;

                3'd3: debug_body_bytes[31:24] <= rom_data;

                3'd4: debug_body_bytes[39:32] <= rom_data;

                default: debug_body_bytes[47:40] <= rom_data;

              endcase

              debug_body_next_addr <= debug_body_next_addr + 18'd1;

              if (debug_body_count == 3'd5) begin

                debug_body_capture <= 1'b0;

                debug_body_done <= 1'b1;

              end

              else begin

                debug_body_count <= debug_body_count + 3'd1;

              end

            end

          end

          ctrl_ok <= 1'b0;

          wait2 <= 2'b0;

          ctrl_ok_pending <= 1'b0;

        end

        default: begin

          rom_addr <= ctrl_addr;



          if (new_addr) begin

            ctrl_ok <= 1'b0;

            ctrl_ok_pending <= 1'b0;

            wait2 <= 2'b0;

          end

          else begin

            ctrl_ok <= 1'b0;

            wait2 <= {wait2[0], 1'b1};



            if (align_ctrl_ok) begin

              if (ctrl_ok_pending) begin

                ctrl_ok <= 1'b1;

                ctrl_ok_pending <= 1'b0;

              end

              else if ((wait2 == 2'b11) && rom_ok) begin

                ctrl_dout <= rom_data;

                ctrl_ok_pending <= 1'b1;

                case (ctrl_addr[2:0])

                  3'd0: debug_table_live_bytes[7:0] <= rom_data;

                  3'd1: debug_table_live_bytes[15:8] <= rom_data;

                  3'd2: debug_table_live_bytes[23:16] <= rom_data;

                  3'd3: debug_table_live_bytes[31:24] <= rom_data;

                  3'd4: debug_table_live_bytes[39:32] <= rom_data;

                  default: debug_table_live_bytes[47:40] <= rom_data;

                endcase

              end

            end

            else if (wait2 == 2'b11) begin

              ctrl_ok <= rom_ok;

              if (rom_ok) begin

                ctrl_dout <= rom_data;

                case (ctrl_addr[2:0])

                  3'd0: debug_table_live_bytes[7:0] <= rom_data;

                  3'd1: debug_table_live_bytes[15:8] <= rom_data;

                  3'd2: debug_table_live_bytes[23:16] <= rom_data;

                  3'd3: debug_table_live_bytes[31:24] <= rom_data;

                  3'd4: debug_table_live_bytes[39:32] <= rom_data;

                  default: debug_table_live_bytes[47:40] <= rom_data;

                endcase

              end

            end

            else begin

              ctrl_ok_pending <= 1'b0;

            end

          end

        end

      endcase

    end

  end
if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
0: begin
    debug_body_next_addr <= auto_ss_data_in[17:0];
end
1: begin
    rom_addr <= auto_ss_data_in[17:0];
end
2: begin
    adpcm_dout <= auto_ss_data_in[7:0];
    ctrl_dout <= auto_ss_data_in[15:8];
    debug_body_count <= auto_ss_data_in[18:16];
    wait2 <= auto_ss_data_in[20:19];
    ctrl_ok <= auto_ss_data_in[21];
    ctrl_ok_pending <= auto_ss_data_in[22];
    debug_body_capture <= auto_ss_data_in[23];
    debug_body_done <= auto_ss_data_in[24];
end
3: begin
    debug_body_bytes[31:0] <= auto_ss_data_in[31:0];
end
4: begin
    debug_body_bytes[47:32] <= auto_ss_data_in[15:0];
end
5: begin
    debug_table_bytes[31:0] <= auto_ss_data_in[31:0];
end
6: begin
    debug_table_bytes[47:32] <= auto_ss_data_in[15:0];
end
7: begin
    debug_table_live_bytes[31:0] <= auto_ss_data_in[31:0];
end
8: begin
    debug_table_live_bytes[47:32] <= auto_ss_data_in[15:0];
end
default: begin
end
endcase
end
end


always_comb begin
    auto_ss_data_out = 32'h0;
    auto_ss_ack = 1'b0;
    if (auto_ss_rd && device_match) begin
        case (auto_ss_state_idx)
        0: begin
            auto_ss_data_out[18-1:0] = debug_body_next_addr;
            auto_ss_ack = 1'b1;
        end
        1: begin
            auto_ss_data_out[25:0] = {st, rom_addr};
            auto_ss_ack = 1'b1;
        end
        2: begin
            auto_ss_data_out[24:0] = {debug_body_done, debug_body_capture, ctrl_ok_pending, ctrl_ok, wait2, debug_body_count, ctrl_dout, adpcm_dout};
            auto_ss_ack = 1'b1;
        end
        3: begin
            auto_ss_data_out[32-1:0] = debug_body_bytes[31:0];
            auto_ss_ack = 1'b1;
        end
        4: begin
            auto_ss_data_out[16-1:0] = debug_body_bytes[47:32];
            auto_ss_ack = 1'b1;
        end
        5: begin
            auto_ss_data_out[32-1:0] = debug_table_bytes[31:0];
            auto_ss_ack = 1'b1;
        end
        6: begin
            auto_ss_data_out[16-1:0] = debug_table_bytes[47:32];
            auto_ss_ack = 1'b1;
        end
        7: begin
            auto_ss_data_out[32-1:0] = debug_table_live_bytes[31:0];
            auto_ss_ack = 1'b1;
        end
        8: begin
            auto_ss_data_out[16-1:0] = debug_table_live_bytes[47:32];
            auto_ss_ack = 1'b1;
        end
        default: begin
        end
        endcase
    end
end



endmodule


///////////////////////////////////////////
// MODULE cave_pwrinst2_ss_jt6295_ctrl
module cave_pwrinst2_ss_jt6295_ctrl(

    input                  rst,

    input                  clk,

    input                  cen4,

    input                  cen1,

    // CPU

    input                  wrn,

    input      [ 7:0]      din,

    // Channel address

    output reg [17:0]      start_addr,

    output reg [17:0]      stop_addr,

    // Attenuation

    output reg [ 3:0]      att,

    // ROM interface

    output     [ 9:0]      rom_addr,

    input      [ 7:0]      rom_data,

    input                  rom_ok,

    // Debug

    input                  debug_capture_enable,

    output reg [47:0]      debug_table_bytes,

    output reg [47:0]      debug_decode_bytes,

    output reg             debug_capture_done,

    // flow control

    output reg [ 3:0]      start,

    output reg [ 3:0]      stop,

    input      [ 3:0]      busy,

    input      [ 3:0]      ack,

    input                  zero
,
input auto_ss_rd, input auto_ss_wr, input [31:0] auto_ss_data_in, input [7:0] auto_ss_device_idx, input [15:0] auto_ss_state_idx, input [7:0] auto_ss_base_device_idx, output logic [31:0] auto_ss_data_out, output logic auto_ss_ack


);
genvar auto_ss_idx;

wire device_match = (auto_ss_device_idx == auto_ss_base_device_idx);




reg  last_wrn;

wire negedge_wrn  = !wrn && last_wrn;



// new request

reg [6:0] phrase;

reg       push, pull;

reg [3:0] ch, new_att;

reg       cmd;



always @(posedge clk)
begin
 begin

    last_wrn <= wrn;

end
if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
4: begin
    last_wrn <= auto_ss_data_in[3];
end
default: begin
end
endcase
end
end





reg stop_clr;









// Bus interface

always @(posedge clk)
begin
 begin

    if( rst ) begin

        cmd      <= 1'b0;

        stop     <= 4'd0;

        ch       <= 4'd0;

        pull     <= 1'b1;

        phrase   <= 7'd0;

    end else begin

        if( cen4 ) begin

            stop <= stop & busy;

        end

        if( push ) pull <= 1'b0;

        if( negedge_wrn  ) begin // new write

            if( cmd ) begin // 2nd byte

                ch      <= din[7:4];

                new_att <= din[3:0];

                cmd     <= 1'b0;

                pull    <= 1'b1;

            end

            else if( din[7] ) begin // channel start

                phrase <= din[6:0];

                cmd    <= 1'b1; // wait for second byte

                stop   <= 4'd0;

            end else begin // stop data

                stop   <= din[6:3];

            end

        end

    end

end
if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
3: begin
    phrase <= auto_ss_data_in[6:0];
    ch <= auto_ss_data_in[10:7];
    new_att <= auto_ss_data_in[14:11];
    stop <= auto_ss_data_in[18:15];
end
4: begin
    cmd <= auto_ss_data_in[4];
    pull <= auto_ss_data_in[5];
end
default: begin
end
endcase
end
end





reg [17:0] new_start;

reg [17:8] new_stop;

reg [ 2:0] st, addr_lsb;

reg        wrom;

reg        debug_capture_active;



assign rom_addr = { phrase, addr_lsb };



// Request phrase address

always @(posedge clk)
begin
 begin

    if( rst ) begin

        st <= 3'd7;

        att <= 4'd0;

        start_addr <= 18'd0;

        stop_addr  <= 18'd0;

        start  <= 4'd0;

        push      <= 1'b0;

        addr_lsb  <= 3'b0;

        debug_table_bytes <= 48'h000000000000;

        debug_decode_bytes <= 48'h000000000000;

        debug_capture_active <= 1'b0;

        debug_capture_done <= 1'b0;

    end else begin

        if( negedge_wrn && cmd && debug_capture_enable && !debug_capture_active && !debug_capture_done ) begin

            debug_capture_active <= 1'b1;

            debug_table_bytes <= 48'h000000000000;

            debug_decode_bytes <= 48'h000000000000;

        end



        if(st!=3'd7) begin

            wrom <= 1'b0;

            if( !wrom && rom_ok ) begin

                st       <= st+3'd1;

                addr_lsb <= st;

                wrom     <= 1'b1;

            end

        end

        case(st)

            3'd7: begin

                start    <= start & ~ack;

                addr_lsb <= 3'd0;

                if(pull) begin

                    st       <= 3'd0;

                    wrom     <= 1'b1;

                    push     <= 1'b1;

                end

            end

            3'd0:;

            3'd1: begin

                new_start[17:16] <= rom_data[1:0];

                if( debug_capture_active ) debug_table_bytes[7:0] <= rom_data;

            end

            3'd2: begin

                new_start[15: 8] <= rom_data;

                if( debug_capture_active ) debug_table_bytes[15:8] <= rom_data;

            end

            3'd3: begin

                new_start[ 7: 0] <= rom_data;

                if( debug_capture_active ) debug_table_bytes[23:16] <= rom_data;

            end

            3'd4: begin

                new_stop [17:16] <= rom_data[1:0];

                if( debug_capture_active ) debug_table_bytes[31:24] <= rom_data;

            end

            3'd5: begin

                new_stop [15: 8] <= rom_data;

                if( debug_capture_active ) debug_table_bytes[39:32] <= rom_data;

            end

            3'd6: begin

                if( debug_capture_active ) begin

                    debug_table_bytes[47:40] <= rom_data;

                    debug_decode_bytes <= {

                        rom_data,

                        new_stop[15:8],

                        {6'b000000, new_stop[17:16]},

                        new_start[7:0],

                        new_start[15:8],

                        {6'b000000, new_start[17:16]}

                    };

                    debug_capture_active <= 1'b0;

                    debug_capture_done <= 1'b1;

                end

                start       <= ch;

                start_addr  <= new_start;

                stop_addr   <= {new_stop[17:8], rom_data} ;

                att         <= new_att;

                push        <= 1'b0;

            end

        endcase

    end

end
if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
0: begin
    new_start <= auto_ss_data_in[17:0];
end
1: begin
    start_addr <= auto_ss_data_in[17:0];
end
2: begin
    stop_addr <= auto_ss_data_in[17:0];
    new_stop <= auto_ss_data_in[27:18];
end
3: begin
    att <= auto_ss_data_in[22:19];
    start <= auto_ss_data_in[26:23];
    addr_lsb <= auto_ss_data_in[29:27];
end
4: begin
    st <= auto_ss_data_in[2:0];
    debug_capture_active <= auto_ss_data_in[6];
    debug_capture_done <= auto_ss_data_in[7];
    push <= auto_ss_data_in[8];
    wrom <= auto_ss_data_in[9];
end
5: begin
    debug_decode_bytes[31:0] <= auto_ss_data_in[31:0];
end
6: begin
    debug_decode_bytes[47:32] <= auto_ss_data_in[15:0];
end
7: begin
    debug_table_bytes[31:0] <= auto_ss_data_in[31:0];
end
8: begin
    debug_table_bytes[47:32] <= auto_ss_data_in[15:0];
end
default: begin
end
endcase
end
end


always_comb begin
    auto_ss_data_out = 32'h0;
    auto_ss_ack = 1'b0;
    if (auto_ss_rd && device_match) begin
        case (auto_ss_state_idx)
        0: begin
            auto_ss_data_out[18-1:0] = new_start;
            auto_ss_ack = 1'b1;
        end
        1: begin
            auto_ss_data_out[18-1:0] = start_addr;
            auto_ss_ack = 1'b1;
        end
        2: begin
            auto_ss_data_out[27:0] = {new_stop, stop_addr};
            auto_ss_ack = 1'b1;
        end
        3: begin
            auto_ss_data_out[29:0] = {addr_lsb, start, att, stop, new_att, ch, phrase};
            auto_ss_ack = 1'b1;
        end
        4: begin
            auto_ss_data_out[9:0] = {wrom, push, debug_capture_done, debug_capture_active, pull, cmd, last_wrn, st};
            auto_ss_ack = 1'b1;
        end
        5: begin
            auto_ss_data_out[32-1:0] = debug_decode_bytes[31:0];
            auto_ss_ack = 1'b1;
        end
        6: begin
            auto_ss_data_out[16-1:0] = debug_decode_bytes[47:32];
            auto_ss_ack = 1'b1;
        end
        7: begin
            auto_ss_data_out[32-1:0] = debug_table_bytes[31:0];
            auto_ss_ack = 1'b1;
        end
        8: begin
            auto_ss_data_out[16-1:0] = debug_table_bytes[47:32];
            auto_ss_ack = 1'b1;
        end
        default: begin
        end
        endcase
    end
end





endmodule


///////////////////////////////////////////
// MODULE cave_pwrinst2_ss_jt6295_sh_rst
module cave_pwrinst2_ss_jt6295_sh_rst #(parameter WIDTH=5, STAGES=32, RSTVAL=1'b0 )

(

	input					rst,	

	input 					clk,

	input					clk_en /* synthesis direct_enable */,

	input		[WIDTH-1:0]	din,

   	output		[WIDTH-1:0]	drop
,
input auto_ss_rd, input auto_ss_wr, input [31:0] auto_ss_data_in, input [7:0] auto_ss_device_idx, input [15:0] auto_ss_state_idx, input [7:0] auto_ss_base_device_idx, output logic [31:0] auto_ss_data_out, output logic auto_ss_ack


);
genvar auto_ss_idx;

wire device_match = (auto_ss_device_idx == auto_ss_base_device_idx);




reg [STAGES-1:0] bits[WIDTH-1:0];



genvar i;

integer k;

generate

initial

	for (k=0; k < WIDTH; k=k+1) begin

		bits[k] = { STAGES{RSTVAL}};

	end

endgenerate



generate

	for (i=0; i < WIDTH; i=i+1) begin: bit_shifter

		always @(posedge clk, posedge rst) 

			if( rst ) begin

				bits[i] <= {STAGES{RSTVAL}};

			end
else if (auto_ss_wr && device_match) begin
    if (auto_ss_state_idx == (i)) begin
        bits[i] <= auto_ss_data_in[STAGES-1:0];
    end
end
 else if(clk_en) begin

				bits[i] <= {bits[i][STAGES-2:0], din[i]};

			end

		assign drop[i] = bits[i][STAGES-1];

	end

endgenerate
always_comb begin
    auto_ss_data_out = 32'h0;
    auto_ss_ack = 1'b0;
    if (auto_ss_rd && device_match) begin
            if (auto_ss_state_idx < (WIDTH)) begin
                auto_ss_data_out[STAGES-1:0] = bits[auto_ss_state_idx];
                auto_ss_ack = 1'b1;
            end
    end
end





endmodule


///////////////////////////////////////////
// MODULE cave_pwrinst2_ss_jt6295_serial
module cave_pwrinst2_ss_jt6295_serial(

    input               rst,

    input               clk,

    input               cen,

    input               cen4,

    // Flow

    input      [17:0]   start_addr,

    input      [17:0]   stop_addr,

    input      [ 3:0]   att,

    input      [ 3:0]   start,

    input      [ 3:0]   stop,

    input               restart_mute_busy_start,

    input               reset_adpcm_on_start,

    output reg [ 3:0]   busy,

    output reg [ 3:0]   ack,

    output              zero,

    // ADPCM data feed    

    output     [17:0]   rom_addr,

    input      [ 7:0]   rom_data,

    // serialized data

    output reg          pipe_en,

    output reg          pipe_clear,

    output reg [ 3:0]   pipe_att,

    output reg [ 3:0]   pipe_data
,
input auto_ss_rd, input auto_ss_wr, input [31:0] auto_ss_data_in, input [7:0] auto_ss_device_idx, input [15:0] auto_ss_state_idx, input [7:0] auto_ss_base_device_idx, output logic [31:0] auto_ss_data_out, output logic auto_ss_ack


);
genvar auto_ss_idx;

wire device_match = (auto_ss_device_idx == auto_ss_base_device_idx);

wire [31:0] auto_ss_u_cnt_data_out;

wire auto_ss_u_cnt_ack;

logic [31:0] auto_ss_local_data_out;

logic auto_ss_local_ack;

assign auto_ss_data_out = auto_ss_local_data_out | auto_ss_u_cnt_data_out;

assign auto_ss_ack = auto_ss_local_ack | auto_ss_u_cnt_ack;




localparam CSRW = 18+19+4+1;



reg  [ 3:0] ch;

wire [ 3:0] att_in, att_out;

wire [18:0] cnt, cnt_next, cnt_in;

wire [17:0] ch_end, stop_in, stop_out;

wire        update;

wire        over, busy_in, busy_out, cont;

reg         up_start, up_stop;

reg  [ 1:0] restart_mute_0, restart_mute_1, restart_mute_2, restart_mute_3;

reg         start_clear_0, start_clear_1, start_clear_2, start_clear_3;

wire [ 1:0] restart_mute_count =

    ch[0] ? restart_mute_0 :

    ch[1] ? restart_mute_1 :

    ch[2] ? restart_mute_2 :

            restart_mute_3;

wire        busy_restart_start = restart_mute_busy_start & up_start & busy_out;

wire        restart_mute_active = restart_mute_busy_start &

                                  (busy_restart_start | (restart_mute_count != 2'd0));

wire        start_clear_next =

    ch[0] ? start_clear_0 :

    ch[1] ? start_clear_1 :

    ch[2] ? start_clear_2 :

            start_clear_3;

wire        start_clear_old_sample = reset_adpcm_on_start & up_start & busy_out;



// current channel

always @(posedge clk, posedge rst) begin

    if(rst)

        ch <= 4'b1;
else if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
0: begin
    ch <= auto_ss_data_in[3:0];
end
default: begin
end
endcase
end


    else begin

        // if(cen4) ch <= { ch[0], ch[3:1]  };

        if(cen4) ch <= { ch[2:0], ch[3]  };

    end

end



always @(*) begin

    case( ch )

        4'b0001: { up_start, up_stop } = { start[0], stop[0] };

        4'b0010: { up_start, up_stop } = { start[1], stop[1] };

        4'b0100: { up_start, up_stop } = { start[2], stop[2] };

        4'b1000: { up_start, up_stop } = { start[3], stop[3] };

        default: { up_start, up_stop } = 2'b00;

    endcase

end



reg [17:0] cnt0, cnt1, cnt2, cnt3;



always @(posedge clk, posedge rst) begin

    if( rst ) begin

        restart_mute_0 <= 2'd0;

        restart_mute_1 <= 2'd0;

        restart_mute_2 <= 2'd0;

        restart_mute_3 <= 2'd0;

        start_clear_0 <= 1'b0;

        start_clear_1 <= 1'b0;

        start_clear_2 <= 1'b0;

        start_clear_3 <= 1'b0;

    end
else if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
0: begin
    restart_mute_0 <= auto_ss_data_in[21:20];
    restart_mute_1 <= auto_ss_data_in[23:22];
    restart_mute_2 <= auto_ss_data_in[25:24];
    restart_mute_3 <= auto_ss_data_in[27:26];
    start_clear_0 <= auto_ss_data_in[28];
    start_clear_1 <= auto_ss_data_in[29];
    start_clear_2 <= auto_ss_data_in[30];
    start_clear_3 <= auto_ss_data_in[31];
end
default: begin
end
endcase
end
 else if( cen4 ) begin

        case( ch )

            4'b0001: begin

                restart_mute_0 <= busy_restart_start ? 2'd2 :

                                  (restart_mute_0 != 2'd0 ? restart_mute_0 - 2'd1 : 2'd0);

                start_clear_0 <= up_start;

            end

            4'b0010: begin

                restart_mute_1 <= busy_restart_start ? 2'd2 :

                                  (restart_mute_1 != 2'd0 ? restart_mute_1 - 2'd1 : 2'd0);

                start_clear_1 <= up_start;

            end

            4'b0100: begin

                restart_mute_2 <= busy_restart_start ? 2'd2 :

                                  (restart_mute_2 != 2'd0 ? restart_mute_2 - 2'd1 : 2'd0);

                start_clear_2 <= up_start;

            end

            4'b1000: begin

                restart_mute_3 <= busy_restart_start ? 2'd2 :

                                  (restart_mute_3 != 2'd0 ? restart_mute_3 - 2'd1 : 2'd0);

                start_clear_3 <= up_start;

            end

            default:;

        endcase

    end

end



always @(posedge clk, posedge rst ) begin

    if( rst ) begin

        busy <= 4'd0;

    end
else if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
0: begin
    ack <= auto_ss_data_in[7:4];
    busy <= auto_ss_data_in[11:8];
end
default: begin
end
endcase
end
 else begin

        case( ch )

            4'b0001: busy[0] <= busy_in;

            4'b0010: busy[1] <= busy_in;

            4'b0100: busy[2] <= busy_in;

            4'b1000: busy[3] <= busy_in;

            default: busy    <= 4'd0;

        endcase

        if( cen4 ) begin

            case( ch )

                4'b0001: ack <= up_start ? ch : 4'b0;

                4'b0010: ack <= up_start ? ch : 4'b0;

                4'b0100: ack <= up_start ? ch : 4'b0;

                4'b1000: ack <= up_start ? ch : 4'b0;

                default: ack <= 4'd0;

            endcase

        end

        

    end

end



assign zero     = ch[0];

assign update   = up_start | up_stop;

assign cont     = busy_out & ~over;

assign cnt_next = cont      ? cnt+19'd1 : cnt;

assign stop_in  = up_start  ? stop_addr : stop_out;

assign cnt_in   = up_start  ? {start_addr, 1'b0} : cnt_next;

assign att_in   = up_start  ? att : att_out;

assign busy_in  = update    ? (up_start & ~up_stop) : cont;



wire [CSRW-1:0] csr_in, csr_out;

assign csr_in = { stop_in, cnt_in, att_in, busy_in };

assign {stop_out, cnt, att_out, busy_out } = csr_out;

assign rom_addr = cnt[18:1];

assign over     = rom_addr >= stop_out;



cave_pwrinst2_ss_jt6295_sh_rst #(.WIDTH(CSRW), .STAGES(4) ) u_cnt(

    .rst    ( rst       ),

    .clk    ( clk       ),

    .clk_en ( cen4      ),

    .din    ( csr_in    ),

    .drop   ( csr_out   )
,
                .auto_ss_rd(auto_ss_rd),
                .auto_ss_wr(auto_ss_wr),
                .auto_ss_data_in(auto_ss_data_in),
                .auto_ss_device_idx(auto_ss_device_idx),
                .auto_ss_state_idx(auto_ss_state_idx),
                .auto_ss_base_device_idx(auto_ss_base_device_idx + 8'd1),
                .auto_ss_data_out(auto_ss_u_cnt_data_out),
                .auto_ss_ack(auto_ss_u_cnt_ack)


);



// Channel data is latched for a clock cycle to wait for ROM data



always @(posedge clk, posedge rst) begin

    if(rst) begin

        pipe_data<= 4'd0;

        pipe_en  <= 1'b0;

        pipe_clear <= 1'b0;

        pipe_att <= 4'd0;

    end
else if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
0: begin
    pipe_att <= auto_ss_data_in[15:12];
    pipe_data <= auto_ss_data_in[19:16];
end
1: begin
    pipe_clear <= auto_ss_data_in[0];
    pipe_en <= auto_ss_data_in[1];
end
default: begin
end
endcase
end
 else if(cen4) begin

        // data

        pipe_data <= !cnt[0] ? rom_data[7:4] : rom_data[3:0];

        // reset the ADPCM predictor on the first valid nibble of a new phrase

        pipe_clear <= reset_adpcm_on_start & start_clear_next;

        // attenuation

        pipe_att  <= att_out;

        // busy / enable

        pipe_en   <= busy_out & ~restart_mute_active & ~start_clear_old_sample;

    end

end
always_comb begin
    auto_ss_local_data_out = 32'h0;
    auto_ss_local_ack = 1'b0;
    if (auto_ss_rd && device_match) begin
        case (auto_ss_state_idx)
        0: begin
            auto_ss_local_data_out[31:0] = {start_clear_3, start_clear_2, start_clear_1, start_clear_0, restart_mute_3, restart_mute_2, restart_mute_1, restart_mute_0, pipe_data, pipe_att, busy, ack, ch};
            auto_ss_local_ack = 1'b1;
        end
        1: begin
            auto_ss_local_data_out[1:0] = {pipe_en, pipe_clear};
            auto_ss_local_ack = 1'b1;
        end
        default: begin
        end
        endcase
    end
end





endmodule


///////////////////////////////////////////
// MODULE cave_pwrinst2_ss_jt6295_adpcm
module cave_pwrinst2_ss_jt6295_adpcm(

    input                    rst,

    input                    clk,

    input                    cen,

    input                    en,

    input                    clear,

    input             [ 3:0] att,

    input             [ 3:0] data,

    output reg signed [11:0] sound
,
input auto_ss_rd, input auto_ss_wr, input [31:0] auto_ss_data_in, input [7:0] auto_ss_device_idx, input [15:0] auto_ss_state_idx, input [7:0] auto_ss_base_device_idx, output logic [31:0] auto_ss_data_out, output logic auto_ss_ack


);
genvar auto_ss_idx;

wire device_match = (auto_ss_device_idx == auto_ss_base_device_idx);

wire [31:0] auto_ss_u_enable_data_out;

wire auto_ss_u_enable_ack;

wire [31:0] auto_ss_u_clear_data_out;

wire auto_ss_u_clear_ack;

wire [31:0] auto_ss_u_att_data_out;

wire auto_ss_u_att_ack;

wire [31:0] auto_ss_u_sound_data_out;

wire auto_ss_u_sound_ack;

logic [31:0] auto_ss_local_data_out;

logic auto_ss_local_ack;

assign auto_ss_data_out = auto_ss_local_data_out | auto_ss_u_enable_data_out | auto_ss_u_clear_data_out | auto_ss_u_att_data_out | auto_ss_u_sound_data_out;

assign auto_ss_ack = auto_ss_local_ack | auto_ss_u_enable_ack | auto_ss_u_clear_ack | auto_ss_u_att_ack | auto_ss_u_sound_ack;






reg [10:0] lut[0:48];



reg [ 5:0] idx_inc_II;

reg [ 5:0] delta_idx_I,delta_idx_II, delta_idx_III, delta_idx_IV;



reg [ 2:0] factor_II, factor_III;

reg        factor_IV;

reg        sign_II, sign_III, sign_IV, sign_V;

reg [11:0] dn_II, qn_II, dn_III, qn_III, dn_IV, qn_IV, qn_V;



wire [5:0] delta_idx_base = clear ? 6'd0 : delta_idx_I;



always @(posedge clk, posedge rst ) begin

    if(rst) begin

        idx_inc_II    <= 6'd0;

        delta_idx_I   <= 6'd0;

        delta_idx_II  <= 6'd0;

        delta_idx_III <= 6'd0;

        delta_idx_IV  <= 6'd0;



        factor_II  <= 3'd0;

        factor_III <= 0;

        factor_IV  <= 1'd0;

        { sign_II, sign_III, sign_IV, sign_V } <=4'd0;

        dn_II   <= 12'd0;

        qn_II   <= 12'd0;

        dn_III  <= 12'd0;

        qn_III  <= 12'd0;

        dn_IV   <= 12'd0;

        qn_IV   <= 12'd0;

        qn_V    <= 12'd0;

    end
else if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
0: begin
    dn_II <= auto_ss_data_in[11:0];
    dn_III <= auto_ss_data_in[23:12];
end
1: begin
    dn_IV <= auto_ss_data_in[11:0];
    qn_II <= auto_ss_data_in[23:12];
end
2: begin
    qn_III <= auto_ss_data_in[11:0];
    qn_IV <= auto_ss_data_in[23:12];
end
3: begin
    qn_V <= auto_ss_data_in[11:0];
end
4: begin
    delta_idx_I <= auto_ss_data_in[24:19];
    delta_idx_II <= auto_ss_data_in[30:25];
end
5: begin
    delta_idx_III <= auto_ss_data_in[5:0];
    delta_idx_IV <= auto_ss_data_in[11:6];
    idx_inc_II <= auto_ss_data_in[17:12];
    factor_II <= auto_ss_data_in[20:18];
    factor_III <= auto_ss_data_in[23:21];
    factor_IV <= auto_ss_data_in[24];
    sign_II <= auto_ss_data_in[25];
    sign_III <= auto_ss_data_in[26];
    sign_IV <= auto_ss_data_in[27];
    sign_V <= auto_ss_data_in[28];
end
default: begin
end
endcase
end
 else if(cen) begin

        // I

        case( data[1:0] )

            2'd0: idx_inc_II <= 6'd2;

            2'd1: idx_inc_II <= 6'd4;

            2'd2: idx_inc_II <= 6'd6;

            2'd3: idx_inc_II <= 6'd8;

        endcase

        sign_II      <= data[3];

        delta_idx_II <= en ? delta_idx_base : 6'd0;

        factor_II    <= en ? data[2:0] : 3'd0;

        dn_II        <= { 1'b0, lut[delta_idx_base] };

        qn_II        <= { 1'd0, lut[delta_idx_base]>>3};

        // II

        sign_III      <= sign_II;

        delta_idx_III <= factor_II[2] ? (delta_idx_II+idx_inc_II) : (delta_idx_II-6'd1);

        qn_III        <= factor_II[2] ? qn_II + dn_II : qn_II;

        dn_III        <= dn_II>>1;

        factor_III    <= factor_II;

        // III

        sign_IV      <= sign_III;

        qn_IV        <= factor_III[1] ? qn_III + dn_III : qn_III;

        dn_IV        <= dn_III>>1;

        factor_IV    <= factor_III[0];

        delta_idx_IV <=  delta_idx_III>6'd48 ?

            (factor_III[2] ? 6'd48 : 6'd0) :

            delta_idx_III;

        // IV

        sign_V      <= sign_IV;

        qn_V        <= factor_IV ? qn_IV + dn_IV : qn_IV;

        delta_idx_I <= delta_idx_IV;

    end

end



wire en_V;

wire clear_V;



cave_pwrinst2_ss_jt6295_sh_rst #(.WIDTH(1), .STAGES(4) ) u_enable

(

    .rst    ( rst       ),

    .clk    ( clk       ),

    .clk_en ( cen       ),

    .din    ( en        ),

    .drop   ( en_V      )
,
                .auto_ss_rd(auto_ss_rd),
                .auto_ss_wr(auto_ss_wr),
                .auto_ss_data_in(auto_ss_data_in),
                .auto_ss_device_idx(auto_ss_device_idx),
                .auto_ss_state_idx(auto_ss_state_idx),
                .auto_ss_base_device_idx(auto_ss_base_device_idx + 8'd1),
                .auto_ss_data_out(auto_ss_u_enable_data_out),
                .auto_ss_ack(auto_ss_u_enable_ack)


);



cave_pwrinst2_ss_jt6295_sh_rst #(.WIDTH(1), .STAGES(4) ) u_clear

(

    .rst    ( rst       ),

    .clk    ( clk       ),

    .clk_en ( cen       ),

    .din    ( clear     ),

    .drop   ( clear_V   )
,
                .auto_ss_rd(auto_ss_rd),
                .auto_ss_wr(auto_ss_wr),
                .auto_ss_data_in(auto_ss_data_in),
                .auto_ss_device_idx(auto_ss_device_idx),
                .auto_ss_state_idx(auto_ss_state_idx),
                .auto_ss_base_device_idx(auto_ss_base_device_idx + 8'd2),
                .auto_ss_data_out(auto_ss_u_clear_data_out),
                .auto_ss_ack(auto_ss_u_clear_ack)


);



wire [3:0] att_V;



cave_pwrinst2_ss_jt6295_sh_rst #(.WIDTH(4), .STAGES(4) ) u_att

(

    .rst    ( rst       ),

    .clk    ( clk       ),

    .clk_en ( cen       ),

    .din    ( att       ),

    .drop   ( att_V     )
,
                .auto_ss_rd(auto_ss_rd),
                .auto_ss_wr(auto_ss_wr),
                .auto_ss_data_in(auto_ss_data_in),
                .auto_ss_device_idx(auto_ss_device_idx),
                .auto_ss_state_idx(auto_ss_state_idx),
                .auto_ss_base_device_idx(auto_ss_base_device_idx + 8'd3),
                .auto_ss_data_out(auto_ss_u_att_data_out),
                .auto_ss_ack(auto_ss_u_att_ack)


);





wire signed [11:0] snd_in, snd_out;

reg  signed [11:0] snd_VI;

reg  signed [ 6:0] gain_lut[0:15];

reg  signed [ 6:0] gain_VI; // leave the MSB for the sign

wire signed [16:0] mul_VI = snd_VI * gain_VI; // multipliers are abundant

    // in the FPGA, so I just use one.

reg  signed [12:0] snd_V;



wire signed [12:0] lim_pos =  13'd2047;

wire signed [12:0] lim_neg = -13'd2048;



function [12:0] extend;

    input [11:0] a;

    extend = { a[11], a };

endfunction



always @(*) begin

    snd_V = !en_V ? 13'd0 : (sign_V ? extend(clear_V ? 12'sd0 : snd_out) - { 1'b0, qn_V }  :

                                      extend(clear_V ? 12'sd0 : snd_out) + { 1'b0, qn_V } );

end



assign snd_in = snd_V > lim_pos ? lim_pos[11:0] :

    (snd_V < lim_neg ? lim_neg[11:0] : snd_V[11:0]);



always @(posedge clk, posedge rst) begin

    if(rst) begin

        snd_VI  <= 12'd0;

        gain_VI <= 7'd0;

        sound   <= 12'd0;

    end
else if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
3: begin
    snd_VI <= auto_ss_data_in[23:12];
end
4: begin
    sound <= auto_ss_data_in[11:0];
    gain_VI <= auto_ss_data_in[18:12];
end
default: begin
end
endcase
end
 else if(cen) begin

        snd_VI  <= snd_in;

        gain_VI <= gain_lut[att_V];

        sound   <= mul_VI[16:5];

    end

end
always_comb begin
    auto_ss_local_data_out = 32'h0;
    auto_ss_local_ack = 1'b0;
    if (auto_ss_rd && device_match) begin
        case (auto_ss_state_idx)
        0: begin
            auto_ss_local_data_out[23:0] = {dn_III, dn_II};
            auto_ss_local_ack = 1'b1;
        end
        1: begin
            auto_ss_local_data_out[23:0] = {qn_II, dn_IV};
            auto_ss_local_ack = 1'b1;
        end
        2: begin
            auto_ss_local_data_out[23:0] = {qn_IV, qn_III};
            auto_ss_local_ack = 1'b1;
        end
        3: begin
            auto_ss_local_data_out[23:0] = {snd_VI, qn_V};
            auto_ss_local_ack = 1'b1;
        end
        4: begin
            auto_ss_local_data_out[30:0] = {delta_idx_II, delta_idx_I, gain_VI, sound};
            auto_ss_local_ack = 1'b1;
        end
        5: begin
            auto_ss_local_data_out[28:0] = {sign_V, sign_IV, sign_III, sign_II, factor_IV, factor_III, factor_II, idx_inc_II, delta_idx_IV, delta_idx_III};
            auto_ss_local_ack = 1'b1;
        end
        default: begin
        end
        endcase
    end
end





cave_pwrinst2_ss_jt6295_sh_rst #(.WIDTH(12), .STAGES(4) ) u_sound(

    .rst    ( rst       ),

    .clk    ( clk       ),

    .clk_en ( cen       ),

    .din    ( snd_in    ),

    .drop   ( snd_out   )
,
                .auto_ss_rd(auto_ss_rd),
                .auto_ss_wr(auto_ss_wr),
                .auto_ss_data_in(auto_ss_data_in),
                .auto_ss_device_idx(auto_ss_device_idx),
                .auto_ss_state_idx(auto_ss_state_idx),
                .auto_ss_base_device_idx(auto_ss_base_device_idx + 8'd4),
                .auto_ss_data_out(auto_ss_u_sound_data_out),
                .auto_ss_ack(auto_ss_u_sound_ack)


);



initial begin

lut[ 0] = 11'd0016; lut[ 1] = 11'd0017; lut[ 2] = 11'd0019; lut[ 3] = 11'd0021; lut[ 4] = 11'd0023; lut[ 5] = 11'd0025; lut[ 6] = 11'd0028;

lut[ 7] = 11'd0031; lut[ 8] = 11'd0034; lut[ 9] = 11'd0037; lut[10] = 11'd0041; lut[11] = 11'd0045; lut[12] = 11'd0050; lut[13] = 11'd0055;

lut[14] = 11'd0060; lut[15] = 11'd0066; lut[16] = 11'd0073; lut[17] = 11'd0080; lut[18] = 11'd0088; lut[19] = 11'd0097; lut[20] = 11'd0107;

lut[21] = 11'd0118; lut[22] = 11'd0130; lut[23] = 11'd0143; lut[24] = 11'd0157; lut[25] = 11'd0173; lut[26] = 11'd0190; lut[27] = 11'd0209;

lut[28] = 11'd0230; lut[29] = 11'd0253; lut[30] = 11'd0279; lut[31] = 11'd0307; lut[32] = 11'd0337; lut[33] = 11'd0371; lut[34] = 11'd0408;

lut[35] = 11'd0449; lut[36] = 11'd0494; lut[37] = 11'd0544; lut[38] = 11'd0598; lut[39] = 11'd0658; lut[40] = 11'd0724; lut[41] = 11'd0796;

lut[42] = 11'd0876; lut[43] = 11'd0963; lut[44] = 11'd1060; lut[45] = 11'd1166; lut[46] = 11'd1282; lut[47] = 11'd1411; lut[48] = 11'd1552;

end



initial begin

    gain_lut[0]  = 7'd32;

    gain_lut[1]  = 7'd22;

    gain_lut[2]  = 7'd16;

    gain_lut[3]  = 7'd11;

    gain_lut[4]  = 7'd8;

    gain_lut[5]  = 7'd6;

    gain_lut[6]  = 7'd4;

    gain_lut[7]  = 7'd3;

    gain_lut[8]  = 7'd2;

    gain_lut[9]  = 7'd0; gain_lut[10] = 7'd0; gain_lut[11] = 7'd0;

    gain_lut[12] = 7'd0; gain_lut[13] = 7'd0; gain_lut[14] = 7'd0;

    gain_lut[15] = 7'd0;

end







endmodule


///////////////////////////////////////////
// MODULE cave_pwrinst2_ss_jt6295_acc
module cave_pwrinst2_ss_jt6295_acc(
    input                rst,
    input                clk,
    input                cen,
    input                cen4,
    input  signed [11:0] sound_in,
    output signed [13:0] sound_out,
    output               sample
,
input auto_ss_rd, input auto_ss_wr, input [31:0] auto_ss_data_in, input [7:0] auto_ss_device_idx, input [15:0] auto_ss_state_idx, input [7:0] auto_ss_base_device_idx, output logic [31:0] auto_ss_data_out, output logic auto_ss_ack

);
genvar auto_ss_idx;

wire device_match = (auto_ss_device_idx == auto_ss_base_device_idx);


parameter INTERPOL = 0;

reg signed [13:0] acc;
reg signed [13:0] sum;

always @(posedge clk, posedge rst) begin
    if (rst)
        acc <= 14'd0;
else if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
0: begin
    acc <= auto_ss_data_in[13:0];
end
default: begin
end
endcase
end

    else if (cen4)
        acc <= cen ? sound_in : acc + sound_in;
end

always @(posedge clk, posedge rst) begin
    if (rst)
        sum <= 14'd0;
else if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
0: begin
    sum <= auto_ss_data_in[27:14];
end
default: begin
end
endcase
end

    else if (cen)
        sum <= acc;
end
always_comb begin
    auto_ss_data_out = 32'h0;
    auto_ss_ack = 1'b0;
    if (auto_ss_rd && device_match) begin
        case (auto_ss_state_idx)
        0: begin
            auto_ss_data_out[27:0] = {sum, acc};
            auto_ss_ack = 1'b1;
        end
        default: begin
        end
        endcase
    end
end



assign sound_out = sum;
assign sample = cen;

endmodule


///////////////////////////////////////////
// MODULE cave_pwrinst2_ss_CaveOKIM6295Core
module cave_pwrinst2_ss_CaveOKIM6295Core #(

  parameter INTERPOL = 1

)(

  input                rst,

  input                clk,

  input                cen,

  input                save_hold,

  input                ss,

  input                wait_for_rom,

  input                ignore_busy_start,

  input                duplicate_busy_start_filter,

  input                restart_busy_start,

  input                restart_mute_busy_start,

  input                reset_adpcm_on_start,

  input                status_includes_start,

  input                debug_capture_enable,

  input                align_ctrl_ok,

  input                wrn,

  input         [7:0]  din,

  output        [7:0]  dout,

  output        [17:0] rom_addr,

  input         [7:0]  rom_data,

  input                rom_ok,

  output signed [13:0] sound,

  output               sample,

  output reg    [47:0] debug_ctrl_bytes,

  output reg    [47:0] debug_decode_bytes,

  output reg    [47:0] debug_table_bytes,

  output        [47:0] debug_body_bytes,

  output        debug_body_done,

  output        [7:0]  debug_busy_state,
  output               cen_sr_out,
  output               cen_sr4_out,
input auto_ss_rd, input auto_ss_wr, input [31:0] auto_ss_data_in, input [7:0] auto_ss_device_idx, input [15:0] auto_ss_state_idx, input [7:0] auto_ss_base_device_idx, output logic [31:0] auto_ss_data_out, output logic auto_ss_ack


);
genvar auto_ss_idx;

wire device_match = (auto_ss_device_idx == auto_ss_base_device_idx);

wire [31:0] auto_ss_u_timing_data_out;

wire auto_ss_u_timing_ack;

wire [31:0] auto_ss_u_rom_data_out;

wire auto_ss_u_rom_ack;

wire [31:0] auto_ss_u_ctrl_data_out;

wire auto_ss_u_ctrl_ack;

wire [31:0] auto_ss_u_serial_data_out;

wire auto_ss_u_serial_ack;

wire [31:0] auto_ss_u_adpcm_data_out;

wire auto_ss_u_adpcm_ack;

wire [31:0] auto_ss_u_acc_data_out;

wire auto_ss_u_acc_ack;

logic [31:0] auto_ss_local_data_out;

logic auto_ss_local_ack;

assign auto_ss_data_out = auto_ss_local_data_out | auto_ss_u_timing_data_out | auto_ss_u_rom_data_out | auto_ss_u_ctrl_data_out | auto_ss_u_serial_data_out | auto_ss_u_adpcm_data_out | auto_ss_u_acc_data_out;

assign auto_ss_ack = auto_ss_local_ack | auto_ss_u_timing_ack | auto_ss_u_rom_ack | auto_ss_u_ctrl_ack | auto_ss_u_serial_ack | auto_ss_u_adpcm_ack | auto_ss_u_acc_ack;


  wire        cen_sr;

  wire        cen_sr4;

  wire        cen_sr4b;

  wire        cen_sr32;

  assign cen_sr_out = cen_sr;
  assign cen_sr4_out = cen_sr4;

  wire [3:0]  busy;

  wire [3:0]  ack;

  wire [3:0]  ctrl_start;

  wire [3:0]  start;

  wire [3:0]  serial_start;

  wire [3:0]  direct_start;

  wire [3:0]  serial_stop;

  wire [3:0]  busy_start;

  wire [3:0]  ctrl_ack;
  wire [3:0]  stop;
  wire [17:0] start_addr;

  wire [17:0] stop_addr;

  wire [17:0] serial_start_addr;

  wire [17:0] serial_stop_addr;

  wire [17:0] ch_addr;

  wire [9:0]  ctrl_addr;

  wire [7:0]  ch_data;

  wire [7:0]  ctrl_data;

  wire [3:0]  pipe_data;

  wire [3:0]  att;

  wire [3:0]  serial_att;

  wire [3:0]  pipe_att;

  wire        ctrl_ok;

  wire        zero;

  wire        pipe_en;

  wire        pipe_clear;

  wire signed [11:0] pipe_snd;

  wire        debug_start = |serial_start;

  wire        debug_capture_start = debug_start & debug_capture_enable;

  wire [47:0] ctrl_debug_table_bytes;

  wire [47:0] ctrl_debug_decode_bytes;

  wire        ctrl_debug_capture_done;

  reg         ctrl_debug_capture_done_d;

  wire        ctrl_debug_done_rise = ctrl_debug_capture_done & ~ctrl_debug_capture_done_d;

  wire [47:0] rom_debug_table_bytes;
  reg  [3:0]  start_seen;
  reg  [3:0]  start_busy_latched;

  reg         ctrl_start_final_byte_seen;


  localparam [21:0] DUP_BUSY_WINDOW_RELOAD = 22'h3fffff;



  reg  [3:0]  duplicate_start_valid;

  reg  [17:0] duplicate_start_addr_0;

  reg  [17:0] duplicate_start_addr_1;

  reg  [17:0] duplicate_start_addr_2;

  reg  [17:0] duplicate_start_addr_3;

  reg  [17:0] duplicate_stop_addr_0;

  reg  [17:0] duplicate_stop_addr_1;

  reg  [17:0] duplicate_stop_addr_2;

  reg  [17:0] duplicate_stop_addr_3;

  reg  [21:0] duplicate_window_0;

  reg  [21:0] duplicate_window_1;

  reg  [21:0] duplicate_window_2;

  reg  [21:0] duplicate_window_3;



  reg  [3:0]  restart_pending;

  reg  [17:0] restart_start_addr_0;

  reg  [17:0] restart_start_addr_1;

  reg  [17:0] restart_start_addr_2;

  reg  [17:0] restart_start_addr_3;

  reg  [17:0] restart_stop_addr_0;

  reg  [17:0] restart_stop_addr_1;

  reg  [17:0] restart_stop_addr_2;

  reg  [17:0] restart_stop_addr_3;

  reg  [3:0]  restart_att_0;

  reg  [3:0]  restart_att_1;

  reg  [3:0]  restart_att_2;

  reg  [3:0]  restart_att_3;



  wire [3:0]  duplicate_start_recent = {

    duplicate_window_3 != 22'd0,

    duplicate_window_2 != 22'd0,

    duplicate_window_1 != 22'd0,

    duplicate_window_0 != 22'd0

  };

  wire [3:0]  duplicate_start_match = {

    duplicate_start_valid[3] & duplicate_start_recent[3] &

      (start_addr == duplicate_start_addr_3) & (stop_addr == duplicate_stop_addr_3),

    duplicate_start_valid[2] & duplicate_start_recent[2] &

      (start_addr == duplicate_start_addr_2) & (stop_addr == duplicate_stop_addr_2),

    duplicate_start_valid[1] & duplicate_start_recent[1] &

      (start_addr == duplicate_start_addr_1) & (stop_addr == duplicate_stop_addr_1),

    duplicate_start_valid[0] & duplicate_start_recent[0] &

      (start_addr == duplicate_start_addr_0) & (stop_addr == duplicate_stop_addr_0)

  };

  wire [3:0]  duplicate_busy_start =

    duplicate_busy_start_filter ? (busy_start & duplicate_start_match) : 4'd0;

  wire [3:0]  ignored_busy_start =

    (ignore_busy_start ? busy_start : 4'd0) | duplicate_busy_start;

  wire [3:0]  restart_new = restart_busy_start ? (busy_start & ~ignored_busy_start) : 4'd0;

  wire [3:0]  restart_ack = restart_busy_start ? (ack & restart_pending) : 4'd0;

  wire [3:0]  restart_cancel = restart_busy_start ? stop : 4'd0;

  wire [3:0]  restart_stop = restart_busy_start ? (restart_pending & busy) : 4'd0;

  wire [3:0]  restart_ready = restart_busy_start ?

    (restart_pending & ~busy & {4{~(|direct_start)}}) : 4'd0;

  wire [3:0]  restart_start =

    restart_ready[0] ? 4'b0001 :

    restart_ready[1] ? 4'b0010 :

    restart_ready[2] ? 4'b0100 :

    restart_ready[3] ? 4'b1000 :

                       4'b0000;

  wire        restart_replay = |restart_start;

  wire [17:0] restart_start_addr =

    restart_start[0] ? restart_start_addr_0 :

    restart_start[1] ? restart_start_addr_1 :

    restart_start[2] ? restart_start_addr_2 :

                       restart_start_addr_3;

  wire [17:0] restart_stop_addr =

    restart_start[0] ? restart_stop_addr_0 :

    restart_start[1] ? restart_stop_addr_1 :

    restart_start[2] ? restart_stop_addr_2 :

                       restart_stop_addr_3;

  wire [3:0] restart_att =

    restart_start[0] ? restart_att_0 :

    restart_start[1] ? restart_att_1 :

    restart_start[2] ? restart_att_2 :

                       restart_att_3;

  wire [3:0]  handled_busy_start = ignored_busy_start | restart_new;

  wire [3:0]  accepted_direct_start = ack & direct_start;



  wire [3:0] new_start_request = start & ~start_seen;
  assign start = align_ctrl_ok
    ? (ctrl_start & {4{ctrl_start_final_byte_seen}})
    : ctrl_start;
  assign busy_start =
    (new_start_request & busy) |
    (start & start_seen & start_busy_latched);
  assign direct_start = start & ~handled_busy_start;

  assign serial_start = direct_start | restart_start;

  assign serial_stop = stop | restart_stop;

  assign serial_start_addr = restart_replay ? restart_start_addr : start_addr;

  assign serial_stop_addr = restart_replay ? restart_stop_addr : stop_addr;

  assign serial_att = restart_replay ? restart_att : att;

  assign ctrl_ack = ack | handled_busy_start;

  assign dout = {4'hf, busy | (status_includes_start ? serial_start : 4'd0)};

  assign debug_busy_state = {restart_pending, restart_start};

  // Delay the Cave-local start handshake until JT6295 has consumed the sixth
  // control-table byte and the complete stop address is stable.
  always @(posedge clk)
  begin
    begin
      if (rst || !(|ctrl_start)) begin
        ctrl_start_final_byte_seen <= 1'b0;
      end
      else if (!save_hold && ctrl_ok) begin
        ctrl_start_final_byte_seen <= 1'b1;
      end
    end
    if (auto_ss_wr && device_match) begin
      case (auto_ss_state_idx)
        20: begin
          ctrl_start_final_byte_seen <= auto_ss_data_in[21];
        end
        default: begin
        end
      endcase
    end
  end

  // Classify a request against the pre-existing voice state once. The serial
  // engine can assert busy before it acknowledges a free start; re-evaluating
  // busy throughout that handshake would make an ignore policy eat its own
  // newly accepted request.
  always @(posedge clk)
begin
 begin
    if (rst) begin
      start_seen <= 4'd0;
      start_busy_latched <= 4'd0;
    end
    else if (!save_hold) begin
      start_seen <= (start_seen | start) & start;
      start_busy_latched <=
        (start_busy_latched & start_seen & start) |
        (busy & new_start_request);
    end
  end
if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
19: begin
    start_busy_latched <= auto_ss_data_in[21:18];
    start_seen <= auto_ss_data_in[25:22];
end
default: begin
end
endcase
end
end



  always @(posedge clk)
begin
 begin
    if (rst) begin

      duplicate_start_valid <= 4'd0;

      duplicate_start_addr_0 <= 18'd0;

      duplicate_start_addr_1 <= 18'd0;

      duplicate_start_addr_2 <= 18'd0;

      duplicate_start_addr_3 <= 18'd0;

      duplicate_stop_addr_0 <= 18'd0;

      duplicate_stop_addr_1 <= 18'd0;

      duplicate_stop_addr_2 <= 18'd0;

      duplicate_stop_addr_3 <= 18'd0;

      duplicate_window_0 <= 22'd0;

      duplicate_window_1 <= 22'd0;

      duplicate_window_2 <= 22'd0;

      duplicate_window_3 <= 22'd0;

    end

    else if (!save_hold) begin

      if (duplicate_window_0 != 22'd0)

        duplicate_window_0 <= duplicate_window_0 - 22'd1;

      if (duplicate_window_1 != 22'd0)

        duplicate_window_1 <= duplicate_window_1 - 22'd1;

      if (duplicate_window_2 != 22'd0)

        duplicate_window_2 <= duplicate_window_2 - 22'd1;

      if (duplicate_window_3 != 22'd0)

        duplicate_window_3 <= duplicate_window_3 - 22'd1;



      if (~busy[0] | stop[0]) begin

        duplicate_start_valid[0] <= 1'b0;

        duplicate_window_0 <= 22'd0;

      end

      if (~busy[1] | stop[1]) begin

        duplicate_start_valid[1] <= 1'b0;

        duplicate_window_1 <= 22'd0;

      end

      if (~busy[2] | stop[2]) begin

        duplicate_start_valid[2] <= 1'b0;

        duplicate_window_2 <= 22'd0;

      end

      if (~busy[3] | stop[3]) begin

        duplicate_start_valid[3] <= 1'b0;

        duplicate_window_3 <= 22'd0;

      end



      if (accepted_direct_start[0]) begin

        duplicate_start_valid[0] <= 1'b1;

        duplicate_start_addr_0 <= start_addr;

        duplicate_stop_addr_0 <= stop_addr;

        duplicate_window_0 <= DUP_BUSY_WINDOW_RELOAD;

      end

      else if (duplicate_busy_start[0]) begin

        duplicate_window_0 <= DUP_BUSY_WINDOW_RELOAD;

      end



      if (accepted_direct_start[1]) begin

        duplicate_start_valid[1] <= 1'b1;

        duplicate_start_addr_1 <= start_addr;

        duplicate_stop_addr_1 <= stop_addr;

        duplicate_window_1 <= DUP_BUSY_WINDOW_RELOAD;

      end

      else if (duplicate_busy_start[1]) begin

        duplicate_window_1 <= DUP_BUSY_WINDOW_RELOAD;

      end



      if (accepted_direct_start[2]) begin

        duplicate_start_valid[2] <= 1'b1;

        duplicate_start_addr_2 <= start_addr;

        duplicate_stop_addr_2 <= stop_addr;

        duplicate_window_2 <= DUP_BUSY_WINDOW_RELOAD;

      end

      else if (duplicate_busy_start[2]) begin

        duplicate_window_2 <= DUP_BUSY_WINDOW_RELOAD;

      end



      if (accepted_direct_start[3]) begin

        duplicate_start_valid[3] <= 1'b1;

        duplicate_start_addr_3 <= start_addr;

        duplicate_stop_addr_3 <= stop_addr;

        duplicate_window_3 <= DUP_BUSY_WINDOW_RELOAD;

      end

      else if (duplicate_busy_start[3]) begin

        duplicate_window_3 <= DUP_BUSY_WINDOW_RELOAD;

      end

    end

  end
if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
0: begin
    duplicate_window_0 <= auto_ss_data_in[21:0];
end
1: begin
    duplicate_window_1 <= auto_ss_data_in[21:0];
end
2: begin
    duplicate_window_2 <= auto_ss_data_in[21:0];
end
3: begin
    duplicate_window_3 <= auto_ss_data_in[21:0];
end
4: begin
    duplicate_start_addr_0 <= auto_ss_data_in[17:0];
end
5: begin
    duplicate_start_addr_1 <= auto_ss_data_in[17:0];
end
6: begin
    duplicate_start_addr_2 <= auto_ss_data_in[17:0];
end
7: begin
    duplicate_start_addr_3 <= auto_ss_data_in[17:0];
end
8: begin
    duplicate_stop_addr_0 <= auto_ss_data_in[17:0];
end
9: begin
    duplicate_stop_addr_1 <= auto_ss_data_in[17:0];
end
10: begin
    duplicate_stop_addr_2 <= auto_ss_data_in[17:0];
end
11: begin
    duplicate_stop_addr_3 <= auto_ss_data_in[17:0];
end
19: begin
    duplicate_start_valid <= auto_ss_data_in[29:26];
end
default: begin
end
endcase
end
end





  always @(posedge clk)
begin
 begin

    if (rst) begin

      restart_pending <= 4'd0;

      restart_start_addr_0 <= 18'd0;

      restart_start_addr_1 <= 18'd0;

      restart_start_addr_2 <= 18'd0;

      restart_start_addr_3 <= 18'd0;

      restart_stop_addr_0 <= 18'd0;

      restart_stop_addr_1 <= 18'd0;

      restart_stop_addr_2 <= 18'd0;

      restart_stop_addr_3 <= 18'd0;

      restart_att_0 <= 4'd0;

      restart_att_1 <= 4'd0;

      restart_att_2 <= 4'd0;

      restart_att_3 <= 4'd0;

    end

    else if (!save_hold) begin

      restart_pending <= ((restart_pending & ~restart_ack) | restart_new) & ~restart_cancel;



      if (restart_new[0]) begin

        restart_start_addr_0 <= start_addr;

        restart_stop_addr_0 <= stop_addr;

        restart_att_0 <= att;

      end

      if (restart_new[1]) begin

        restart_start_addr_1 <= start_addr;

        restart_stop_addr_1 <= stop_addr;

        restart_att_1 <= att;

      end

      if (restart_new[2]) begin

        restart_start_addr_2 <= start_addr;

        restart_stop_addr_2 <= stop_addr;

        restart_att_2 <= att;

      end

      if (restart_new[3]) begin

        restart_start_addr_3 <= start_addr;

        restart_stop_addr_3 <= stop_addr;

        restart_att_3 <= att;

      end

    end

  end
if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
12: begin
    restart_start_addr_0 <= auto_ss_data_in[17:0];
end
13: begin
    restart_start_addr_1 <= auto_ss_data_in[17:0];
end
14: begin
    restart_start_addr_2 <= auto_ss_data_in[17:0];
end
15: begin
    restart_start_addr_3 <= auto_ss_data_in[17:0];
end
16: begin
    restart_stop_addr_0 <= auto_ss_data_in[17:0];
end
17: begin
    restart_stop_addr_1 <= auto_ss_data_in[17:0];
end
18: begin
    restart_stop_addr_2 <= auto_ss_data_in[17:0];
end
19: begin
    restart_stop_addr_3 <= auto_ss_data_in[17:0];
end
20: begin
    restart_att_0 <= auto_ss_data_in[3:0];
    restart_att_1 <= auto_ss_data_in[7:4];
    restart_att_2 <= auto_ss_data_in[11:8];
    restart_att_3 <= auto_ss_data_in[15:12];
    restart_pending <= auto_ss_data_in[19:16];
end
default: begin
end
endcase
end
end





  cave_pwrinst2_ss_jt6295_timing u_timing(

    .clk      (clk),

    .cen      (cen),

    .ss       (ss),

    .cen_sr   (cen_sr),

    .cen_sr4  (cen_sr4),

    .cen_sr4b (cen_sr4b),

    .cen_sr32 (cen_sr32)
,
                .auto_ss_rd(auto_ss_rd),
                .auto_ss_wr(auto_ss_wr),
                .auto_ss_data_in(auto_ss_data_in),
                .auto_ss_device_idx(auto_ss_device_idx),
                .auto_ss_state_idx(auto_ss_state_idx),
                .auto_ss_base_device_idx(auto_ss_base_device_idx + 8'd1),
                .auto_ss_data_out(auto_ss_u_timing_data_out),
                .auto_ss_ack(auto_ss_u_timing_ack)


  );



  cave_pwrinst2_ss_CaveOKIM6295Rom u_rom(

    .rst          (rst),

    .clk          (clk),

    .cen4         (cen_sr4),

    .cen32        (cen_sr32),

    .wait_for_rom (wait_for_rom),

    .align_ctrl_ok (align_ctrl_ok),

    .save_hold    (save_hold),

    .adpcm_addr   (ch_addr),

    .ctrl_addr    ({8'd0, ctrl_addr}),

    .adpcm_dout   (ch_data),

    .ctrl_dout    (ctrl_data),

    .ctrl_ok      (ctrl_ok),

    .debug_capture_start (debug_capture_start),

    .debug_capture_addr  (serial_start_addr),

    .debug_table_bytes   (rom_debug_table_bytes),

    .debug_body_bytes    (debug_body_bytes),

    .debug_body_done     (debug_body_done),

    .rom_addr     (rom_addr),

    .rom_data     (rom_data),

    .rom_ok       (rom_ok)
,
                .auto_ss_rd(auto_ss_rd),
                .auto_ss_wr(auto_ss_wr),
                .auto_ss_data_in(auto_ss_data_in),
                .auto_ss_device_idx(auto_ss_device_idx),
                .auto_ss_state_idx(auto_ss_state_idx),
                .auto_ss_base_device_idx(auto_ss_base_device_idx + 8'd2),
                .auto_ss_data_out(auto_ss_u_rom_data_out),
                .auto_ss_ack(auto_ss_u_rom_ack)


  );



  cave_pwrinst2_ss_jt6295_ctrl u_ctrl(

    .rst        (rst),

    .clk        (clk),

    .cen1       (cen_sr),

    .cen4       (cen_sr4),

    .wrn        (wrn),

    .din        (din),

    .start_addr (start_addr),

    .stop_addr  (stop_addr),

    .att        (att),

    .rom_addr   (ctrl_addr),

    .rom_data   (ctrl_data),

    .rom_ok     (ctrl_ok),

    .debug_capture_enable (debug_capture_enable),

    .debug_table_bytes (ctrl_debug_table_bytes),

    .debug_decode_bytes (ctrl_debug_decode_bytes),

    .debug_capture_done (ctrl_debug_capture_done),

    .start      (ctrl_start),

    .stop       (stop),

    .busy       (busy),

    .ack        (ctrl_ack),

    .zero       (zero)
,
                .auto_ss_rd(auto_ss_rd),
                .auto_ss_wr(auto_ss_wr),
                .auto_ss_data_in(auto_ss_data_in),
                .auto_ss_device_idx(auto_ss_device_idx),
                .auto_ss_state_idx(auto_ss_state_idx),
                .auto_ss_base_device_idx(auto_ss_base_device_idx + 8'd3),
                .auto_ss_data_out(auto_ss_u_ctrl_data_out),
                .auto_ss_ack(auto_ss_u_ctrl_ack)


  );



  cave_pwrinst2_ss_jt6295_serial u_serial(

    .rst        (rst),

    .clk        (clk),

    .cen        (cen_sr),

    .cen4       (cen_sr4),

    .start_addr (serial_start_addr),

    .stop_addr  (serial_stop_addr),

    .att        (serial_att),

    .start      (serial_start),

    .stop       (serial_stop),

    .restart_mute_busy_start (restart_mute_busy_start),

    .reset_adpcm_on_start (reset_adpcm_on_start),

    .busy       (busy),

    .ack        (ack),

    .zero       (zero),

    .rom_addr   (ch_addr),

    .rom_data   (ch_data),

    .pipe_en    (pipe_en),

    .pipe_clear (pipe_clear),

    .pipe_att   (pipe_att),

    .pipe_data  (pipe_data)
,
                .auto_ss_rd(auto_ss_rd),
                .auto_ss_wr(auto_ss_wr),
                .auto_ss_data_in(auto_ss_data_in),
                .auto_ss_device_idx(auto_ss_device_idx),
                .auto_ss_state_idx(auto_ss_state_idx),
                .auto_ss_base_device_idx(auto_ss_base_device_idx + 8'd4),
                .auto_ss_data_out(auto_ss_u_serial_data_out),
                .auto_ss_ack(auto_ss_u_serial_ack)


  );



  cave_pwrinst2_ss_jt6295_adpcm u_adpcm(

    .rst   (rst),

    .clk   (clk),

    .cen   (cen_sr4),

    .en    (pipe_en),

    .clear (pipe_clear),

    .att   (pipe_att),

    .data  (pipe_data),

    .sound (pipe_snd)
,
                .auto_ss_rd(auto_ss_rd),
                .auto_ss_wr(auto_ss_wr),
                .auto_ss_data_in(auto_ss_data_in),
                .auto_ss_device_idx(auto_ss_device_idx),
                .auto_ss_state_idx(auto_ss_state_idx),
                .auto_ss_base_device_idx(auto_ss_base_device_idx + 8'd6),
                .auto_ss_data_out(auto_ss_u_adpcm_data_out),
                .auto_ss_ack(auto_ss_u_adpcm_ack)


  );



  cave_pwrinst2_ss_jt6295_acc #(.INTERPOL(INTERPOL)) u_acc(

    .rst       (rst),

    .clk       (clk),

    .cen       (cen_sr),

    .cen4      (cen_sr4),

    .sound_in  (pipe_snd),

    .sound_out (sound),

    .sample    (sample)
,
                .auto_ss_rd(auto_ss_rd),
                .auto_ss_wr(auto_ss_wr),
                .auto_ss_data_in(auto_ss_data_in),
                .auto_ss_device_idx(auto_ss_device_idx),
                .auto_ss_state_idx(auto_ss_state_idx),
                .auto_ss_base_device_idx(auto_ss_base_device_idx + 8'd11),
                .auto_ss_data_out(auto_ss_u_acc_data_out),
                .auto_ss_ack(auto_ss_u_acc_ack)


  );



  always @(posedge clk)
begin
 begin

    if (rst) begin

      debug_ctrl_bytes <= 48'h000000000000;

      debug_decode_bytes <= 48'h000000000000;

      debug_table_bytes <= 48'h000000000000;

      ctrl_debug_capture_done_d <= 1'b0;

    end

    else if (!save_hold) begin

      ctrl_debug_capture_done_d <= ctrl_debug_capture_done;



      if (debug_capture_start & ~ctrl_debug_capture_done) begin

        debug_ctrl_bytes <= 48'h000000000000;

        debug_decode_bytes <= 48'h000000000000;

        debug_table_bytes <= 48'h000000000000;

      end



      if (ctrl_debug_done_rise) begin

        debug_ctrl_bytes <= {

          stop_addr[7:0],

          stop_addr[15:8],

          {6'b000000, stop_addr[17:16]},

          start_addr[7:0],

          start_addr[15:8],

          {6'b000000, start_addr[17:16]}

        };

        debug_decode_bytes <= ctrl_debug_decode_bytes;

        debug_table_bytes <= ctrl_debug_table_bytes;

      end

    end

  end
if (auto_ss_wr && device_match) begin
case (auto_ss_state_idx)
20: begin
    ctrl_debug_capture_done_d <= auto_ss_data_in[20];
end
21: begin
    debug_ctrl_bytes[31:0] <= auto_ss_data_in[31:0];
end
22: begin
    debug_ctrl_bytes[47:32] <= auto_ss_data_in[15:0];
end
23: begin
    debug_decode_bytes[31:0] <= auto_ss_data_in[31:0];
end
24: begin
    debug_decode_bytes[47:32] <= auto_ss_data_in[15:0];
end
25: begin
    debug_table_bytes[31:0] <= auto_ss_data_in[31:0];
end
26: begin
    debug_table_bytes[47:32] <= auto_ss_data_in[15:0];
end
default: begin
end
endcase
end
end


always_comb begin
    auto_ss_local_data_out = 32'h0;
    auto_ss_local_ack = 1'b0;
    if (auto_ss_rd && device_match) begin
        case (auto_ss_state_idx)
        0: begin
            auto_ss_local_data_out[22-1:0] = duplicate_window_0;
            auto_ss_local_ack = 1'b1;
        end
        1: begin
            auto_ss_local_data_out[22-1:0] = duplicate_window_1;
            auto_ss_local_ack = 1'b1;
        end
        2: begin
            auto_ss_local_data_out[22-1:0] = duplicate_window_2;
            auto_ss_local_ack = 1'b1;
        end
        3: begin
            auto_ss_local_data_out[22-1:0] = duplicate_window_3;
            auto_ss_local_ack = 1'b1;
        end
        4: begin
            auto_ss_local_data_out[18-1:0] = duplicate_start_addr_0;
            auto_ss_local_ack = 1'b1;
        end
        5: begin
            auto_ss_local_data_out[18-1:0] = duplicate_start_addr_1;
            auto_ss_local_ack = 1'b1;
        end
        6: begin
            auto_ss_local_data_out[18-1:0] = duplicate_start_addr_2;
            auto_ss_local_ack = 1'b1;
        end
        7: begin
            auto_ss_local_data_out[18-1:0] = duplicate_start_addr_3;
            auto_ss_local_ack = 1'b1;
        end
        8: begin
            auto_ss_local_data_out[18-1:0] = duplicate_stop_addr_0;
            auto_ss_local_ack = 1'b1;
        end
        9: begin
            auto_ss_local_data_out[18-1:0] = duplicate_stop_addr_1;
            auto_ss_local_ack = 1'b1;
        end
        10: begin
            auto_ss_local_data_out[18-1:0] = duplicate_stop_addr_2;
            auto_ss_local_ack = 1'b1;
        end
        11: begin
            auto_ss_local_data_out[18-1:0] = duplicate_stop_addr_3;
            auto_ss_local_ack = 1'b1;
        end
        12: begin
            auto_ss_local_data_out[18-1:0] = restart_start_addr_0;
            auto_ss_local_ack = 1'b1;
        end
        13: begin
            auto_ss_local_data_out[18-1:0] = restart_start_addr_1;
            auto_ss_local_ack = 1'b1;
        end
        14: begin
            auto_ss_local_data_out[18-1:0] = restart_start_addr_2;
            auto_ss_local_ack = 1'b1;
        end
        15: begin
            auto_ss_local_data_out[18-1:0] = restart_start_addr_3;
            auto_ss_local_ack = 1'b1;
        end
        16: begin
            auto_ss_local_data_out[18-1:0] = restart_stop_addr_0;
            auto_ss_local_ack = 1'b1;
        end
        17: begin
            auto_ss_local_data_out[18-1:0] = restart_stop_addr_1;
            auto_ss_local_ack = 1'b1;
        end
        18: begin
            auto_ss_local_data_out[18-1:0] = restart_stop_addr_2;
            auto_ss_local_ack = 1'b1;
        end
        19: begin
            auto_ss_local_data_out[29:0] = {duplicate_start_valid, start_seen, start_busy_latched, restart_stop_addr_3};
            auto_ss_local_ack = 1'b1;
        end
        20: begin
            auto_ss_local_data_out[21:0] = {ctrl_start_final_byte_seen, ctrl_debug_capture_done_d, restart_pending, restart_att_3, restart_att_2, restart_att_1, restart_att_0};
            auto_ss_local_ack = 1'b1;
        end
        21: begin
            auto_ss_local_data_out[32-1:0] = debug_ctrl_bytes[31:0];
            auto_ss_local_ack = 1'b1;
        end
        22: begin
            auto_ss_local_data_out[16-1:0] = debug_ctrl_bytes[47:32];
            auto_ss_local_ack = 1'b1;
        end
        23: begin
            auto_ss_local_data_out[32-1:0] = debug_decode_bytes[31:0];
            auto_ss_local_ack = 1'b1;
        end
        24: begin
            auto_ss_local_data_out[16-1:0] = debug_decode_bytes[47:32];
            auto_ss_local_ack = 1'b1;
        end
        25: begin
            auto_ss_local_data_out[32-1:0] = debug_table_bytes[31:0];
            auto_ss_local_ack = 1'b1;
        end
        26: begin
            auto_ss_local_data_out[16-1:0] = debug_table_bytes[47:32];
            auto_ss_local_ack = 1'b1;
        end
        default: begin
        end
        endcase
    end
end



endmodule


