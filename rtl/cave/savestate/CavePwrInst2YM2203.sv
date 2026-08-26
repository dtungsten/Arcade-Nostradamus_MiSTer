module CavePwrInst2YM2203 #(
  parameter [7:0] SS_IDX = 8'd35
) (
  input         clock,
  input         reset,
  input         io_cpu_wr,
  input         io_cpu_addr,
  input  [7:0]  io_cpu_din,
  output [7:0]  io_cpu_dout,
  output        io_cpu_wait_n,
  output        io_cpu_queue_full,
  output        io_irq,
  output        io_audio_valid,
  output [15:0] io_audio_bits_psg,
  output [15:0] io_audio_bits_fm,
  input         io_ss_hold,
  input         io_ss_restore_enable,
  output        io_ss_idle,
  cave_ssbus_if.slave io_ssbus
);

reg [15:0] clock_accumulator = 16'd0;
reg        ym_cen = 1'b0;
reg        write_active;
reg        write_queued;
reg        write_addr;
reg        write_queued_addr;
reg [7:0]  write_data;
reg [7:0]  write_queued_data;
reg [2:0]  hold_stable_count;

wire [16:0] clock_next =
  {1'b0, clock_accumulator} + 17'h2000;
wire write_complete = write_active & ym_cen;
wire write_can_accept =
  ~write_active | ~write_queued | write_complete;

wire       ym_irq_n;
wire [9:0] ym_psg_snd;
wire       auto_rd;
wire       auto_wr;
wire [31:0] auto_data_in;
wire [7:0]  auto_device_idx;
wire [15:0] auto_state_idx;
wire [31:0] auto_data_out;
wire       auto_ack;
wire       wrapper_restore_wr;
wire [31:0] wrapper_restore_addr;
wire [31:0] wrapper_restore_data;

wire [63:0] wrapper_state = {
  {
    12'd0,
    write_queued_data,
    write_data,
    write_queued_addr,
    write_addr,
    write_queued,
    write_active
  },
  {16'd0, clock_accumulator}
};

always @(posedge clock) begin
  if (wrapper_restore_wr &&
      (wrapper_restore_addr == 32'd0)) begin
    clock_accumulator <= wrapper_restore_data[15:0];
    ym_cen <= 1'b0;
  end else if (io_ss_hold) begin
    ym_cen <= 1'b0;
  end else begin
    clock_accumulator <= clock_next[15:0];
    ym_cen <= clock_next[16];
  end
end

always @(posedge clock) begin
  if (reset) begin
    write_active <= 1'b0;
    write_queued <= 1'b0;
    write_addr <= 1'b0;
    write_queued_addr <= 1'b0;
    write_data <= 8'd0;
    write_queued_data <= 8'd0;
  end else if (wrapper_restore_wr &&
               (wrapper_restore_addr == 32'd1)) begin
    write_active <= wrapper_restore_data[0];
    write_queued <= wrapper_restore_data[1];
    write_addr <= wrapper_restore_data[2];
    write_queued_addr <= wrapper_restore_data[3];
    write_data <= wrapper_restore_data[11:4];
    write_queued_data <= wrapper_restore_data[19:12];
  end else if (!io_ss_hold) begin
    if (write_complete) begin
      if (write_queued) begin
        write_active <= 1'b1;
        write_addr <= write_queued_addr;
        write_data <= write_queued_data;
        write_queued <= 1'b0;
      end else begin
        write_active <= 1'b0;
      end
    end

    if (io_cpu_wr) begin
      if (~write_active | (write_complete & ~write_queued)) begin
        write_active <= 1'b1;
        write_addr <= io_cpu_addr;
        write_data <= io_cpu_din;
      end else if (~write_queued | write_complete) begin
        write_queued <= 1'b1;
        write_queued_addr <= io_cpu_addr;
        write_queued_data <= io_cpu_din;
      end
    end
  end
end

always @(posedge clock) begin
  if (reset || !io_ss_hold)
    hold_stable_count <= 3'd0;
  else if (!(&hold_stable_count))
    hold_stable_count <= hold_stable_count + 3'd1;
end

cave_pwrinst2_ss_jt03 decoder (
  .rst        (reset),
  .clk        (clock),
  .cen        (ym_cen),
  .din        (write_active ? write_data : io_cpu_din),
  .addr       (write_active ? write_addr : io_cpu_addr),
  .cs_n       (1'b0),
  .wr_n       (~(write_active & ~io_ss_hold)),
  .dout       (io_cpu_dout),
  .irq_n      (ym_irq_n),
  .IOA_in     (8'h00),
  .IOB_in     (8'h00),
  .psg_A      (),
  .psg_B      (),
  .psg_C      (),
  .fm_snd     (io_audio_bits_fm),
  .psg_snd    (ym_psg_snd),
  .snd        (),
  .snd_sample (io_audio_valid),
  .debug_view (),
  .auto_ss_rd(auto_rd),
  .auto_ss_wr(auto_wr),
  .auto_ss_data_in(auto_data_in),
  .auto_ss_device_idx(auto_device_idx),
  .auto_ss_state_idx(auto_state_idx),
  .auto_ss_base_device_idx(8'd0),
  .auto_ss_data_out(auto_data_out),
  .auto_ss_ack(auto_ack)
);

CavePwrInst2YM2203StatePort #(
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
  .auto_rd(auto_rd),
  .auto_wr(auto_wr),
  .auto_data_in(auto_data_in),
  .auto_device_idx(auto_device_idx),
  .auto_state_idx(auto_state_idx),
  .auto_data_out(auto_data_out),
  .auto_ack(auto_ack),
  .ssbus(io_ssbus)
);

assign io_cpu_wait_n = write_can_accept;
assign io_cpu_queue_full =
  write_active & write_queued & ~write_complete;
assign io_irq = ~ym_irq_n;
assign io_audio_bits_psg = {1'b0, ym_psg_snd, 5'b0};
assign io_ss_idle = io_ss_hold & (&hold_stable_count);

endmodule

module CavePwrInst2YM2203StatePort #(
  parameter [7:0] SS_IDX = 8'd35
) (
  input         clock,
  input         reset,
  input         state_enable,
  input         restore_enable,
  input  [63:0] wrapper_state,
  output reg    wrapper_restore_wr,
  output reg [31:0] wrapper_restore_addr,
  output reg [31:0] wrapper_restore_data,
  output reg    auto_rd,
  output reg    auto_wr,
  output reg [31:0] auto_data_in,
  output reg [7:0] auto_device_idx,
  output reg [15:0] auto_state_idx,
  input  [31:0] auto_data_out,
  input         auto_ack,
  cave_ssbus_if.slave ssbus
);

localparam [31:0] AUTO_WORDS = 32'd241;
localparam [31:0] WRAPPER_BASE = 32'd241;
localparam [31:0] WORD_COUNT = 32'd243;

localparam [2:0] ST_IDLE = 3'd0;
localparam [2:0] ST_AUTO_READ = 3'd1;
localparam [2:0] ST_AUTO_WRITE = 3'd2;
localparam [2:0] ST_DIRECT_WRITE = 3'd3;
localparam [2:0] ST_WAIT_REQUEST = 3'd4;

reg [2:0] state;
reg [31:0] request_addr;
wire selected = ssbus.select == SS_IDX;
wire request_active = ssbus.query || ssbus.read || ssbus.write;

function automatic [23:0] auto_location(input [7:0] flat_index);
begin
  if (flat_index == 8'd0)
    auto_location = {8'd2, 16'd0};
  else if (flat_index <= 8'd8)
    auto_location = {8'd3, 8'd0, flat_index - 8'd1};
  else if (flat_index <= 8'd10)
    auto_location = {8'd4, 8'd0, flat_index - 8'd9};
  else if (flat_index == 8'd11)
    auto_location = {8'd5, 16'd0};
  else if (flat_index == 8'd12)
    auto_location = {8'd6, 16'd0};
  else if (flat_index == 8'd13)
    auto_location = {8'd11, 16'd0};
  else if (flat_index <= 8'd38)
    auto_location = {8'd12, 8'd0, flat_index - 8'd14};
  else if (flat_index <= 8'd82)
    auto_location = {8'd18, 8'd0, flat_index - 8'd39};
  else if (flat_index <= 8'd85)
    auto_location = {8'd21, 8'd0, flat_index - 8'd83};
  else if (flat_index <= 8'd88)
    auto_location = {8'd22, 8'd0, flat_index - 8'd86};
  else if (flat_index == 8'd89)
    auto_location = {8'd23, 16'd0};
  else if (flat_index <= 8'd109)
    auto_location = {8'd24, 8'd0, flat_index - 8'd90};
  else if (flat_index <= 8'd119)
    auto_location = {8'd25, 8'd0, flat_index - 8'd110};
  else if (flat_index <= 8'd121)
    auto_location = {8'd26, 8'd0, flat_index - 8'd120};
  else if (flat_index == 8'd122)
    auto_location = {8'd27, 16'd0};
  else if (flat_index == 8'd123)
    auto_location = {8'd28, 16'd0};
  else if (flat_index <= 8'd133)
    auto_location = {8'd29, 8'd0, flat_index - 8'd124};
  else if (flat_index <= 8'd136)
    auto_location = {8'd30, 8'd0, flat_index - 8'd134};
  else if (flat_index == 8'd137)
    auto_location = {8'd31, 16'd0};
  else if (flat_index == 8'd138)
    auto_location = {8'd32, 16'd0};
  else if (flat_index <= 8'd148)
    auto_location = {8'd33, 8'd0, flat_index - 8'd139};
  else if (flat_index <= 8'd151)
    auto_location = {8'd34, 8'd0, flat_index - 8'd149};
  else if (flat_index <= 8'd165)
    auto_location = {8'd35, 8'd0, flat_index - 8'd152};
  else if (flat_index <= 8'd179)
    auto_location = {8'd36, 8'd0, flat_index - 8'd166};
  else if (flat_index <= 8'd193)
    auto_location = {8'd37, 8'd0, flat_index - 8'd180};
  else if (flat_index <= 8'd203)
    auto_location = {8'd38, 8'd0, flat_index - 8'd194};
  else if (flat_index == 8'd204)
    auto_location = {8'd39, 16'd0};
  else if (flat_index == 8'd205)
    auto_location = {8'd40, 16'd0};
  else if (flat_index <= 8'd224)
    auto_location = {8'd59, 8'd0, flat_index - 8'd206};
  else if (flat_index == 8'd225)
    auto_location = {8'd60, 16'd0};
  else if (flat_index <= 8'd227)
    auto_location = {8'd61, 8'd0, flat_index - 8'd226};
  else if (flat_index <= 8'd229)
    auto_location = {8'd62, 8'd0, flat_index - 8'd228};
  else if (flat_index <= 8'd231)
    auto_location = {8'd63, 8'd0, flat_index - 8'd230};
  else if (flat_index == 8'd232)
    auto_location = {8'd64, 16'd0};
  else if (flat_index <= 8'd234)
    auto_location = {8'd65, 8'd0, flat_index - 8'd233};
  else if (flat_index <= 8'd236)
    auto_location = {8'd66, 8'd0, flat_index - 8'd235};
  else if (flat_index == 8'd237)
    auto_location = {8'd67, 16'd0};
  else if (flat_index == 8'd238)
    auto_location = {8'd68, 16'd0};
  else
    auto_location = {8'd76, 8'd0, flat_index - 8'd239};
end
endfunction

reg [23:0] mapped_location;

always @(posedge clock) begin
  ssbus.ack <= 1'b0;
  wrapper_restore_wr <= 1'b0;

  if (reset) begin
    state <= ST_IDLE;
    request_addr <= 32'd0;
    ssbus.data_out <= 64'd0;
    wrapper_restore_addr <= 32'd0;
    wrapper_restore_data <= 32'd0;
    auto_rd <= 1'b0;
    auto_wr <= 1'b0;
    auto_data_in <= 32'd0;
    auto_device_idx <= 8'd0;
    auto_state_idx <= 16'd0;
    mapped_location <= 24'd0;
  end else begin
    case (state)
      ST_IDLE: begin
        auto_rd <= 1'b0;
        auto_wr <= 1'b0;

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
          request_addr <= ssbus.addr;
          if (ssbus.addr >= WORD_COUNT) begin
            ssbus.data_out <= 64'd0;
            ssbus.ack <= 1'b1;
            state <= ST_WAIT_REQUEST;
          end else if (ssbus.addr < AUTO_WORDS) begin
            mapped_location =
              auto_location(8'd240 - ssbus.addr[7:0]);
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
          end else if (ssbus.write) begin
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
            ssbus.data_out <= ssbus.addr == WRAPPER_BASE
              ? {32'd0, wrapper_state[31:0]}
              : {32'd0, wrapper_state[63:32]};
            ssbus.ack <= 1'b1;
            state <= ST_WAIT_REQUEST;
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

      ST_WAIT_REQUEST: begin
        if (!request_active)
          state <= ST_IDLE;
      end

      default: state <= ST_IDLE;
    endcase
  end
end

endmodule
