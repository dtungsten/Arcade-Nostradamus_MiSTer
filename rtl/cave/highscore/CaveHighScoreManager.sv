// Cave-local high-score persistence using MRA-described work-RAM ranges.
module CaveHighScoreManager (
  input         sys_clock,
  input         sys_reset,
  input         cpu_clock,
  input         cpu_reset,

  input         config_download,
  input         config_wr,
  input  [26:0] config_addr,
  input  [15:0] config_dout,

  input         nvram_download,
  input         nvram_upload,
  input         nvram_rd,
  input         nvram_wr,
  input  [26:0] nvram_addr,
  input  [15:0] nvram_dout,
  output [15:0] nvram_din,
  output        nvram_wait_n,

  input         ss_hold_cpu,
  input         cpu_idle,
  input         normal_ram_wr,
  input  [23:0] normal_byte_addr,
  input  [1:0]  normal_ram_mask,
  input  [15:0] normal_ram_din,

  output        cpu_hold,
  output        ram_owned,
  output        ram_rd,
  output        ram_wr,
  output [14:0] ram_addr,
  output [1:0]  ram_mask,
  output [15:0] ram_din,
  input  [15:0] ram_dout,

  output        dirty_sys,
  output        active_sys
);

  localparam [26:0] NVRAM_METADATA_BASE = 27'd128;
  localparam [26:0] NVRAM_METADATA_END  = 27'd160;
  localparam [26:0] NVRAM_SCORE_BASE    = 27'd160;
  localparam [26:0] NVRAM_SCORE_END     = 27'd672;

  localparam [3:0] STATE_IDLE          = 4'd0;
  localparam [3:0] STATE_RESTORE_HOLD  = 4'd1;
  localparam [3:0] STATE_RESTORE_READ  = 4'd2;
  localparam [3:0] STATE_RESTORE_WRITE = 4'd3;
  localparam [3:0] STATE_CAPTURE_HOLD  = 4'd4;
  localparam [3:0] STATE_CAPTURE_READ  = 4'd5;
  localparam [3:0] STATE_CAPTURE_WRITE = 4'd6;

  wire [15:0] config_word = {config_dout[7:0], config_dout[15:8]};

  reg         config_download_d;
  reg  [7:0]  config_written;
  reg  [31:0] range0_start_sys;
  reg  [15:0] range0_length_sys;
  reg  [7:0]  range0_first_sys;
  reg  [7:0]  range0_last_sys;
  reg  [31:0] range1_start_sys;
  reg  [15:0] range1_length_sys;
  reg  [7:0]  range1_first_sys;
  reg  [7:0]  range1_last_sys;
  reg         range1_valid_sys;
  reg         config_valid_sys;
  reg         config_toggle_sys;

  wire [16:0] range0_end_offset_sys =
    {1'b0, range0_start_sys[15:0]} + {1'b0, range0_length_sys};
  wire [16:0] range1_end_offset_sys =
    {1'b0, range1_start_sys[15:0]} + {1'b0, range1_length_sys};
  wire [16:0] total_length_sys =
    {1'b0, range0_length_sys} + {1'b0, range1_length_sys};
  wire        range0_complete_sys = &config_written[3:0];
  wire        range1_complete_sys = &config_written[7:4];
  wire        range1_absent_sys = ~(|config_written[7:4]);
  wire        range0_candidate_valid =
    range0_complete_sys && (range0_length_sys != 16'd0) &&
    (range0_length_sys <= 16'd512) &&
    (range0_end_offset_sys <= 17'h10000);
  wire        range1_candidate_valid =
    range1_complete_sys && (range1_length_sys != 16'd0) &&
    (range1_length_sys <= 16'd512) &&
    (range1_end_offset_sys <= 17'h10000);
  wire        config_candidate_valid =
    range0_candidate_valid &&
    (range1_absent_sys || range1_candidate_valid) &&
    (range1_absent_sys || (total_length_sys <= 17'd512));

  always @(posedge sys_clock) begin
    config_download_d <= config_download;

    if (sys_reset) begin
      config_download_d <= 1'b0;
      config_written <= 8'd0;
      range0_start_sys <= 32'd0;
      range0_length_sys <= 16'd0;
      range0_first_sys <= 8'd0;
      range0_last_sys <= 8'd0;
      range1_start_sys <= 32'd0;
      range1_length_sys <= 16'd0;
      range1_first_sys <= 8'd0;
      range1_last_sys <= 8'd0;
      range1_valid_sys <= 1'b0;
      config_valid_sys <= 1'b0;
      config_toggle_sys <= 1'b0;
    end else begin
      if (config_download && !config_download_d) begin
        config_written <= 8'd0;
        range0_start_sys <= 32'd0;
        range0_length_sys <= 16'd0;
        range0_first_sys <= 8'd0;
        range0_last_sys <= 8'd0;
        range1_start_sys <= 32'd0;
        range1_length_sys <= 16'd0;
        range1_first_sys <= 8'd0;
        range1_last_sys <= 8'd0;
        range1_valid_sys <= 1'b0;
        config_valid_sys <= 1'b0;
      end

      if (config_download && config_wr && (config_addr[26:4] == 23'd0)) begin
        config_written[config_addr[3:1]] <= 1'b1;
        case (config_addr[3:1])
          3'd0: range0_start_sys[31:16] <= config_word;
          3'd1: range0_start_sys[15:0] <= config_word;
          3'd2: range0_length_sys <= config_word;
          3'd3: begin
            range0_first_sys <= config_word[15:8];
            range0_last_sys <= config_word[7:0];
          end
          3'd4: range1_start_sys[31:16] <= config_word;
          3'd5: range1_start_sys[15:0] <= config_word;
          3'd6: range1_length_sys <= config_word;
          3'd7: begin
            range1_first_sys <= config_word[15:8];
            range1_last_sys <= config_word[7:0];
          end
        endcase
      end

      if (!config_download && config_download_d) begin
        config_valid_sys <= config_candidate_valid;
        range1_valid_sys <= config_candidate_valid && range1_candidate_valid;
        config_toggle_sys <= ~config_toggle_sys;
      end
    end
  end

  wire metadata_nvram_address =
    (nvram_addr >= NVRAM_METADATA_BASE) &&
    (nvram_addr < NVRAM_METADATA_END);
  wire score_nvram_address =
    (nvram_addr >= NVRAM_SCORE_BASE) && (nvram_addr < NVRAM_SCORE_END);
  wire [3:0] metadata_word_address_sys = nvram_addr[4:1];
  reg  [15:0] expected_metadata_word_sys;
  always @* begin
    case (metadata_word_address_sys)
      4'd0: expected_metadata_word_sys = 16'h4356; // "CV"
      4'd1: expected_metadata_word_sys = 16'h4853; // "HS"
      4'd2: expected_metadata_word_sys = 16'h0120; // schema 1, 32 bytes
      4'd3: expected_metadata_word_sys = range1_valid_sys
        ? 16'h0200 : 16'h0100;
      4'd4: expected_metadata_word_sys = total_length_sys[15:0];
      4'd5: expected_metadata_word_sys = 16'h0000;
      4'd6: expected_metadata_word_sys = range0_start_sys[31:16];
      4'd7: expected_metadata_word_sys = range0_start_sys[15:0];
      4'd8: expected_metadata_word_sys = range0_length_sys;
      4'd9: expected_metadata_word_sys =
        {range0_first_sys, range0_last_sys};
      4'd10: expected_metadata_word_sys = range1_valid_sys
        ? range1_start_sys[31:16] : 16'h0000;
      4'd11: expected_metadata_word_sys = range1_valid_sys
        ? range1_start_sys[15:0] : 16'h0000;
      4'd12: expected_metadata_word_sys = range1_valid_sys
        ? range1_length_sys : 16'h0000;
      4'd13: expected_metadata_word_sys = range1_valid_sys
        ? {range1_first_sys, range1_last_sys} : 16'h0000;
      4'd14: expected_metadata_word_sys = 16'h454E; // "EN"
      4'd15: expected_metadata_word_sys = 16'h4421; // "D!"
    endcase
  end
  wire [9:0] score_byte_offset_sys = nvram_addr[9:0] - 10'd160;
  wire [7:0] score_word_address_sys = score_byte_offset_sys[8:1];
  wire [15:0] nvram_file_word_sys =
    {nvram_dout[7:0], nvram_dout[15:8]};
  wire [15:0] score_buffer_din_sys = nvram_file_word_sys;
  wire metadata_wr_sys =
    nvram_download && nvram_wr && metadata_nvram_address;
  wire load_buffer_wr_sys =
    nvram_download && nvram_wr && score_nvram_address;
  // Main samples upload data before pulsing nvram_rd, so read ahead while the
  // requested score word is selected.
  wire load_buffer_rd_sys =
    nvram_upload && score_nvram_address;
  wire [15:0] load_buffer_q_sys;
  wire [7:0]  load_buffer_q_cpu;
  wire [15:0] save_buffer_q_sys;

  reg         nvram_download_d;
  reg  [15:0] metadata_written_sys;
  reg  [15:0] metadata_words_sys [0:15];
  reg  [8:0]  score_word_count_sys;
  reg         score_sequence_error_sys;
  reg         nvram_payload_ready_sys;
  reg         nvram_validation_pending_sys;
  reg         nvram_has_data_sys;
  reg         nvram_load_toggle_sys;

  reg         nvram_upload_started_sys;
  reg         upload_ready_sys;
  reg         capture_pending_sys;
  reg         capture_complete_delay_sys;
  reg         capture_request_toggle_sys;
  reg         capture_done_meta_sys;
  reg         capture_done_sync_sys;
  reg         capture_done_seen_sys;
  reg         capture_valid_meta_sys;
  reg         capture_valid_sync_sys;
  reg         snapshot_valid_sys;

  reg         dirty_meta_sys;
  reg         dirty_sync_sys;
  reg         active_meta_sys;
  reg         active_sync_sys;

  wire        capture_done_toggle_cpu;
  wire        capture_valid_cpu;
  wire        dirty_cpu;
  wire        active_cpu;

  wire metadata_matches_sys =
    (metadata_words_sys[0]  == 16'h4356) &&
    (metadata_words_sys[1]  == 16'h4853) &&
    (metadata_words_sys[2]  == 16'h0120) &&
    (metadata_words_sys[3]  ==
      (range1_valid_sys ? 16'h0200 : 16'h0100)) &&
    (metadata_words_sys[4]  == total_length_sys[15:0]) &&
    (metadata_words_sys[5]  == 16'h0000) &&
    (metadata_words_sys[6]  == range0_start_sys[31:16]) &&
    (metadata_words_sys[7]  == range0_start_sys[15:0]) &&
    (metadata_words_sys[8]  == range0_length_sys) &&
    (metadata_words_sys[9]  ==
      {range0_first_sys, range0_last_sys}) &&
    (metadata_words_sys[10] ==
      (range1_valid_sys ? range1_start_sys[31:16] : 16'h0000)) &&
    (metadata_words_sys[11] ==
      (range1_valid_sys ? range1_start_sys[15:0] : 16'h0000)) &&
    (metadata_words_sys[12] ==
      (range1_valid_sys ? range1_length_sys : 16'h0000)) &&
    (metadata_words_sys[13] ==
      (range1_valid_sys
        ? {range1_first_sys, range1_last_sys} : 16'h0000)) &&
    (metadata_words_sys[14] == 16'h454E) &&
    (metadata_words_sys[15] == 16'h4421);
  wire [8:0] expected_score_word_count_sys =
    total_length_sys[9:1] + total_length_sys[0];

  always @(posedge sys_clock) begin
    nvram_download_d <= nvram_download;
    capture_done_meta_sys <= capture_done_toggle_cpu;
    capture_done_sync_sys <= capture_done_meta_sys;
    capture_valid_meta_sys <= capture_valid_cpu;
    capture_valid_sync_sys <= capture_valid_meta_sys;
    dirty_meta_sys <= dirty_cpu;
    dirty_sync_sys <= dirty_meta_sys;
    active_meta_sys <= active_cpu;
    active_sync_sys <= active_meta_sys;

    if (sys_reset) begin
      nvram_download_d <= 1'b0;
      metadata_written_sys <= 16'd0;
      score_word_count_sys <= 9'd0;
      score_sequence_error_sys <= 1'b0;
      nvram_payload_ready_sys <= 1'b0;
      nvram_validation_pending_sys <= 1'b0;
      nvram_has_data_sys <= 1'b0;
      nvram_load_toggle_sys <= 1'b0;
      nvram_upload_started_sys <= 1'b0;
      upload_ready_sys <= 1'b0;
      capture_pending_sys <= 1'b0;
      capture_complete_delay_sys <= 1'b0;
      capture_request_toggle_sys <= 1'b0;
      capture_done_meta_sys <= 1'b0;
      capture_done_sync_sys <= 1'b0;
      capture_done_seen_sys <= 1'b0;
      capture_valid_meta_sys <= 1'b0;
      capture_valid_sync_sys <= 1'b0;
      snapshot_valid_sys <= 1'b0;
      dirty_meta_sys <= 1'b0;
      dirty_sync_sys <= 1'b0;
      active_meta_sys <= 1'b0;
      active_sync_sys <= 1'b0;
    end else begin
      if (nvram_download && !nvram_download_d) begin
        metadata_written_sys <= 16'd0;
        score_word_count_sys <= 9'd0;
        score_sequence_error_sys <= 1'b0;
        nvram_payload_ready_sys <= 1'b0;
        nvram_validation_pending_sys <= 1'b0;
        nvram_has_data_sys <= 1'b0;
        snapshot_valid_sys <= 1'b0;
      end
      if (metadata_wr_sys) begin
        metadata_written_sys[metadata_word_address_sys] <= 1'b1;
        metadata_words_sys[metadata_word_address_sys] <= nvram_file_word_sys;
      end
      if (load_buffer_wr_sys && !score_sequence_error_sys) begin
        if (score_byte_offset_sys == {score_word_count_sys, 1'b0})
          score_word_count_sys <= score_word_count_sys + 9'd1;
        else
          score_sequence_error_sys <= 1'b1;
      end
      if (!nvram_download && nvram_download_d) begin
        nvram_payload_ready_sys <=
          (&metadata_written_sys) && !score_sequence_error_sys;
        nvram_validation_pending_sys <= 1'b1;
      end
      if (nvram_validation_pending_sys && config_valid_sys) begin
        nvram_has_data_sys <=
          nvram_payload_ready_sys && metadata_matches_sys &&
          (score_word_count_sys == expected_score_word_count_sys);
        nvram_load_toggle_sys <= ~nvram_load_toggle_sys;
        nvram_validation_pending_sys <= 1'b0;
      end

      if (!nvram_upload) begin
        nvram_upload_started_sys <= 1'b0;
        upload_ready_sys <= 1'b0;
        capture_pending_sys <= 1'b0;
        capture_complete_delay_sys <= 1'b0;
      end else if (!nvram_upload_started_sys) begin
        nvram_upload_started_sys <= 1'b1;
        if (config_valid_sys) begin
          capture_request_toggle_sys <= ~capture_request_toggle_sys;
          capture_pending_sys <= 1'b1;
        end
      end

      if (capture_pending_sys &&
          (capture_done_sync_sys != capture_done_seen_sys)) begin
        capture_done_seen_sys <= capture_done_sync_sys;
        capture_complete_delay_sys <= 1'b1;
      end

      if (capture_complete_delay_sys) begin
        snapshot_valid_sys <= capture_valid_sync_sys;
        capture_pending_sys <= 1'b0;
        capture_complete_delay_sys <= 1'b0;
        upload_ready_sys <= 1'b1;
      end
    end
  end

  assign nvram_wait_n =
    !nvram_upload || !config_valid_sys || upload_ready_sys;
  wire [15:0] metadata_upload_word_sys = snapshot_valid_sys
    ? expected_metadata_word_sys : 16'h0000;
  assign nvram_din = metadata_nvram_address
    ? {metadata_upload_word_sys[7:0], metadata_upload_word_sys[15:8]}
    : snapshot_valid_sys
      ? {save_buffer_q_sys[7:0], save_buffer_q_sys[15:8]}
      : {load_buffer_q_sys[7:0], load_buffer_q_sys[15:8]};
  assign dirty_sys = dirty_sync_sys;
  assign active_sys = active_sync_sys;

  reg         config_toggle_meta_cpu;
  reg         config_toggle_sync_cpu;
  reg         config_toggle_seen_cpu;
  reg         config_valid_meta_cpu;
  reg         config_valid_sync_cpu;
  reg         range1_valid_meta_cpu;
  reg         range1_valid_sync_cpu;
  reg  [31:0] range0_start_meta_cpu;
  reg  [31:0] range0_start_sync_cpu;
  reg  [15:0] range0_length_meta_cpu;
  reg  [15:0] range0_length_sync_cpu;
  reg  [7:0]  range0_first_meta_cpu;
  reg  [7:0]  range0_first_sync_cpu;
  reg  [7:0]  range0_last_meta_cpu;
  reg  [7:0]  range0_last_sync_cpu;
  reg  [31:0] range1_start_meta_cpu;
  reg  [31:0] range1_start_sync_cpu;
  reg  [15:0] range1_length_meta_cpu;
  reg  [15:0] range1_length_sync_cpu;
  reg  [7:0]  range1_first_meta_cpu;
  reg  [7:0]  range1_first_sync_cpu;
  reg  [7:0]  range1_last_meta_cpu;
  reg  [7:0]  range1_last_sync_cpu;

  reg         nvram_load_toggle_meta_cpu;
  reg         nvram_load_toggle_sync_cpu;
  reg         nvram_load_toggle_seen_cpu;
  reg         nvram_has_data_meta_cpu;
  reg         nvram_has_data_sync_cpu;
  reg         capture_request_meta_cpu;
  reg         capture_request_sync_cpu;

  always @(posedge cpu_clock) begin
    config_toggle_meta_cpu <= config_toggle_sys;
    config_toggle_sync_cpu <= config_toggle_meta_cpu;
    config_valid_meta_cpu <= config_valid_sys;
    config_valid_sync_cpu <= config_valid_meta_cpu;
    range1_valid_meta_cpu <= range1_valid_sys;
    range1_valid_sync_cpu <= range1_valid_meta_cpu;
    range0_start_meta_cpu <= range0_start_sys;
    range0_start_sync_cpu <= range0_start_meta_cpu;
    range0_length_meta_cpu <= range0_length_sys;
    range0_length_sync_cpu <= range0_length_meta_cpu;
    range0_first_meta_cpu <= range0_first_sys;
    range0_first_sync_cpu <= range0_first_meta_cpu;
    range0_last_meta_cpu <= range0_last_sys;
    range0_last_sync_cpu <= range0_last_meta_cpu;
    range1_start_meta_cpu <= range1_start_sys;
    range1_start_sync_cpu <= range1_start_meta_cpu;
    range1_length_meta_cpu <= range1_length_sys;
    range1_length_sync_cpu <= range1_length_meta_cpu;
    range1_first_meta_cpu <= range1_first_sys;
    range1_first_sync_cpu <= range1_first_meta_cpu;
    range1_last_meta_cpu <= range1_last_sys;
    range1_last_sync_cpu <= range1_last_meta_cpu;
    nvram_load_toggle_meta_cpu <= nvram_load_toggle_sys;
    nvram_load_toggle_sync_cpu <= nvram_load_toggle_meta_cpu;
    nvram_has_data_meta_cpu <= nvram_has_data_sys;
    nvram_has_data_sync_cpu <= nvram_has_data_meta_cpu;
    capture_request_meta_cpu <= capture_request_toggle_sys;
    capture_request_sync_cpu <= capture_request_meta_cpu;
  end

  reg  [31:0] range0_start_cpu;
  reg  [15:0] range0_length_cpu;
  reg  [7:0]  range0_first_cpu;
  reg  [7:0]  range0_last_cpu;
  reg  [31:0] range1_start_cpu;
  reg  [15:0] range1_length_cpu;
  reg  [7:0]  range1_first_cpu;
  reg  [7:0]  range1_last_cpu;
  reg         range1_valid_cpu;
  reg         config_valid_cpu;
  reg         config_initialized_cpu;
  reg         load_data_available_cpu;

  reg         range0_first_match_cpu;
  reg         range0_last_match_cpu;
  reg         range1_first_match_cpu;
  reg         range1_last_match_cpu;
  reg         scores_ready_cpu;
  reg         restore_applied_cpu;
  reg         dirty_cpu_r;
  reg         capture_done_toggle_cpu_r;
  reg         capture_valid_cpu_r;
  reg  [3:0]  state_cpu;
  reg         range_select_cpu;
  reg  [15:0] range_offset_cpu;
  reg  [8:0]  buffer_offset_cpu;

  wire [31:0] current_range_start_cpu =
    range_select_cpu ? range1_start_cpu : range0_start_cpu;
  wire [15:0] current_range_length_cpu =
    range_select_cpu ? range1_length_cpu : range0_length_cpu;
  wire [16:0] current_byte_offset_cpu =
    {1'b0, current_range_start_cpu[15:0]} +
    {1'b0, range_offset_cpu};
  wire [23:0] range0_end_byte_cpu =
    range0_start_cpu[23:0] + {8'd0, range0_length_cpu} - 24'd1;
  wire [23:0] range1_end_byte_cpu =
    range1_start_cpu[23:0] + {8'd0, range1_length_cpu} - 24'd1;
  wire        range0_ready_cpu =
    range0_first_match_cpu && range0_last_match_cpu;
  wire        range1_ready_cpu =
    !range1_valid_cpu ||
    (range1_first_match_cpu && range1_last_match_cpu);
  wire        normal_even_write = normal_ram_wr && normal_ram_mask[1];
  wire        normal_odd_write = normal_ram_wr && normal_ram_mask[0];
  wire        normal_even_write_in_range0 = normal_even_write &&
    (normal_byte_addr >= range0_start_cpu[23:0]) &&
    (normal_byte_addr <
      (range0_start_cpu[23:0] + {8'd0, range0_length_cpu}));
  wire        normal_odd_write_in_range0 = normal_odd_write &&
    ((normal_byte_addr + 24'd1) >= range0_start_cpu[23:0]) &&
    ((normal_byte_addr + 24'd1) <
      (range0_start_cpu[23:0] + {8'd0, range0_length_cpu}));
  wire        normal_even_write_in_range1 = range1_valid_cpu &&
    normal_even_write &&
    (normal_byte_addr >= range1_start_cpu[23:0]) &&
    (normal_byte_addr <
      (range1_start_cpu[23:0] + {8'd0, range1_length_cpu}));
  wire        normal_odd_write_in_range1 = range1_valid_cpu &&
    normal_odd_write &&
    ((normal_byte_addr + 24'd1) >= range1_start_cpu[23:0]) &&
    ((normal_byte_addr + 24'd1) <
      (range1_start_cpu[23:0] + {8'd0, range1_length_cpu}));

  always @(posedge cpu_clock) begin
    if (cpu_reset) begin
      config_toggle_seen_cpu <= ~config_toggle_sync_cpu;
      nvram_load_toggle_seen_cpu <= nvram_load_toggle_sync_cpu;
      range0_start_cpu <= 32'd0;
      range0_length_cpu <= 16'd0;
      range0_first_cpu <= 8'd0;
      range0_last_cpu <= 8'd0;
      range1_start_cpu <= 32'd0;
      range1_length_cpu <= 16'd0;
      range1_first_cpu <= 8'd0;
      range1_last_cpu <= 8'd0;
      range1_valid_cpu <= 1'b0;
      config_valid_cpu <= 1'b0;
      config_initialized_cpu <= 1'b0;
      load_data_available_cpu <= 1'b0;
      range0_first_match_cpu <= 1'b0;
      range0_last_match_cpu <= 1'b0;
      range1_first_match_cpu <= 1'b0;
      range1_last_match_cpu <= 1'b0;
      scores_ready_cpu <= 1'b0;
      restore_applied_cpu <= 1'b0;
      dirty_cpu_r <= 1'b0;
      capture_done_toggle_cpu_r <= capture_request_sync_cpu;
      capture_valid_cpu_r <= 1'b0;
      state_cpu <= STATE_IDLE;
      range_select_cpu <= 1'b0;
      range_offset_cpu <= 16'd0;
      buffer_offset_cpu <= 9'd0;
    end else if ((config_toggle_sync_cpu != config_toggle_seen_cpu) ||
                 (!config_initialized_cpu && config_valid_sync_cpu)) begin
      config_toggle_seen_cpu <= config_toggle_sync_cpu;
      range0_start_cpu <= range0_start_sync_cpu;
      range0_length_cpu <= range0_length_sync_cpu;
      range0_first_cpu <= range0_first_sync_cpu;
      range0_last_cpu <= range0_last_sync_cpu;
      range1_start_cpu <= range1_start_sync_cpu;
      range1_length_cpu <= range1_length_sync_cpu;
      range1_first_cpu <= range1_first_sync_cpu;
      range1_last_cpu <= range1_last_sync_cpu;
      range1_valid_cpu <= range1_valid_sync_cpu;
      config_valid_cpu <= config_valid_sync_cpu;
      config_initialized_cpu <= 1'b1;
      range0_first_match_cpu <= 1'b0;
      range0_last_match_cpu <= 1'b0;
      range1_first_match_cpu <= 1'b0;
      range1_last_match_cpu <= 1'b0;
      scores_ready_cpu <= 1'b0;
      restore_applied_cpu <= 1'b0;
      dirty_cpu_r <= 1'b0;
      capture_valid_cpu_r <= 1'b0;
      state_cpu <= STATE_IDLE;
    end else begin
      if (nvram_load_toggle_sync_cpu != nvram_load_toggle_seen_cpu) begin
        nvram_load_toggle_seen_cpu <= nvram_load_toggle_sync_cpu;
        load_data_available_cpu <= nvram_has_data_sync_cpu;
        restore_applied_cpu <= 1'b0;
        capture_valid_cpu_r <= 1'b0;
      end else if (!load_data_available_cpu && nvram_has_data_sync_cpu) begin
        load_data_available_cpu <= 1'b1;
      end

      if (config_valid_cpu && normal_ram_wr) begin
        if (normal_even_write &&
            (normal_byte_addr == range0_start_cpu[23:0]))
          range0_first_match_cpu <= normal_ram_din[15:8] == range0_first_cpu;
        if (normal_odd_write &&
            ((normal_byte_addr + 24'd1) == range0_start_cpu[23:0]))
          range0_first_match_cpu <= normal_ram_din[7:0] == range0_first_cpu;
        if (normal_even_write &&
            (normal_byte_addr == range0_end_byte_cpu))
          range0_last_match_cpu <= normal_ram_din[15:8] == range0_last_cpu;
        if (normal_odd_write &&
            ((normal_byte_addr + 24'd1) == range0_end_byte_cpu))
          range0_last_match_cpu <= normal_ram_din[7:0] == range0_last_cpu;

        if (range1_valid_cpu) begin
          if (normal_even_write &&
              (normal_byte_addr == range1_start_cpu[23:0]))
            range1_first_match_cpu <= normal_ram_din[15:8] == range1_first_cpu;
          if (normal_odd_write &&
              ((normal_byte_addr + 24'd1) == range1_start_cpu[23:0]))
            range1_first_match_cpu <= normal_ram_din[7:0] == range1_first_cpu;
          if (normal_even_write &&
              (normal_byte_addr == range1_end_byte_cpu))
            range1_last_match_cpu <= normal_ram_din[15:8] == range1_last_cpu;
          if (normal_odd_write &&
              ((normal_byte_addr + 24'd1) == range1_end_byte_cpu))
            range1_last_match_cpu <= normal_ram_din[7:0] == range1_last_cpu;
        end
      end

      if (config_valid_cpu && range0_ready_cpu && range1_ready_cpu)
        scores_ready_cpu <= 1'b1;

      if (scores_ready_cpu && normal_ram_wr &&
          (normal_even_write_in_range0 || normal_odd_write_in_range0 ||
           normal_even_write_in_range1 || normal_odd_write_in_range1))
        dirty_cpu_r <= 1'b1;

      case (state_cpu)
        STATE_IDLE: begin
          if (config_valid_cpu && load_data_available_cpu &&
              scores_ready_cpu && !restore_applied_cpu && !ss_hold_cpu) begin
            state_cpu <= STATE_RESTORE_HOLD;
          end else if (capture_request_sync_cpu !=
                       capture_done_toggle_cpu_r) begin
            if (config_valid_cpu && scores_ready_cpu && !ss_hold_cpu) begin
              capture_valid_cpu_r <= 1'b0;
              state_cpu <= STATE_CAPTURE_HOLD;
            end else if (!ss_hold_cpu) begin
              capture_valid_cpu_r <= 1'b0;
              capture_done_toggle_cpu_r <= capture_request_sync_cpu;
            end
          end
        end

        STATE_RESTORE_HOLD: begin
          if (cpu_idle) begin
            range_select_cpu <= 1'b0;
            range_offset_cpu <= 16'd0;
            buffer_offset_cpu <= 9'd0;
            state_cpu <= STATE_RESTORE_READ;
          end
        end

        STATE_RESTORE_READ:
          state_cpu <= STATE_RESTORE_WRITE;

        STATE_RESTORE_WRITE: begin
          if ((range_offset_cpu + 16'd1) == current_range_length_cpu) begin
            if (!range_select_cpu && range1_valid_cpu) begin
              range_select_cpu <= 1'b1;
              range_offset_cpu <= 16'd0;
              buffer_offset_cpu <= buffer_offset_cpu + 9'd1;
              state_cpu <= STATE_RESTORE_READ;
            end else begin
              restore_applied_cpu <= 1'b1;
              state_cpu <= STATE_IDLE;
            end
          end else begin
            range_offset_cpu <= range_offset_cpu + 16'd1;
            buffer_offset_cpu <= buffer_offset_cpu + 9'd1;
            state_cpu <= STATE_RESTORE_READ;
          end
        end

        STATE_CAPTURE_HOLD: begin
          if (cpu_idle) begin
            range_select_cpu <= 1'b0;
            range_offset_cpu <= 16'd0;
            buffer_offset_cpu <= 9'd0;
            state_cpu <= STATE_CAPTURE_READ;
          end
        end

        STATE_CAPTURE_READ:
          state_cpu <= STATE_CAPTURE_WRITE;

        STATE_CAPTURE_WRITE: begin
          if ((range_offset_cpu + 16'd1) == current_range_length_cpu) begin
            if (!range_select_cpu && range1_valid_cpu) begin
              range_select_cpu <= 1'b1;
              range_offset_cpu <= 16'd0;
              buffer_offset_cpu <= buffer_offset_cpu + 9'd1;
              state_cpu <= STATE_CAPTURE_READ;
            end else begin
              dirty_cpu_r <= 1'b0;
              capture_valid_cpu_r <= 1'b1;
              capture_done_toggle_cpu_r <= capture_request_sync_cpu;
              state_cpu <= STATE_IDLE;
            end
          end else begin
            range_offset_cpu <= range_offset_cpu + 16'd1;
            buffer_offset_cpu <= buffer_offset_cpu + 9'd1;
            state_cpu <= STATE_CAPTURE_READ;
          end
        end

        default:
          state_cpu <= STATE_IDLE;
      endcase
    end
  end

  assign cpu_hold = state_cpu != STATE_IDLE;
  assign active_cpu = state_cpu != STATE_IDLE;
  assign ram_owned =
    (state_cpu == STATE_RESTORE_READ) ||
    (state_cpu == STATE_RESTORE_WRITE) ||
    (state_cpu == STATE_CAPTURE_READ) ||
    (state_cpu == STATE_CAPTURE_WRITE);
  assign ram_rd = state_cpu == STATE_CAPTURE_READ;
  assign ram_wr = state_cpu == STATE_RESTORE_WRITE;
  assign ram_addr = current_byte_offset_cpu[15:1];
  assign ram_mask = current_byte_offset_cpu[0] ? 2'b01 : 2'b10;
  assign ram_din = current_byte_offset_cpu[0]
    ? {8'd0, load_buffer_q_cpu}
    : {load_buffer_q_cpu, 8'd0};
  assign dirty_cpu = dirty_cpu_r;
  assign capture_done_toggle_cpu = capture_done_toggle_cpu_r;
  assign capture_valid_cpu = capture_valid_cpu_r;

  wire load_buffer_rd_cpu = state_cpu == STATE_RESTORE_READ;
  wire save_buffer_wr_cpu = state_cpu == STATE_CAPTURE_WRITE;
  wire [8:0] buffer_address_cpu = buffer_offset_cpu ^ 9'd1;
  wire [7:0] save_buffer_din_cpu = current_byte_offset_cpu[0]
    ? ram_dout[7:0]
    : ram_dout[15:8];

  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (8),
    .ADDR_WIDTH_B (9),
    .DATA_WIDTH_A (16),
    .DATA_WIDTH_B (8),
    .DEPTH_A      (256),
    .DEPTH_B      (512),
    .MASK_ENABLE  (1)
  ) loadBuffer (
    .clock_a (sys_clock),
    .rd_a    (load_buffer_rd_sys),
    .wr_a    (load_buffer_wr_sys),
    .addr_a  (score_word_address_sys),
    .mask_a  (2'b11),
    .din_a   (score_buffer_din_sys),
    .dout_a  (load_buffer_q_sys),
    .clock_b (cpu_clock),
    .rd_b    (load_buffer_rd_cpu),
    .addr_b  (buffer_address_cpu),
    .dout_b  (load_buffer_q_cpu)
  );

  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (9),
    .ADDR_WIDTH_B (8),
    .DATA_WIDTH_A (8),
    .DATA_WIDTH_B (16),
    .DEPTH_A      (512),
    .DEPTH_B      (256),
    .MASK_ENABLE  (0)
  ) saveBuffer (
    .clock_a (cpu_clock),
    .rd_a    (1'b0),
    .wr_a    (save_buffer_wr_cpu),
    .addr_a  (buffer_address_cpu),
    .mask_a  (1'b1),
    .din_a   (save_buffer_din_cpu),
    .dout_a  (),
    .clock_b (sys_clock),
    .rd_b    (load_buffer_rd_sys),
    .addr_b  (score_word_address_sys),
    .dout_b  (save_buffer_q_sys)
  );

endmodule
