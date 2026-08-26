module CavePwrInst2OKIM6295 #(
  parameter [7:0] SS_IDX = 8'd36,
  parameter FIR_COEFFS = "jt6295_up4_soft.hex",
  parameter WRITE_HOLD_CYCLES = 8,
  parameter FIXED_SAMPLE_CLOCK = 0
) (
  input         clock,
  input         reset,
  input  [16:0] io_cen_step,
  input         io_ss,
  input         io_cpu_wr,
  input  [7:0]  io_cpu_din,
  input         io_stretch_cpu_wr,
  input         io_wait_for_rom,
  input         io_ignore_busy_start,
  input         io_duplicate_busy_start_filter,
  input         io_restart_busy_start,
  input         io_restart_mute_busy_start,
  input         io_reset_adpcm_on_start,
  input         io_status_includes_start,
  input         io_debug_capture_enable,
  input         io_align_ctrl_ok,
  output [7:0]  io_cpu_dout,
  output        io_rom_rd,
  output [17:0] io_rom_addr,
  input  [24:0] io_rom_cache_addr,
  input  [7:0]  io_rom_dout,
  input         io_rom_valid,
  output        io_audio_valid,
  output [13:0] io_audio_bits,
  output [47:0] io_debug_ctrl_bytes,
  output [47:0] io_debug_decode_bytes,
  output [47:0] io_debug_table_bytes,
  output [47:0] io_debug_body_bytes,
  output        io_debug_body_done,
  output [7:0]  io_debug_busy_state,
  input         io_ss_hold,
  input         io_ss_restore_enable,
  output        io_ss_idle,
  cave_ssbus_if.slave io_ssbus
);

reg        adpcm_cen;
reg [15:0] cen_accumulator;
reg [3:0]  write_hold;
reg [7:0]  write_data;
reg [24:0] requested_rom_addr;
reg [7:0]  rom_data;
reg        rom_data_ready;
reg [15:0] fir_din;
reg [2:0]  hold_stable_count;

wire [16:0] cen_next =
  {1'b0, cen_accumulator} + io_cen_step;
wire rom_addr_changed = io_rom_cache_addr != requested_rom_addr;
wire buffered_rom_ready = rom_data_ready & ~rom_addr_changed;
wire chip_rom_ok =
  io_wait_for_rom ? buffered_rom_ready : io_rom_valid;
wire [7:0] chip_rom_data =
  io_wait_for_rom ? rom_data : io_rom_dout;
wire hold_for_rom =
  !FIXED_SAMPLE_CLOCK & io_wait_for_rom & cen_next[16] & ~chip_rom_ok;
wire stretch_cpu_wr =
  io_stretch_cpu_wr & (WRITE_HOLD_CYCLES > 1);
wire chip_cpu_wr = stretch_cpu_wr
  ? (io_cpu_wr | (write_hold != 4'd0))
  : io_cpu_wr;
wire [7:0] chip_cpu_din = stretch_cpu_wr
  ? (io_cpu_wr ? io_cpu_din : write_data)
  : io_cpu_din;
wire rom_quiescent =
  ~io_wait_for_rom | buffered_rom_ready;

localparam integer WRITE_HOLD_RELOAD =
  WRITE_HOLD_CYCLES <= 1 ? 0 :
  WRITE_HOLD_CYCLES > 16 ? 15 :
  WRITE_HOLD_CYCLES - 1;

wire core_cen1;
wire core_cen4;
wire core_sample;
wire signed [13:0] core_sound;
wire signed [15:0] fir_dout;
wire fir_idle;

wire auto_rd;
wire auto_wr;
wire [31:0] auto_data_in;
wire [7:0] auto_device_idx;
wire [15:0] auto_state_idx;
wire [31:0] auto_data_out;
wire auto_ack;

wire wrapper_restore_wr;
wire [31:0] wrapper_restore_addr;
wire [31:0] wrapper_restore_data;
wire fir_state_wr;
wire [31:0] fir_state_din;
wire [31:0] fir_state_dout;
wire [6:0] fir_mem_addr;
wire fir_mem_wr;
wire [15:0] fir_mem_din;
wire [15:0] fir_mem_dout;

wire [95:0] wrapper_state = {
  {
    11'd0,
    write_hold,
    write_data,
    rom_data,
    rom_data_ready
  },
  {7'd0, requested_rom_addr},
  {fir_din, cen_accumulator}
};

always @(posedge clock) begin
  if (reset) begin
    cen_accumulator <= 16'd0;
    adpcm_cen <= 1'b0;
  end else if (wrapper_restore_wr &&
               (wrapper_restore_addr == 32'd0)) begin
    cen_accumulator <= wrapper_restore_data[15:0];
    adpcm_cen <= 1'b0;
  end else if (io_ss_hold) begin
    adpcm_cen <= 1'b0;
  end else if (hold_for_rom) begin
    adpcm_cen <= 1'b0;
  end else begin
    cen_accumulator <= cen_next[15:0];
    adpcm_cen <= cen_next[16];
  end
end

always @(posedge clock) begin
  if (reset) begin
    write_hold <= 4'd0;
    write_data <= 8'd0;
  end else if (wrapper_restore_wr &&
               (wrapper_restore_addr == 32'd2)) begin
    write_hold <= wrapper_restore_data[20:17];
    write_data <= wrapper_restore_data[16:9];
  end else if (!io_ss_hold) begin
    if (io_cpu_wr) begin
      write_hold <= WRITE_HOLD_RELOAD;
      write_data <= io_cpu_din;
    end else if (write_hold != 4'd0) begin
      write_hold <= write_hold - 4'd1;
    end
  end
end

always @(posedge clock) begin
  if (reset) begin
    requested_rom_addr <= 25'd0;
    rom_data <= 8'd0;
    rom_data_ready <= 1'b0;
  end else if (wrapper_restore_wr &&
               (wrapper_restore_addr == 32'd1)) begin
    requested_rom_addr <= wrapper_restore_data[24:0];
  end else if (wrapper_restore_wr &&
               (wrapper_restore_addr == 32'd2)) begin
    rom_data <= wrapper_restore_data[8:1];
    rom_data_ready <= wrapper_restore_data[0];
  end else if (rom_addr_changed) begin
    requested_rom_addr <= io_rom_cache_addr;
    rom_data_ready <= 1'b0;
  end else if (io_rom_valid) begin
    rom_data <= io_rom_dout;
    rom_data_ready <= 1'b1;
  end
end

always @(posedge clock) begin
  if (reset)
    fir_din <= 16'd0;
  else if (wrapper_restore_wr &&
           (wrapper_restore_addr == 32'd0))
    fir_din <= wrapper_restore_data[31:16];
  else if (!io_ss_hold && core_cen4)
    fir_din <= core_cen1
      ? {{1{core_sound[13]}}, core_sound, 1'b0}
      : 16'd0;
end

always @(posedge clock) begin
  if (reset || !io_ss_hold || !rom_quiescent || !fir_idle)
    hold_stable_count <= 3'd0;
  else if (!(&hold_stable_count))
    hold_stable_count <= hold_stable_count + 3'd1;
end

cave_pwrinst2_ss_CaveOKIM6295Core #(
  .INTERPOL(0)
) decoder (
  .rst(reset),
  .clk(clock),
  .cen(io_ss_hold ? 1'b0 : adpcm_cen),
  .save_hold(io_ss_hold),
  .ss(io_ss),
  .wait_for_rom(io_wait_for_rom),
  .ignore_busy_start(io_ignore_busy_start),
  .duplicate_busy_start_filter(io_duplicate_busy_start_filter),
  .restart_busy_start(io_restart_busy_start),
  .restart_mute_busy_start(io_restart_mute_busy_start),
  .reset_adpcm_on_start(io_reset_adpcm_on_start),
  .status_includes_start(io_status_includes_start),
  .debug_capture_enable(io_debug_capture_enable),
  .align_ctrl_ok(io_align_ctrl_ok),
  .wrn(~(chip_cpu_wr & ~io_ss_hold)),
  .din(chip_cpu_din),
  .dout(io_cpu_dout),
  .rom_addr(io_rom_addr),
  .rom_data(chip_rom_data),
  .rom_ok(chip_rom_ok),
  .sound(core_sound),
  .sample(core_sample),
  .debug_ctrl_bytes(io_debug_ctrl_bytes),
  .debug_decode_bytes(io_debug_decode_bytes),
  .debug_table_bytes(io_debug_table_bytes),
  .debug_body_bytes(io_debug_body_bytes),
  .debug_body_done(io_debug_body_done),
  .debug_busy_state(io_debug_busy_state),
  .cen_sr_out(core_cen1),
  .cen_sr4_out(core_cen4),
  .auto_ss_rd(auto_rd),
  .auto_ss_wr(auto_wr),
  .auto_ss_data_in(auto_data_in),
  .auto_ss_device_idx(auto_device_idx),
  .auto_ss_state_idx(auto_state_idx),
  .auto_ss_base_device_idx(8'd0),
  .auto_ss_data_out(auto_data_out),
  .auto_ss_ack(auto_ack)
);

CaveDonPachiOkiFir #(
  .COEFFS(FIR_COEFFS)
) interpolator (
  .clock(clock),
  .reset(reset),
  .sample(core_cen4 & ~io_ss_hold),
  .din(fir_din),
  .dout(fir_dout),
  .ss_hold(io_ss_hold),
  .ss_idle(fir_idle),
  .ss_state_wr(fir_state_wr),
  .ss_state_din(fir_state_din),
  .ss_state_dout(fir_state_dout),
  .ss_mem_addr(fir_mem_addr),
  .ss_mem_wr(fir_mem_wr),
  .ss_mem_din(fir_mem_din),
  .ss_mem_dout(fir_mem_dout)
);

CavePwrInst2OkiStatePort #(
  .SS_IDX(SS_IDX)
) state_port (
  .clock(clock),
  .reset(reset),
  .state_enable(io_ss_idle),
  .restore_enable(io_ss_restore_enable),
  .wrapper_state(wrapper_state),
  .wrapper_restore_wr(wrapper_restore_wr),
  .wrapper_restore_addr(wrapper_restore_addr),
  .wrapper_restore_data(wrapper_restore_data),
  .fir_state_dout(fir_state_dout),
  .fir_state_wr(fir_state_wr),
  .fir_state_din(fir_state_din),
  .fir_mem_addr(fir_mem_addr),
  .fir_mem_wr(fir_mem_wr),
  .fir_mem_din(fir_mem_din),
  .fir_mem_dout(fir_mem_dout),
  .auto_rd(auto_rd),
  .auto_wr(auto_wr),
  .auto_data_in(auto_data_in),
  .auto_device_idx(auto_device_idx),
  .auto_state_idx(auto_state_idx),
  .auto_data_out(auto_data_out),
  .auto_ack(auto_ack),
  .ssbus(io_ssbus)
);

assign io_rom_rd = io_wait_for_rom
  ? (rom_addr_changed | ~rom_data_ready)
  : 1'b1;
assign io_audio_valid = core_cen4 & ~io_ss_hold;
assign io_audio_bits = fir_dout[13:0];
assign io_ss_idle = io_ss_hold & (&hold_stable_count);

wire _unused_core_sample = core_sample;

endmodule

module CavePwrInst2OkiStatePort #(
  parameter [7:0] SS_IDX = 8'd36
) (
  input         clock,
  input         reset,
  input         state_enable,
  input         restore_enable,
  input  [95:0] wrapper_state,
  output reg    wrapper_restore_wr,
  output reg [31:0] wrapper_restore_addr,
  output reg [31:0] wrapper_restore_data,
  input  [31:0] fir_state_dout,
  output reg    fir_state_wr,
  output reg [31:0] fir_state_din,
  output reg [6:0] fir_mem_addr,
  output reg    fir_mem_wr,
  output reg [15:0] fir_mem_din,
  input  [15:0] fir_mem_dout,
  output reg    auto_rd,
  output reg    auto_wr,
  output reg [31:0] auto_data_in,
  output reg [7:0] auto_device_idx,
  output reg [15:0] auto_state_idx,
  input  [31:0] auto_data_out,
  input         auto_ack,
  cave_ssbus_if.slave ssbus
);

localparam [31:0] AUTO_WORDS = 32'd115;
localparam [31:0] WRAPPER_BASE = 32'd115;
localparam [31:0] FIR_STATE_WORD = 32'd118;
localparam [31:0] FIR_MEMORY_BASE = 32'd119;
localparam [31:0] FIR_MEMORY_WORDS = 32'd35;
localparam [31:0] WORD_COUNT = 32'd154;

localparam [3:0] ST_IDLE = 4'd0;
localparam [3:0] ST_AUTO_READ = 4'd1;
localparam [3:0] ST_AUTO_WRITE = 4'd2;
localparam [3:0] ST_DIRECT_WRITE = 4'd3;
localparam [3:0] ST_MEM_READ_0_WAIT = 4'd4;
localparam [3:0] ST_MEM_READ_0_CAPTURE = 4'd5;
localparam [3:0] ST_MEM_READ_1_WAIT = 4'd6;
localparam [3:0] ST_MEM_READ_1_CAPTURE = 4'd7;
localparam [3:0] ST_MEM_WRITE_0 = 4'd8;
localparam [3:0] ST_MEM_WRITE_1 = 4'd9;
localparam [3:0] ST_WAIT_REQUEST = 4'd10;

reg [3:0] state;
reg [31:0] request_data;
reg [15:0] memory_word_0;
reg memory_second_valid;
reg [23:0] mapped_location;
reg [7:0] history_index;

wire selected = ssbus.select == SS_IDX;
wire request_active = ssbus.query || ssbus.read || ssbus.write;

function automatic [23:0] auto_location(input [6:0] flat_index);
begin
  if (flat_index <= 7'd26)
    auto_location = {8'd0, 9'd0, flat_index};
  else if (flat_index == 7'd27)
    auto_location = {8'd1, 16'd0};
  else if (flat_index <= 7'd36)
    auto_location = {8'd2, 9'd0, flat_index - 7'd28};
  else if (flat_index <= 7'd45)
    auto_location = {8'd3, 9'd0, flat_index - 7'd37};
  else if (flat_index <= 7'd47)
    auto_location = {8'd4, 9'd0, flat_index - 7'd46};
  else if (flat_index <= 7'd89)
    auto_location = {8'd5, 9'd0, flat_index - 7'd48};
  else if (flat_index <= 7'd95)
    auto_location = {8'd6, 9'd0, flat_index - 7'd90};
  else if (flat_index == 7'd96)
    auto_location = {8'd7, 16'd0};
  else if (flat_index == 7'd97)
    auto_location = {8'd8, 16'd0};
  else if (flat_index <= 7'd101)
    auto_location = {8'd9, 9'd0, flat_index - 7'd98};
  else if (flat_index <= 7'd113)
    auto_location = {8'd10, 9'd0, flat_index - 7'd102};
  else
    auto_location = {8'd11, 16'd0};
end
endfunction

always @(posedge clock) begin
  ssbus.ack <= 1'b0;
  wrapper_restore_wr <= 1'b0;
  fir_state_wr <= 1'b0;

  if (reset) begin
    state <= ST_IDLE;
    ssbus.data_out <= 64'd0;
    wrapper_restore_addr <= 32'd0;
    wrapper_restore_data <= 32'd0;
    fir_state_din <= 32'd0;
    fir_mem_addr <= 7'd0;
    fir_mem_wr <= 1'b0;
    fir_mem_din <= 16'd0;
    auto_rd <= 1'b0;
    auto_wr <= 1'b0;
    auto_data_in <= 32'd0;
    auto_device_idx <= 8'd0;
    auto_state_idx <= 16'd0;
    request_data <= 32'd0;
    memory_word_0 <= 16'd0;
    memory_second_valid <= 1'b0;
    mapped_location <= 24'd0;
    history_index <= 8'd0;
  end else begin
    case (state)
      ST_IDLE: begin
        auto_rd <= 1'b0;
        auto_wr <= 1'b0;
        fir_mem_wr <= 1'b0;

        if (selected && !state_enable && request_active) begin
          ssbus.data_out <= 64'd0;
          ssbus.ack <= 1'b1;
          state <= ST_WAIT_REQUEST;
        end else if (selected && state_enable && ssbus.query) begin
          ssbus.data_out <= {SS_IDX, 22'd0, 2'd2, WORD_COUNT};
          ssbus.ack <= 1'b1;
          state <= ST_WAIT_REQUEST;
        end else if (selected && state_enable &&
                     (ssbus.read || ssbus.write)) begin
          request_data <= ssbus.data[31:0];

          if (ssbus.addr >= WORD_COUNT) begin
            ssbus.data_out <= 64'd0;
            ssbus.ack <= 1'b1;
            state <= ST_WAIT_REQUEST;
          end else if (ssbus.addr < AUTO_WORDS) begin
            mapped_location =
              auto_location(7'd114 - ssbus.addr[6:0]);
            auto_device_idx <= mapped_location[23:16];
            auto_state_idx <= mapped_location[15:0];
            auto_data_in <= ssbus.data[31:0];
            if (ssbus.write) begin
              if (restore_enable) begin
                auto_wr <= 1'b1;
                state <= ST_AUTO_WRITE;
              end else begin
                ssbus.ack <= 1'b1;
                state <= ST_WAIT_REQUEST;
              end
            end else begin
              auto_rd <= 1'b1;
              state <= ST_AUTO_READ;
            end
          end else if (ssbus.addr < FIR_STATE_WORD) begin
            if (ssbus.write) begin
              if (restore_enable) begin
                wrapper_restore_addr <= ssbus.addr - WRAPPER_BASE;
                wrapper_restore_data <= ssbus.data[31:0];
                wrapper_restore_wr <= 1'b1;
                state <= ST_DIRECT_WRITE;
              end else begin
                ssbus.ack <= 1'b1;
                state <= ST_WAIT_REQUEST;
              end
            end else begin
              case (ssbus.addr - WRAPPER_BASE)
                32'd0: ssbus.data_out <= {32'd0, wrapper_state[31:0]};
                32'd1: ssbus.data_out <= {32'd0, wrapper_state[63:32]};
                default:
                  ssbus.data_out <= {32'd0, wrapper_state[95:64]};
              endcase
              ssbus.ack <= 1'b1;
              state <= ST_WAIT_REQUEST;
            end
          end else if (ssbus.addr == FIR_STATE_WORD) begin
            if (ssbus.write) begin
              if (restore_enable) begin
                fir_state_din <= ssbus.data[31:0];
                fir_state_wr <= 1'b1;
                state <= ST_DIRECT_WRITE;
              end else begin
                ssbus.ack <= 1'b1;
                state <= ST_WAIT_REQUEST;
              end
            end else begin
              ssbus.data_out <= {32'd0, fir_state_dout};
              ssbus.ack <= 1'b1;
              state <= ST_WAIT_REQUEST;
            end
          end else begin
            history_index =
              (ssbus.addr - FIR_MEMORY_BASE) << 1;
            fir_mem_addr <= history_index[6:0];
            memory_second_valid <= history_index < 8'd68;
            if (ssbus.write) begin
              if (restore_enable) begin
                fir_mem_din <= ssbus.data[15:0];
                fir_mem_wr <= 1'b1;
                state <= ST_MEM_WRITE_0;
              end else begin
                ssbus.ack <= 1'b1;
                state <= ST_WAIT_REQUEST;
              end
            end else begin
              state <= ST_MEM_READ_0_WAIT;
            end
          end
        end
      end

      ST_AUTO_READ: begin
        if (auto_ack) begin
          auto_rd <= 1'b0;
          ssbus.data_out <= {32'd0, auto_data_out};
          ssbus.ack <= 1'b1;
          state <= ST_WAIT_REQUEST;
        end
      end

      ST_AUTO_WRITE: begin
        auto_wr <= 1'b0;
        ssbus.ack <= 1'b1;
        state <= ST_WAIT_REQUEST;
      end

      ST_DIRECT_WRITE: begin
        ssbus.ack <= 1'b1;
        state <= ST_WAIT_REQUEST;
      end

      ST_MEM_READ_0_WAIT:
        state <= ST_MEM_READ_0_CAPTURE;

      ST_MEM_READ_0_CAPTURE: begin
        memory_word_0 <= fir_mem_dout;
        fir_mem_addr <= fir_mem_addr + 7'd1;
        state <= ST_MEM_READ_1_WAIT;
      end

      ST_MEM_READ_1_WAIT:
        state <= ST_MEM_READ_1_CAPTURE;

      ST_MEM_READ_1_CAPTURE: begin
        ssbus.data_out <= {
          32'd0,
          memory_second_valid ? fir_mem_dout : 16'd0,
          memory_word_0
        };
        ssbus.ack <= 1'b1;
        state <= ST_WAIT_REQUEST;
      end

      ST_MEM_WRITE_0: begin
        fir_mem_wr <= 1'b0;
        if (memory_second_valid) begin
          fir_mem_addr <= fir_mem_addr + 7'd1;
          fir_mem_din <= request_data[31:16];
          state <= ST_MEM_WRITE_1;
        end else begin
          ssbus.ack <= 1'b1;
          state <= ST_WAIT_REQUEST;
        end
      end

      ST_MEM_WRITE_1: begin
        fir_mem_wr <= 1'b1;
        state <= ST_DIRECT_WRITE;
      end

      ST_WAIT_REQUEST: begin
        fir_mem_wr <= 1'b0;
        if (!request_active)
          state <= ST_IDLE;
      end

      default: state <= ST_IDLE;
    endcase
  end
end

wire [31:0] _unused_fir_memory_words = FIR_MEMORY_WORDS;

endmodule
